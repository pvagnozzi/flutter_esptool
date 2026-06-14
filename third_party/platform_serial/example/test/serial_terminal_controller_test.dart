// Copyright (c) 2026 Piergiorgio Vagnozzi.
// Licensed under the MIT License.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';
import 'package:platform_serial_example/src/services/serial_terminal_controller.dart';

class FakeSerialConnection implements SerialConnection {
  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  final StreamController<SerialError> _errorController =
      StreamController<SerialError>.broadcast();
  bool _open = true;
  final List<String> sent = <String>[];

  @override
  bool get isOpen => _open;

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  Stream<SerialError> get errorStream => _errorController.stream;

  @override
  Future<void> close() async {
    _open = false;
    await _textController.close();
    await _errorController.close();
  }

  @override
  Future<int> writeText(String data) async {
    sent.add(data);
    return data.length;
  }

  void emitText(String value) => _textController.add(value);
}

class FakeSerialApi implements SerialApi {
  final List<SerialPortInfo> ports;
  final FakeSerialConnection connection = FakeSerialConnection();
  SerialConfig? openedConfig;

  FakeSerialApi(this.ports);

  @override
  Future<List<SerialPortInfo>> getAvailablePorts() async => ports;

  @override
  Future<SerialConnection> openPort(SerialConfig config) async {
    openedConfig = config;
    return connection;
  }
}

void main() {
  test('controller refreshes, opens and sends data', () async {
    final FakeSerialApi api = FakeSerialApi(
      const <SerialPortInfo>[
        SerialPortInfo(
          portName: 'COM7',
          description: 'USB Serial Device',
          platform: 'windows',
        ),
      ],
    );
    final SerialTerminalController controller =
        SerialTerminalController(api: api);

    await controller.refreshPorts();
    expect(controller.availablePorts, hasLength(1));

    await controller.open(
      const SerialConfig(portName: 'COM7', baudRate: 57600),
    );
    expect(api.openedConfig?.portName, 'COM7');
    expect(controller.isConnected, true);

    api.connection.emitText('HELLO');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      controller.entries.any((entry) => entry.message == 'HELLO'),
      isTrue,
    );

    await controller.sendText('AT');
    expect(api.connection.sent, contains('AT'));

    await controller.close();
    expect(controller.isConnected, false);
  });
}
