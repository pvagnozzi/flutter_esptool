// coverage:ignore-file

import 'dart:typed_data';

import '../models/serial_config.dart';
import '../models/serial_control_signals.dart';
import '../models/serial_error.dart';
import '../models/serial_port_info.dart';
import 'serial_platform_interface.dart';

SerialPlatformInterface createSerialPlatformInterface() =>
    WebSerialPlatformInterface();

/// Web-safe placeholder implementation.
///
/// The package currently talks to platform-native serial backends. Returning a
/// deterministic platform-unavailable error lets Flutter web example apps run
/// and debug while the UI can display that serial I/O is unsupported there.
class WebSerialPlatformInterface implements SerialPlatformInterface {
  const WebSerialPlatformInterface();

  Never _unsupported() {
    throw SerialError(
      type: SerialErrorType.platformUnavailable,
      message: 'Serial ports are not available in the web backend.',
    );
  }

  @override
  Future<List<SerialPortInfo>> getAvailablePorts() async =>
      const <SerialPortInfo>[];

  @override
  Future<void> openPort(SerialConfig config) async => _unsupported();

  @override
  Future<void> closePort(String portName) async => _unsupported();

  @override
  Future<Uint8List> readData(String portName, int length) async =>
      _unsupported();

  @override
  Future<int> writeData(String portName, Uint8List data) async =>
      _unsupported();

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
  Stream<dynamic> getEventStream(String portName) => const Stream.empty();
}
