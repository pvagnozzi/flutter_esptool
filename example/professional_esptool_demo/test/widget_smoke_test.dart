// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_test/flutter_test.dart';
import 'package:professional_esptool_demo/main.dart';

void main() {
  testWidgets('renders app shell', (tester) async {
    await tester.pumpWidget(const ProfessionalEspToolDemoApp());
    expect(find.textContaining('firmware toolkit'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsOneWidget);
  });
}
