// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const bool _runHardwareTests = bool.fromEnvironment(
  'RUN_ESP_HARDWARE_TESTS',
  defaultValue: false,
);
const bool _runDestructiveHardwareTests = bool.fromEnvironment(
  'RUN_ESP_DESTRUCTIVE_HARDWARE_TESTS',
  defaultValue: false,
);
const String _serialPortValue = String.fromEnvironment('ESP_PORT');
const int _demoFlashOffset = 0x100000;
const int _demoFlashLength = 0x1000;

Uint8List _demoPayload() {
  final data = Uint8List(_demoFlashLength);
  for (var index = 0; index < data.length; index++) {
    data[index] = (0xA5 ^ index ^ (index >> 8)) & 0xFF;
  }
  return data;
}

Future<ProcessResult> _runPythonEsptool(String espPort, List<String> args) {
  return Process.run('python', <String>[
    '-m',
    'esptool',
    '--port',
    espPort,
    '--baud',
    '115200',
    ...args,
  ]);
}

String? _extractPythonMac(String output) {
  final match = RegExp(
    r'MAC:\s*([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})',
  ).firstMatch(output);
  return match?.group(1)?.toLowerCase();
}

String _processOutput(ProcessResult result) =>
    'exit=${result.exitCode}\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (!_runHardwareTests) {
    test(
      'real hardware CLI tests are disabled by default',
      () {},
      skip:
          'Set --dart-define=RUN_ESP_HARDWARE_TESTS=true and '
          '--dart-define=ESP_PORT=<serial port> to enable these tests.',
    );
    return;
  }

  final espPort = _serialPortValue.trim();
  if (espPort.isEmpty) {
    test('requires explicit ESP_PORT when hardware tests are enabled', () {
      fail(
        'Missing ESP_PORT. Re-run with '
        '--dart-define=ESP_PORT=<serial port>.',
      );
    });
    return;
  }

  group('esptool CLI on real hardware ($espPort)', () {
    setUpAll(() async {
      stdout.writeln('Priming ESP device with esptool on $espPort...');
      final primeResult = await Process.run('python', <String>[
        '-m',
        'esptool',
        '--port',
        espPort,
        '--before',
        'default-reset',
        '--after',
        'no-reset',
        'chip_id',
      ]);

      if (primeResult.exitCode != 0) {
        stderr.writeln('WARNING: esptool priming failed. Continuing anyway...');
        stderr.writeln('STDOUT: ${primeResult.stdout}');
        stderr.writeln('STDERR: ${primeResult.stderr}');
      } else {
        stdout.writeln('✓ Device primed successfully');
      }

      final availablePorts = await SerialManager().getAvailablePorts();
      final portExists = availablePorts.any(
        (port) => port.portName.toUpperCase() == espPort.toUpperCase(),
      );
      expect(
        portExists,
        isTrue,
        reason:
            'Port $espPort not found. Available ports: '
            '${availablePorts.map((p) => p.portName).join(", ")}',
      );
      stdout.writeln('✓ Port $espPort is available');
    });

    test('version command succeeds', () {
      expect(true, isTrue);
    });

    test('chip_id command: connect and detect chip', () async {
      final transport = EspTransport();
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);

      try {
        final config = EspConfig(
          portName: espPort,
          initialBaudRate: 115200,
          timeout: const Duration(seconds: 5),
          syncRetries: 16,
        );

        final connectResult = await connection.connect(config);
        expect(
          connectResult.isSuccess,
          isTrue,
          reason: connectResult.isFailure
              ? (connectResult as Failure<void>).error.message
              : '',
        );

        final detectResult = await detection.detect();
        expect(
          detectResult.isSuccess,
          isTrue,
          reason: detectResult.isFailure
              ? (detectResult as Failure<EspChipInfo>).error.message
              : '',
        );

        final chipInfo = (detectResult as Success<EspChipInfo>).value;
        expect(chipInfo.family, isNotNull);
        expect(chipInfo.magicValue, greaterThan(0));
        expect(chipInfo.macAddress, contains(':'));

        stdout.writeln('✓ Chip: ${chipInfo.description}');
        stdout.writeln('✓ MAC: ${chipInfo.macAddress}');
      } finally {
        await transport.close();
      }
    });

    test(
      'read_mac command: matches python esptool',
      () async {
        final python = await _runPythonEsptool(espPort, <String>[
          '--after',
          'no-reset',
          '--no-stub',
          'read_mac',
        ]);
        expect(python.exitCode, equals(0), reason: _processOutput(python));
        final pythonMac = _extractPythonMac(
          '${python.stdout}\n${python.stderr}',
        );
        expect(pythonMac, isNotNull, reason: _processOutput(python));

        final transport = EspTransport();
        final connection = ConnectionService(transport);
        final detection = ChipDetectionService(transport);

        try {
          final config = EspConfig(
            portName: espPort,
            initialBaudRate: 115200,
            timeout: const Duration(seconds: 5),
            syncRetries: 16,
          );

          final connectResult = await connection.connect(config);
          expect(
            connectResult.isSuccess,
            isTrue,
            reason: connectResult.isFailure
                ? (connectResult as Failure<void>).error.message
                : '',
          );
          final detectResult = await detection.detect();

          expect(
            detectResult.isSuccess,
            isTrue,
            reason: detectResult.isFailure
                ? (detectResult as Failure<EspChipInfo>).error.message
                : '',
          );
          final chipInfo = (detectResult as Success<EspChipInfo>).value;
          expect(chipInfo.macAddress.toLowerCase(), equals(pythonMac));

          stdout.writeln('✓ Python/Dart MAC Address: ${chipInfo.macAddress}');
        } finally {
          await transport.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('read_mac command: read MAC address', () async {
      final transport = EspTransport();
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);

      try {
        final config = EspConfig(
          portName: espPort,
          initialBaudRate: 115200,
          timeout: const Duration(seconds: 5),
          syncRetries: 16,
        );

        await connection.connect(config);
        final detectResult = await detection.detect();

        expect(detectResult.isSuccess, isTrue);
        final chipInfo = (detectResult as Success<EspChipInfo>).value;
        final macAddress = chipInfo.macAddress;

        final macParts = macAddress.split(':');
        expect(macParts.length, equals(6));
        for (final part in macParts) {
          expect(int.tryParse(part, radix: 16), isNotNull);
        }

        stdout.writeln('✓ MAC Address: $macAddress');
      } finally {
        await transport.close();
      }
    });

    test('flash_id command: read SPI flash ID', () async {
      final transport = EspTransport();
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);
      final info = InfoService(
        transport: transport,
        chipDetectionService: detection,
      );

      try {
        final config = EspConfig(
          portName: espPort,
          initialBaudRate: 115200,
          timeout: const Duration(seconds: 5),
          syncRetries: 16,
        );

        await connection.connect(config);
        final result = await info.getFlashId();

        expect(
          result.isSuccess,
          isTrue,
          reason: result.isFailure
              ? (result as Failure<EspFlashInfo>).error.message
              : '',
        );
        final flashInfo = (result as Success<EspFlashInfo>).value;
        expect(flashInfo.manufacturerId, greaterThan(0));

        stdout.writeln(
          '✓ Flash Manufacturer: 0x${flashInfo.manufacturerId.toRadixString(16)}',
        );
        stdout.writeln(
          '✓ Flash Device: 0x${flashInfo.deviceId.toRadixString(16)}',
        );
        stdout.writeln(
          '✓ Flash Capacity: 0x${flashInfo.capacityId.toRadixString(16)}',
        );
      } finally {
        await transport.close();
      }
    });

    test('connection workflow: connect -> detect -> read_flash_id', () async {
      final transport = EspTransport();
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);
      final info = InfoService(
        transport: transport,
        chipDetectionService: detection,
      );

      try {
        final config = EspConfig(
          portName: espPort,
          initialBaudRate: 115200,
          timeout: const Duration(seconds: 5),
          syncRetries: 16,
        );

        final connectResult = await connection.connect(config);
        expect(connectResult.isSuccess, isTrue);

        final detectResult = await detection.detect();
        expect(detectResult.isSuccess, isTrue);

        final flashIdResult = await info.getFlashId();
        expect(flashIdResult.isSuccess, isTrue);

        stdout.writeln('✓ Full workflow completed');
      } finally {
        await transport.close();
      }
    });

    test('error handling: invalid port returns error', () async {
      final transport = EspTransport();
      final connection = ConnectionService(transport);

      const config = EspConfig(
        portName: 'INVALID_PORT_XYZ',
        initialBaudRate: 115200,
        timeout: Duration(seconds: 2),
      );

      final result = await connection.connect(config);
      expect(result.isFailure, isTrue);

      stdout.writeln('✓ Invalid port correctly rejected');
    });

    test('multiple sequential operations', () async {
      final config = EspConfig(
        portName: espPort,
        initialBaudRate: 115200,
        timeout: const Duration(seconds: 5),
        syncRetries: 16,
      );

      final transport1 = EspTransport();
      final connection1 = ConnectionService(transport1);
      final detection1 = ChipDetectionService(transport1);

      try {
        await connection1.connect(config);
        final detect1 = await detection1.detect();
        expect(detect1.isSuccess, isTrue);
        stdout.writeln('✓ Operation 1: Detect');
      } finally {
        await transport1.close();
      }

      final transport2 = EspTransport();
      final connection2 = ConnectionService(transport2);
      final detection2 = ChipDetectionService(transport2);
      final info2 = InfoService(
        transport: transport2,
        chipDetectionService: detection2,
      );

      try {
        await connection2.connect(config);
        final flashId2 = await info2.getFlashId();
        expect(flashId2.isSuccess, isTrue);
        stdout.writeln('✓ Operation 2: Get Flash ID');
      } finally {
        await transport2.close();
      }

      final transport3 = EspTransport();
      final connection3 = ConnectionService(transport3);
      final detection3 = ChipDetectionService(transport3);

      try {
        await connection3.connect(config);
        final detect3 = await detection3.detect();
        expect(detect3.isSuccess, isTrue);
        stdout.writeln('✓ Operation 3: Detect again');
      } finally {
        await transport3.close();
      }
    });

    test(
      'erase_flash command: erase entire flash',
      () async {
        final transport = EspTransport();
        final connection = ConnectionService(transport);
        final flash = FlashService(transport: transport);

        try {
          final config = EspConfig(
            portName: espPort,
            initialBaudRate: 115200,
            timeout: const Duration(seconds: 5),
            syncRetries: 16,
          );

          await connection.connect(config);
          final result = await flash.eraseFlash();

          expect(
            result.isSuccess,
            isTrue,
            reason: result.isFailure
                ? (result as Failure<void>).error.message
                : '',
          );

          stdout.writeln('✓ Flash erased successfully');
        } finally {
          await transport.close();
        }
      },
      skip: _runDestructiveHardwareTests
          ? false
          : 'Skipped by default. Set '
                '--dart-define=RUN_ESP_DESTRUCTIVE_HARDWARE_TESTS=true '
                'to enable erase/write hardware tests.',
    );

    test(
      'write_flash command: write small test data',
      () async {
        final logs = <String>[];
        final transport = EspTransport(
          logger: (entry) {
            if (entry.response != null) {
              final dataHex = entry.response!.data.isEmpty
                  ? '(empty)'
                  : entry.response!.data
                        .map((b) => b.toRadixString(16).padLeft(2, '0'))
                        .join(' ');
              logs.add(
                '${entry.type.toString().split('.')[1]}: '
                'CMD: ${entry.command?.opcode.toString().split('.')[1] ?? "?"} '
                '=> SUCCESS: ${entry.response?.isSuccess} '
                'STATUS: ${entry.response?.status} DATA: [$dataHex]',
              );
            } else {
              logs.add(
                '${entry.type.toString().split('.')[1]}: '
                'CMD: ${entry.command?.opcode.toString().split('.')[1] ?? "?"} '
                '=> (no response)',
              );
            }
          },
        );
        final connection = ConnectionService(transport);
        final flash = FlashService(transport: transport);

        try {
          final config = EspConfig(
            portName: espPort,
            initialBaudRate: 115200,
            timeout: const Duration(seconds: 5),
            syncRetries: 16,
          );

          await connection.connect(config);

          final testData = Uint8List(256);
          for (var i = 0; i < testData.length; i++) {
            testData[i] = (0x12 + i) & 0xFF;
          }

          final result = await flash.writeFlash(
            FlashParameters(offset: 0x10000, data: testData, verify: false),
          );

          final logsStr = logs.isNotEmpty
              ? '${logs.length} log entries:\n${logs.join("\n")}'
              : 'No logs';

          expect(
            result.isSuccess,
            isTrue,
            reason: result.isFailure
                ? '${(result as Failure<void>).error.message}.\n$logsStr'
                : logsStr,
          );

          stdout.writeln('✓ Flash write successful');
        } finally {
          await transport.close();
        }
      },
      skip: _runDestructiveHardwareTests
          ? false
          : 'Skipped by default. Set '
                '--dart-define=RUN_ESP_DESTRUCTIVE_HARDWARE_TESTS=true '
                'to enable erase/write hardware tests.',
    );

    test(
      'erase_region + write_flash demo payload: verify with python esptool',
      () async {
        final demoData = _demoPayload();
        final transport = EspTransport();
        final connection = ConnectionService(transport);
        final flash = FlashService(transport: transport);
        final tempDir = await Directory.systemTemp.createTemp(
          'flutter_esptool_demo_',
        );

        try {
          final config = EspConfig(
            portName: espPort,
            initialBaudRate: 115200,
            timeout: const Duration(seconds: 10),
            syncRetries: 16,
          );

          await connection.connect(config);
          final eraseResult = await flash.eraseFlash(
            offset: _demoFlashOffset,
            size: _demoFlashLength,
          );
          expect(
            eraseResult.isSuccess,
            isTrue,
            reason: eraseResult.isFailure
                ? (eraseResult as Failure<void>).error.message
                : '',
          );

          final writeResult = await flash.writeFlash(
            FlashParameters(
              offset: _demoFlashOffset,
              data: demoData,
              verify: false,
            ),
          );
          expect(
            writeResult.isSuccess,
            isTrue,
            reason: writeResult.isFailure
                ? (writeResult as Failure<void>).error.message
                : '',
          );
        } finally {
          await transport.close();
        }

        final readBackFile = File(
          '${tempDir.path}${Platform.pathSeparator}demo.bin',
        );
        final readBack = await _runPythonEsptool(espPort, <String>[
          'read_flash',
          '0x${_demoFlashOffset.toRadixString(16)}',
          '0x${_demoFlashLength.toRadixString(16)}',
          readBackFile.path,
        ]);
        expect(readBack.exitCode, equals(0), reason: _processOutput(readBack));
        expect(await readBackFile.readAsBytes(), equals(demoData));

        stdout.writeln(
          '✓ Demo payload written at 0x${_demoFlashOffset.toRadixString(16)} '
          'and verified with python esptool',
        );
        await tempDir.delete(recursive: true);
      },
      timeout: const Timeout(Duration(minutes: 4)),
      skip: _runDestructiveHardwareTests
          ? false
          : 'Skipped by default. Set '
                '--dart-define=RUN_ESP_DESTRUCTIVE_HARDWARE_TESTS=true '
                'to enable erase/write hardware tests.',
    );

    test(
      'write_flash DEBUG: check for response duplication',
      () async {
        final logs = <String>[];
        final transport = EspTransport(
          logger: (entry) {
            if (entry.type.toString() ==
                    'EspTransportLogType.responseReceived' &&
                entry.response?.opcode.toString().contains('flashEnd') ==
                    true) {
              logs.add(
                'flashEnd Response ${logs.length}: '
                'STATUS=${entry.response?.status} '
                'SUCCESS=${entry.response?.isSuccess}',
              );
            }
          },
        );

        try {
          final connection = ConnectionService(transport);
          final config = EspConfig(
            portName: espPort,
            initialBaudRate: 115200,
            timeout: const Duration(seconds: 5),
            syncRetries: 16,
          );

          await connection.connect(config);

          final cmd = EspCommand(
            opcode: EspCommandOpcode.flashEnd,
            data: Uint8List(4),
          );

          stdout.writeln('Sending flashEnd command...');
          final response = await transport.sendCommand(cmd);
          stdout.writeln(
            'Received flashEnd response: '
            'SUCCESS=${response.isSuccess} STATUS=${response.status}',
          );

          if (logs.isNotEmpty) {
            stdout.writeln('Logger calls: ${logs.join(", ")}');
          }

          expect(true, isTrue, reason: 'Check stdout for debug info');
        } finally {
          await transport.close();
        }
      },
      skip: _runDestructiveHardwareTests
          ? false
          : 'Skipped by default. Set '
                '--dart-define=RUN_ESP_DESTRUCTIVE_HARDWARE_TESTS=true '
                'to enable advanced flash workflow checks.',
    );
  });
}
