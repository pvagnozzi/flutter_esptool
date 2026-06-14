import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';
import 'package:mocktail/mocktail.dart';

class MockSerialPlatformInterface extends Mock
    implements SerialPlatformInterface {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const SerialConfig(portName: 'COM1'),
    );
    registerFallbackValue(Uint8List(0));
  });

  group('SerialManager', () {
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

    test('retrieves available ports from platform', () async {
      final ports = [
        const SerialPortInfo(
          portName: 'COM1',
          description: 'Serial Port',
          platform: 'windows',
        ),
        const SerialPortInfo(
          portName: 'COM2',
          description: 'USB Serial Port',
          vendorId: '1A86',
          productId: '7523',
          platform: 'windows',
        ),
      ];

      when(() => mockPlatform.getAvailablePorts())
          .thenAnswer((_) async => ports);

      final result = await manager.getAvailablePorts();

      expect(result, ports);
      expect(result.length, 2);
      expect(result[0].portName, 'COM1');
      expect(result[1].vendorId, '1A86');
      verify(() => mockPlatform.getAvailablePorts()).called(1);
    });

    test('createPort returns a new SerialPort instance', () {
      final port = manager.createPort();

      expect(port, isA<SerialPort>());
      expect(port.isOpen, false);
    });

    test('openPort opens and tracks the port', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port = await manager.openPort('COM1', baudRate: 115200);

      expect(port.isOpen, true);
      expect(manager.getPort('COM1'), port);
      verify(() => mockPlatform.openPort(any())).called(1);
    });

    test('openPort returns existing port if already open', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port1 = await manager.openPort('COM1');
      final port2 = await manager.openPort('COM1');

      expect(port1, port2);
      verify(() => mockPlatform.openPort(any())).called(1);
    });

    test('openPort recreates a stale closed port entry', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      final port1 = await manager.openPort('COM1');
      await port1.close();

      final port2 = await manager.openPort('COM1');

      expect(port2, isNot(same(port1)));
      expect(port2.isOpen, true);
      verify(() => mockPlatform.openPort(any())).called(2);
    });

    test('closePort closes the tracked port', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await manager.openPort('COM1');
      expect(manager.getPort('COM1'), isNotNull);

      await manager.closePort('COM1');
      expect(manager.getPort('COM1'), isNull);
      verify(() => mockPlatform.closePort('COM1')).called(1);
    });

    test('closePort does not fail if port does not exist', () async {
      expect(() => manager.closePort('COM_NONEXISTENT'), returnsNormally);
      verifyNever(() => mockPlatform.closePort(any()));
    });

    test('closeAll closes all ports', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await manager.openPort('COM1');
      await manager.openPort('COM2');
      expect(manager.getOpenPorts().length, 2);

      await manager.closeAll();
      expect(manager.getOpenPorts(), isEmpty);
      verify(() => mockPlatform.closePort('COM1')).called(1);
      verify(() => mockPlatform.closePort('COM2')).called(1);
    });

    test('closeAll continues even if a port fails', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort('COM1')).thenThrow(Exception('Error'));
      when(() => mockPlatform.closePort('COM2')).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await manager.openPort('COM1');
      await manager.openPort('COM2');

      await manager.closeAll();
      verify(() => mockPlatform.closePort('COM1')).called(1);
      verify(() => mockPlatform.closePort('COM2')).called(1);
    });

    test('getOpenPorts returns an immutable map', () async {
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await manager.openPort('COM1');
      final ports = manager.getOpenPorts();

      expect(ports, isA<Map<String, SerialPort>>());
      expect(() => ports['COM2'] = SerialPort(), throwsUnsupportedError);
    });
  });
}
