// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter_esptool/src/domain/flash/flash_parameters.dart';
import 'package:flutter_esptool/src/domain/flash/flash_service_interface.dart';
import 'package:flutter_esptool/src/domain/stub/stub_loader_interface.dart';
import 'package:flutter_esptool/src/infrastructure/compression/zlib_helper.dart';
import 'package:flutter_esptool/src/infrastructure/flash_image/flash_image_builder.dart';
import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_progress.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';
import 'package:flutter_esptool/src/transport/slip_codec.dart';

/// Performs flash erase, write, read, and verify operations.
class FlashService implements FlashServiceInterface {
  /// Creates a [FlashService].
  FlashService({
    required EspTransportInterface transport,
    StubLoaderInterface? stubLoader,
    this.blockSize = 0x4000,
  })  : _transport = transport,
        _stubLoader = stubLoader;

  final EspTransportInterface _transport;

  /// Optional stub loader.  When non-null and [StubLoaderInterface.isLoaded]
  /// is true, flash commands use stub-mode behaviour:
  ///   • SPI_ATTACH is skipped (stub already owns the SPI peripheral).
  ///   • FLASH_END uses data=1 (stay in download mode, no automatic reset).
  ///   • readFlash delegates to readFlashStub for faster streaming reads.
  final StubLoaderInterface? _stubLoader;

  bool get _stubLoaded => _stubLoader?.isLoaded ?? false;

  /// The flash block size used for chunked writes.
  final int blockSize;

  /// True once SPI_ATTACH + SPI_SET_PARAMS have been sent successfully.
  /// Guards against re-sending them on every readFlash call, which causes
  /// the ROM to return error 63 (invalid state) and corrupt the read buffer.
  bool _spiReady = false;

