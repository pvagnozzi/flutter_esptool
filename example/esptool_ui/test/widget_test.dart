import 'package:esptool_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders home controls with connect disabled when no ports exist',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      EsptoolUiApp(
        splashDuration: Duration.zero,
        serialPortsLoader: () async => const <SerialPortInfo>[],
        transportFactory: (_) => _IdleTransport(),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('No serial ports detected'), findsWidgets);

    final connectButton = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(connectButton.onPressed, isNull);
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
    throw UnimplementedError('Transport commands are not exercised in widget tests.');
  }
}
