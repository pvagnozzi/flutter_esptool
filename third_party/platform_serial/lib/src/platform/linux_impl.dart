import 'package:flutter/services.dart';

import '../models/serial_error.dart';

/// Platform-specific implementation for Linux using FFI.
class LinuxSerialImpl {
  static const platform = MethodChannel('dev.flutter/platform_serial/linux');
  static const eventChannel =
      EventChannel('dev.flutter/platform_serial/linux/events');

  /// Gets the available serial ports on Linux.
  static Future<List<Map<String, dynamic>>> getAvailablePorts() async {
    try {
      final result =
          await platform.invokeMethod<List<dynamic>>('getAvailablePorts');
      return result
              ?.map((port) => Map<String, dynamic>.from(port as Map))
              .toList() ??
          [];
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.platformUnavailable,
        message: 'Error retrieving Linux ports: $e',
      );
    }
  }

  /// Opens a port on Linux.
  static Future<void> openPort({
    required String portName,
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required int parity,
    required int flowControl,
    required int readTimeout,
    required int writeTimeout,
  }) async {
    try {
      await platform.invokeMethod('openPort', {
        'portName': portName,
        'baudRate': baudRate,
        'dataBits': dataBits,
        'stopBits': stopBits,
        'parity': parity,
        'flowControl': flowControl,
        'readTimeout': readTimeout,
        'writeTimeout': writeTimeout,
      });
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error opening port on Linux: $e',
      );
    }
  }

  /// Closes a port on Linux.
  static Future<void> closePort(String portName) async {
    try {
      await platform.invokeMethod('closePort', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error closing port on Linux: $e',
      );
    }
  }

  /// Reads data from a port on Linux.
  static Future<Uint8List> readData(String portName, int length) async {
    try {
      final result = await platform.invokeMethod<Uint8List>(
        'readData',
        {'portName': portName, 'length': length},
      );
      return result ?? Uint8List(0);
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error reading on Linux: $e',
      );
    }
  }

  /// Writes data to a port on Linux.
  static Future<int> writeData(String portName, Uint8List data) async {
    try {
      final result = await platform.invokeMethod<int>(
        'writeData',
        {'portName': portName, 'data': data},
      );
      return result ?? 0;
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error writing on Linux: $e',
      );
    }
  }

  /// Gets the number of available bytes on Linux.
  static Future<int> bytesAvailable(String portName) async {
    try {
      final result = await platform.invokeMethod<int>(
        'bytesAvailable',
        {'portName': portName},
      );
      return result ?? 0;
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error retrieving available bytes on Linux: $e',
      );
    }
  }

  /// Resets buffers on Linux.
  static Future<void> resetBuffers(String portName) async {
    try {
      await platform.invokeMethod('resetBuffers', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error resetting buffers on Linux: $e',
      );
    }
  }

  /// Flushes the output buffer on Linux.
  static Future<void> flush(String portName) async {
    try {
      await platform.invokeMethod('flush', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error flushing buffer on Linux: $e',
      );
    }
  }

  /// Gets the event stream on Linux.
  static Stream<dynamic> getEventStream(String portName) {
    return eventChannel
        .receiveBroadcastStream({'portName': portName})
        .handleError((error) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Linux stream error: $error',
      );
    });
  }
}
