import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_mobile/main.dart';

void main() {
  testWidgets('AEGIS app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AegisApp());
    expect(find.byType(AegisApp), findsOneWidget);
  });
}
