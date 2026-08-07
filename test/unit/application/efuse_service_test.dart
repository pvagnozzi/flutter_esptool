// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  group('EfuseService.keyBlockWords', () {
    test('matches espefuse golden register words for 0x00..0x1f', () {
      final digest = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final words = EfuseService.keyBlockWords(digest);

      // Captured from `espefuse --virt --chip esp32s3 burn_key BLOCK_KEY1`:
      //   PGM_DATA0..7  = 03020100 07060504 0b0a0908 0f0e0d0c
      //                   13121110 17161514 1b1a1918 1f1e1d1c
      //   CHECK_VALUE0..2 = 0d474ca0 03b2fc3f 13f4e9da
      expect(words, <int>[
        0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c, //
        0x13121110, 0x17161514, 0x1b1a1918, 0x1f1e1d1c, //
        0x0d474ca0, 0x03b2fc3f, 0x13f4e9da, //
      ]);
    });

    test('produces 11 words (8 data + 3 RS)', () {
      final digest = Uint8List(32);
      expect(EfuseService.keyBlockWords(digest).length, 11);
    });

    test('rejects a digest that is not 32 bytes', () {
      expect(
        () => EfuseService.keyBlockWords(Uint8List(31)),
        throwsArgumentError,
      );
    });
  });

  group('EfuseService.flashEncryptionLockBlock0', () {
    test('sets KEY_PURPOSE_0=XTS_AES_128, WR_DIS and RD_DIS by default', () {
      final block0 = EfuseService.flashEncryptionLockBlock0();
      expect(block0.length, 8);
      // word2: KEY_PURPOSE_0 = 4 << 24
      expect(block0[2], 0x04 << 24);
      // word0: WR_DIS bit 8 (KEY_PURPOSE_0) | bit 23 (BLOCK_KEY0)
      expect(block0[0], (1 << 8) | (1 << 23));
      // word1: RD_DIS bit 0 (BLOCK_KEY0)
      expect(block0[1], 1 << 0);
      // no other words set
      expect(block0[3], 0);
      expect(block0.sublist(4), everyElement(0));
    });

    test('omits RD_DIS when readProtect is false', () {
      final block0 = EfuseService.flashEncryptionLockBlock0(readProtect: false);
      expect(block0[1], 0); // RD_DIS word untouched
      expect(block0[2], 0x04 << 24); // purpose still set
      expect(block0[0], (1 << 8) | (1 << 23)); // WR_DIS still set
    });

    test('key purpose constants match ESP32-S3 values', () {
      expect(EfuseService.keyPurposeXtsAes128, 4);
      expect(EfuseService.keyPurposeSecureBootDigest0, 9);
      expect(EfuseService.blockKey0, 4);
      expect(EfuseService.blockKey1, 5);
    });
  });

  group('EfuseService – transport-backed operations', () {
    final digest = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('burnSecureBootKeyDigest programs BLOCK_KEY1 then BLOCK0', () async {
      final transport = FakeTransport(); // all reads return 0 → idle
      final service = EfuseService(transport: transport);

      final result = await service.burnSecureBootKeyDigest(digest);

      expect(result.isSuccess, isTrue);
      // Two _programBlock passes issue many WRITE_REG commands.
      final writes = transport.sentCommands
          .where((c) => c.opcode == EspCommandOpcode.writeReg)
          .length;
      expect(writes, greaterThan(20));
    });

    test('burnSecureBootKeyDigest rejects a non-32-byte digest', () async {
      final service = EfuseService(transport: FakeTransport());
      final result = await service.burnSecureBootKeyDigest(Uint8List(16));
      expect(result.isFailure, isTrue);
      expect(
        (result as Failure<void>).error.type,
        EspErrorType.unsupportedOperation,
      );
    });

    test('burnSecureBootKeyDigest surfaces a transport failure', () async {
      final transport = FakeTransport(failOpcodes: {EspCommandOpcode.writeReg});
      final service = EfuseService(transport: transport);
      final result = await service.burnSecureBootKeyDigest(digest);
      expect(result.isFailure, isTrue);
      expect(
        (result as Failure<void>).error.type,
        EspErrorType.invalidResponse,
      );
    });

    test('enableSecureBoot burns SECURE_BOOT_EN', () async {
      final transport = FakeTransport();
      final service = EfuseService(transport: transport);
      final result = await service.enableSecureBoot();
      expect(result.isSuccess, isTrue);
      expect(
        transport.sentCommands
            .any((c) => c.opcode == EspCommandOpcode.writeReg),
        isTrue,
      );
    });

    test('enableSecureBoot reports a write failure', () async {
      final service = EfuseService(
        transport: FakeTransport(failOpcodes: {EspCommandOpcode.writeReg}),
      );
      expect((await service.enableSecureBoot()).isFailure, isTrue);
    });

    test('burnFlashEncryptionKeyData validates key length', () async {
      final service = EfuseService(transport: FakeTransport());
      expect(
        (await service.burnFlashEncryptionKeyData(Uint8List(10))).isFailure,
        isTrue,
      );
      expect(
        (await service.burnFlashEncryptionKeyData(digest)).isSuccess,
        isTrue,
      );
    });

    test('lockFlashEncryptionKey with and without read protection', () async {
      final service = EfuseService(transport: FakeTransport());
      expect((await service.lockFlashEncryptionKey()).isSuccess, isTrue);
      expect(
        (await service.lockFlashEncryptionKey(readProtect: false)).isSuccess,
        isTrue,
      );
    });

    test('lockFlashEncryptionKey reports a write failure', () async {
      final service = EfuseService(
        transport: FakeTransport(failOpcodes: {EspCommandOpcode.writeReg}),
      );
      expect((await service.lockFlashEncryptionKey()).isFailure, isTrue);
    });

    test('readSecureBootKeyDigest reconstructs 32 bytes from 8 words', () async {
      // 8 words, each 0x03020100 + i pattern → predictable little-endian bytes.
      final words = List<int>.generate(8, (i) => 0x04030201 * (i + 1) & 0xFFFFFFFF);
      final transport = FakeTransport(readRegValues: words);
      final service = EfuseService(transport: transport);

      final result = await service.readSecureBootKeyDigest();
      expect(result.isSuccess, isTrue);
      final bytes = (result as Success<Uint8List>).value;
      expect(bytes.length, 32);
      // First word 0x04030201 → little-endian bytes 01 02 03 04.
      expect(bytes.sublist(0, 4), <int>[0x01, 0x02, 0x03, 0x04]);
    });

    test('readSecureBootKeyDigest reports a read failure', () async {
      final service = EfuseService(
        transport: FakeTransport(failOpcodes: {EspCommandOpcode.readReg}),
      );
      expect((await service.readSecureBootKeyDigest()).isFailure, isTrue);
    });

    test('readFlashEncryptionKey returns 32 bytes', () async {
      final service = EfuseService(
        transport: FakeTransport(readRegValues: List<int>.filled(8, 0xDEADBEEF)),
      );
      final result = await service.readFlashEncryptionKey();
      expect((result as Success<Uint8List>).value.length, 32);
    });

    test('readFlashEncryptionKey reports a read failure', () async {
      final service = EfuseService(
        transport: FakeTransport(failOpcodes: {EspCommandOpcode.readReg}),
      );
      expect((await service.readFlashEncryptionKey()).isFailure, isTrue);
    });

    test('readProvisioningState decodes BLOCK0 fields', () async {
      // Command-register reads (for _waitEfuseIdle) must be 0 (idle). The four
      // provisioning reads happen after; use onCommand to shape them precisely.
      var readCount = 0;
      final transport = FakeTransport(
        onCommand: (command) {
          if (command.opcode == EspCommandOpcode.writeReg) {
            return okResponse(command.opcode);
          }
          // readReg
          readCount++;
          // The read sequence during readProvisioningState:
          //   _triggerEfuseRead → _waitEfuseIdle reads cmd (idle=0)
          //   then w0,w1,w2,w3.
          // Return 0 for idle polls; shape the last 4 as provisioning words.
          // Simplest: encode via value based on the register address.
          final addr = ByteData.sublistView(command.data).getUint32(0, Endian.little);
          const rdBlock0Base = 0x60007000 + 0x02C;
          if (addr == rdBlock0Base) {
            return okResponse(command.opcode, value: (1 << 23) | (1 << 8));
          } else if (addr == rdBlock0Base + 4) {
            return okResponse(command.opcode, value: 0x01);
          } else if (addr == rdBlock0Base + 8) {
            return okResponse(command.opcode,
                value: (4 << 24) | (9 << 28) | (1 << 18));
          } else if (addr == rdBlock0Base + 12) {
            return okResponse(command.opcode, value: 1 << 20);
          }
          return okResponse(command.opcode); // idle poll = 0
        },
      );
      final service = EfuseService(transport: transport);

      final result = await service.readProvisioningState();
      expect(result.isSuccess, isTrue);
      final state = (result as Success<EfuseProvisioningState>).value;
      expect(state.keyPurpose0, 4);
      expect(state.keyPurpose1, 9);
      expect(state.flashKeyPurposeSet, isTrue);
      expect(state.flashKeyWriteProtected, isTrue);
      expect(state.flashKeyReadProtected, isTrue);
      expect(state.flashKeyLocked, isTrue);
      expect(state.digestBurned, isTrue);
      expect(state.secureBootEnabled, isTrue);
      expect(state.flashEncryptionActive, isTrue); // cryptCnt=1 → odd
      expect(readCount, greaterThan(4));
      expect(state.toString(), contains('keyPurpose0=4'));
    });

    test('readProvisioningState reports a read failure', () async {
      final service = EfuseService(
        transport: FakeTransport(failOpcodes: {EspCommandOpcode.readReg}),
      );
      expect((await service.readProvisioningState()).isFailure, isTrue);
    });

    test('_waitEfuseIdle times out when controller never goes idle', () async {
      // cmd register always reports a pending bit → wait loop exhausts and the
      // operation fails.
      final transport = FakeTransport(
        onCommand: (command) {
          if (command.opcode == EspCommandOpcode.readReg) {
            return okResponse(command.opcode, value: 0x2); // PGM pending forever
          }
          return okResponse(command.opcode);
        },
      );
      final service = EfuseService(transport: transport);
      final result = await service.enableSecureBoot();
      expect(result.isFailure, isTrue);
    });
  });
}
