// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Error categories for ESP serial and flashing operations.
enum EspErrorType {
  connectionFailed,
  syncFailed,
  timeout,
  invalidResponse,
  checksumMismatch,
  portUnavailable,
  badBaudRate,
  invalidChip,
  flashReadFailed,
  flashWriteFailed,
  flashEraseFailed,
  flashVerifyFailed,
  partialPacket,
  stubNotAvailable,
  compressionError,
  imageParseError,
  unsupportedOperation,
  /// The circuit breaker is open — requests are rejected immediately.
  circuitBreakerOpen,
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
