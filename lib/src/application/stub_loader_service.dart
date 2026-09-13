// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_esptool/src/domain/stub/stub_loader_interface.dart';
import 'package:flutter_esptool/src/models/esp_chip_info.dart';
import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';

void _d(String msg) {
  // ignore: avoid_print
  print('${DateTime.now().toIso8601String()} [StubLoader] $msg');
}

// ---------------------------------------------------------------------------
// ESP32-S3 stub flasher binary (embedded as base64).
//
// Source: esptool/targets/stub_flasher/1/esp32s3.json
// from the esptool Python package (MIT-licensed).
//
// text_start = 0x40378000   text length = 5292 bytes
// data_start = 0x3FCB2BFC   data length = 252 bytes
// entry      = 0x40378A80
// ---------------------------------------------------------------------------
const _esp32s3TextB64 =
    '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';

const _esp32s3DataB64 =
    'XADKP16ON0AzjzdAR5Q3QL2PN0BTjzdAvY83QB2QN0A6kTdArJE3QFWRN0DpjTdA0JA3QCyRN0BA'
    'kDdA0JE3QGiQN0DQkTdAIY83QH6PN0C9jzdAHZA3QDmPN0AqjjdAkJI3QA2UN0AAjTdALZQ3QACN'
    'N0AAjTdAAI03QACNN0AAjTdAAI03QACNN0AAjTdAKpI3QACNN0AlkzdADZQ3QAQInwAAAAAAAAAY'
    'AQQIBQAAAAAAAAAIAQQIBgAAAAAAAAAAAQQIIQAAAAAAIAAAEQQI3AAAAAAAIAAAEQQIDAAAAAAA'
    'IAAAAQQIEgAAAAAAIAAAESAoDAAQAQAA';

const _esp32s3TextStart = 0x40378000;
const _esp32s3DataStart = 0x3FCB2BFC;
const _esp32s3Entry = 0x40378A80;

// Block size used for MEM_DATA packets (matches esptool default).
const _memBlockSize = 0x1800; // 6144 bytes

// ---------------------------------------------------------------------------
// ESP32-S3 register addresses (from esptool/targets/esp32s3.py)
// ---------------------------------------------------------------------------
// UARTDEV_BUF_NO: ROM .bss variable — indicates which console port is active.
// Value 4 = USB-JTAG/Serial (our device).
const _uartdevBufNo = 0x3FCEF14C;
const _uartdevBufNoUsbJtagSerial = 4;

// RTC WDT registers
const _rtcCntlBase = 0x60008000;
const _rtcCntlWdtConfig0Reg = _rtcCntlBase + 0x0098;
const _rtcCntlWdtWprotectReg = _rtcCntlBase + 0x00B0;
const _rtcCntlWdtWkey = 0x50D83AA1;

// Super WDT (SWD) registers
const _rtcCntlSwdConfReg = _rtcCntlBase + 0x00B4;
const _rtcCntlSwdAutoFeedEn = 1 << 31;
const _rtcCntlSwdWprotectReg = _rtcCntlBase + 0x00B8;
const _rtcCntlSwdWkey = 0x8F1D312A;

/// Loads the ESP32-S3 flasher stub into device RAM via MEM_BEGIN/MEM_DATA/MEM_END.
///
/// Once loaded, the stub takes over from the ROM bootloader and enables
/// stub-only commands such as eraseFlash (0xD0), eraseRegion (0xD1), and
/// flashMd5 (0x13).
class StubLoaderService implements StubLoaderInterface {
  /// Creates a [StubLoaderService] bound to [transport].
  StubLoaderService({required EspTransportInterface transport})
      : _transport = transport;

  final EspTransportInterface _transport;
  bool _loaded = false;

  @override
  bool get isLoaded => _loaded;

