// coverage:ignore-file

import 'dart:io' show Platform;
import 'dart:typed_data';

import '../models/serial_config.dart';
import '../models/serial_control_signals.dart';
import '../models/serial_error.dart';
import '../models/serial_port_info.dart';
import 'serial_platform_interface.dart';
import 'windows_impl.dart';

SerialPlatformInterface createSerialPlatformInterface() {
  if (Platform.isWindows) {
    return WindowsSerialImpl();
  }
  return _UnsupportedSerialPlatformInterface();
}

class _UnsupportedSerialPlatformInterface implements SerialPlatformInterface {
  Never _unsupported() {
    throw SerialError(
      type: SerialErrorType.platformUnavailable,
      message:
          'platform_serial direct Dart mode supports Windows only; use Flutter runtime for other platforms.',
    );
  }

  @override
  Future<List<SerialPortInfo>> getAvailablePorts() async => _unsupported();
  @override
  Future<void> openPort(SerialConfig config) async => _unsupported();
  @override
  Future<void> closePort(String portName) async => _unsupported();
  @override
  Future<Uint8List> readData(String portName, int length) async => _unsupported();
  @override
  Future<int> writeData(String portName, Uint8List data) async => _unsupported();
  @override
  Future<int> bytesAvailable(String portName) async => _unsupported();
  @override
  Future<void> resetBuffers(String portName) async => _unsupported();
  @override
  Future<void> flush(String portName) async => _unsupported();
  @override
  Future<SerialControlSignals> getControlSignals(String portName) async =>
      _unsupported();
  @override
  Future<void> setDtr(String portName, bool enabled) async => _unsupported();
  @override
  Future<void> setRts(String portName, bool enabled) async => _unsupported();
  @override
  Stream<dynamic> getEventStream(String portName) => _unsupported();
}
