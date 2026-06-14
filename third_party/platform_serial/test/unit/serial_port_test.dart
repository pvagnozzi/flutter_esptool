import 'dart:async';
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

  group('SerialPort', () {
    late MockSerialPlatformInterface mockPlatform;
    late SerialPort port;

    setUp(() {
      mockPlatform = MockSerialPlatformInterface();
      port = SerialPort(platform: mockPlatform);
    });

    tearDown(() async {
      if (port.isOpen) {
        try {
          await port.dispose();
        } catch (_) {}
      }
    });

    test('initially the port is closed', () {
      expect(port.isOpen, false);
    });

    test('opens port with configuration', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);

      expect(port.isOpen, true);
      expect(port.config, config);
      verify(() => mockPlatform.openPort(config)).called(1);
    });

    test('throws when the port is already open', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);

      expect(
        () => port.open(config),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.portAlreadyOpen,
        )),
      );
    });

    test('closes an open port', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.closePort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      expect(port.isOpen, true);

      await port.close();
      expect(port.isOpen, false);
      verify(() => mockPlatform.closePort('COM1')).called(1);
    });

    test('throws when closing a port that is not open', () async {
      expect(
        () => port.close(),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.portClosed,
        )),
      );
    });

    test('writes data to the port', () async {
      const config = SerialConfig(portName: 'COM1');
      final data = Uint8List.fromList([1, 2, 3]);

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.writeData(any(), any()))
          .thenAnswer((_) async => 3);
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      final bytesWritten = await port.write(data);

      expect(bytesWritten, 3);
      verify(() => mockPlatform.writeData('COM1', data)).called(1);
    });

    test('writes text to the port', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.writeData(any(), any()))
          .thenAnswer((_) async => 11);
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      final bytesWritten = await port.writeText('Hello World');

      expect(bytesWritten, 11);
    });

    test('throws when writing to a closed port', () async {
      final data = Uint8List.fromList([1, 2, 3]);

      expect(
        () => port.write(data),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.portClosed,
        )),
      );
    });

    test('reads data synchronously', () async {
      const config = SerialConfig(portName: 'COM1');
      final data = Uint8List.fromList([65, 66, 67]); // ABC

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => data);
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      final result = await port.readSync();

      expect(result, data);
      verify(() => mockPlatform.readData('COM1', 1024)).called(1);
    });

    test('reads text synchronously', () async {
      const config = SerialConfig(portName: 'COM1');
      final data = Uint8List.fromList([72, 105]); // Hi

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => data);
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      final result = await port.readTextSync();

      expect(result, 'Hi');
    });

    test('readSync timeout throws SerialError', () async {
      const config = SerialConfig(
        portName: 'COM1',
        readTimeout: Duration(milliseconds: 100),
      );

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.readData(any(), any())).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return Uint8List(0);
      });
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);

      expect(
        () => port.readSync(),
        throwsA(isA<SerialError>().having(
          (e) => e.type,
          'type',
          SerialErrorType.timeout,
        )),
      );
    });

    test('reads a specific number of bytes', () async {
      const config = SerialConfig(portName: 'COM1');
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.readData(any(), any()))
          .thenAnswer((_) async => data);
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      final result = await port.read(5);

      expect(result, data);
      verify(() => mockPlatform.readData('COM1', 5)).called(1);
    });

    test('flush clears the output buffer', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.flush(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      await port.flush();

      verify(() => mockPlatform.flush('COM1')).called(1);
    });

    test('bytesAvailable returns the number of bytes', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.bytesAvailable(any()))
          .thenAnswer((_) async => 42);
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      final available = await port.bytesAvailable();

      expect(available, 42);
      verify(() => mockPlatform.bytesAvailable('COM1')).called(1);
    });

    test('resetBuffers restores the buffers', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.resetBuffers(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());

      await port.open(config);
      await port.resetBuffers();

      verify(() => mockPlatform.resetBuffers('COM1')).called(1);
    });

    test('dataStream emits received data', () async {
      const config = SerialConfig(portName: 'COM1');
      final testData = Uint8List.fromList([1, 2, 3]);

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => Stream.value({
                'type': 'data',
                'data': [1, 2, 3],
              }));

      await port.open(config);

      expect(port.dataStream, emits(testData));
    });

    test('textStream emits received text', () async {
      const config = SerialConfig(portName: 'COM1');

      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => Stream.value({
                'type': 'data',
                'data': [72, 105], // Hi
              }));

      await port.open(config);

      expect(port.textStream, emits('Hi'));
    });

    test('config throws typed error before the port is configured', () {
      expect(
        () => port.config,
        throwsA(isA<SerialError>().having(
          (error) => error.type,
          'type',
          SerialErrorType.portClosed,
        )),
      );
    });

    test('read, flush and control operations reject closed ports', () async {
      await expectLater(port.readSync(), throwsA(isA<SerialError>()));
      await expectLater(port.read(1), throwsA(isA<SerialError>()));
      await expectLater(port.readUntil('\n'), throwsA(isA<SerialError>()));
      await expectLater(port.flush(), throwsA(isA<SerialError>()));
      await expectLater(port.bytesAvailable(), throwsA(isA<SerialError>()));
      await expectLater(port.getControlSignals(), throwsA(isA<SerialError>()));
      await expectLater(port.getCts(), throwsA(isA<SerialError>()));
      await expectLater(port.resetBuffers(), throwsA(isA<SerialError>()));
      await expectLater(port.setDtr(true), throwsA(isA<SerialError>()));
      await expectLater(port.setRts(true), throwsA(isA<SerialError>()));
    });

    test('read and write custom timeout values are honored', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.readData(any(), any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return Uint8List(0);
      });
      when(() => mockPlatform.writeData(any(), any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 0;
      });

      await port.open(config);

      await expectLater(
        port.read(1, timeout: const Duration(milliseconds: 1)),
        throwsA(isA<SerialError>().having(
          (error) => error.type,
          'type',
          SerialErrorType.timeout,
        )),
      );
      await expectLater(
        port.write(Uint8List(0), timeout: const Duration(milliseconds: 1)),
        throwsA(isA<SerialError>().having(
          (error) => error.type,
          'type',
          SerialErrorType.timeout,
        )),
      );
    });

    test('readUntil returns after the terminator is read', () async {
      const config = SerialConfig(portName: 'COM1');
      final chunks = <int>[65, 66, 10];
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.readData(any(), 1)).thenAnswer((_) async {
        return Uint8List.fromList([chunks.removeAt(0)]);
      });

      await port.open(config);

      expect(await port.readUntil('\n'), 'AB\n');
    });

    test('readUntil times out when no terminator arrives', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.readData(any(), 1))
          .thenAnswer((_) async => Uint8List(0));

      await port.open(config);

      await expectLater(
        port.readUntil('\n', timeout: const Duration(milliseconds: 5)),
        throwsA(isA<SerialError>().having(
          (error) => error.type,
          'type',
          SerialErrorType.timeout,
        )),
      );
    });

    test('readUntil wraps platform errors', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.readData(any(), 1)).thenThrow(Exception('boom'));

      await port.open(config);

      await expectLater(
        port.readUntil('\n', timeout: const Duration(milliseconds: 50)),
        throwsA(isA<SerialError>().having(
          (error) => error.type,
          'type',
          SerialErrorType.ioError,
        )),
      );
    });

    test('event listener ignores other ports and surfaces errors', () async {
      const config = SerialConfig(portName: 'COM1');
      final controller = StreamController<dynamic>();
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => controller.stream);

      await port.open(config);

      controller.add({
        'type': 'data',
        'portName': 'COM2',
        'data': [1],
      });
      controller.add({'type': 'error'});
      controller.addError('transport failed');

      await expectLater(
        port.errorStream,
        emitsInOrder([
          isA<SerialError>().having(
            (error) => error.message,
            'message',
            'Unknown error',
          ),
          isA<SerialError>().having(
            (error) => error.message,
            'message',
            contains('transport failed'),
          ),
        ]),
      );
      await controller.close();
    });

    test('control signal snapshot and CTS delegate to the platform', () async {
      const config = SerialConfig(portName: 'COM1');
      const signals = SerialControlSignals(
        mask: 0x06,
        cts: true,
        dtr: true,
      );
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.getControlSignals(any()))
          .thenAnswer((_) async => signals);

      await port.open(config);

      expect(await port.getControlSignals(), signals);
      expect(await port.getCts(), true);
      verify(() => mockPlatform.getControlSignals('COM1')).called(2);
    });

    test('DTR and RTS delegate to the platform when open', () async {
      const config = SerialConfig(portName: 'COM1');
      when(() => mockPlatform.openPort(any())).thenAnswer((_) async => {});
      when(() => mockPlatform.getEventStream(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockPlatform.setDtr(any(), any())).thenAnswer((_) async => {});
      when(() => mockPlatform.setRts(any(), any())).thenAnswer((_) async => {});

      await port.open(config);
      await port.setDtr(true);
      await port.setRts(false);

      verify(() => mockPlatform.setDtr('COM1', true)).called(1);
      verify(() => mockPlatform.setRts('COM1', false)).called(1);
    });
  });
}
