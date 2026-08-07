// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/infrastructure/compression/zlib_helper.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sample =
      Uint8List.fromList(List<int>.generate(1024, (i) => (i * 7) & 0xFF));

  group('ZlibHelper (sync)', () {
    test('compress → decompress round-trips', () {
      final compressed = ZlibHelper.compress(sample);
      expect(compressed.isSuccess, isTrue);
      final bytes = (compressed as Success<Uint8List>).value;

      final restored = ZlibHelper.decompress(bytes);
      expect(restored.isSuccess, isTrue);
      expect((restored as Success<Uint8List>).value, sample);
    });

    test('decompress fails on invalid input', () {
      final result = ZlibHelper.decompress(
        Uint8List.fromList(<int>[0, 1, 2, 3, 4, 5]),
      );
      expect(result.isFailure, isTrue);
    });
  });

  group('ZlibHelper (async)', () {
    test('compressAsync → decompressAsync round-trips', () async {
      final compressed = await ZlibHelper.compressAsync(sample);
      final bytes = (compressed as Success<Uint8List>).value;

      final restored = await ZlibHelper.decompressAsync(bytes);
      expect(restored.isSuccess, isTrue);
      expect((restored as Success<Uint8List>).value, sample);
    });

    test('decompressAsync fails on invalid input', () async {
      final result = await ZlibHelper.decompressAsync(
        Uint8List.fromList(<int>[9, 9, 9, 9]),
      );
      expect(result.isFailure, isTrue);
    });
  });
}
