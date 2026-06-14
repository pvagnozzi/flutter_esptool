import 'dart:async';
import 'dart:typed_data';

import '../models/serial_config.dart';
import '../models/serial_control_signals.dart';
import '../models/serial_error.dart';

/// Abstract contract for the serial port interface.
abstract interface class SerialPortInterface {
  /// Current port configuration.
  SerialConfig get config;

  /// Whether the port is open.
  bool get isOpen;

  /// Stream of received binary data.
  Stream<Uint8List> get dataStream;

  /// Stream of received text data.
  Stream<String> get textStream;

  /// Stream of errors.
  Stream<SerialError> get errorStream;

  /// Opens the serial port with the specified configuration.
  Future<void> open(SerialConfig config);

  /// Closes the serial port.
  Future<void> close();

  /// Reads data synchronously with an optional timeout.
  /// Throws [SerialError] if the port is not open or on timeout.
  Future<Uint8List> readSync({Duration? timeout});

  /// Reads text data synchronously with an optional timeout.
  /// Throws [SerialError] if the port is not open or on timeout.
  Future<String> readTextSync({Duration? timeout});

  /// Reads up to the specified number of bytes.
  /// Returns available data or waits until timeout.
  Future<Uint8List> read(int length, {Duration? timeout});

  /// Reads until the terminator string is found.
  /// Throws [SerialError] if it is not found within the timeout.
  Future<String> readUntil(String terminator, {Duration? timeout});

  /// Writes binary data to the port.
  /// Returns the number of bytes written.
  Future<int> write(Uint8List data, {Duration? timeout});

  /// Writes text data to the port.
  /// Returns the number of bytes written.
  Future<int> writeText(String data, {Duration? timeout});

  /// Flushes the output buffer.
  Future<void> flush();

  /// Gets the number of bytes available in the input buffer.
  Future<int> bytesAvailable();

  /// Gets the current modem control/status signal states.
  ///
  /// Throws [SerialErrorType.platformUnavailable] on platforms that do not
  /// expose modem-control status.
  Future<SerialControlSignals> getControlSignals();

  /// Returns whether the CTS input line is currently asserted.
  Future<bool> getCts();

  /// Resets the input and output buffers.
  Future<void> resetBuffers();

  /// Sets the DTR modem control line.
  Future<void> setDtr(bool enabled);

  /// Sets the RTS modem control line.
  Future<void> setRts(bool enabled);
}