  @override
  Future<Result<void>> writeFlash(FlashParameters params) async {
    try {
      if (params.encrypted && _stubLoaded) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashWriteFailed,
            message: 'Encrypted flash writes are only supported in ROM-'
                'loader mode (no flasher stub); the stub does not '
                'implement on-the-fly encryption.',
          ),
        );
      }
      if (params.encrypted && params.compress) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashWriteFailed,
            message: 'Encrypted and compressed flash writes cannot be '
                'combined — the ROM cannot decompress and encrypt a block '
                'in the same pass.',
          ),
        );
      }

      // The ESP ROM requires SPI_ATTACH (0x0D) before any flash write
      // commands.  Without this step the ROM does not know how the SPI flash
      // is wired and silently ignores FLASH_BEGIN.
      //
      // When the flasher stub is loaded, SPI_ATTACH is NOT sent: the stub
      // already owns the SPI peripheral and rejects ROM-mode setup opcodes.
      if (!_stubLoaded) {
        final attachResponse = await _transport.sendCommand(
          EspCommand(opcode: EspCommandOpcode.spiAttach, data: Uint8List(8)),
        );
        if (!attachResponse.isSuccess) {
          return const Failure<void>(
            EspError(
              type: EspErrorType.flashWriteFailed,
              message: 'The device rejected the SPI attach request',
            ),
          );
        }
      }

      final paddedData = FlashImageBuilder.buildPaddedImage(
        params.data,
        alignment: blockSize,
      );
      final blocks = FlashImageBuilder.splitIntoBlocks(
        paddedData,
        params.offset,
        blockSize,
      );

      // Compression (ZLibCodec) and block-copying are CPU-bound.  Offload to a
      // helper isolate so the Flutter UI stays responsive during large writes.
      final rawBlocks = blocks.map((b) => Uint8List.fromList(b.data)).toList();
      final dataBlocks = params.compress
          ? await Isolate.run(
              () => rawBlocks.map((b) {
                final result = ZlibHelper.compress(b);
                return result.fold((v) => v, (e) => throw e);
              }).toList(),
            )
          : rawBlocks;
      final compressedTotalBytes = dataBlocks.fold<int>(
        0,
        (total, block) => total + block.length,
      );

      // Flash writes can lose their small ACK frame to macOS USB-Serial-JTAG
      // byte loss (the device applies the block but the reply is dropped,
      // surfacing as a SLIP read timeout).  esptool handles this by retrying;
      // because the stub tracks a per-block sequence number that is reset by
      // FLASH_BEGIN, the whole begin→data→end sequence is restarted on failure
      // rather than resending an individual block with a stale sequence.
      const maxWriteAttempts = 3;
      var attempt = 0;
      while (true) {
        attempt++;
        try {
          final failure = await _writeFlashAttempt(
            params: params,
            paddedData: paddedData,
            blocks: blocks,
            dataBlocks: dataBlocks,
            compressedTotalBytes: compressedTotalBytes,
          );
          if (failure != null) {
            // A definitive device-side rejection (not a transport timeout) is
            // not retried — retrying would not change the outcome.
            return failure;
          }
          break; // Write + FLASH_END succeeded.
        } on EspError catch (error) {
          final isTransient = error.type == EspErrorType.timeout ||
              error.type == EspErrorType.partialPacket ||
              error.type == EspErrorType.connectionFailed;
          if (!isTransient || attempt >= maxWriteAttempts) {
            rethrow;
          }
          // ignore: avoid_print
          print('[FlashService] flash write attempt $attempt failed '
              '(${error.type}); flushing and retrying');
          await _transport.flushRx();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      if (params.verify) {
        // The device flash was written with a padded image (aligned to blockSize).
        // The MD5 region on the device must cover the same padded length, and the
        // expected hash must be computed over the same padded bytes — not the raw
        // unpadded input — otherwise the comparison will always fail.
        final actualResult = await md5Flash(params.offset, paddedData.length);
        if (actualResult is Failure<String>) {
          return Failure<void>(actualResult.error);
        }
        // MD5 over the padded firmware image is CPU-bound; run off the UI isolate.
        final dataToHash = paddedData;
        final expected = await Isolate.run(() => _md5HexStatic(dataToHash));
        final actual = (actualResult as Success<String>).value.toLowerCase();
        if (expected != actual) {
          return Failure<void>(
            EspError(
              type: EspErrorType.flashVerifyFailed,
              message:
                  'Flash verification failed: expected $expected but got $actual',
            ),
          );
        }
      }

      _emitProgress(
        params.onProgress,
        EspProgress(
          stage: EspProgressStage.done,
          current: params.data.length,
          total: params.data.length,
          message: 'Flash write complete',
        ),
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.flashWriteFailed,
              message: error.toString(),
              stackTrace: stackTrace,
            );
      return Failure<void>(espError);
    }
  }

  /// Runs a single FLASH_BEGIN → FLASH_DATA… → FLASH_END attempt.
  ///
  /// Returns `null` on success.  Returns a [Failure] for a *definitive*
  /// device-side rejection (the caller must NOT retry these).  A transport
  /// timeout / dropped ACK is thrown as an [EspError] so the caller can flush
  /// and restart the whole sequence (FLASH_BEGIN resets the stub's per-block
  /// sequence counter, so the entire begin→data→end must be replayed).
  Future<Result<void>?> _writeFlashAttempt({
    required FlashParameters params,
    required Uint8List paddedData,
    required List<({int offset, Uint8List data})> blocks,
    required List<Uint8List> dataBlocks,
    required int compressedTotalBytes,
  }) async {
    final beginResponse = await _transport.sendCommand(
      EspCommand(
        opcode: params.compress
            ? EspCommandOpcode.flashDeflBegin
            : EspCommandOpcode.flashBegin,
        // ESP ROM expects checksum=0 for FLASH_BEGIN (not XOR of payload).
        checksum: 0,
        data: params.compress
            ? _buildFlashDeflBeginPayload(
                uncompressedBytes: paddedData.length,
                compressedBytes: compressedTotalBytes,
                blockCount: dataBlocks.length,
                offset: params.offset,
              )
            : _buildFlashBeginPayload(
                totalBytes: paddedData.length,
                blockCount: blocks.length,
                offset: params.offset,
                encrypted: params.encrypted,
              ),
      ),
    );
    if (!beginResponse.isSuccess) {
      return const Failure<void>(
        EspError(
          type: EspErrorType.flashWriteFailed,
          message: 'The device rejected the flash begin request',
        ),
      );
    }

    // Debug: log the first 8 bytes of the first block so we can confirm
    // the correct data (e.g. AA 50 for partition table) reaches the device.
    if (dataBlocks.isNotEmpty) {
      final first = dataBlocks[0];
      final preview = first
          .take(8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      // ignore: avoid_print
      print('[FlashService] offset=0x${params.offset.toRadixString(16)}'
          ' first8bytes=$preview');
    }

    var written = 0;
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final payload = dataBlocks[index];
      final response = await _transport.sendCommand(
        EspCommand(
          opcode: params.compress
              ? EspCommandOpcode.flashDeflData
              : EspCommandOpcode.flashData,
          data: _buildFlashDataPayload(payload: payload, sequence: index),
          checksum: EspCommand.calculateChecksum(payload),
        ),
      );
      if (!response.isSuccess) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashWriteFailed,
            message: 'The device rejected a flash data block',
          ),
        );
      }
      written += block.data.length;
      _emitProgress(
        params.onProgress,
        EspProgress(
          stage: EspProgressStage.writing,
          current: written,
          total: params.data.length,
          message: 'Writing flash data',
        ),
      );
      // Yield after each block so progress callbacks and UI frames are
      // processed between serial round-trips.
      await Future<void>.delayed(Duration.zero);
    }

    // Give the device a moment to settle after the last data block
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // FLASH_END / FLASH_DEFL_END data field:
    //   0 = run user code (reboot out of download mode) — ROM mode behaviour
    //   1 = stay in download mode — required when stub is running so that
    //       subsequent commands (verify, readback) work on the same connection
    //
    // In ROM mode FLASH_END(0) immediately reboots the chip and any
    // subsequent command on the same connection will fail.  When the stub is
    // loaded we pass 1 to keep the device in download mode.
    final endData = _stubLoaded ? 1 : 0;
    final endResponse = await _transport.sendCommand(
      EspCommand(
        opcode: params.compress
            ? EspCommandOpcode.flashDeflEnd
            : EspCommandOpcode.flashEnd,
        // ESP ROM expects checksum=0 for FLASH_END.
        checksum: 0,
        data: _u32(endData),
      ),
    );
    if (!endResponse.isSuccess) {
      return const Failure<void>(
        EspError(
          type: EspErrorType.flashWriteFailed,
          message: 'The device rejected the flash end request',
        ),
      );
    }
    return null;
  }

  @override
  Future<Result<Uint8List>> readFlash(FlashReadParameters params) async {
    // When the flasher stub is loaded, delegate to the stub-mode streaming
    // read.  The ROM READ_FLASH_SLOW (0x0E) path below is REJECTED by the stub
    // ("device rejected a flash read request"), so it is only usable on a bare
    // ROM connection.
    if (_stubLoaded) {
      return readFlashStub(params);
    }

    try {
      if (params.offset < 0 || params.size < 0) {
        return const Failure<Uint8List>(
          EspError(
            type: EspErrorType.flashReadFailed,
            message: 'Flash read requires a non-negative offset and size',
          ),
        );
      }

      await _configureSpiFlashForRomRead();

      const romReadBlockSize = 64;
      final output = BytesBuilder(copy: false);
      while (output.length < params.size) {
        final bytesRead = output.length;
        final chunkSize = (params.size - bytesRead).clamp(0, romReadBlockSize);
        final payload = Uint8List(8);
        final data = ByteData.sublistView(payload);
        data.setUint32(0, params.offset + bytesRead, Endian.little);
        data.setUint32(4, chunkSize, Endian.little);

        final response = await _transport.sendCommand(
          EspCommand(opcode: EspCommandOpcode.readFlashSlow, data: payload),
        );
        if (!response.isSuccess) {
          return const Failure<Uint8List>(
            EspError(
              type: EspErrorType.flashReadFailed,
              message: 'The device rejected a flash read request',
            ),
          );
        }
        if (response.data.length < chunkSize) {
          return Failure<Uint8List>(
            EspError(
              type: EspErrorType.flashReadFailed,
              message:
                  'Short flash read: expected $chunkSize bytes, got ${response.data.length}',
            ),
          );
        }

        output.add(response.data.sublist(0, chunkSize));
        _emitProgress(
          params.onProgress,
          EspProgress(
            stage: EspProgressStage.reading,
            current: output.length,
            total: params.size,
            message: 'Reading flash data',
          ),
        );
        // Yield every chunk so the UI can render progress during long reads.
        await Future<void>.delayed(Duration.zero);
      }
      return Success<Uint8List>(output.toBytes());
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.flashReadFailed,
              message: error.toString(),
              stackTrace: stackTrace,
            );
      return Failure<Uint8List>(espError);
    }
  }

  /// Extracts exactly one complete SLIP frame from the front of [buf].
  ///
  /// Returns the decoded payload plus the number of raw bytes to remove from
  /// [buf].  Returns `null` when [buf] does not yet contain a complete frame
  /// (the caller should read more bytes and retry).
  ///
  /// The closing `0xC0` delimiter is intentionally left in the buffer (only
  /// `consumed == end` bytes are reported) so it can double as the opening
  /// delimiter of the next frame.  This makes the extractor robust to both
  /// double-delimiter (`… C0 C0 …`) and shared-delimiter (`… C0 …`) framing of
  /// back-to-back stub data packets.  Empty payloads (from a `C0 C0` pair) are
  /// returned as an empty list and should be skipped by the caller.
  static ({Uint8List? payload, int consumed})? _extractOneSlipFrame(
    List<int> buf,
  ) {
    final start = buf.indexOf(0xC0);
    if (start < 0) {
      return null; // no frame start yet
    }
    final end = buf.indexOf(0xC0, start + 1);
    if (end < 0) {
      return null; // frame not yet complete
    }
    final raw = Uint8List.fromList(buf.sublist(start, end + 1));
    final payload = SlipCodec.decode(raw);
    return (payload: payload, consumed: end);
  }

  /// Reads [params.size] bytes from flash at [params.offset] using the
  /// flasher stub's streaming READ_FLASH command (opcode 0xD2).
  ///
  /// The stub must have been loaded before calling this method.
  ///
  /// Protocol (mirrors esptool.py ESPLoader.read_flash):
  ///   1. Send READ_FLASH_STUB command with offset/length/packetSize/maxInflight.
  ///   2. Receive (length / packetSize) SLIP-framed data packets of [packetSize] bytes.
  ///   3. ACK each packet by writing the running total as uint32 LE (raw bytes).
  ///   4. Receive one final SLIP frame containing the 16-byte MD5 digest.
  ///   5. Verify digest; return data on success.
  Future<Result<Uint8List>> readFlashStub(FlashReadParameters params) async {
    // Block size for a single READ_FLASH_STUB transaction.  Multi-block
    // streaming (issuing one 0xD2 for the whole range and letting the stub
    // stream N packets with running-total ACK flow control) proved unreliable
    // over macOS USB-CDC: the device stalls mid-first-block on transfers that
    // span more than one packet, so the closing SLIP delimiter never arrives,
    // no ACK is sent, and the stub eventually gives up.  Single-block reads
    // (offset..offset+blockSize) are rock solid, so we drive the read as a
    // sequence of independent single-block 0xD2 commands and reassemble the
    // blocks host-side.
    //
    // Block size is deliberately small: macOS AppleUSBCDC drops roughly one
    // byte per 64-byte USB packet during sustained stub reads, so a large
    // frame (spanning dozens of USB packets) reliably arrives corrupt/short.
    // A 512-byte frame spans only ~8 packets, so intact delivery is the common
    // case; the stub's trailing MD5 digest lets us verify each block and retry
    // the rare corrupt one.
    const blockSize = 512;
    const maxInflight = 64;
    const maxRetriesPerBlock = 5;

    try {
      final output = BytesBuilder(copy: false);

      while (output.length < params.size) {
        final blockOffset = params.offset + output.length;
        final blockLen = (params.size - output.length) < blockSize
            ? (params.size - output.length)
            : blockSize;

        Result<Uint8List>? blockResult;
        for (var attempt = 1; attempt <= maxRetriesPerBlock; attempt++) {
          blockResult = await _readFlashStubBlock(
            offset: blockOffset,
            length: blockLen,
            maxInflight: maxInflight,
          );
          if (blockResult.isSuccess) break;
          // Corrupt/short block (USB byte loss): flush and retry the same
          // block.  The stub is stateless per 0xD2 command, so re-issuing is
          // safe.
          await _transport.flushRx();
        }

        if (blockResult == null || blockResult.isFailure) {
          return Failure<Uint8List>(
            (blockResult as Failure<Uint8List>).error,
          );
        }
        output.add((blockResult as Success<Uint8List>).value);

        if (params.onProgress != null) {
          params.onProgress!(EspProgress(
            stage: EspProgressStage.reading,
            current: output.length,
            total: params.size,
            message: 'Reading flash…',
          ));
        }
      }

      return Success<Uint8List>(output.toBytes());
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.flashReadFailed,
              message: 'Stub flash read failed: $error',
              stackTrace: stackTrace,
            );
      return Failure<Uint8List>(espError);
    }
  }

  /// Reads a single flash block (<= 4096 bytes) using one READ_FLASH_STUB
  /// (0xD2) transaction: send the command, receive exactly one SLIP data
  /// frame, ACK the running total, consume the trailing 16-byte MD5 digest
  /// frame, then flush so the connection is clean for the next command.
  ///
  /// This is the reliable primitive [readFlashStub] drives in a loop — the
  /// stub streams a single packet per command without any inter-block flow
  /// control, which avoids the multi-block streaming stall seen over USB-CDC.
  Future<Result<Uint8List>> _readFlashStubBlock({
    required int offset,
    required int length,
    required int maxInflight,
  }) async {
    // Ask the stub for exactly [length] bytes in a single packet.
    final payload = Uint8List(16);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, offset, Endian.little);
    bd.setUint32(4, length, Endian.little);
    bd.setUint32(8, length, Endian.little); // packetSize == whole block
    bd.setUint32(12, maxInflight, Endian.little);

    final ackResp = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.readFlashStub, data: payload),
      timeout: const Duration(seconds: 10),
    );
    if (!ackResp.isSuccess) {
      return const Failure<Uint8List>(EspError(
        type: EspErrorType.flashReadFailed,
        message: 'READ_FLASH_STUB command rejected',
      ));
    }

    // rxBuf accumulates raw SLIP bytes not yet consumed by frame extraction.
    final rxBuf = <int>[];

    // Reads and consumes exactly one non-empty SLIP frame from [rxBuf],
    // pulling more bytes from the transport as needed until [deadline].
    //
    // We poll in small chunks with a short per-call timeout rather than asking
    // readRaw() for the whole frame at once.  readRaw() blocks until it either
    // collects the requested byte count OR its timeout elapses; requesting
    // `length + 16` meant every call waited the full 5 s (the frame is always a
    // few bytes short of that count), which pushed each data/digest frame out of
    // its command window and leaked the trailing MD5 digest into the next
    // command.  Short polling returns the instant a complete frame is on the
    // wire.
    Future<Uint8List?> readOneFrame(DateTime deadline) async {
      while (true) {
        final extracted = _extractOneSlipFrame(rxBuf);
        if (extracted != null) {
          rxBuf.removeRange(0, extracted.consumed);
          final framePayload = extracted.payload;
          if (framePayload != null && framePayload.isNotEmpty) {
            return framePayload;
          }
          // Empty frame (a `C0 C0` delimiter pair) — skip and keep scanning.
          continue;
        }
        if (DateTime.now().isAfter(deadline)) {
          return null;
        }
        try {
          final remaining = deadline.difference(DateTime.now());
          final pollTimeout = remaining < const Duration(milliseconds: 200)
              ? remaining
              : const Duration(milliseconds: 200);
          final chunk = await _transport.readRaw(
            128, // small poll window; readRaw returns whatever has arrived
            timeout: pollTimeout,
          );
          rxBuf.addAll(chunk);
        } on Object {
          // A readRaw timeout simply means no bytes arrived in this window;
          // keep looping until our own [deadline] elapses.
          if (DateTime.now().isAfter(deadline)) {
            return null;
          }
        }
      }
    }

    // Step 1: the single data packet.
    final dataDeadline = DateTime.now().add(const Duration(seconds: 10));
    final frame = await readOneFrame(dataDeadline);
    if (frame == null) {
      return Failure<Uint8List>(EspError(
        type: EspErrorType.flashReadFailed,
        message: 'Timeout waiting for stub read block at '
            '0x${offset.toRadixString(16)}',
      ));
    }

    // Step 2: ACK the running total so the stub proceeds to emit its digest.
    // We ACK unconditionally — even for a short/corrupt frame — so the stub's
    // SLIP_recv() completes and it doesn't stay blocked (which would otherwise
    // leak the digest into the next command).  The stub reads this via
    // SLIP_recv(), so it MUST be a SLIP-framed packet:
    //   C0 <4-byte LE running total, SLIP-escaped> C0
    // (esptool.py's own write() SLIP-encodes this ACK; sending raw bytes leaves
    //  the stub's SLIP_recv() stalled.)
    final ackPayload = Uint8List(4);
    ByteData.sublistView(ackPayload).setUint32(0, frame.length, Endian.little);
    final ackFrame = <int>[0xC0];
    for (final byte in ackPayload) {
      if (byte == 0xC0) {
        ackFrame.addAll(const [0xDB, 0xDC]);
      } else if (byte == 0xDB) {
        ackFrame.addAll(const [0xDB, 0xDD]);
      } else {
        ackFrame.add(byte);
      }
    }
    ackFrame.add(0xC0);
    await _transport.writeRaw(Uint8List.fromList(ackFrame));

    // Step 3: read the trailing 16-byte MD5 digest frame.  It can arrive a
    // little after the ACK.  We capture it (not just drain it) so we can verify
    // the block's integrity — essential because USB byte loss can silently
    // corrupt a frame that still happens to decode to the expected length.
    const digestLength = 16;
    Uint8List? digest;
    final digestDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(digestDeadline)) {
      final digestFrame = await readOneFrame(digestDeadline);
      if (digestFrame == null) {
        break; // deadline elapsed with no further frame
      }
      if (digestFrame.length == digestLength) {
        digest = digestFrame;
        break; // digest captured — buffer is now clean
      }
      // Any other stray frame: keep draining until the real digest shows up.
    }

    // Guarantee a clean slate for the next command: clear the transport's
    // in-memory read buffer AND the serial hardware RX buffer.
    await _transport.flushRx();

    // Step 4: validate length and MD5.  Any mismatch → failure so the caller
    // retries this block (USB byte loss is transient).
    if (frame.length != length) {
      return Failure<Uint8List>(EspError(
        type: EspErrorType.flashReadFailed,
        message: 'Corrupt stub read: block at 0x${offset.toRadixString(16)} '
            'was ${frame.length} bytes (expected $length)',
      ));
    }
    if (digest == null) {
      return Failure<Uint8List>(EspError(
        type: EspErrorType.flashReadFailed,
        message: 'Missing MD5 digest for block at '
            '0x${offset.toRadixString(16)}',
      ));
    }
    final computed = Uint8List.fromList(md5.convert(frame).bytes);
    var digestMatches = true;
    for (var i = 0; i < digestLength; i++) {
      if (computed[i] != digest[i]) {
        digestMatches = false;
        break;
      }
    }
    if (!digestMatches) {
      return Failure<Uint8List>(EspError(
        type: EspErrorType.flashReadFailed,
        message: 'MD5 mismatch for block at 0x${offset.toRadixString(16)}',
      ));
    }

    return Success<Uint8List>(frame);
  }

  Future<void> _configureSpiFlashForRomRead() async {
    if (_spiReady) return; // already attached — don't re-send

    await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.spiAttach, data: Uint8List(8)),
    );

    // Same parameter layout used by esptool.py's ROM read path:
    // fl_id, total_size, block_size, sector_size, page_size, status_mask.
    final payload = Uint8List(24);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, 0, Endian.little);
    data.setUint32(4, 0x01000000, Endian.little);
    data.setUint32(8, 0x00010000, Endian.little);
    data.setUint32(12, 0x00001000, Endian.little);
    data.setUint32(16, 0x00000100, Endian.little);
    data.setUint32(20, 0x0000FFFF, Endian.little);
    // spiSetParams (0x0B) is only supported by the stub; ESP32 ROM may not
    // respond to it.  Use a short timeout and treat a timeout or failure as
    // non-fatal so ROM-only connections can still attempt readFlashSlow.
    try {
      final response = await _transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.spiSetParams, data: payload),
        timeout: const Duration(seconds: 4),
      );
      if (!response.isSuccess) {
        // Non-fatal: continue without SPI params.
      }
    } on EspError {
      // Timeout or transport error — spiSetParams is not supported by this
      // ROM; continue without it.
    }

    _spiReady = true; // don't repeat attach/params on next readFlash call
  }

  @override
  Future<Result<void>> eraseFlash({int? offset, int? size}) async {
    try {
      final EspCommand command;
      final Duration timeout;
      if (offset == null && size == null) {
        command = EspCommand(opcode: EspCommandOpcode.eraseFlash);
        // Full chip erase via stub (0xD0) can take up to ~3-4 minutes on a
        // 16 MB flash, or ~30-60 s on a 4 MB flash. Python esptool uses
        // CHIP_ERASE_TIMEOUT = 120 s × 3 = 360 s for the stub eraseFlash.
        timeout = const Duration(seconds: 300);
      } else if (offset != null && size != null) {
        if (offset < 0 || size <= 0) {
          return const Failure<void>(
            EspError(
              type: EspErrorType.flashEraseFailed,
              message:
                  'Erase region requires a non-negative offset and positive size',
            ),
          );
        }
        final payload = Uint8List(8);
        final data = ByteData.sublistView(payload);
        data.setUint32(0, offset, Endian.little);
        data.setUint32(4, size, Endian.little);
        command = EspCommand(
          opcode: EspCommandOpcode.eraseRegion,
          data: payload,
        );
        // Allow up to 300 s for large erases (8 MB @ ~25 s/MB ≈ 200 s ROM-only).
        final seconds = (30 * (size / (1024 * 1024))).ceil().clamp(3, 300);
        timeout = Duration(seconds: seconds);
      } else {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashEraseFailed,
            message: 'Erase region requires both offset and size',
          ),
        );
      }

      final response = await _transport.sendCommand(command, timeout: timeout);
      if (!response.isSuccess) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashEraseFailed,
            message: 'The device rejected the erase request',
          ),
        );
      }
      return const Success<void>(null);
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.flashEraseFailed,
              message: error.toString(),
              stackTrace: stackTrace,
            );
      return Failure<void>(espError);
    }
  }

  @override
  Future<Result<void>> eraseRegionRom({
    required int offset,
    required int eraseSize,
  }) async {
    try {
      if (eraseSize <= 0 || eraseSize % 4096 != 0) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashEraseFailed,
            message: 'eraseSize must be a positive multiple of 4096',
          ),
        );
      }

      // SPI_ATTACH is required before any flash command.
      final attachResponse = await _transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.spiAttach, data: Uint8List(8)),
      );
      if (!attachResponse.isSuccess) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashEraseFailed,
            message: 'SPI attach failed before erase',
          ),
        );
      }

      // FLASH_BEGIN with num_blocks=0 and erase_size = full region.
      // The ROM erases synchronously before returning the ACK, so the
      // timeout must cover the full erase duration (~25 s/MB for ROM).
      final eraseSeconds =
          (25 * (eraseSize / (1024 * 1024))).ceil().clamp(10, 600);
      // ignore: avoid_print
      print(
          '[FlashService] eraseRegionRom: offset=0x${offset.toRadixString(16)}'
          ' eraseSize=0x${eraseSize.toRadixString(16)} timeout=${eraseSeconds}s');
      final beginResponse = await _transport.sendCommand(
        EspCommand(
          opcode: EspCommandOpcode.flashBegin,
          checksum: 0,
          data: _buildFlashBeginPayload(
            totalBytes: eraseSize,
            blockCount: 0,
            offset: offset,
          ),
        ),
        timeout: Duration(seconds: eraseSeconds),
      );
      if (!beginResponse.isSuccess) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashEraseFailed,
            message: 'FLASH_BEGIN erase rejected by device',
          ),
        );
      }

      // FLASH_END with reboot=1 (stay in download mode) so we can continue.
      final endResponse = await _transport.sendCommand(
        EspCommand(
          opcode: EspCommandOpcode.flashEnd,
          checksum: 0,
          data: _u32(1), // 1 = stay in download mode
        ),
      );
      if (!endResponse.isSuccess) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashEraseFailed,
            message: 'FLASH_END after erase rejected by device',
          ),
        );
      }

      return const Success<void>(null);
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.flashEraseFailed,
              message: error.toString(),
              stackTrace: stackTrace,
            );
      return Failure<void>(espError);
    }
  }

  /// Sends SPI_ATTACH (0x0D) once to initialise flash access.
  /// Must be called before any flash read/MD5 command sequence.
  Future<Result<void>> spiAttach() async {
    try {
      final response = await _transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.spiAttach, data: Uint8List(8)),
      );
      if (!response.isSuccess) {
        return const Failure<void>(
          EspError(
            type: EspErrorType.flashVerifyFailed,
            message: 'SPI attach rejected by device',
          ),
        );
      }
      _spiReady =
          true; // suppress re-attach inside _configureSpiFlashForRomRead
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return Failure<void>(
        EspError(
          type: EspErrorType.flashVerifyFailed,
          message: error.toString(),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<String>> md5Flash(int offset, int size) async {
    try {
      final payload = Uint8List(16);
      final data = ByteData.sublistView(payload);
      data.setUint32(0, offset, Endian.little);
      data.setUint32(4, size, Endian.little);
      // Bytes 8-11 and 12-15 are reserved (0).  Payload is 4 × uint32 LE.
      // Use a generous timeout: the ROM must read and hash the entire region
      // from SPI flash without DMA.  esptool uses ~8 s/MB; we use 5 s/MB
      // with a minimum of 5 s. Empirically the ESP32-S3 ROM hashes ~3 MB/s.
      final timeoutSeconds = (5 * (size / (1024 * 1024))).ceil().clamp(5, 60);
      final response = await _transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.flashMd5, data: payload),
        timeout: Duration(seconds: timeoutSeconds),
      );
      if (!response.isSuccess) {
        return const Failure<String>(
          EspError(
            type: EspErrorType.flashVerifyFailed,
            message: 'The device rejected the flash MD5 request',
          ),
        );
      }
      final hash = _normalizeMd5Response(response.data);
      if (hash.isEmpty) {
        return const Failure<String>(
          EspError(
            type: EspErrorType.flashVerifyFailed,
            message: 'The device returned an empty flash MD5 response',
          ),
        );
      }
      return Success<String>(hash);
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.flashVerifyFailed,
              message: error.toString(),
              stackTrace: stackTrace,
            );
      return Failure<String>(espError);
    }
  }

  Uint8List _buildFlashBeginPayload({
    required int totalBytes,
    required int blockCount,
    required int offset,
    bool encrypted = false,
  }) {
    // FLASH_BEGIN payload format differs between ROM and stub:
    //
    // ROM (20 bytes — extended format required by ESP32-S3 ROM):
    //   [0]  erase_size  (uint32 LE)
    //   [4]  num_blocks  (uint32 LE)
    //   [8]  block_size  (uint32 LE)
    //   [12] offset      (uint32 LE)
    //   [16] encrypted   (uint32 LE, 0 = not encrypted, 1 = ROM encrypts
    //        each block on-the-fly with the burned flash-encryption key
    //        before writing — equivalent to esptool.py's `--encrypt`).
    // Sending only 16 bytes in ROM mode causes subsequent FLASH_DATA to be
    // rejected with ROM_INVALID_RECV_MSG (status=1, error=5).
    //
    // Stub (16 bytes — stub firmware parses only 4 fields):
    //   [0]  erase_size  (uint32 LE)
    //   [4]  num_blocks  (uint32 LE)
    //   [8]  block_size  (uint32 LE)
    //   [12] offset      (uint32 LE)
    // The stub ignores any extra bytes but rejects a 20-byte payload as
    // malformed (status=1, error=0) because it counts the payload length
    // to determine the encrypted flag. [encrypted] MUST be false here —
    // callers are responsible for guarding this (see [writeFlash]).
    final payloadLen = _stubLoaded ? 16 : 20;
    final payload = Uint8List(payloadLen);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, totalBytes, Endian.little);
    data.setUint32(4, blockCount, Endian.little);
    data.setUint32(8, blockSize, Endian.little);
    data.setUint32(12, offset, Endian.little);
    if (!_stubLoaded) {
      data.setUint32(16, encrypted ? 1 : 0, Endian.little);
    }
    return payload;
  }

  Uint8List _buildFlashDeflBeginPayload({
    required int uncompressedBytes,
    required int compressedBytes,
    required int blockCount,
    required int offset,
  }) {
    final writeSize = _roundUpToBlock(uncompressedBytes);
    final payload = Uint8List(16);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, writeSize, Endian.little);
    data.setUint32(4, blockCount, Endian.little);
    data.setUint32(8, blockSize, Endian.little);
    data.setUint32(12, offset, Endian.little);
    if (compressedBytes == 0 && uncompressedBytes > 0) {
      throw const EspError(
        type: EspErrorType.compressionError,
        message: 'Compressed payload is empty for non-empty flash write',
      );
    }
    return payload;
  }

  Uint8List _buildFlashDataPayload({
    required Uint8List payload,
    required int sequence,
  }) {
    final header = Uint8List(16 + payload.length);
    final data = ByteData.sublistView(header);
    data.setUint32(0, payload.length, Endian.little);
    data.setUint32(4, sequence, Endian.little);
    data.setUint32(8, 0, Endian.little);
    data.setUint32(12, 0, Endian.little);
    header.setRange(16, header.length, payload);
    return header;
  }

  Uint8List _u32(int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value, Endian.little);
    return bytes;
  }

  int _roundUpToBlock(int size) {
    if (size <= 0) {
      return 0;
    }
    return ((size + blockSize - 1) ~/ blockSize) * blockSize;
  }

  void _emitProgress(
    Stream<EspProgress> Function(EspProgress progress)? callback,
    EspProgress progress,
  ) {
    callback?.call(progress);
  }

  /// Computes MD5 hex string for [data].
  /// Public so callers can compute a local expected hash for comparison.
  static String md5HexOf(Uint8List data) => _md5HexStatic(data);

  /// Computes MD5 hex string for [data].  Static so it can be called from
  /// [Isolate.run] (which requires top-level or static functions).
  static String _md5HexStatic(Uint8List data) {
    final digest = _Md5().convert(data);
    final buffer = StringBuffer();
    for (final byte in digest) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _normalizeMd5Response(Uint8List raw) {
    final text = String.fromCharCodes(raw).trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(text)) {
      return text;
    }
    if (raw.length == 16) {
      final buffer = StringBuffer();
      for (final byte in raw) {
        buffer.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      return buffer.toString();
    }
    return text;
  }
}

