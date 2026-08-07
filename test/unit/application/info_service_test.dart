// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

// ESP32-S3 magic value so ChipDetectionService resolves a supported family.
const _esp32s3Magic = 0x9;

void main() {
  group('InfoService.getSecurityInfo', () {
    Uint8List buildSecurityPayload({
      int flags = 0,
      int flashCryptCnt = 0,
      List<int>? keyPurposes,
      int chipId = 0x1234,
      int apiVersion = 1,
    }) {
      final data = Uint8List(20);
      final bd = ByteData.sublistView(data);
      bd.setUint32(0, flags, Endian.little);
      data[4] = flashCryptCnt;
      final kp = keyPurposes ?? List<int>.filled(7, 0);
      for (var i = 0; i < 7; i++) {
        data[5 + i] = kp[i];
      }
      bd.setUint32(12, chipId, Endian.little);
      bd.setUint32(16, apiVersion, Endian.little);
      return data;
    }

    test('parses a valid 20-byte payload', () async {
      final transport = FakeTransport(
        securityInfoData: buildSecurityPayload(
          flags: 0x01,
          flashCryptCnt: 0x07, // 3 bits set → odd → encryption active
          chipId: 0xABCD,
          apiVersion: 3,
        ),
      );
      final service = InfoService(transport: transport);

      final result = await service.getSecurityInfo();
      expect(result.isSuccess, isTrue);
      final info = (result as Success<EspSecurityInfo>).value;
      expect(info.chipId, 0xABCD);
      expect(info.apiVersion, 3);
      expect(info.secureBootEnabled, isTrue);
      expect(info.flashEncryptionEnabled, isTrue);
    });

    test('fails on a short payload', () async {
      final transport = FakeTransport(securityInfoData: Uint8List(8));
      final result = await InfoService(transport: transport).getSecurityInfo();
      expect(result.isFailure, isTrue);
      expect(
        (result as Failure<EspSecurityInfo>).error.message,
        contains('too short'),
      );
    });

    test('fails when the command reports an error status', () async {
      final transport = FakeTransport(
        onCommand: (c) => failResponse(c.opcode),
      );
      final result = await InfoService(transport: transport).getSecurityInfo();
      expect(result.isFailure, isTrue);
    });

    test('fails when the transport throws', () async {
      final transport = FakeTransport(
        throwOnOpcodes: {EspCommandOpcode.getSecurityInfo},
      );
      final result = await InfoService(transport: transport).getSecurityInfo();
      expect(result.isFailure, isTrue);
    });
  });

  group('InfoService.getFlashId / getMac / getChipInfo', () {
    // The detection + SPI register dance issues many readReg calls. Returning a
    // non-zero value for every read makes both detection and the SPI "done"
    // poll succeed (spiCmdUsr bit clears because value & (1<<18) == 0 when we
    // return a value without that bit). We craft the JEDEC id via defaultRead.
    FakeTransport chipTransport({int jedec = 0x00EF4016}) {
      return FakeTransport(
        onCommand: (command) {
          if (command.opcode == EspCommandOpcode.readReg) {
            final addr = ByteData.sublistView(command.data)
                .getUint32(0, Endian.little);
            // Chip magic register → ESP32-S3.
            if (addr == 0x40001000) {
              return okResponse(command.opcode, value: _esp32s3Magic);
            }
            // SPI command register polls must read back with the USR bit clear
            // (0) so the "transaction complete" branch is taken; and the W0
            // register returns the JEDEC id.
            return okResponse(command.opcode, value: jedec);
          }
          return okResponse(command.opcode);
        },
      );
    }

    test('getChipInfo detects ESP32-S3', () async {
      final service = InfoService(transport: chipTransport());
      final result = await service.getChipInfo();
      expect(result.isSuccess, isTrue);
      expect((result as Success<EspChipInfo>).value.family, ChipFamily.esp32s3);
    });

    test('getMac returns a formatted MAC string', () async {
      final service = InfoService(transport: chipTransport());
      final result = await service.getMac();
      expect(result.isSuccess, isTrue);
      expect((result as Success<String>).value, contains(':'));
    });

    test('getFlashId parses a Winbond JEDEC id', () async {
      // JEDEC read returns W0 register value; low byte = manufacturer.
      final service = InfoService(transport: chipTransport(jedec: 0x004016EF));
      final result = await service.getFlashId();
      expect(result.isSuccess, isTrue);
      final info = (result as Success<EspFlashInfo>).value;
      expect(info.manufacturerId, 0xEF);
      expect(info.manufacturerName, 'Winbond');
    });

    test('getFlashId fails when chip detection fails', () async {
      // Magic register returns 0 → unknown family → detection failure.
      final transport = FakeTransport(); // all reads = 0
      final result = await InfoService(transport: transport).getFlashId();
      expect(result.isFailure, isTrue);
    });
  });

  group('InfoService.readFlashViaSpi', () {
    test('rejects a non-positive size', () async {
      final service = InfoService(transport: FakeTransport());
      final result = await service.readFlashViaSpi(0, 0);
      expect(result.isFailure, isTrue);
      expect(
        (result as Failure<Uint8List>).error.type,
        EspErrorType.flashReadFailed,
      );
    });

    test('reads bytes from ESP32-S3 flash via SPI registers', () async {
      final transport = FakeTransport(
        onCommand: (command) {
          if (command.opcode == EspCommandOpcode.readReg) {
            final addr = ByteData.sublistView(command.data)
                .getUint32(0, Endian.little);
            if (addr == 0x40001000) {
              return okResponse(command.opcode, value: _esp32s3Magic);
            }
            // SPI command poll must read back 0 (USR bit clear → done); W regs
            // then read 0 too, yielding zero-filled flash bytes.
            return okResponse(command.opcode, value: 0);
          }
          return okResponse(command.opcode);
        },
      );
      final service = InfoService(transport: transport);
      final result = await service.readFlashViaSpi(0x1000, 8);
      expect(result.isSuccess, isTrue);
      expect((result as Success<Uint8List>).value.length, 8);
    });

    test('fails for an unknown chip family', () async {
      // Magic = 0 → unknown → registerMap null path.
      final service = InfoService(transport: FakeTransport());
      final result = await service.readFlashViaSpi(0, 16);
      expect(result.isFailure, isTrue);
    });
  });
}
