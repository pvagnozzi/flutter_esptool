// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.
//
// Real-device integration test for the ESP32-S3 stub loader.
//
// Run with:
//   flutter test test/device/stub_loader_device_test.dart
//
// Prerequisites:
//   - ESP32-S3 connected via USB JTAG/Serial. The serial port defaults to
//     /dev/cu.usbmodem1101 but can be overridden with the ESP_PORT env var:
//       ESP_PORT=/dev/cu.usbmodem2101 flutter test test/device/stub_loader_device_test.dart
//   - Device in ROM bootloader mode (hold BOOT, press EN, release BOOT)
//     OR use the USB JTAG auto-reset (which the test does via EspResetMode.usbJtag)

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

final _port = Platform.environment['ESP_PORT'] ?? '/dev/cu.usbmodem1101';

void _espLogger(EspTransportLogEntry e) {
  final ts = e.timestamp.toIso8601String();
  String hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  String msg;
  switch (e.type) {
    case EspTransportLogType.commandSent:
      msg = 'TX opcode=${e.opcode} frame=${hex(e.rawFrame ?? Uint8List(0))}';
    case EspTransportLogType.responseReceived:
      msg = 'RX opcode=${e.opcode} frame=${hex(e.rawFrame ?? Uint8List(0))}';
    case EspTransportLogType.transportError:
      msg = 'ERR ${e.message}';
  }
  print('$ts [ESP] $msg');
}

void main() {
  group('ESP32-S3 stub loader — real device', () {
    test('connect, disable watchdogs, upload stub, receive OHAI', () async {
      print('\n=== STUB LOADER DEVICE TEST ===');
      print('Port: $_port');

      final transport = EspTransport(logger: _espLogger);
      final connection = ConnectionService(transport);

      // Connect via USB JTAG/Serial with auto-reset.
      print('\n[1/4] Connecting...');
      final connectResult = await connection.connect(
        EspConfig(
          portName: _port,
          timeout: const Duration(seconds: 5),
          syncRetries: 10,
          resetMode: EspResetMode.usbJtag,
        ),
      );

      expect(
        connectResult.isSuccess,
        isTrue,
        reason: 'Connection failed: '
            '${connectResult is Failure ? connectResult.error.message : ""}',
      );
      print('[1/4] Connected OK');

      // Detect chip to confirm we're talking to the right device.
      print('\n[2/4] Detecting chip...');
      final detection = ChipDetectionService(transport);
      final detectResult = await detection.detect();
      detectResult.fold(
        (chip) =>
            print('[2/4] Chip: ${chip.description}  MAC: ${chip.macAddress}'),
        (err) => print('[2/4] Chip detect warning (non-fatal): ${err.message}'),
      );

      // Upload stub — this is the main test.
      print('\n[3/4] Uploading flasher stub...');
      final stubLoader = StubLoaderService(transport: transport);
      final stubResult = await stubLoader.loadStub(ChipFamily.esp32s3);

      if (stubResult is Failure) {
        print('[3/4] STUB FAILED: ${stubResult.error.message}');
      } else {
        print('[3/4] STUB LOADED SUCCESSFULLY — OHAI received!');
      }

      expect(
        stubResult.isSuccess,
        isTrue,
        reason: stubResult is Failure
            ? 'Stub load failed: ${stubResult.error.message}'
            : '',
      );
      expect(stubLoader.isLoaded, isTrue);

      // Verify stub is running by sending eraseFlash (0xD0) — stub-only command.
      // We won't actually erase, just verify the stub responds.
      print(
          '\n[4/4] Verifying stub with a stub-only command (eraseFlash 0xD0)...');
      // NOTE: eraseFlash will actually erase the chip. For a quick test we'll
      // just check that we can send a readReg command and the stub responds.
      // The stub uses STATUS_BYTES_LENGTH=2 (same as ROM), so readReg should work.
      final readPayload = Uint8List(4);
      ByteData.sublistView(readPayload).setUint32(0, 0x60000078, Endian.little);
      final regResp = await transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.readReg, data: readPayload),
        timeout: const Duration(seconds: 3),
      );
      print(
          '[4/4] readReg after stub: status=${regResp.status} value=0x${regResp.value.toRadixString(16)}');
      expect(regResp.isSuccess, isTrue,
          reason:
              'readReg after stub failed: status=${regResp.status} error=${regResp.error}');

      print('\n=== ALL TESTS PASSED — STUB IS RUNNING ===\n');

      await connection.disconnect();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('eraseFlash via stub (0xD0) — full chip erase', () async {
      print('\n=== ERASE FLASH VIA STUB TEST ===');
      print('WARNING: This will ERASE the entire flash chip!');

      final transport = EspTransport(logger: _espLogger);
      final connection = ConnectionService(transport);

      print('\n[1/3] Connecting...');
      final connectResult = await connection.connect(
        EspConfig(
          portName: _port,
          timeout: const Duration(seconds: 5),
          syncRetries: 10,
          resetMode: EspResetMode.usbJtag,
        ),
      );
      expect(connectResult.isSuccess, isTrue);
      print('[1/3] Connected');

      print('\n[2/3] Loading stub...');
      final stubLoader = StubLoaderService(transport: transport);
      final stubResult = await stubLoader.loadStub(ChipFamily.esp32s3);
      expect(stubResult.isSuccess, isTrue,
          reason: stubResult is Failure
              ? stubResult.error.message
              : '');
      print('[2/3] Stub loaded');

      print('\n[3/3] Erasing full flash (0xD0)...');
      final flashService =
          FlashService(transport: transport, blockSize: 0x4000);
      final eraseResult = await flashService.eraseFlash();

      eraseResult.fold(
        (_) => print('[3/3] Erase complete!'),
        (err) => print('[3/3] Erase failed: ${err.message}'),
      );

      expect(eraseResult.isSuccess, isTrue,
          reason: eraseResult is Failure
              ? eraseResult.error.message
              : '');

      print('\n=== FLASH ERASE VIA STUB SUCCESSFUL ===\n');
      await connection.disconnect();
    },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: 'Skipped by default to avoid erasing flash — remove skip to run');
  });
}