class _Md5 {
  static const List<int> _shiftAmounts = <int>[
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
  ];

  static const List<int> _constants = <int>[
    0xd76aa478,
    0xe8c7b756,
    0x242070db,
    0xc1bdceee,
    0xf57c0faf,
    0x4787c62a,
    0xa8304613,
    0xfd469501,
    0x698098d8,
    0x8b44f7af,
    0xffff5bb1,
    0x895cd7be,
    0x6b901122,
    0xfd987193,
    0xa679438e,
    0x49b40821,
    0xf61e2562,
    0xc040b340,
    0x265e5a51,
    0xe9b6c7aa,
    0xd62f105d,
    0x02441453,
    0xd8a1e681,
    0xe7d3fbc8,
    0x21e1cde6,
    0xc33707d6,
    0xf4d50d87,
    0x455a14ed,
    0xa9e3e905,
    0xfcefa3f8,
    0x676f02d9,
    0x8d2a4c8a,
    0xfffa3942,
    0x8771f681,
    0x6d9d6122,
    0xfde5380c,
    0xa4beea44,
    0x4bdecfa9,
    0xf6bb4b60,
    0xbebfbc70,
    0x289b7ec6,
    0xeaa127fa,
    0xd4ef3085,
    0x04881d05,
    0xd9d4d039,
    0xe6db99e5,
    0x1fa27cf8,
    0xc4ac5665,
    0xf4292244,
    0x432aff97,
    0xab9423a7,
    0xfc93a039,
    0x655b59c3,
    0x8f0ccc92,
    0xffeff47d,
    0x85845dd1,
    0x6fa87e4f,
    0xfe2ce6e0,
    0xa3014314,
    0x4e0811a1,
    0xf7537e82,
    0xbd3af235,
    0x2ad7d2bb,
    0xeb86d391,
  ];

