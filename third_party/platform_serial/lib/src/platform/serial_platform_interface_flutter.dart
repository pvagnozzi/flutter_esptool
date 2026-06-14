// coverage:ignore-file

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/serial_config.dart';
import '../models/serial_control_signals.dart';
import '../models/serial_error.dart';
import '../models/serial_port_info.dart';
import 'ios_impl.dart';
import 'macos_impl.dart';
import 'serial_platform_interface.dart';
import 'windows_impl.dart';

const int _linuxSignalRts = 1 << 0;
const int _linuxSignalDtr = 1 << 2;

SerialPlatformInterface createSerialPlatformInterface() {
  if (Platform.isWindows) {
    return WindowsSerialImpl();
  }
  return MethodChannelSerialPlatformInterface();
}

/// MethodChannel-based fallback implementation for non-Windows platforms.
class MethodChannelSerialPlatformInterface implements SerialPlatformInterface {
  static const platform = MethodChannel('dev.flutter/platform_serial');
  static const eventChannel =
      EventChannel('dev.flutter/platform_serial_events');

  @override
  Future<List<SerialPortInfo>> getAvailablePorts() async {
    if (Platform.isMacOS) {
      final ports = await MacOSSerialImpl.getAvailablePorts();
      return ports.map((port) {
        return SerialPortInfo(
          portName: port['portName'] as String? ?? 'Unknown',
          description: port['description'] as String? ?? '',
          vendorId: port['vendorId'] as String?,
          productId: port['productId'] as String?,
          serialNumber: port['serialNumber'] as String?,
          isOpen: port['isOpen'] as bool? ?? false,
          platform: port['platform'] as String? ?? 'macos',
        );
      }).toList(growable: false);
    }

    if (Platform.isIOS) {
      final ports = await IOSSerialImpl.getAvailablePorts();
      return ports.map((port) {
        return SerialPortInfo(
          portName: port['portName'] as String? ?? 'Unknown',
          description: port['description'] as String? ?? '',
          vendorId: port['vendorId'] as String?,
          productId: port['productId'] as String?,
          serialNumber: port['serialNumber'] as String?,
          isOpen: port['isOpen'] as bool? ?? false,
          platform: port['platform'] as String? ?? 'ios',
        );
      }).toList(growable: false);
    }

    try {
      final ports = await platform.invokeMethod<List<dynamic>>(
        'getAvailablePorts',
      );
      if (ports == null) {
        return [];
      }

      return ports
          .map((port) {
            if (port is Map) {
              return SerialPortInfo(
                portName: port['portName'] as String? ?? 'Unknown',
                description: port['description'] as String? ?? '',
                vendorId: port['vendorId'] as String?,
                productId: port['productId'] as String?,
                serialNumber: port['serialNumber'] as String?,
                isOpen: port['isOpen'] as bool? ?? false,
                platform: port['platform'] as String? ?? 'unknown',
              );
            }
            return null;
          })
          .whereType<SerialPortInfo>()
          .toList(growable: false);
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.platformUnavailable,
        message: 'Error retrieving ports: $e',
      );
    }
  }

  @override
  Future<void> openPort(SerialConfig config) async {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.openPort(
        portName: config.portName,
        baudRate: config.baudRate,
        dataBits: config.dataBits,
        stopBits: config.stopBits.index,
        parity: config.parity.index,
        flowControl: config.flowControl.index,
        readTimeout: config.readTimeout.inMilliseconds,
        writeTimeout: config.writeTimeout.inMilliseconds,
      );
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.openPort(
        portName: config.portName,
        baudRate: config.baudRate,
        dataBits: config.dataBits,
        stopBits: config.stopBits.index,
        parity: config.parity.index,
        flowControl: config.flowControl.index,
        readTimeout: config.readTimeout.inMilliseconds,
        writeTimeout: config.writeTimeout.inMilliseconds,
      );
    }

    try {
      await platform.invokeMethod('openPort', {
        'portName': config.portName,
        'baudRate': config.baudRate,
        'dataBits': config.dataBits,
        'stopBits': config.stopBits.index,
        'parity': config.parity.index,
        'flowControl': config.flowControl.index,
        'readTimeout': config.readTimeout.inMilliseconds,
        'writeTimeout': config.writeTimeout.inMilliseconds,
      });
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error opening port: $e',
      );
    }
  }

  @override
  Future<void> closePort(String portName) async {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.closePort(portName);
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.closePort(portName);
    }

    try {
      await platform.invokeMethod('closePort', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error closing port: $e',
      );
    }
  }

  @override
  Future<Uint8List> readData(String portName, int length) async {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.readData(portName, length);
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.readData(portName, length);
    }

    try {
      final result = await platform.invokeMethod<Uint8List>(
        'readData',
        {'portName': portName, 'length': length},
      );
      return result ?? Uint8List(0);
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error reading data: $e',
      );
    }
  }

  @override
  Future<int> writeData(String portName, Uint8List data) async {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.writeData(portName, data);
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.writeData(portName, data);
    }

    try {
      final result = await platform.invokeMethod<int>(
        'writeData',
        {'portName': portName, 'data': data},
      );
      return result ?? 0;
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error writing data: $e',
      );
    }
  }

  @override
  Future<int> bytesAvailable(String portName) async {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.bytesAvailable(portName);
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.bytesAvailable(portName);
    }

    try {
      final result = await platform.invokeMethod<int>(
        'bytesAvailable',
        {'portName': portName},
      );
      return result ?? 0;
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error retrieving available bytes: $e',
      );
    }
  }

  @override
  Future<void> resetBuffers(String portName) async {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.resetBuffers(portName);
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.resetBuffers(portName);
    }

    try {
      await platform.invokeMethod('resetBuffers', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error resetting buffers: $e',
      );
    }
  }

  @override
  Future<void> flush(String portName) async {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.flush(portName);
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.flush(portName);
    }

    try {
      await platform.invokeMethod('flush', {'portName': portName});
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error flushing buffer: $e',
      );
    }
  }

  @override
  Future<SerialControlSignals> getControlSignals(String portName) async {
    if (Platform.isLinux) {
      try {
        final result = await platform.invokeMethod<Map<dynamic, dynamic>>(
          'getControlSignals',
          {'portName': portName},
        );
        return SerialControlSignals.fromMap(result ?? const {});
      } catch (e) {
        throw SerialError(
          type: SerialErrorType.ioError,
          message: 'Error reading control signals: $e',
        );
      }
    }

    throw SerialError(
      type: SerialErrorType.platformUnavailable,
      message: 'CTS/DTR status is not supported on this platform.',
    );
  }

  @override
  Future<void> setDtr(String portName, bool enabled) async {
    if (Platform.isLinux) {
      return _setLinuxControlSignal(portName, _linuxSignalDtr, enabled);
    }

    throw SerialError(
      type: SerialErrorType.platformUnavailable,
      message: 'DTR control is not supported on this platform implementation.',
    );
  }

  @override
  Future<void> setRts(String portName, bool enabled) async {
    if (Platform.isLinux) {
      return _setLinuxControlSignal(portName, _linuxSignalRts, enabled);
    }

    throw SerialError(
      type: SerialErrorType.platformUnavailable,
      message: 'RTS control is not supported on this platform implementation.',
    );
  }

  Future<void> _setLinuxControlSignal(
    String portName,
    int signalMask,
    bool enabled,
  ) async {
    try {
      await platform.invokeMethod('setControlSignals', {
        'portName': portName,
        'setMask': enabled ? signalMask : 0,
        'clearMask': enabled ? 0 : signalMask,
      });
    } catch (e) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Error setting control signal: $e',
      );
    }
  }

  @override
  Stream<dynamic> getEventStream(String portName) {
    if (Platform.isMacOS) {
      return MacOSSerialImpl.getEventStream(portName);
    }

    if (Platform.isIOS) {
      return IOSSerialImpl.getEventStream(portName);
    }

    return eventChannel
        .receiveBroadcastStream({'portName': portName}).handleError((error) {
      throw SerialError(
        type: SerialErrorType.ioError,
        message: 'Event stream error: $error',
      );
    });
  }
}
