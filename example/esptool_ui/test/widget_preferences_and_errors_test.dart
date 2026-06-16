import 'package:esptool_ui/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';

void main() {
  testWidgets(
    'changes locale from dropdown on wide layout',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        app.EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM44',
              description: 'Mock',
              platform: 'windows',
            ),
          ],
          transportFactory: (_) => _NoopTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<Locale>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Italiano').last);
      await tester.pumpAndSettle();

      expect(find.text('Demo Professionale ESP Tool'), findsOneWidget);
      expect(find.text('Connetti'), findsOneWidget);
    },
  );

  testWidgets(
    'changes theme mode from dropdown on wide layout',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        app.EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM45',
              description: 'Mock',
              platform: 'windows',
            ),
          ],
          transportFactory: (_) => _NoopTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<ThemeMode>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);
    },
  );

  testWidgets(
    'serial timeout error keeps plugin available and shows error text',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        app.EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async {
            throw SerialError(
              type: SerialErrorType.timeout,
              message: 'port list timeout',
            );
          },
          transportFactory: (_) => _NoopTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('port list timeout'), findsOneWidget);
      expect(find.text('No serial ports detected'), findsOneWidget);

      final connectButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect'),
      );
      expect(connectButton.onPressed, isNull);
    },
  );

  testWidgets(
    'unexpected serial loader error shows plugin unavailable message',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        app.EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => throw StateError('boom'),
          transportFactory: (_) => _NoopTransport(),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('Serial plugin unavailable. Run on a supported target.'),
        findsOneWidget,
      );
    },
  );

}

class _NoopTransport implements EspTransportInterface {
  @override
  bool get isOpen => false;

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> open(EspConfig config) async {}

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout}) {
    throw UnimplementedError('Not used in these widget tests');
  }
}
