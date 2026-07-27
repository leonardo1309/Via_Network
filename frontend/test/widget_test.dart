// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:via_network_movil/main.dart';

void main() {
  testWidgets('renders dashboard smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ViaNetworkApp());
    await tester.pump();

    expect(find.text('VIA NETWORK'), findsOneWidget);
    expect(find.text('MOSTRAR QR'), findsOneWidget);
    expect(find.text('ACTUALIZAR'), findsOneWidget);
    expect(find.text('PAGAR'), findsOneWidget);
  });
}
