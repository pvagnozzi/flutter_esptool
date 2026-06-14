import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';
import 'package:mocktail/mocktail.dart';

class MockSerialPlatformInterface extends Mock
    implements SerialPlatformInterface {}

/// E2E tests: good path, bad path, edge cases.
void main() {
  setUpAll(() {
    registerFallbackValue(
      const SerialConfig(portName: 'COM1'),
    );
    registerFallbackValue(Uint8List(0));
  });

  group('E2E - Good Path', () {
    late MockSerialPlatformInterface mockPlatform;
    late SerialManager manager;

    setUp(() {
      mockPlatform = MockSerialPlatformInterface();
      manager = SerialManager(platform: mockPlatform);
    });

    tearDown(() async {
      try {
        await manager.closeAll();
      } catch (_) {}
    });

    test('complete communication scenario', () async {
      when(() => mockPlatform.getAvailablePorts()).thenAnswer((_) async => [
            const SerialPortInfo(
              portName: 'COM1',
              description: 'Test Port',
              platform: 'test',
            ),
          ]);

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.writeData(any(), any()))
          .thenAnswer((_) async => 12);
      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => Uint8List.fromList(
                'OK\r\n'.codeUnits,
              ));
      when(() => mockPlatform.flush(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      // Verify available ports.
      final ports = await manager.getAvailablePorts();
      expect(ports, isNotEmpty);
      expect(ports[0].portName, 'COM1');

      // Open the port.
      final port = await manager.openPort('COM1', baudRate: 9600);
      expect(port.isOpen, true);

      // Write the command.
      final sent = await port.writeText('AT+TEST\n');
      expect(sent, 12);

      // Read the response.
      final response = await port.readSync();
      expect(response, isNotEmpty);

      // Flush and close.
      await port.flush();
      await manager.closePort('COM1');
      expect(port.isOpen, false);
    });

    test('reading with terminator', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});

      var readCount = 0;
      when(() => mockPlatform.readData(any(), any())).thenAnswer((_) async {
        readCount++;
        // Simulate gradual reads until the terminator.
        if (readCount == 1) return Uint8List.fromList('H'.codeUnits);
        if (readCount == 2) return Uint8List.fromList('e'.codeUnits);
        if (readCount == 3) return Uint8List.fromList('llo'.codeUnits);
        if (readCount == 4) return Uint8List.fromList('\n'.codeUnits);
        return Uint8List(0);
      });
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');
      final result =
          await port.readUntil('\n', timeout: const Duration(seconds: 2));

      expect(result, contains('Hello'));

      await manager.closePort('COM1');
    });
  });

  group('E2E - Bad Path', () {
    late MockSerialPlatformInterface mockPlatform;
    late SerialManager manager;

    setUp(() {
      mockPlatform = MockSerialPlatformInterface();
      manager = SerialManager(platform: mockPlatform);
    });

    tearDown(() async {
      try {
        await manager.closeAll();
      } catch (_) {}
    });

    test('error: port not found', () async {
      when(() => mockPlatform.getAvailablePorts()).thenAnswer((_) async => []);

      final ports = await manager.getAvailablePorts();
      expect(ports, isEmpty);
    });

    test('error: port open failure', () async {
      when(() => mockPlatform.openPort(any())).thenThrow(SerialError(
        type: SerialErrorType.portNotFound,
        message: 'COM1 not found',
      ));

      expect(
        () => manager.openPort('COM1'),
        throwsA(isA<SerialError>()),
      );
    });

    test('error: operation on closed port', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');
      await manager.closePort('COM1');

      expect(
        () => port.writeText('test'),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.portClosed,
        )),
      );
    });

    test('error: opening already-open port', () async {
      const config = SerialConfig(portName: 'COM1');

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = SerialPort(platform: mockPlatform);
      await port.open(config);

      expect(
        () => port.open(config),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.portAlreadyOpen,
        )),
      );

      await port.close();
    });

    test('error: read timeout', () async {
      const config = SerialConfig(
        portName: 'COM1',
        readTimeout: Duration(milliseconds: 50),
      );

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.readData(any(), any())).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return Uint8List(0);
      });
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});

      final port = SerialPort(platform: mockPlatform);
      await port.open(config);

      expect(
        () => port.readSync(),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.timeout,
        )),
      );

      await port.close();
    });

    test('error: I/O during write', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.writeData(any(), any())).thenThrow(SerialError(
        type: SerialErrorType.ioError,
        message: 'Write error',
      ));
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});

      final port = await manager.openPort('COM1');

      expect(
        () => port.writeText('test'),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.ioError,
        )),
      );

      await manager.closeAll();
    });
  });

  group('E2E - Edge Cases', () {
    late MockSerialPlatformInterface mockPlatform;
    late SerialManager manager;

    setUp(() {
      mockPlatform = MockSerialPlatformInterface();
      manager = SerialManager(platform: mockPlatform);
    });

    tearDown(() async {
      try {
        await manager.closeAll();
      } catch (_) {}
    });

    test('fragmented data received separately', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});

      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => Stream.fromIterable([
                {
                  'type': 'data',
                  'data': [72]
                }, // H
                {
                  'type': 'data',
                  'data': [101]
                }, // e
                {
                  'type': 'data',
                  'data': [108, 108, 111]
                }, // llo
              ]));

      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});

      final port = await manager.openPort('COM1');

      final received = <String>[];
      port.textStream.listen(received.add);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 3);
      expect(received.join(''), 'Hello');

      await manager.closeAll();
    });

    test('buffer overflow: very large data', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});

      final largeData = Uint8List(10000);
      for (var i = 0; i < largeData.length; i++) {
        largeData[i] = i % 256;
      }

      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => largeData);
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');
      final data = await port.readSync();

      expect(data.length, 10000);

      await manager.closeAll();
    });

    test('quick search for available ports', () async {
      final ports = List.generate(
        50,
        (i) => SerialPortInfo(
          portName: 'COM${i + 1}',
          description: 'Port ${i + 1}',
          platform: 'test',
        ),
      );

      when(() => mockPlatform.getAvailablePorts())
          .thenAnswer((_) async => ports);

      final result = await manager.getAvailablePorts();

      expect(result.length, 50);
      expect(result[0].portName, 'COM1');
      expect(result[49].portName, 'COM50');
    });

    test('reading mixed binary data', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});

      final mixedData = Uint8List.fromList([
        0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD, // Binary data
        65, 66, 67, // ASCII ABC
      ]);

      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => mixedData);
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');
      final data = await port.read(9);

      expect(data.length, 9);
      expect(data[0], 0x00);
      expect(data[9 - 1], 67); // Last 'C'

      await manager.closeAll();
    });

    test('configuration with all non-default parameters', () async {
      const config = SerialConfig(
        portName: 'COM1',
        baudRate: 256000,
        dataBits: 5,
        stopBits: SerialStopBits.two,
        parity: SerialParity.odd,
        flowControl: SerialFlowControl.xonxoff,
        readTimeout: Duration(milliseconds: 100),
        writeTimeout: Duration(milliseconds: 100),
      );

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});

      final port = SerialPort(platform: mockPlatform);
      await port.open(config);

      expect(port.config.baudRate, 256000);
      expect(port.config.dataBits, 5);
      expect(port.config.stopBits, SerialStopBits.two);
      expect(port.config.parity, SerialParity.odd);

      await port.close();
    });

    test('multiple port closure does not fail', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');

      await port.close();
      expect(port.isOpen, false);

      // A second close throws an error.
      expect(
        () => port.close(),
        throwsA(isA<SerialError>()),
      );
    });
  });
}
