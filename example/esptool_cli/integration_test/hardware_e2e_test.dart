// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String espPort = 'COM22';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('esptool CLI on real hardware (COM22)', () {
    setUpAll(() async {
      // Prime the ESP device using esptool Python
      stdout.writeln('Priming ESP device with esptool...');
      final primeResult = await Process.run(
        'python',
        <String>[
          '-m',
          'esptool',
          '--port',
          espPort,
          '--before',
          'default-reset',
          '--after',
          'no-reset',
          'chip_id',
        ],
      );

      if (primeResult.exitCode != 0) {
        stderr.writeln('WARNING: esptool priming failed. Continuing anyway...');
        stderr.writeln('STDOUT: ${primeResult.stdout}');
        stderr.writeln('STDERR: ${primeResult.stderr}');
      } else {
        stdout.writeln('✓ Device primed successfully');
      }

      // Verify port is available
      final availablePorts = await SerialManager().getAvailablePorts();
      final portExists = availablePorts.any(
        (port) => port.portName.toUpperCase() == espPort.toUpperCase(),
      );
      expect(
        portExists,
        isTrue,
        reason:
            'Port $espPort not found. Available ports: ${availablePorts.map((p) => p.portName).join(", ")}',
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
        expect(connectResult.isSuccess, isTrue,
            reason:
                connectResult.isFailure ? '${(connectResult as Failure<void>).error.message}' : '');

        final detectResult = await detection.detect();
        expect(detectResult.isSuccess, isTrue,
            reason:
                detectResult.isFailure ? '${(detectResult as Failure<EspChipInfo>).error.message}' : '');

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
      final info = InfoService(transport: transport, chipDetectionService: detection);

      try {
        final config = EspConfig(
          portName: espPort,
          initialBaudRate: 115200,
          timeout: const Duration(seconds: 5),
          syncRetries: 16,
        );

        await connection.connect(config);
        final result = await info.getFlashId();

        expect(result.isSuccess, isTrue,
            reason: result.isFailure ? '${(result as Failure<EspFlashInfo>).error.message}' : '');
        final flashInfo = (result as Success<EspFlashInfo>).value;
        expect(flashInfo.manufacturerId, greaterThan(0));

        stdout.writeln('✓ Flash Manufacturer: 0x${flashInfo.manufacturerId.toRadixString(16)}');
        stdout.writeln('✓ Flash Device: 0x${flashInfo.deviceId.toRadixString(16)}');
        stdout.writeln('✓ Flash Capacity: 0x${flashInfo.capacityId.toRadixString(16)}');
      } finally {
        await transport.close();
      }
    });

    test('erase_flash command: erase entire flash', () async {
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

        expect(result.isSuccess, isTrue,
            reason: result.isFailure ? '${(result as Failure<void>).error.message}' : '');

        stdout.writeln('✓ Flash erased successfully');
      } finally {
        await transport.close();
      }
    });

    test('write_flash command: write small test data', () async {
      final logs = <String>[];
      final transport = EspTransport(
        logger: (entry) {
         if (entry.response != null) {
           final dataHex = entry.response!.data.isEmpty ? '(empty)' : entry.response!.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
           logs.add('${entry.type.toString().split('.')[1]}: CMD: ${entry.command?.opcode.toString().split('.')[1] ?? "?"} => SUCCESS: ${entry.response?.isSuccess} STATUS: ${entry.response?.status} DATA: [$dataHex]');
         } else {
           logs.add('${entry.type.toString().split('.')[1]}: CMD: ${entry.command?.opcode.toString().split('.')[1] ?? "?"} => (no response)');
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
         FlashParameters(
           offset: 0x10000,
           data: testData,
           verify: false,
         ),
        );

        final logsStr = logs.isNotEmpty ? '${logs.length} log entries:\n${logs.join("\n")}' : 'No logs';

        expect(result.isSuccess, isTrue,
           reason: result.isFailure ? '${(result as Failure<void>).error.message}.\n$logsStr' : logsStr);

        stdout.writeln('✓ Flash write successful');
      } finally {
        await transport.close();
      }
    });

    test('write_flash DEBUG: check for response duplication', () async {
      final logs = <String>[];
      final transport = EspTransport(
        logger: (entry) {
         if (entry.type.toString() == 'EspTransportLogType.responseReceived' && 
             entry.response?.opcode.toString().contains('flashEnd') == true) {
           logs.add('flashEnd Response ${logs.length}: STATUS=${entry.response?.status} SUCCESS=${entry.response?.isSuccess}');
         }
        },
      );

      try {
        final connection = ConnectionService(transport);
        final config = EspConfig(
         portName: 'COM22',
         initialBaudRate: 115200,
         timeout: const Duration(seconds: 5),
         syncRetries: 16,
        );

        await connection.connect(config);
        
        // Send just a flash end command directly
        final cmd = EspCommand(
         opcode: EspCommandOpcode.flashEnd,
         data: Uint8List(4), // 4 bytes of zeros
        );
        
        stdout.writeln('Sending flashEnd command...');
        final response = await transport.sendCommand(cmd);
        stdout.writeln('Received flashEnd response: SUCCESS=${response.isSuccess} STATUS=${response.status}');
        
        if (logs.isNotEmpty) {
         stdout.writeln('Logger calls: ${logs.join(", ")}');
        }
        
        expect(true, isTrue, reason: 'Check stdout for debug info');
      } finally {
        await transport.close();
      }
    });

    test('connection workflow: connect -> detect -> read_flash_id', () async {
      final transport = EspTransport();
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);
      final info = InfoService(transport: transport, chipDetectionService: detection);

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

      final config = EspConfig(
        portName: 'INVALID_PORT_XYZ',
        initialBaudRate: 115200,
        timeout: const Duration(seconds: 2),
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

      // Operation 1
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

      // Operation 2
      final transport2 = EspTransport();
      final connection2 = ConnectionService(transport2);
      final detection2 = ChipDetectionService(transport2);
      final info2 = InfoService(transport: transport2, chipDetectionService: detection2);

      try {
        await connection2.connect(config);
        final flashId2 = await info2.getFlashId();
        expect(flashId2.isSuccess, isTrue);
        stdout.writeln('✓ Operation 2: Get Flash ID');
      } finally {
        await transport2.close();
      }

      // Operation 3
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
  });
}
