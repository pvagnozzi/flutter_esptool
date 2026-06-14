// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:esptool_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'renders app shell on wide screens with flag asset and available port',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1100, 900));

    await tester.pumpWidget(
      EsptoolUiApp(
        splashDuration: Duration.zero,
        serialPortsLoader: () async => const <SerialPortInfo>[
          SerialPortInfo(
            portName: 'COM7',
            description: 'USB Serial Device',
            platform: 'windows',
          ),
        ],
        transportFactory: (_) => _IdleTransport(),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('firmware toolkit'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.textContaining('COM7'), findsOneWidget);

    final englishFlag = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == 'assets/flags/en.png',
    );
    expect(englishFlag, findsWidgets);

    final connectButton = tester.widget<FilledButton>(
      find.byType(FilledButton).first,
    );
    expect(connectButton.onPressed, isNotNull);
  });
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
