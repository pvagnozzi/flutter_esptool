/// Information about an available serial port.
class SerialPortInfo {
  /// Port name (for example COM1 or /dev/ttyUSB0).
  final String portName;

  /// Port description.
  final String description;

  /// USB vendor ID, if available.
  final String? vendorId;

  /// USB product ID, if available.
  final String? productId;

  /// Device serial number, if available.
  final String? serialNumber;

  /// Whether the port is already open.
  final bool isOpen;

  /// Supported platform for the port.
  final String platform;

  /// Creates information for a serial port.
  const SerialPortInfo({
    required this.portName,
    required this.description,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.isOpen = false,
    required this.platform,
  });

  /// Creates a copy with updated values.
  SerialPortInfo copyWith({
    String? portName,
    String? description,
    String? vendorId,
    String? productId,
    String? serialNumber,
    bool? isOpen,
    String? platform,
  }) {
    return SerialPortInfo(
      portName: portName ?? this.portName,
      description: description ?? this.description,
      vendorId: vendorId ?? this.vendorId,
      productId: productId ?? this.productId,
      serialNumber: serialNumber ?? this.serialNumber,
      isOpen: isOpen ?? this.isOpen,
      platform: platform ?? this.platform,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialPortInfo &&
          runtimeType == other.runtimeType &&
          portName == other.portName &&
          description == other.description &&
          vendorId == other.vendorId &&
          productId == other.productId &&
          serialNumber == other.serialNumber &&
          isOpen == other.isOpen &&
          platform == other.platform;

  @override
  int get hashCode =>
      portName.hashCode ^
      description.hashCode ^
      vendorId.hashCode ^
      productId.hashCode ^
      serialNumber.hashCode ^
      isOpen.hashCode ^
      platform.hashCode;

  @override
  String toString() => 'SerialPortInfo(name: $portName, desc: $description, '
      'vid: $vendorId, pid: $productId, sn: $serialNumber, open: $isOpen)';
}
