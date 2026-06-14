import 'package:flutter_test/flutter_test.dart';
import 'package:professional_esptool_demo/main.dart';

void main() {
  testWidgets('renders home controls', (WidgetTester tester) async {
    await tester.pumpWidget(const ProfessionalEspToolDemoApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsOneWidget);
  });
}
