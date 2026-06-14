import 'models/serial_config.dart';
import 'models/serial_port_info.dart';
import 'platform/serial_platform_interface.dart';
import 'serial_port.dart';

/// Central manager for serial ports.
/// Provides access to available ports and manages their lifecycle.
class SerialManager {
  SerialManager._internal({SerialPlatformInterface? platform})
      : _platform = platform ?? SerialPlatformInterface();

  factory SerialManager({SerialPlatformInterface? platform}) {
    if (platform != null) {
      _instance._platform = platform;
    }
    return _instance;
  }

  static final SerialManager _instance = SerialManager._internal();

  SerialPlatformInterface _platform;
  final Map<String, SerialPort> _openPorts = {};

  /// Gets the list of available serial ports.
  Future<List<SerialPortInfo>> getAvailablePorts() async {
    return _platform.getAvailablePorts();
  }

  /// Creates a new SerialPort instance for the specified port.
  /// The port is not opened until open() is called.
  SerialPort createPort() {
    return SerialPort(platform: _platform);
  }

  /// Opens a serial port and tracks it.
  Future<SerialPort> openPort(
    String portName, {
        int baudRate = 115200,
        int dataBits = 8
    }) =>
      openPortFromConfig(
          SerialConfig(
              portName: portName,
              baudRate: baudRate,
              dataBits: dataBits));

  /// Opens a serial port and tracks it.
  Future<SerialPort> openPortFromConfig(
      SerialConfig config) async {
    final portName = config.portName;
    final existingPort = _openPorts[portName];
    if (existingPort != null) {
      if (existingPort.isOpen) {
        return existingPort;
      }
      _openPorts.remove(portName);
    }

    final port = createPort();
    await port.open(config);
    _openPorts[portName] = port;
    return port;
  }

  /// Closes a tracked serial port.
  Future<void> closePort(String portName) async {
    final port = _openPorts.remove(portName);
    if (port != null) {
      await port.close();
    }
  }

  /// Closes all open ports.
  Future<void> closeAll() async {
    final ports = _openPorts.values.toList();
    _openPorts.clear();
    for (final port in ports) {
      try {
        await port.close();
      } catch (_) {
        // Continue with the remaining ports.
      }
    }
  }

  /// Gets an open port by name.
  SerialPort? getPort(String portName) => _openPorts[portName];

  /// Gets all open ports.
  Map<String, SerialPort> getOpenPorts() => Map.unmodifiable(_openPorts);
}
