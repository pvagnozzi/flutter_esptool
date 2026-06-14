// Copyright (c) 2026 Piergiorgio Vagnozzi.
// Licensed under the MIT License.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform_serial/platform_serial.dart';

class _MockSerialPlatformInterface extends Mock
    implements SerialPlatformInterface {}

void main() {
  setUpAll(() {
    registerFallbackValue(const SerialConfig(portName: 'COM1'));
    registerFallbackValue(Uint8List(0));
  });

  test('openPortFromConfig forwards full serial configuration', () async {
    final _MockSerialPlatformInterface platform =
        _MockSerialPlatformInterface();
    final SerialManager manager = SerialManager(platform: platform);

    when(() => platform.openPort(any())).thenAnswer((_) async {});
    when(() => platform.getEventStream(any()))
        .thenAnswer((_) => const Stream<dynamic>.empty());
    when(() => platform.closePort(any())).thenAnswer((_) async {});

    const SerialConfig config = SerialConfig(
      portName: 'COM9',
      baudRate: 57600,
      dataBits: 7,
      stopBits: SerialStopBits.two,
      parity: SerialParity.even,
      flowControl: SerialFlowControl.rtscts,
      readTimeout: Duration(milliseconds: 1500),
      writeTimeout: Duration(milliseconds: 900),
    );

    final SerialPort port = await manager.openPortFromConfig(config);

    expect(port.isOpen, isTrue);
    verify(() => platform.openPort(config)).called(1);
    await manager.closeAll();
  });
}