  List<int> convert(Uint8List input) {
    final messageLength = input.length;
    final bitLength = messageLength * 8;
    final paddedLength = (((messageLength + 8) >> 6) + 1) << 6;
    final buffer = Uint8List(paddedLength);
    buffer.setRange(0, input.length, input);
    buffer[input.length] = 0x80;
    final lengthData = ByteData.sublistView(buffer);
    lengthData.setUint32(
      paddedLength - 8,
      bitLength & 0xFFFFFFFF,
      Endian.little,
    );
    lengthData.setUint32(paddedLength - 4, bitLength >> 32, Endian.little);

    var a0 = 0x67452301;
    var b0 = 0xEFCDAB89;
    var c0 = 0x98BADCFE;
    var d0 = 0x10325476;

    for (var offset = 0; offset < buffer.length; offset += 64) {
      var a = a0;
      var b = b0;
      var c = c0;
      var d = d0;
      final chunk = ByteData.sublistView(buffer, offset, offset + 64);

      for (var index = 0; index < 64; index++) {
        late final int f;
        late final int g;
        if (index < 16) {
          f = (b & c) | ((~b) & d);
          g = index;
        } else if (index < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * index + 1) % 16;
        } else if (index < 48) {
          f = b ^ c ^ d;
          g = (3 * index + 5) % 16;
        } else {
          f = c ^ (b | (~d));
          g = (7 * index) % 16;
        }

        final temp = d;
        final message = chunk.getUint32(g * 4, Endian.little);
        final sum = _add32(a, f, _constants[index], message);
        d = c;
        c = b;
        b = _add32(b, _leftRotate(sum, _shiftAmounts[index]));
        a = temp;
      }

      a0 = _add32(a0, a);
      b0 = _add32(b0, b);
      c0 = _add32(c0, c);
      d0 = _add32(d0, d);
    }

    final output = Uint8List(16);
    final result = ByteData.sublistView(output);
    result.setUint32(0, a0, Endian.little);
    result.setUint32(4, b0, Endian.little);
    result.setUint32(8, c0, Endian.little);
    result.setUint32(12, d0, Endian.little);
    return output;
  }

  int _leftRotate(int value, int shift) {
    return ((value << shift) | (value >> (32 - shift))) & 0xFFFFFFFF;
  }

  int _add32(int a, int b, [int c = 0, int d = 0]) {
    return (a + b + c + d) & 0xFFFFFFFF;
  }
}
