import 'dart:typed_data';

import 'package:esptool_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders write flash dialog with address and .bin picker controls',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM22',
              description: 'USB Serial Device',
              platform: 'windows',
            ),
          ],
          transportFactory: (_) => _SyncTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write flash'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Binary file'), findsOneWidget);
      expect(find.text('Select .bin'), findsOneWidget);
      expect(find.text('Add binary'), findsOneWidget);
    },
  );

  testWidgets(
    'renders home controls on narrow screens with connect disabled when no ports exist',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 640));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[],
          transportFactory: (_) => _IdleTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('No serial ports detected'), findsWidgets);

      final connectButton = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(connectButton.onPressed, isNull);
    },
  );
}

class _SyncTransport extends _IdleTransport {
  @override
  Future<EspResponse> sendCommand(EspCommand command,
      {Duration? timeout}) async {
    return EspResponse(
      opcode: command.opcode,
      value: 0,
      data: Uint8List(0),
      status: 0,
      error: 0,
    );
  }
}

class _IdleTransport implements EspTransportInterface {
  bool _open = false;

  @override
  bool get isOpen => _open;

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<void> close() async {
    _open = false;
  }

  @override
  Future<void> open(EspConfig config) async {
    _open = true;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout}) {
    throw UnimplementedError(
        'Transport commands are not exercised in widget tests.');
  }
}
