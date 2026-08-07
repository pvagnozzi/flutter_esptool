// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/infrastructure/efuse/reed_solomon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReedSolomon12', () {
    final rs = ReedSolomon12();

    test('matches espefuse golden parity for 0x00..0x1f', () {
      final data = List<int>.generate(32, (i) => i);
      final parity = rs.computeParity(data);
      // Captured from `espefuse --virt --chip esp32s3 burn_key BLOCK_KEY1`
      // for the input 00 01 .. 1f (CHECK_VALUE regs, little-endian words
      // 0x0d474ca0 0x03b2fc3f 0x13f4e9da).
      expect(
        parity,
        equals(<int>[
          0xa0, 0x4c, 0x47, 0x0d, //
          0x3f, 0xfc, 0xb2, 0x03, //
          0xda, 0xe9, 0xf4, 0x13, //
        ]),
      );
    });

    test('encode appends parity producing a 44-byte codeword', () {
      final data = List<int>.generate(32, (i) => i);
      final codeword = rs.encode(data);
      expect(codeword.length, 44);
      expect(codeword.sublist(0, 32), equals(data));
    });

    test('all-zero block yields all-zero parity', () {
      final parity = rs.computeParity(List<int>.filled(32, 0));
      expect(parity, equals(Uint8List(12)));
    });

    test('parity is deterministic', () {
      final data = List<int>.generate(32, (i) => (i * 7 + 3) & 0xFF);
      expect(rs.computeParity(data), equals(rs.computeParity(data)));
    });
  });
}
