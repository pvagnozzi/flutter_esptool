/// Error types specific to serial communication.
enum SerialErrorType {
  /// Port not found.
  portNotFound,

  /// Port already open.
  portAlreadyOpen,

  /// Port not open.
  portClosed,

  /// Configuration error.
  configurationError,

  /// Timeout during read/write.
  timeout,

  /// Unsupported platform.
  platformUnavailable,

  /// Generic I/O error.
  ioError,

  /// Permission error.
  permissionDenied,

  /// Buffer full.
  bufferOverflow,

  /// Unknown error.
  unknown,
}

/// Represents a serial communication error.
class SerialError implements Exception {
  /// Error type.
  final SerialErrorType type;

  /// Error message.
  final String message;

  /// Optional stack trace.
  final StackTrace? stackTrace;

  /// Creates a new [SerialError].
  SerialError({
    required this.type,
    required this.message,
    this.stackTrace,
  });

  @override
  String toString() => 'SerialError: [$type] $message';
}
