// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Error categories for ESP serial and flashing operations.
enum EspErrorType {
  /// The serial port connection could not be established.
  connectionFailed,

  /// The ROM bootloader SYNC handshake failed.
  syncFailed,

  /// A command or read operation exceeded its deadline.
  timeout,

  /// The device returned a malformed or unexpected response.
  invalidResponse,

  /// The response or image checksum did not match the expected value.
  checksumMismatch,

  /// The specified serial port is not available or could not be opened.
  portUnavailable,

  /// The device rejected the requested baud-rate change.
  badBaudRate,

  /// The connected chip could not be identified.
  invalidChip,

  /// A flash read operation failed.
  flashReadFailed,

  /// A flash write operation failed.
  flashWriteFailed,

  /// A flash erase operation failed.
  flashEraseFailed,

  /// Flash verification (MD5) failed.
  flashVerifyFailed,

  /// A complete SLIP frame was not received before the timeout.
  partialPacket,

  /// The flash stub is not available or not loaded.
  stubNotAvailable,

  /// zlib compression or decompression failed.
  compressionError,

  /// The ESP boot image could not be parsed.
  imageParseError,

  /// The requested operation is not supported by this chip or configuration.
  unsupportedOperation,

  /// The circuit breaker is open — requests are rejected immediately.
  circuitBreakerOpen,

  /// An unclassified error occurred.
  unknown,
}

/// Exception raised by flutter_esptool operations.
class EspError implements Exception {
  /// Creates an [EspError].
  const EspError({
    required this.type,
    required this.message,
    this.stackTrace,
  });

  /// The error category.
  final EspErrorType type;

  /// The human-readable message.
  final String message;

  /// The optional source stack trace.
  final StackTrace? stackTrace;

  @override
  String toString() => 'EspError[$type]: $message';
}
