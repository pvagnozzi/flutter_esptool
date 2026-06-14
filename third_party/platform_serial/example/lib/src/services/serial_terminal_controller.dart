// Copyright (c) 2026 Piergiorgio Vagnozzi.
// Licensed under the MIT License.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:platform_serial/platform_serial.dart';

import '../models/terminal_entry.dart';

abstract class SerialConnection {
  bool get isOpen;
  Stream<String> get textStream;
  Stream<SerialError> get errorStream;
  Future<int> writeText(String data);
  Future<void> close();
}

abstract class SerialApi {
  Future<List<SerialPortInfo>> getAvailablePorts();
  Future<SerialConnection> openPort(SerialConfig config);
}

class PlatformSerialApi implements SerialApi {
  PlatformSerialApi({SerialManager? manager})
      : _manager = manager ?? SerialManager();

  final SerialManager _manager;

  @override
  Future<List<SerialPortInfo>> getAvailablePorts() {
    return _manager.getAvailablePorts();
  }

  @override
  Future<SerialConnection> openPort(SerialConfig config) async {
    final SerialPort port = await _manager.openPortFromConfig(config);
    return _PlatformSerialConnection(port);
  }
}

class _PlatformSerialConnection implements SerialConnection {
  _PlatformSerialConnection(this._port);

  final SerialPort _port;

  @override
  bool get isOpen => _port.isOpen;

  @override
  Stream<String> get textStream => _port.textStream;

  @override
  Stream<SerialError> get errorStream => _port.errorStream;

  @override
  Future<int> writeText(String data) => _port.writeText(data);

  @override
  Future<void> close() => _port.close();
}

class SerialTerminalController extends ChangeNotifier {
  SerialTerminalController({SerialApi? api})
      : _api = api ?? PlatformSerialApi();

  final SerialApi _api;

  List<SerialPortInfo> _availablePorts = const <SerialPortInfo>[];
  final List<TerminalEntry> _entries = <TerminalEntry>[];
  SerialConnection? _connection;
  StreamSubscription<String>? _textSubscription;
  StreamSubscription<SerialError>? _errorSubscription;
  String? _connectedPortName;
  bool _isBusy = false;

  List<SerialPortInfo> get availablePorts => _availablePorts;
  List<TerminalEntry> get entries => List.unmodifiable(_entries);
  bool get isConnected => _connection?.isOpen ?? false;
  bool get isBusy => _isBusy;
  String? get connectedPortName => _connectedPortName;

  Future<void> refreshPorts() async {
    _setBusy(true);
    try {
      _availablePorts = await _api.getAvailablePorts();
      if (_availablePorts.isEmpty) {
        _append(TerminalEntryType.system, 'No serial ports found.');
      }
    } catch (error) {
      _append(TerminalEntryType.error, 'Unable to list serial ports: $error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> open(SerialConfig config) async {
    _setBusy(true);
    try {
      if (isConnected) {
        await close();
      }
      _connection = await _api.openPort(config);
      _connectedPortName = config.portName;
      _textSubscription = _connection!.textStream.listen((String data) {
        _append(TerminalEntryType.incoming, data);
      });
      _errorSubscription = _connection!.errorStream.listen((SerialError error) {
        _append(TerminalEntryType.error, error.message);
      });
      _append(TerminalEntryType.system, 'Connected to ${config.portName}.');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> close() async {
    _setBusy(true);
    try {
      await _textSubscription?.cancel();
      await _errorSubscription?.cancel();
      _textSubscription = null;
      _errorSubscription = null;
      if (_connection != null && _connection!.isOpen) {
        await _connection!.close();
      }
      if (_connectedPortName != null) {
        _append(
            TerminalEntryType.system, 'Disconnected from $_connectedPortName.');
      }
      _connection = null;
      _connectedPortName = null;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty || !isConnected || _connection == null) {
      return;
    }
    try {
      await _connection!.writeText(text);
      _append(TerminalEntryType.outgoing, text);
    } catch (error) {
      _append(TerminalEntryType.error, 'Send error: $error');
      rethrow;
    }
  }

  void clearTerminal() {
    _entries.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  void _append(TerminalEntryType type, String message) {
    _entries.add(
      TerminalEntry(
        type: type,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
    if (_entries.length > 1000) {
      _entries.removeRange(0, _entries.length - 1000);
    }
    notifyListeners();
  }
}
