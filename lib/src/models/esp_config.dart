// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Configuration for an ESP serial session.
class EspConfig {
  /// Creates an [EspConfig].
  const EspConfig({
    required this.portName,
    this.initialBaudRate = 115200,
    this.flashBaudRate = 460800,
    this.timeout = const Duration(seconds: 3),
    this.syncRetries = 10,
    this.flashBlockSize = 0x4000,
  });

  /// The serial port name.
  final String portName;

  /// The baud rate used for the initial ROM connection.
  final int initialBaudRate;

  /// The baud rate used for higher speed flashing.
  final int flashBaudRate;

  /// The default command timeout.
  final Duration timeout;

  /// The number of sync retries.
  final int syncRetries;

  /// The flash block size.
  final int flashBlockSize;

  /// Creates a copy of this config with modified values.
  EspConfig copyWith({
    String? portName,
    int? initialBaudRate,
    int? flashBaudRate,
    Duration? timeout,
    int? syncRetries,
    int? flashBlockSize,
  }) {
    return EspConfig(
      portName: portName ?? this.portName,
      initialBaudRate: initialBaudRate ?? this.initialBaudRate,
      flashBaudRate: flashBaudRate ?? this.flashBaudRate,
      timeout: timeout ?? this.timeout,
      syncRetries: syncRetries ?? this.syncRetries,
      flashBlockSize: flashBlockSize ?? this.flashBlockSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EspConfig &&
            portName == other.portName &&
            initialBaudRate == other.initialBaudRate &&
            flashBaudRate == other.flashBaudRate &&
            timeout == other.timeout &&
            syncRetries == other.syncRetries &&
            flashBlockSize == other.flashBlockSize;
  }

  @override
  int get hashCode => Object.hash(
        portName,
        initialBaudRate,
        flashBaudRate,
        timeout,
        syncRetries,
        flashBlockSize,
      );

  @override
  String toString() {
    return 'EspConfig(portName: $portName, initialBaudRate: $initialBaudRate, '
        'flashBaudRate: $flashBaudRate, timeout: $timeout, '
        'syncRetries: $syncRetries, flashBlockSize: $flashBlockSize)';
  }
}
