// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

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

/// Performs flash erase, write, read, and verify operations.
class FlashService implements FlashServiceInterface {
  /// Creates a [FlashService].
  FlashService({
    required EspTransportInterface transport,
    StubLoaderInterface? stubLoader,
    this.blockSize = 0x4000,
  }) : _transport = transport;

  final EspTransportInterface _transport;

  /// The flash block size used for chunked writes.
  final int blockSize;

  @override
  Future<Result<void>> writeFlash(FlashParameters params) async {
    try {
      final paddedData = FlashImageBuilder.buildPaddedImage(
        params.data,
        alignment: blockSize,
      );
      final blocks = FlashImageBuilder.splitIntoBlocks(
        paddedData,
        params.offset,
        blockSize,
      );
      final dataBlocks = <Uint8List>[
        for (final block in blocks)
          params.compress
              ? _compressOrThrow(block.data)
              : Uint8List.fromList(block.data),
      ];
      final compressedTotalBytes =
          dataBlocks.fold<int>(0, (total, block) => total + block.length);
      final beginResponse = await _transport.sendCommand(
        EspCommand(
          opcode: params.compress
              ? EspCommandOpcode.flashDeflBegin
              : EspCommandOpcode.flashBegin,
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
      }

      // Give the device a moment to settle after the last data block
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final endResponse = await _transport.sendCommand(
        EspCommand(
          opcode: params.compress
              ? EspCommandOpcode.flashDeflEnd
              : EspCommandOpcode.flashEnd,
          data: _u32(0),
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

      if (params.verify) {
        final actualResult = await md5Flash(params.offset, params.data.length);
        if (actualResult is Failure<String>) {
          return Failure<void>(actualResult.error);
        }
        final expected = _md5Hex(params.data);
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

  @override
  Future<Result<Uint8List>> readFlash(FlashReadParameters params) async {
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

  Future<void> _configureSpiFlashForRomRead() async {
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
    final response = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.spiSetParams, data: payload),
    );
    if (!response.isSuccess) {
      throw const EspError(
        type: EspErrorType.flashReadFailed,
        message: 'The device rejected SPI flash read parameters',
      );
    }
  }

  @override
  Future<Result<void>> eraseFlash({int? offset, int? size}) async {
    try {
      final EspCommand command;
      final Duration timeout;
      if (offset == null && size == null) {
        command = EspCommand(opcode: EspCommandOpcode.eraseFlash);
        timeout = const Duration(seconds: 120);
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
        command =
            EspCommand(opcode: EspCommandOpcode.eraseRegion, data: payload);
        final seconds = (30 * (size / (1024 * 1024))).ceil().clamp(3, 120);
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
  Future<Result<String>> md5Flash(int offset, int size) async {
    try {
      final payload = Uint8List(16);
      final data = ByteData.sublistView(payload);
      data.setUint32(0, offset, Endian.little);
      data.setUint32(4, size, Endian.little);
      final response = await _transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.flashMd5, data: payload),
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
  }) {
    final eraseSize = _roundUpToBlock(totalBytes);
    final payload = Uint8List(16);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, eraseSize, Endian.little);
    data.setUint32(4, blockCount, Endian.little);
    data.setUint32(8, blockSize, Endian.little);
    data.setUint32(12, offset, Endian.little);
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

  Uint8List _compressOrThrow(Uint8List data) {
    final result = ZlibHelper.compress(data);
    return result.fold((value) => value, (error) => throw error);
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

  String _md5Hex(Uint8List data) {
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
        paddedLength - 8, bitLength & 0xFFFFFFFF, Endian.little);
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
