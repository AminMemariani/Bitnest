// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:bitnest/main.dart';

void main() {
  testWidgets('BitNest app loads and shows welcome screen', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BitNestApp());

    // Verify that the app title is displayed.
    expect(find.text('BitNest'), findsOneWidget);

    // Verify that the welcome screen is shown when no wallets exist.
    expect(find.text('Welcome to BitNest'), findsOneWidget);
    expect(
      find.text('Create your first Bitcoin wallet to get started'),
      findsOneWidget,
    );

    // There are multiple "Create Wallet" buttons (welcome screen + FAB),
    // so we check that at least one exists
    expect(find.text('Create Wallet'), findsWidgets);
  });
}
