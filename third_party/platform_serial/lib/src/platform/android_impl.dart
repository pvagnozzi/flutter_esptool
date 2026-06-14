import 'package:flutter/services.dart';

import '../models/serial_error.dart';

/// Platform-specific implementation for Android using Platform Channels.
class AndroidSerialImpl {
  static const platform = MethodChannel('dev.flutter/platform_serial');
  static const eventChannel = EventChannel('dev.flutter/platform_serial_events');

  /// Gets the available serial ports on Android (OTG).
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
        message: 'Error retrieving Android ports: $e',
      );
    }
  }

  /// Opens a port on Android (OTG).
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
        message: 'Error opening port on Android: $e',
      );
    }
  }

  /// Closes a port on Android.
  static Future<void> closePort(String portName) async {
    try {
      await platform.invokeMethod('closePort', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error closing port on Android: $e',
      );
    }
  }

  /// Reads data from a port on Android.
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
        message: 'Error reading on Android: $e',
      );
    }
  }

  /// Writes data to a port on Android.
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
        message: 'Error writing on Android: $e',
      );
    }
  }

  /// Gets the number of available bytes on Android.
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
        message: 'Error retrieving available bytes on Android: $e',
      );
    }
  }

  /// Resets buffers on Android.
  static Future<void> resetBuffers(String portName) async {
    try {
      await platform.invokeMethod('resetBuffers', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error resetting buffers on Android: $e',
      );
    }
  }

  /// Flushes the output buffer on Android.
  static Future<void> flush(String portName) async {
    try {
      await platform.invokeMethod('flush', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error flushing buffer on Android: $e',
      );
    }
  }

  /// Gets the event stream on Android.
  static Stream<dynamic> getEventStream(String portName) {
    return eventChannel
        .receiveBroadcastStream({'portName': portName}).handleError((error) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Android stream error: $error',
      );
    });
  }
}
