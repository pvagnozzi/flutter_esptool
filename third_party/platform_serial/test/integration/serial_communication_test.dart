import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';
import 'package:mocktail/mocktail.dart';

class MockSerialPlatformInterface extends Mock
    implements SerialPlatformInterface {}

/// Integration tests for serial communication.
void main() {
  setUpAll(() {
    registerFallbackValue(
      const SerialConfig(portName: 'COM1'),
    );
    registerFallbackValue(Uint8List(0));
  });

  group('Serial Communication Integration', () {
    late MockSerialPlatformInterface mockPlatform;
    late SerialManager manager;

    setUp(() {
      mockPlatform = MockSerialPlatformInterface();
      manager = SerialManager(platform: mockPlatform);
    });

    tearDown(() async {
      await manager.closeAll();
    });

    test('complete flow: open, write, read, close', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.writeData(any(), any()))
          .thenAnswer((_) async => 5);
      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => Uint8List.fromList([72, 105])); // Hi
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');
      expect(port.isOpen, true);

      final written = await port.writeText('Hello');
      expect(written, 5);

      final data = await port.readSync();
      expect(data, isNotEmpty);

      await manager.closePort('COM1');
      expect(port.isOpen, false);
    });

    test('asynchronous communication with stream', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => Stream.fromIterable([
                {
                  'type': 'data',
                  'data': [72, 105]
                }, // Hi
                {
                  'type': 'data',
                  'data': [33]
                }, // !
              ]));
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});

      final port = await manager.openPort('COM1');

      final messages = <String>[];
      port.textStream.listen(messages.add);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(messages.length, 2);
      expect(messages[0], 'Hi');
      expect(messages[1], '!');

      await manager.closePort('COM1');
    });

    test('error handling during read', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.readData(any(), any())).thenThrow(SerialError(
        type: SerialErrorType.ioError,
        message: 'Read error',
      ));
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');

      expect(
        () => port.readSync(),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.ioError,
        )),
      );

      await manager.closePort('COM1');
    });

    test('port configuration respected by platform', () async {
      final capturedConfig = <SerialConfig>[];

      when(() => mockPlatform.openPort(any())).thenAnswer((invocation) {
        capturedConfig.add(invocation.positionalArguments[0] as SerialConfig);
        return Future.value();
      });

      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});

      await manager.openPort(
        'COM1',
        baudRate: 115200,
        dataBits: 7,
      );

      expect(capturedConfig, isNotEmpty);
      expect(capturedConfig[0].portName, 'COM1');
      expect(capturedConfig[0].baudRate, 115200);
      expect(capturedConfig[0].dataBits, 7);

      await manager.closeAll();
    });

    test('multiple simultaneous ports', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.writeData(any(), any()))
          .thenAnswer((_) async => 5);
      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => Uint8List(0));
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port1 = await manager.openPort('COM1');
      final port2 = await manager.openPort('COM2');
      final port3 = await manager.openPort('COM3');

      expect(manager.getOpenPorts().length, 3);

      await port1.writeText('Port1');
      await port2.writeText('Port2');
      await port3.writeText('Port3');

      await manager.closeAll();
      expect(manager.getOpenPorts(), isEmpty);
    });

    test('port reopening after closure', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      var port = await manager.openPort('COM1');
      expect(port.isOpen, true);

      await manager.closePort('COM1');
      expect(port.isOpen, false);

      port = await manager.openPort('COM1');
      expect(port.isOpen, true);

      await manager.closeAll();
    });

    test('buffer operations: flush e reset', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.flush(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.resetBuffers(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.bytesAvailable(any()))
          .thenAnswer((_) async => 10);
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1');

      await port.flush();
      verify(() => mockPlatform.flush('COM1')).called(1);

      await port.resetBuffers();
      verify(() => mockPlatform.resetBuffers('COM1')).called(1);

      final available = await port.bytesAvailable();
      expect(available, 10);

      await manager.closeAll();
    });
  });
}
