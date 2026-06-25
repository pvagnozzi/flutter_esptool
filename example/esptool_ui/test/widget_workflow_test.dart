import 'dart:typed_data';

import 'package:esptool_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'good path workflow updates chip/mac/flash and logs erase + md5',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM9',
              description: 'USB Bridge',
              platform: 'windows',
            ),
          ],
          transportFactory: (_) => _ScriptedTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detect chip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read MAC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flash info'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read MD5'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chip: ESP32'), findsOneWidget);
      expect(find.textContaining('MAC: cc:dd:ee:ff:00:11'), findsWidgets);
      expect(find.textContaining('Flash: Winbond (0xef)'), findsOneWidget);
      expect(find.text('Flash erase completed'), findsOneWidget);
      expect(
        find.text('Device MD5: 0123456789abcdef0123456789abcdef'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'bad path shows connection failure log when transport open fails',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM5',
              description: 'Mock port',
              platform: 'windows',
            ),
          ],
          transportFactory: (_) => _ScriptedTransport(failOnOpen: true),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Connection failed: open timeout'), findsOneWidget);

      final detectButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Detect chip'),
      );
      expect(detectButton.onPressed, isNull);
    },
  );

  testWidgets(
    'edge path surfaces serial plugin unavailable and disables connect',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async {
            throw SerialError(
              type: SerialErrorType.platformUnavailable,
              message: 'platform plugin missing',
            );
          },
          transportFactory: (_) => _ScriptedTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('Serial plugin unavailable. Run on a supported target.'),
        findsOneWidget,
      );

      final connectButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect'),
      );
      expect(connectButton.onPressed, isNull);
    },
  );

  testWidgets(
    'write flash dialog validates missing file selection',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM3',
              description: 'Mock',
              platform: 'windows',
            ),
          ],
          transportFactory: (_) => _ScriptedTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();

      expect(find.text('Row 1: select a .bin file'), findsOneWidget);
    },
  );

  testWidgets(
    'write flash dialog validates malformed address values',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM31',
              description: 'Mock',
              platform: 'windows',
            ),
          ],
          transportFactory: (_) => _ScriptedTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write flash'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'not-an-address');
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();

      expect(find.text('Row 1: enter a valid address'), findsOneWidget);
    },
  );
}

class _ScriptedTransport implements EspTransportInterface {
  _ScriptedTransport({this.failOnOpen = false});

  final bool failOnOpen;
  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> open(EspConfig config) async {
    if (failOnOpen) {
      throw SerialError(type: SerialErrorType.timeout, message: 'open timeout');
    }
    _isOpen = true;
  }

  @override
  Future<void> close() async {
    _isOpen = false;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout}) async {
    switch (command.opcode) {
      case EspCommandOpcode.readReg:
        return _readRegister(command);
      case EspCommandOpcode.flashMd5:
        return EspResponse(
          opcode: command.opcode,
          value: 0,
          data: Uint8List.fromList(
            '0123456789abcdef0123456789abcdef'.codeUnits,
          ),
          status: 0,
          error: 0,
        );
      default:
        return EspResponse(
          opcode: command.opcode,
          value: 0,
          data: Uint8List(0),
          status: 0,
          error: 0,
        );
    }
  }

  EspResponse _readRegister(EspCommand command) {
    final payload = command.data;
    final address = ByteData.sublistView(payload).getUint32(0, Endian.little);

    final value = switch (address) {
      0x40001000 => 0x00F01D83,
      0x3FF5A00C => 1,
      0x3FF5A008 => 0xAABBCCDD,
      0x3FF5A004 => 0xEEFF0011,
      0x3FF42000 => 0,
      0x3FF4201C => 0,
      0x3FF42024 => 0,
      0x3FF42080 => 0x1840EF,
      _ => 0,
    };

    return EspResponse(
      opcode: command.opcode,
      value: value,
      data: Uint8List(0),
      status: 0,
      error: 0,
    );
  }
}
