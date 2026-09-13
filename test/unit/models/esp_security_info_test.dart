// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EspSecurityInfo', () {
    EspSecurityInfo make({int flags = 0, int flashCryptCnt = 0}) =>
        EspSecurityInfo(
          flags: flags,
          flashCryptCnt: flashCryptCnt,
          keyPurposes: const <int>[0, 0, 0, 0, 0, 0, 0],
          chipId: 0x1234,
          apiVersion: 2,
        );

    test('flashEncryptionEnabled is true for odd popcount of low 3 bits', () {
      expect(make(flashCryptCnt: 0x01).flashEncryptionEnabled, isTrue); // 1 bit
      expect(make(flashCryptCnt: 0x07).flashEncryptionEnabled, isTrue); // 3 bits
      expect(make(flashCryptCnt: 0x02).flashEncryptionEnabled, isTrue); // 1 bit
    });

    test('flashEncryptionEnabled is false for even popcount', () {
      expect(make(flashCryptCnt: 0x00).flashEncryptionEnabled, isFalse); // 0
      expect(make(flashCryptCnt: 0x03).flashEncryptionEnabled, isFalse); // 2
      // Bits above the low 3 are ignored.
      expect(make(flashCryptCnt: 0xF8).flashEncryptionEnabled, isFalse);
    });

    test('secureBootEnabled reflects flags bit 0', () {
      expect(make(flags: 0x01).secureBootEnabled, isTrue);
      expect(make(flags: 0x00).secureBootEnabled, isFalse);
      expect(make(flags: 0x02).secureBootEnabled, isFalse);
    });

    test('toString includes the decoded fields', () {
      final s = make(flags: 0x01, flashCryptCnt: 0x01).toString();
      expect(s, contains('flashEncryptionEnabled=true'));
      expect(s, contains('secureBootEnabled=true'));
      expect(s, contains('chipId=0x1234'));
      expect(s, contains('apiVersion=2'));
    });
  });
}
