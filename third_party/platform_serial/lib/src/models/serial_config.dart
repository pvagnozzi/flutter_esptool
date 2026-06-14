/// Enumeration for data bit parity.
enum SerialParity {
  /// No parity.
  none,

  /// Even parity.
  even,

  /// Odd parity.
  odd,

  /// Mark
  mark,

  /// Space
  space,
}

/// Enumeration for stop bits.
enum SerialStopBits {
  /// 1 stop bit.
  one,

  /// 1.5 stop bits.
  onePointFive,

  /// 2 stop bits.
  two,
}

/// Enumeration for flow control.
enum SerialFlowControl {
  /// No flow control.
  none,

  /// Hardware flow control (RTS/CTS).
  rtscts,

  /// Software flow control (XON/XOFF).
  xonxoff,
}

/// Serial port configuration.
class SerialConfig {
  /// Port name (for example COM1 or /dev/ttyUSB0).
  final String portName;

  /// Baud rate in bits per second.
  final int baudRate;

  /// Number of data bits (5-8).
  final int dataBits;

  /// Stop bits.
  final SerialStopBits stopBits;

  /// Parity type.
  final SerialParity parity;

  /// Flow control.
  final SerialFlowControl flowControl;

  /// Read timeout in milliseconds (0 = no timeout).
  final Duration readTimeout;

  /// Write timeout in milliseconds (0 = no timeout).
  final Duration writeTimeout;

  /// Creates a new serial port configuration.
  const SerialConfig({
    required this.portName,
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = SerialStopBits.one,
    this.parity = SerialParity.none,
    this.flowControl = SerialFlowControl.none,
    this.readTimeout = const Duration(seconds: 5),
    this.writeTimeout = const Duration(seconds: 5),
  }) : assert(
          dataBits >= 5 && dataBits <= 8,
          'dataBits must be between 5 and 8',
        );

  /// Creates a copy of this configuration with updated values.
  SerialConfig copyWith({
    String? portName,
    int? baudRate,
    int? dataBits,
    SerialStopBits? stopBits,
    SerialParity? parity,
    SerialFlowControl? flowControl,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) {
    return SerialConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      stopBits: stopBits ?? this.stopBits,
      parity: parity ?? this.parity,
      flowControl: flowControl ?? this.flowControl,
      readTimeout: readTimeout ?? this.readTimeout,
      writeTimeout: writeTimeout ?? this.writeTimeout,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialConfig &&
          runtimeType == other.runtimeType &&
          portName == other.portName &&
          baudRate == other.baudRate &&
          dataBits == other.dataBits &&
          stopBits == other.stopBits &&
          parity == other.parity &&
          flowControl == other.flowControl &&
          readTimeout == other.readTimeout &&
          writeTimeout == other.writeTimeout;

  @override
  int get hashCode =>
      portName.hashCode ^
      baudRate.hashCode ^
      dataBits.hashCode ^
      stopBits.hashCode ^
      parity.hashCode ^
      flowControl.hashCode ^
      readTimeout.hashCode ^
      writeTimeout.hashCode;

  @override
  String toString() =>
      'SerialConfig(port: $portName, baud: $baudRate, bits: $dataBits, '
      'stop: $stopBits, parity: $parity, flow: $flowControl)';
}
