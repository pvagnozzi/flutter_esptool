// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/infrastructure/flash_image/esp_image_header.dart';
import 'package:flutter_esptool/src/infrastructure/flash_image/esp_image_parser.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EspImageParser', () {
    test('parses a minimal valid image', () {
      final image = _buildValidImage();
      final result = EspImageParser.parse(image);

      expect(result, isA<Success<EspImageHeader>>());
      final header = (result as Success<EspImageHeader>).value;
      expect(header.magic, espImageMagic);
      expect(header.segmentCount, 1);
      expect(header.entryPoint, 0x40100000);
      expect(header.segments.single.loadAddress, 0x3FFE0000);
      expect(header.segments.single.data, <int>[0x01, 0x02, 0x03, 0x04]);
    });

    test('returns failure for bad magic', () {
      final image = _buildValidImage();
      image[0] = 0x00;
      final result = EspImageParser.parse(image);

      expect(result, isA<Failure<EspImageHeader>>());
      expect((result as Failure<EspImageHeader>).error.type,
          EspErrorType.imageParseError);
    });

    test('returns failure for truncated data', () {
      final image = Uint8List.fromList(_buildValidImage().sublist(0, 10));
      final result = EspImageParser.parse(image);

      expect(result, isA<Failure<EspImageHeader>>());
    });

    test('returns failure for checksum mismatch', () {
      final image = _buildValidImage();
      image[image.length - 1] ^= 0xFF;
      final result = EspImageParser.parse(image);

      expect(result, isA<Failure<EspImageHeader>>());
      expect((result as Failure<EspImageHeader>).error.type,
          EspErrorType.checksumMismatch);
    });
  });
}

Uint8List _buildValidImage() {
  final segmentData = Uint8List.fromList(<int>[0x01, 0x02, 0x03, 0x04]);
  var checksum = 0xEF;
  for (final byte in segmentData) {
    checksum ^= byte;
  }

  return Uint8List.fromList(<int>[
    0xE9,
    0x01,
    0x02,
    0x20,
    0x00,
    0x00,
    0x10,
    0x40,
    0x00,
    0x00,
    0xFE,
    0x3F,
    0x04,
    0x00,
    0x00,
    0x00,
    ...segmentData,
    checksum & 0xFF,
  ]);
}
