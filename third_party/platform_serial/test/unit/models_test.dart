import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';

void main() {
  group('SerialPortInfo', () {
    test('creates port info with minimum values', () {
      const info = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        platform: 'windows',
      );

      expect(info.portName, 'COM1');
      expect(info.description, 'Serial Port');
      expect(info.vendorId, isNull);
      expect(info.productId, isNull);
      expect(info.serialNumber, isNull);
      expect(info.isOpen, false);
      expect(info.platform, 'windows');
    });

    test('creates port info with all values', () {
      const info = SerialPortInfo(
        portName: '/dev/ttyUSB0',
        description: 'CH340 Serial',
        vendorId: '1A86',
        productId: '7523',
        serialNumber: 'ABC123',
        isOpen: true,
        platform: 'linux',
      );

      expect(info.portName, '/dev/ttyUSB0');
      expect(info.description, 'CH340 Serial');
      expect(info.vendorId, '1A86');
      expect(info.productId, '7523');
      expect(info.serialNumber, 'ABC123');
      expect(info.isOpen, true);
      expect(info.platform, 'linux');
    });

    test('copyWith modifies specified values', () {
      const info = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        platform: 'windows',
      );

      final modified = info.copyWith(
        isOpen: true,
        vendorId: '1234',
      );

      expect(modified.portName, 'COM1');
      expect(modified.isOpen, true);
      expect(modified.vendorId, '1234');
      expect(modified.description, 'Serial Port');
    });

    test('operator == compares correctly', () {
      const info1 = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        platform: 'windows',
      );
      const info2 = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        platform: 'windows',
      );
      const info3 = SerialPortInfo(
        portName: 'COM2',
        description: 'Serial Port',
        platform: 'windows',
      );

      expect(info1, info2);
      expect(info1, isNot(info3));
    });

    test('toString returns a useful description', () {
      const info = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        platform: 'windows',
      );
      expect(info.toString(), contains('COM1'));
      expect(info.toString(), contains('Serial Port'));
    });

    test('copyWith can replace every field', () {
      const info = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        platform: 'windows',
      );

      final modified = info.copyWith(
        portName: 'COM2',
        description: 'USB Serial',
        vendorId: '1234',
        productId: '5678',
        serialNumber: 'SN-1',
        isOpen: true,
        platform: 'linux',
      );

      expect(modified.portName, 'COM2');
      expect(modified.description, 'USB Serial');
      expect(modified.vendorId, '1234');
      expect(modified.productId, '5678');
      expect(modified.serialNumber, 'SN-1');
      expect(modified.isOpen, true);
      expect(modified.platform, 'linux');
    });

    test('copyWith without arguments preserves every field', () {
      const info = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        vendorId: '1234',
        productId: '5678',
        serialNumber: 'SN-1',
        isOpen: true,
        platform: 'windows',
      );

      expect(info.copyWith(), info);
    });

    test('equality covers non-info objects and every differing field', () {
      const info = SerialPortInfo(
        portName: 'COM1',
        description: 'Serial Port',
        vendorId: '1234',
        productId: '5678',
        serialNumber: 'SN-1',
        isOpen: true,
        platform: 'windows',
      );

      expect(info == Object(), isFalse);
      expect(info == info.copyWith(description: 'Other'), isFalse);
      expect(info == info.copyWith(vendorId: '9999'), isFalse);
      expect(info == info.copyWith(productId: '9999'), isFalse);
      expect(info == info.copyWith(serialNumber: 'SN-2'), isFalse);
      expect(info == info.copyWith(isOpen: false), isFalse);
      expect(info == info.copyWith(platform: 'linux'), isFalse);
      expect(
        info.hashCode,
        const SerialPortInfo(
          portName: 'COM1',
          description: 'Serial Port',
          vendorId: '1234',
          productId: '5678',
          serialNumber: 'SN-1',
          isOpen: true,
          platform: 'windows',
        ).hashCode,
      );
      expect(info.toString(), contains('SerialPortInfo'));
    });
  });

  group('SerialControlSignals', () {
    test('creates default signal snapshot', () {
      const signals = SerialControlSignals();

      expect(signals.mask, 0);
      expect(signals.rts, false);
      expect(signals.cts, false);
      expect(signals.dtr, false);
      expect(signals.dsr, false);
      expect(signals.dcd, false);
    });

    test('creates signal snapshot from platform map', () {
      final signals = SerialControlSignals.fromMap({
        'mask': 0x1f,
        'rts': true,
        'cts': true,
        'dtr': true,
        'dsr': true,
        'dcd': true,
      });

      expect(signals.mask, 0x1f);
      expect(signals.rts, true);
      expect(signals.cts, true);
      expect(signals.dtr, true);
      expect(signals.dsr, true);
      expect(signals.dcd, true);
    });

    test('copyWith, equality, hashCode and toString are stable', () {
      const signals = SerialControlSignals(mask: 1, rts: true);
      final modified = signals.copyWith(
        mask: 2,
        rts: false,
        cts: true,
        dtr: true,
        dsr: true,
        dcd: true,
      );

      expect(modified.mask, 2);
      expect(modified.rts, false);
      expect(modified.cts, true);
      expect(modified.dtr, true);
      expect(modified.dsr, true);
      expect(modified.dcd, true);
      expect(signals.copyWith(), signals);
      expect(signals == Object(), isFalse);
      expect(signals.hashCode,
          const SerialControlSignals(mask: 1, rts: true).hashCode);
      expect(signals.toString(), contains('SerialControlSignals'));
    });
  });

  group('SerialError', () {
    test('creates error with type and message', () {
      final error = SerialError(
        type: SerialErrorType.portNotFound,
        message: 'Port not found',
      );

      expect(error.type, SerialErrorType.portNotFound);
      expect(error.message, 'Port not found');
      expect(error.stackTrace, isNull);
    });

    test('creates error with stack trace', () {
      final st = StackTrace.current;
      final error = SerialError(
        type: SerialErrorType.timeout,
        message: 'Timeout',
        stackTrace: st,
      );

      expect(error.type, SerialErrorType.timeout);
      expect(error.stackTrace, st);
    });

    test('toString includes type and message', () {
      final error = SerialError(
        type: SerialErrorType.ioError,
        message: 'I/O error',
      );

      expect(error.toString(), contains('SerialError'));
      expect(error.toString(), contains('ioError'));
      expect(error.toString(), contains('I/O error'));
    });

    test('implements Exception', () {
      final error = SerialError(
        type: SerialErrorType.unknown,
        message: 'Unknown error',
      );

      expect(error, isA<Exception>());
    });
  });

  group('SerialDataType', () {
    test('enum contains binary and text', () {
      expect(SerialDataType.binary, isNotNull);
      expect(SerialDataType.text, isNotNull);
      expect(SerialDataType.values.length, 2);
    });
  });
}
