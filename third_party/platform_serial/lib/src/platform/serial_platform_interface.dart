// coverage:ignore-file

import 'dart:typed_data';

import '../models/serial_config.dart';
import '../models/serial_control_signals.dart';
import '../models/serial_port_info.dart';
import 'serial_platform_interface_io.dart'
    if (dart.library.html) 'serial_platform_interface_web.dart'
    if (dart.library.js) 'serial_platform_interface_web.dart'
    if (dart.library.js_interop) 'serial_platform_interface_web.dart'
    if (dart.library.ui) 'serial_platform_interface_flutter.dart';

/// Platform interface for serial communication.
/// Provides the base methods for platform-specific implementations.
abstract class SerialPlatformInterface {
  factory SerialPlatformInterface() => createSerialPlatformInterface();

  Future<List<SerialPortInfo>> getAvailablePorts();

  Future<void> openPort(SerialConfig config);

  Future<void> closePort(String portName);

  Future<Uint8List> readData(String portName, int length);

  Future<int> writeData(String portName, Uint8List data);

  Future<int> bytesAvailable(String portName);

  Future<void> resetBuffers(String portName);

  Future<void> flush(String portName);

  Future<SerialControlSignals> getControlSignals(String portName);

  Future<void> setDtr(String portName, bool enabled);

  Future<void> setRts(String portName, bool enabled);

  Stream<dynamic> getEventStream(String portName);
}
