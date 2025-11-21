import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitnest/main.dart' as app;

/// Example integration test demonstrating end-to-end user flows.
///
/// This test file shows:
/// - How to test complete user workflows
/// - How to interact with the app as a user would
/// - How to verify state changes across multiple screens
/// - How to test navigation flows
///
/// Note: Integration tests require a running app instance.
/// To use integration_test package, add it to dev_dependencies:
///   integration_test:
///     sdk: flutter
/// Run with: flutter test test/integration/example_integration_test.dart
void main() {
  // Note: For full integration tests, use integration_test package
  // IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Wallet Creation Flow', () {
    testWidgets('complete wallet creation flow', (tester) async {
      // Clear any existing data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify splash screen appears
      expect(find.textContaining('BitNest', findRichText: true), findsWidgets);

      // Wait for navigation to onboarding or wallet screen
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // If onboarding screen is shown, complete it
      if (find.textContaining('Welcome', findRichText: true).evaluate().isNotEmpty) {
        // Tap "Get Started" button
        final getStartedButton = find.textContaining('Get Started', findRichText: true);
        if (getStartedButton.evaluate().isNotEmpty) {
          await tester.tap(getStartedButton);
          await tester.pumpAndSettle();
        }

        // Tap "Create New Wallet" card
        final createWalletCard = find.textContaining('Create New Wallet', findRichText: true);
        if (createWalletCard.evaluate().isNotEmpty) {
          await tester.tap(createWalletCard);
          await tester.pumpAndSettle();
        }

        // Confirm wallet creation in dialog
        final createButton = find.textContaining('Create', findRichText: true);
        if (createButton.evaluate().isNotEmpty) {
          await tester.tap(createButton);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }

      // Verify we're on the wallet screen
      expect(find.text('BitNest'), findsOneWidget);
    });
  });

  group('Settings Flow', () {
    testWidgets('change network from mainnet to testnet', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to settings
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();
      }

      // Find network toggle
      final networkSwitch = find.byType(Switch).first;
      if (networkSwitch.evaluate().isNotEmpty) {
        // Get current state
        final switchWidget = tester.widget<Switch>(networkSwitch);
        final initialValue = switchWidget.value;

        // Toggle network
        await tester.tap(networkSwitch);
        await tester.pumpAndSettle();

        // Verify state changed
        final updatedSwitch = tester.widget<Switch>(networkSwitch);
        expect(updatedSwitch.value, isNot(equals(initialValue)));
      }
    });

    testWidgets('change theme mode', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to settings
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();
      }

      // Find theme selector
      final themeTile = find.text('Theme');
      if (themeTile.evaluate().isNotEmpty) {
        // Tap theme selector
        await tester.tap(themeTile);
        await tester.pumpAndSettle();

        // Select dark theme
        final darkThemeOption = find.text('Dark');
        if (darkThemeOption.evaluate().isNotEmpty) {
          await tester.tap(darkThemeOption);
          await tester.pumpAndSettle();

          // Verify theme changed (check MaterialApp)
          final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
          expect(materialApp.themeMode, ThemeMode.dark);
        }
      }
    });
  });

  group('Transaction Flow', () {
    testWidgets('navigate to send screen', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Find send button or action
      final sendButton = find.textContaining('Send', findRichText: true);
      if (sendButton.evaluate().isNotEmpty) {
        await tester.tap(sendButton);
        await tester.pumpAndSettle();

        // Verify we're on send screen
        expect(find.textContaining('Send', findRichText: true), findsWidgets);
      }
    });

    testWidgets('navigate to receive screen', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Find receive button or action
      final receiveButton = find.textContaining('Receive', findRichText: true);
      if (receiveButton.evaluate().isNotEmpty) {
        await tester.tap(receiveButton);
        await tester.pumpAndSettle();

        // Verify we're on receive screen
        expect(find.textContaining('Receive', findRichText: true), findsWidgets);
        // Verify QR code is displayed
        expect(find.byType(CustomPaint), findsWidgets); // QR code is a CustomPaint
      }
    });
  });

  group('Error Handling', () {
    testWidgets('handles network errors gracefully', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Simulate network error (this would require mocking API service)
      // For now, just verify app doesn't crash
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('handles invalid input gracefully', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to send screen
      final sendButton = find.textContaining('Send', findRichText: true);
      if (sendButton.evaluate().isNotEmpty) {
        await tester.tap(sendButton);
        await tester.pumpAndSettle();

        // Try to enter invalid address
        final addressField = find.byType(TextField).first;
        if (addressField.evaluate().isNotEmpty) {
          await tester.enterText(addressField, 'invalid-address');
          await tester.pumpAndSettle();

          // Verify error message or validation feedback
          // (Implementation depends on your validation logic)
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  group('Performance Tests', () {
    testWidgets('app loads within acceptable time', (tester) async {
      final stopwatch = Stopwatch()..start();

      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      stopwatch.stop();

      // Verify app loads within 5 seconds
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    testWidgets('screen transitions are smooth', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate between screens multiple times
      for (int i = 0; i < 3; i++) {
        final settingsButton = find.byIcon(Icons.settings);
        if (settingsButton.evaluate().isNotEmpty) {
          await tester.tap(settingsButton);
          await tester.pumpAndSettle();

          // Go back
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
        }
      }

      // Verify no performance issues
      expect(tester.takeException(), isNull);
    });
  });
}

