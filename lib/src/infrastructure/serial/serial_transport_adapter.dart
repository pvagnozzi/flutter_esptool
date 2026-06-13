// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_config.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:platform_serial/platform_serial.dart';

/// Adapts [SerialPortInterface] errors into [EspError] failures.
class SerialTransportAdapter {
  /// Creates a [SerialTransportAdapter].
  SerialTransportAdapter(this.serial);

  /// The wrapped serial port.
  final SerialPortInterface serial;

  /// Opens the serial port using [config].
  Future<void> open(EspConfig config) async {
    try {
      await serial.open(
        SerialConfig(
          portName: config.portName,
          baudRate: config.initialBaudRate,
          readTimeout: config.timeout,
          writeTimeout: config.timeout,
        ),
      );
    } on SerialError catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  /// Closes the serial port.
  Future<void> close() async {
    try {
      await serial.close();
    } on SerialError catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  /// Reads up to [length] bytes.
  Future<Uint8List> read(int length, {Duration? timeout}) async {
    try {
      return await serial.read(length, timeout: timeout);
    } on SerialError catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  /// Writes [data] to the serial port.
  Future<int> write(Uint8List data, {Duration? timeout}) async {
    try {
      return await serial.write(data, timeout: timeout);
    } on SerialError catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  /// Flushes serial output.
  Future<void> flush() async {
    try {
      await serial.flush();
    } on SerialError catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  /// Resets serial input and output buffers.
  Future<void> resetBuffers() async {
    try {
      await serial.resetBuffers();
    } on SerialError catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  EspError _map(SerialError error, StackTrace stackTrace) {
    final type = switch (error.type) {
      SerialErrorType.portNotFound => EspErrorType.portUnavailable,
      SerialErrorType.timeout => EspErrorType.timeout,
      SerialErrorType.portClosed => EspErrorType.portUnavailable,
      SerialErrorType.ioError => EspErrorType.connectionFailed,
      _ => EspErrorType.connectionFailed,
    };
    return EspError(type: type, message: error.message, stackTrace: stackTrace);
  }
}