  @override
  Future<Result<void>> loadStub(ChipFamily family) async {
    if (family != ChipFamily.esp32s3) {
      return Failure<void>(
        EspError(
          type: EspErrorType.stubNotAvailable,
          message: 'Stub is only available for ESP32-S3 (got $family)',
        ),
      );
    }

    try {
      _loaded = false;

      // -----------------------------------------------------------------------
      // Step 1: Disable watchdogs (critical for USB-JTAG/Serial).
      //
      // When the device is connected via USB-JTAG/Serial, the RTC WDT and the
      // Super WDT (SWD) are NOT reset between ROM commands and will fire and
      // reset the chip during stub execution if not disabled first.
      //
      // esptool does this in _post_connect() → disable_watchdogs() before any
      // stub upload attempt.
      // -----------------------------------------------------------------------
      await _disableWatchdogsIfUsbJtag();

      final text = base64.decode(_esp32s3TextB64);
      final data = base64.decode(_esp32s3DataB64);

      _d('Uploading stub: text=${text.length}B @ 0x${_esp32s3TextStart.toRadixString(16)}'
          '  data=${data.length}B @ 0x${_esp32s3DataStart.toRadixString(16)}'
          '  entry=0x${_esp32s3Entry.toRadixString(16)}');

      // -----------------------------------------------------------------------
      // Step 2: Upload text segment (MEM_BEGIN + MEM_DATA only, no MEM_END yet).
      // -----------------------------------------------------------------------
      final textResult = await _uploadSegmentBlocks(
        data: text,
        loadAddr: _esp32s3TextStart,
      );
      if (textResult is Failure<void>) return textResult;

      // -----------------------------------------------------------------------
      // Step 3: Upload data segment (MEM_BEGIN + MEM_DATA only, no MEM_END yet).
      // -----------------------------------------------------------------------
      final dataResult = await _uploadSegmentBlocks(
        data: data,
        loadAddr: _esp32s3DataStart,
      );
      if (dataResult is Failure<void>) return dataResult;

      // -----------------------------------------------------------------------
      // Step 4: Send MEM_END to jump to the stub entry point.
      //
      // MEM_END payload encoding (esptool convention):
      //   field[0] = int(entryPoint == 0)  → 0 = jump, 1 = no-jump/reboot
      //   field[1] = entryPoint
      //
      // esptool uses check_command() with MEM_END_ROM_TIMEOUT = 0.2 s and
      // swallows FatalError (i.e. ignores timeout) for the ROM loader case,
      // because the ROM may reset the UART / change baud before the TX FIFO
      // drains.  We do the same: send via sendCommand() with a 300 ms timeout
      // and ignore any failure — the ROM jumps regardless.
      // -----------------------------------------------------------------------
      final endPayload = Uint8List(8);
      final endBd = ByteData.sublistView(endPayload);
      endBd.setUint32(0, 0, Endian.little); // 0 = jump to entryPoint
      endBd.setUint32(4, _esp32s3Entry, Endian.little);

      _d(
        'MEM_END (jump to stub): entry=0x${_esp32s3Entry.toRadixString(16)}',
      );

      // Send MEM_END without prior flushRx so any bytes that arrive between
      // the last MEM_DATA ACK and the MEM_END are not discarded.
      try {
        await _transport.sendCommand(
          EspCommand(
            opcode: EspCommandOpcode.memEnd,
            data: endPayload,
            checksum: 0,
          ),
          timeout: const Duration(milliseconds: 300),
        );
        _d('MEM_END ACK received from ROM');
      } catch (_) {
        // Swallow — the ROM jumps to stub and may not finish its ACK before
        // reinitialising the transport.  This matches esptool behaviour.
        _d('MEM_END timed out or errored (expected for ROM loader) — continuing');
      }

      // -----------------------------------------------------------------------
      // Step 5: Read stub OHAI greeting.
      //
      // esptool does NOT close/reopen the port after mem_finish for USB JTAG.
      // The USB CDC port does NOT re-enumerate when the stub starts on
      // ESP32-S3 — the stub inherits the USB peripheral state from the ROM.
      //
      // The stub sends OHAI as a SLIP-framed packet:
      //   c0  4f 48 41 49  c0   (6 bytes)
      //
      // The stub requires ~300 ms to boot and flush the USB TX FIFO before
      // the OHAI bytes appear in the kernel's RX buffer.  We wait 300 ms,
      // then poll readRaw for up to 5 s total.
      // -----------------------------------------------------------------------
      _d('Waiting 300 ms for stub to boot, then reading OHAI...');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final ohaiResult = await _readOhai(
        timeout: const Duration(seconds: 5),
      );
      if (ohaiResult is Failure<void>) return ohaiResult;

      // Flush any trailing bytes from the greeting before resuming SLIP comms.
      await _transport.flushRx();

      _loaded = true;
      _d('Stub loaded successfully');
      return const Success<void>(null);
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.stubNotAvailable,
              message: 'Stub upload failed: $error',
              stackTrace: stackTrace,
            );
      return Failure<void>(espError);
    }
  }

  // ---------------------------------------------------------------------------
  // Watchdog helpers
  // ---------------------------------------------------------------------------

  /// Reads UARTDEV_BUF_NO to check if connected via USB-JTAG/Serial.
  /// If so, disables the RTC WDT and puts the SWD into auto-feed mode.
  Future<void> _disableWatchdogsIfUsbJtag() async {
    _d('Checking UARTDEV_BUF_NO for USB-JTAG/Serial detection...');
    try {
      final uartNo = await _readReg(_uartdevBufNo);
      _d('UARTDEV_BUF_NO = $uartNo');
      if (uartNo != _uartdevBufNoUsbJtagSerial) {
        _d('Not USB-JTAG/Serial — watchdog disable skipped');
        return;
      }
      _d('USB-JTAG/Serial detected — disabling RTC WDT and SWD');

      // Disable RTC WDT:
      //   1. Unlock write-protect register with the WDT key.
      //   2. Write 0 to WDTCONFIG0 (disables the WDT).
      //   3. Re-lock the write-protect register.
      await _writeReg(_rtcCntlWdtWprotectReg, _rtcCntlWdtWkey);
      await _writeReg(_rtcCntlWdtConfig0Reg, 0);
      await _writeReg(_rtcCntlWdtWprotectReg, 0);
      _d('RTC WDT disabled');

      // Enable SWD auto-feed so the Super WDT never expires:
      //   1. Unlock SWD write-protect register.
      //   2. Set SWD_AUTO_FEED_EN bit in SWD_CONF.
      //   3. Re-lock.
      await _writeReg(_rtcCntlSwdWprotectReg, _rtcCntlSwdWkey);
      final swdConf = await _readReg(_rtcCntlSwdConfReg);
      await _writeReg(_rtcCntlSwdConfReg, swdConf | _rtcCntlSwdAutoFeedEn);
      await _writeReg(_rtcCntlSwdWprotectReg, 0);
      _d('SWD auto-feed enabled');
    } catch (e) {
      // Non-fatal: if we can't disable watchdogs log a warning and proceed.
      // On some ROM versions the read may be unsupported.
      _d('WARNING: Could not disable watchdogs: $e — proceeding anyway');
    }
  }

  /// Reads a 32-bit register from the device.
  Future<int> _readReg(int address) async {
    final payload = Uint8List(4);
    ByteData.sublistView(payload).setUint32(0, address, Endian.little);
    final resp = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.readReg, data: payload),
      timeout: const Duration(seconds: 3),
    );
    if (!resp.isSuccess) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message: 'readReg(0x${address.toRadixString(16)}) failed: '
            'status=${resp.status} error=${resp.error}',
      );
    }
    return resp.value;
  }

  /// Writes a 32-bit value to a device register (mask=0xFFFFFFFF, delay=0).
  Future<void> _writeReg(int address, int value) async {
    final payload = Uint8List(16);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, address, Endian.little);
    bd.setUint32(4, value, Endian.little);
    bd.setUint32(8, 0xFFFFFFFF, Endian.little); // mask: write all bits
    bd.setUint32(12, 0, Endian.little); // delay_us
    final resp = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.writeReg, data: payload),
      timeout: const Duration(seconds: 3),
    );
    if (!resp.isSuccess) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message: 'writeReg(0x${address.toRadixString(16)}, '
            '0x${value.toRadixString(16)}) failed: '
            'status=${resp.status} error=${resp.error}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // OHAI reader
  // ---------------------------------------------------------------------------

  /// Reads raw bytes from the transport until the OHAI SLIP frame is found,
  /// or [timeout] expires.
  ///
  /// The stub sends OHAI as a SLIP-framed packet:
  ///   \xC0  O H A I  \xC0   (6 bytes)
  ///
  /// We look for the inner 4-byte sequence [4F 48 41 49] inside whatever raw
  /// bytes we receive.  The preceding \xC0 may be merged with the ROM ACK
  /// trailing \xC0 in the hardware FIFO.
  Future<Result<void>> _readOhai({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    final accumulated = <int>[];
    const ohaiBytes = [0x4F, 0x48, 0x41, 0x49]; // O H A I

    var iteration = 0;
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      iteration++;

      final readTimeout = remaining > const Duration(milliseconds: 500)
          ? const Duration(milliseconds: 500)
          : remaining;

      _d('OHAI poll #$iteration (${remaining.inMilliseconds}ms left,'
          ' accumulated=${accumulated.length}B)');

      final chunk = await _transport.readRaw(
        64,
        timeout: readTimeout,
      );

      if (chunk.isNotEmpty) {
        accumulated.addAll(chunk);
        _d(
          'OHAI read chunk (${chunk.length}B): '
          '${chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
        );

        // Search for OHAI in accumulated buffer.
        for (var i = 0; i <= accumulated.length - 4; i++) {
          if (accumulated[i] == ohaiBytes[0] &&
              accumulated[i + 1] == ohaiBytes[1] &&
              accumulated[i + 2] == ohaiBytes[2] &&
              accumulated[i + 3] == ohaiBytes[3]) {
            _d('OHAI found at offset $i in accumulated buffer — stub is running');
            return const Success<void>(null);
          }
        }
      } else {
        _d('OHAI poll #$iteration: readRaw returned 0 bytes');
      }

      // Small sleep between read attempts to avoid tight-spin.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final hex =
        accumulated.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return Failure<void>(
      EspError(
        type: EspErrorType.stubNotAvailable,
        message: 'Stub OHAI greeting not found after ${timeout.inSeconds}s '
            '(received ${accumulated.length} bytes: $hex)',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Segment upload
  // ---------------------------------------------------------------------------

  /// Uploads one segment using MEM_BEGIN → MEM_DATA blocks.
  ///
  /// Does NOT send MEM_END — the caller is responsible for sending the single
  /// final MEM_END (with the stub entry point) after all segments are uploaded.
  Future<Result<void>> _uploadSegmentBlocks({
    required Uint8List data,
    required int loadAddr,
  }) async {
    final numBlocks = (data.length + _memBlockSize - 1) ~/ _memBlockSize;
    _d('MEM_BEGIN: size=${data.length} blocks=$numBlocks'
        ' blockSize=$_memBlockSize addr=0x${loadAddr.toRadixString(16)}');

    // MEM_BEGIN payload: [size, numBlocks, blockSize, offset] (4×uint32 LE)
    final beginPayload = Uint8List(16);
    final beginData = ByteData.sublistView(beginPayload);
    beginData.setUint32(0, data.length, Endian.little);
    beginData.setUint32(4, numBlocks, Endian.little);
    beginData.setUint32(8, _memBlockSize, Endian.little);
    beginData.setUint32(12, loadAddr, Endian.little);

    final beginResp = await _transport.sendCommand(
      EspCommand(
        opcode: EspCommandOpcode.memBegin,
        data: beginPayload,
        checksum: 0,
      ),
      timeout: const Duration(seconds: 5),
    );
    if (!beginResp.isSuccess) {
      return Failure<void>(
        EspError(
          type: EspErrorType.stubNotAvailable,
          message:
              'MEM_BEGIN rejected by device (status=${beginResp.status} error=${beginResp.error})',
        ),
      );
    }

    // Send MEM_DATA blocks.
    for (var seq = 0; seq < numBlocks; seq++) {
      final start = seq * _memBlockSize;
      final end = (start + _memBlockSize).clamp(0, data.length);
      // Send only the actual bytes — no padding. esptool sends exactly
      // len(chunk) bytes and the ROM copies exactly that many into RAM.
      // Padding with 0xFF would corrupt memory past the segment boundary.
      final chunk = data.sublist(start, end);

      // MEM_DATA payload: 16-byte header + actual chunk bytes
      //   [dataLen, seq, 0, 0, ...data]
      final payload = Uint8List(16 + chunk.length);
      final pd = ByteData.sublistView(payload);
      pd.setUint32(0, chunk.length, Endian.little);
      pd.setUint32(4, seq, Endian.little);
      pd.setUint32(8, 0, Endian.little);
      pd.setUint32(12, 0, Endian.little);
      payload.setRange(16, payload.length, chunk);

      _d('MEM_DATA seq=$seq size=${chunk.length}');
      final dataResp = await _transport.sendCommand(
        EspCommand(
          opcode: EspCommandOpcode.memData,
          data: payload,
          checksum: EspCommand.calculateChecksum(chunk),
        ),
        timeout: const Duration(seconds: 5),
      );
      if (!dataResp.isSuccess) {
        return Failure<void>(
          EspError(
            type: EspErrorType.stubNotAvailable,
            message:
                'MEM_DATA seq=$seq rejected (status=${dataResp.status} error=${dataResp.error})',
          ),
        );
      }
    }

    return const Success<void>(null);
  }
}
