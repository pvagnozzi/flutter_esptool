// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const bool _runHardwareTests =
    bool.fromEnvironment('RUN_ESP_HARDWARE_TESTS', defaultValue: false);
const String _serialPortValue = String.fromEnvironment('ESP_PORT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (!_runHardwareTests) {
    testWidgets(
      'ESP32 hardware checks are disabled by default',
      (_) async {},
      skip: true,
    );
    return;
  }

  final serialPort = _serialPortValue.trim();
  if (serialPort.isEmpty) {
    testWidgets('requires explicit ESP_PORT when hardware tests are enabled', (
      _,
    ) async {
      fail(
        'Missing ESP_PORT. Re-run with '
        '--dart-define=ESP_PORT=<serial port>.',
      );
    });
    return;
  }

  testWidgets(
    'executes non-destructive ESP32 hardware checks on the configured serial port',
    (tester) async {
      final transportLogs = <String>[];
      final transport = EspTransport(
        logger: (entry) {
          transportLogs.add(
            '${entry.type.name} opcode=${entry.opcode?.name} msg=${entry.message ?? ''}',
          );
        },
      );
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);
      final info = InfoService(
        transport: transport,
        chipDetectionService: detection,
      );
      final flash = FlashService(transport: transport);

      try {
        final primeResult = await Process.run(
          'python',
          <String>[
            '-m',
            'esptool',
            '--port',
            serialPort,
            '--before',
            'default-reset',
            '--after',
            'no-reset',
            'chip-id',
          ],
        );
        expect(
          primeResult.exitCode,
          0,
          reason: 'esptool priming failed:\n${primeResult.stdout}\n${primeResult.stderr}',
        );

        final availablePorts = await SerialManager().getAvailablePorts();
        expect(
          availablePorts.any(
            (port) => port.portName.toUpperCase() == serialPort.toUpperCase(),
          ),
          isTrue,
          reason: 'Configured port $serialPort was not found in available ports',
        );

        final connectResult = await connection.connect(
          EspConfig(
            portName: serialPort,
            timeout: const Duration(seconds: 5),
            syncRetries: 16,
          ),
        );
        expect(
          connectResult.isSuccess,
          isTrue,
          reason: connectResult is Failure<void>
              ? 'Connect failed: ${connectResult.error}\nLogs:\n${transportLogs.join('\n')}'
              : null,
        );

        final detectResult = await detection.detect();
        expect(detectResult.isSuccess, isTrue);

        final macResult = await info.getMac();
        expect(macResult.isSuccess, isTrue);
        final macAddress = (macResult as Success<String>).value;
        expect(
          RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$').hasMatch(macAddress),
          isTrue,
        );

        final flashIdResult = await info.getFlashId();
        expect(
          flashIdResult.isSuccess,
          isTrue,
          reason: flashIdResult is Failure<EspFlashInfo>
              ? 'Flash ID failed: ${flashIdResult.error}\nLogs:\n${transportLogs.join('\n')}'
              : null,
        );
        final flashInfo = (flashIdResult as Success<EspFlashInfo>).value;
        expect(flashInfo.manufacturerId, isNot(0));
        expect(flashInfo.capacityId, isNot(0));

        final md5Result = await flash.md5Flash(0x0, 4096);
        expect(md5Result.isSuccess, isTrue);
        final md5 = (md5Result as Success<String>).value;
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(md5), isTrue);

        final readFlashResult = await flash.readFlash(
          const FlashReadParameters(offset: 0, size: 256),
        );
        expect(readFlashResult.isFailure, isTrue);
        final readError = (readFlashResult as Failure<Uint8List>).error;
        expect(readError.type, EspErrorType.unsupportedOperation);
      } finally {
        await connection.disconnect();
      }
    },
  );
}
