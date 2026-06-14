import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';

void main() {
  group('SerialConfig', () {
    test('creates config with default values', () {
      const config = SerialConfig(portName: 'COM1');

      expect(config.portName, 'COM1');
      expect(config.baudRate, 9600);
      expect(config.dataBits, 8);
      expect(config.stopBits, SerialStopBits.one);
      expect(config.parity, SerialParity.none);
      expect(config.flowControl, SerialFlowControl.none);
      expect(config.readTimeout, const Duration(seconds: 5));
      expect(config.writeTimeout, const Duration(seconds: 5));
    });

    test('creates config with custom values', () {
      const config = SerialConfig(
        portName: '/dev/ttyUSB0',
        baudRate: 115200,
        dataBits: 7,
        stopBits: SerialStopBits.two,
        parity: SerialParity.even,
        flowControl: SerialFlowControl.rtscts,
        readTimeout: Duration(seconds: 10),
        writeTimeout: Duration(seconds: 10),
      );

      expect(config.portName, '/dev/ttyUSB0');
      expect(config.baudRate, 115200);
      expect(config.dataBits, 7);
      expect(config.stopBits, SerialStopBits.two);
      expect(config.parity, SerialParity.even);
      expect(config.flowControl, SerialFlowControl.rtscts);
      expect(config.readTimeout, const Duration(seconds: 10));
      expect(config.writeTimeout, const Duration(seconds: 10));
    });

    test('rejects dataBits < 5', () {
      expect(
        () => SerialConfig(portName: 'COM1', dataBits: 4),
        throwsAssertionError,
      );
    });

    test('rejects dataBits > 8', () {
      expect(
        () => SerialConfig(portName: 'COM1', dataBits: 9),
        throwsAssertionError,
      );
    });

    test('copyWith modifies specified values', () {
      const config = SerialConfig(portName: 'COM1');
      final modified = config.copyWith(
        baudRate: 115200,
        dataBits: 7,
      );

      expect(modified.portName, 'COM1');
      expect(modified.baudRate, 115200);
      expect(modified.dataBits, 7);
      expect(modified.stopBits, SerialStopBits.one);
    });

    test('operator == compares correctly', () {
      const config1 = SerialConfig(portName: 'COM1', baudRate: 9600);
      const config2 = SerialConfig(portName: 'COM1', baudRate: 9600);
      const config3 = SerialConfig(portName: 'COM1', baudRate: 115200);

      expect(config1, config2);
      expect(config1, isNot(config3));
    });

    test('toString returns a useful description', () {
      const config = SerialConfig(portName: 'COM1');
      expect(
        config.toString(),
        contains('COM1'),
      );
    });

    test('copyWith can replace every field', () {
      const config = SerialConfig(portName: 'COM1');
      final modified = config.copyWith(
        portName: 'COM2',
        baudRate: 57600,
        dataBits: 6,
        stopBits: SerialStopBits.onePointFive,
        parity: SerialParity.mark,
        flowControl: SerialFlowControl.xonxoff,
        readTimeout: const Duration(milliseconds: 250),
        writeTimeout: const Duration(milliseconds: 500),
      );

      expect(modified.portName, 'COM2');
      expect(modified.baudRate, 57600);
      expect(modified.dataBits, 6);
      expect(modified.stopBits, SerialStopBits.onePointFive);
      expect(modified.parity, SerialParity.mark);
      expect(modified.flowControl, SerialFlowControl.xonxoff);
      expect(modified.readTimeout, const Duration(milliseconds: 250));
      expect(modified.writeTimeout, const Duration(milliseconds: 500));
    });

    test('copyWith without arguments preserves every field', () {
      const config = SerialConfig(
        portName: 'COM1',
        baudRate: 115200,
        dataBits: 7,
        stopBits: SerialStopBits.two,
        parity: SerialParity.odd,
        flowControl: SerialFlowControl.rtscts,
        readTimeout: Duration(seconds: 1),
        writeTimeout: Duration(seconds: 2),
      );

      expect(config.copyWith(), config);
    });

    test('equality covers non-config objects and every differing field', () {
      const config = SerialConfig(portName: 'COM1');

      expect(config == Object(), isFalse);
      expect(config == config.copyWith(dataBits: 7), isFalse);
      expect(config == config.copyWith(stopBits: SerialStopBits.two), isFalse);
      expect(config == config.copyWith(parity: SerialParity.even), isFalse);
      expect(
        config == config.copyWith(flowControl: SerialFlowControl.rtscts),
        isFalse,
      );
      expect(
        config == config.copyWith(readTimeout: const Duration(seconds: 1)),
        isFalse,
      );
      expect(
        config == config.copyWith(writeTimeout: const Duration(seconds: 1)),
        isFalse,
      );
      expect(config.hashCode, const SerialConfig(portName: 'COM1').hashCode);
      expect(config.toString(), contains('SerialConfig'));
    });
  });
}
