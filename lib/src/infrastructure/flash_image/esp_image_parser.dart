// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/infrastructure/flash_image/esp_image_header.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Parses ESP boot image binaries.
class EspImageParser {
  /// Parses a binary ESP image.
  static Result<EspImageHeader> parse(Uint8List bytes) {
    try {
      if (bytes.length < 9) {
        return const Failure<EspImageHeader>(
          EspError(
            type: EspErrorType.imageParseError,
            message: 'The image is too short to contain a valid header',
          ),
        );
      }

      final data = ByteData.sublistView(bytes);
      final magic = data.getUint8(0);
      if (magic != espImageMagic) {
        return const Failure<EspImageHeader>(
          EspError(
            type: EspErrorType.imageParseError,
            message: 'The image magic value is invalid',
          ),
        );
      }

      final segmentCount = data.getUint8(1);
      final flashMode = _flashModeFromByte(data.getUint8(2));
      final flashInfo = data.getUint8(3);
      final flashSize = _flashSizeFromNibble((flashInfo >> 4) & 0x0F);
      final flashFreq = _flashFreqFromNibble(flashInfo & 0x0F);
      final entryPoint = data.getUint32(4, Endian.little);

      var offset = 8;
      var checksum = 0xEF;
      final segments = <EspImageSegment>[];

      for (var index = 0; index < segmentCount; index++) {
        if (offset + 8 > bytes.length) {
          return const Failure<EspImageHeader>(
            EspError(
              type: EspErrorType.imageParseError,
              message: 'The image ended before all segment headers were read',
            ),
          );
        }

        final loadAddress = data.getUint32(offset, Endian.little);
        final size = data.getUint32(offset + 4, Endian.little);
        offset += 8;
        if (offset + size > bytes.length) {
          return const Failure<EspImageHeader>(
            EspError(
              type: EspErrorType.imageParseError,
              message: 'The image ended before all segment data was read',
            ),
          );
        }

        final segmentBytes =
            Uint8List.fromList(bytes.sublist(offset, offset + size));
        for (final byte in segmentBytes) {
          checksum ^= byte;
        }
        segments
            .add(EspImageSegment(loadAddress: loadAddress, data: segmentBytes));
        offset += size;
      }

      if (offset >= bytes.length) {
        return const Failure<EspImageHeader>(
          EspError(
            type: EspErrorType.imageParseError,
            message: 'The image is missing its checksum byte',
          ),
        );
      }

      if ((checksum & 0xFF) != bytes[offset]) {
        return const Failure<EspImageHeader>(
          EspError(
            type: EspErrorType.checksumMismatch,
            message: 'The image checksum does not match the segment payload',
          ),
        );
      }

      return Success<EspImageHeader>(
        EspImageHeader(
          magic: magic,
          segmentCount: segmentCount,
          flashMode: flashMode,
          flashSize: flashSize,
          flashFreq: flashFreq,
          entryPoint: entryPoint,
          segments: segments,
        ),
      );
    } catch (error, stackTrace) {
      // coverage:ignore-start
      // Bounds and checksum failures are returned explicitly above. This catch
      // keeps parsing defensive against unexpected typed-data/runtime failures.
      return Failure<EspImageHeader>(
        EspError(
          type: EspErrorType.imageParseError,
          message: error.toString(),
          stackTrace: stackTrace,
        ),
      );
      // coverage:ignore-end
    }
  }

  static FlashMode _flashModeFromByte(int value) {
    return switch (value) {
      0 => FlashMode.qio,
      1 => FlashMode.qout,
      2 => FlashMode.dio,
      3 => FlashMode.dout,
      _ => FlashMode.dio,
    };
  }

  static FlashSize _flashSizeFromNibble(int value) {
    return switch (value) {
      0 => FlashSize.s1mb,
      1 => FlashSize.s2mb,
      2 => FlashSize.s4mb,
      3 => FlashSize.s8mb,
      4 => FlashSize.s16mb,
      _ => FlashSize.s4mb,
    };
  }

  static FlashFreq _flashFreqFromNibble(int value) {
    return switch (value) {
      0 => FlashFreq.f40m,
      1 => FlashFreq.f26m,
      2 => FlashFreq.f20m,
      0x0F => FlashFreq.f80m,
      _ => FlashFreq.f40m,
    };
  }
}
