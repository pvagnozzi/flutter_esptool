// Copyright (c) 2026 Piergiorgio Vagnozzi.
// Licensed under the MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_serial/platform_serial.dart';
import 'package:platform_serial_example/src/localization/app_localizations.dart';
import 'package:platform_serial_example/src/services/serial_terminal_controller.dart';
import 'package:platform_serial_example/src/ui/serial_terminal_page.dart';

class _NoopConnection implements SerialConnection {
  @override
  bool get isOpen => true;

  @override
  Stream<String> get textStream => const Stream<String>.empty();

  @override
  Stream<SerialError> get errorStream => const Stream<SerialError>.empty();

  @override
  Future<void> close() async {}

  @override
  Future<int> writeText(String data) async => data.length;
}

class _FakeApi implements SerialApi {
  @override
  Future<List<SerialPortInfo>> getAvailablePorts() async {
    return const <SerialPortInfo>[
      SerialPortInfo(
        portName: 'COM4',
        description: 'Test Port',
        platform: 'windows',
      ),
    ];
  }

  @override
  Future<SerialConnection> openPort(SerialConfig config) async {
    return _NoopConnection();
  }
}

void main() {
  testWidgets('serial terminal page renders localized title', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    final SerialTerminalController controller = SerialTerminalController(
      api: _FakeApi(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SerialTerminalPage(
          controller: controller,
          currentLocale: const Locale('it'),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
          currentThemeMode: ThemeMode.system,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Terminale Seriale Platform'), findsOneWidget);
    expect(find.text('Parametri seriali'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
