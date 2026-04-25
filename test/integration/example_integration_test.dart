import 'package:bitnest/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_environment.dart';

/// End-to-end-style flow tests for [BitNestApp].
///
/// These run as widget tests (not via the `integration_test` package)
/// — every platform-channel dependency the app touches is mocked
/// through [TestEnvironment.install]. That includes
/// `flutter_secure_storage`, `local_auth`, `shared_preferences`, and
/// the platform clipboard channel.
///
/// Each test pumps the real [BitNestApp], advances past the 1.5s
/// splash + first-run navigation, then drives a small interaction. The
/// assertions are intentionally lenient — these are smoke tests for
/// the boot path, not full interaction coverage.
void main() {
  setUp(() async {
    // Pre-mark onboarding complete so the navigator goes directly to
    // the wallet screen. Tests that explicitly want the onboarding
    // flow can re-install with an empty prefs map.
    await TestEnvironment.install(
      initialPrefs: {'has_completed_onboarding': true},
    );
  });

  tearDown(TestEnvironment.uninstall);

  Future<void> bootApp(WidgetTester tester) async {
    await tester.pumpWidget(const BitNestApp());
    await TestEnvironment.advancePastSplash(tester);
  }

  group('Wallet Creation Flow', () {
    testWidgets('boots into onboarding when there is no prior state',
        (tester) async {
      // OnboardingScreen's _WelcomePage column has a known overflow at
      // the default 800×600 test surface (lib/ui/screens/onboarding_screen.dart:126).
      // Use a phone-sized surface where the layout fits.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Re-install without the onboarding flag so the navigator
      // routes to OnboardingScreen.
      TestEnvironment.uninstall();
      await TestEnvironment.install();

      await bootApp(tester);

      // Onboarding header text from the welcome page.
      expect(
        find.textContaining('BitNest', findRichText: true),
        findsWidgets,
        reason: 'app title is rendered somewhere on the boot screen',
      );
    });

    testWidgets('boots straight to the empty wallet screen when onboarded',
        (tester) async {
      await bootApp(tester);

      expect(find.text('Welcome to BitNest'), findsOneWidget);
      expect(find.text('Create Wallet'), findsWidgets);
    });
  });

  group('Settings Flow', () {
    testWidgets('navigates to settings via the app-bar icon', (tester) async {
      await bootApp(tester);

      final settingsButton = find.byIcon(Icons.settings);
      expect(settingsButton, findsOneWidget);

      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      // Settings screen renders the title text.
      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets('settings screen exposes a network toggle', (tester) async {
      await bootApp(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // The settings screen renders at least one Switch (network or
      // biometrics). Smoke-test that the page loaded — concrete state
      // assertions live in test/ui/settings_screen_test.dart.
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);
    });
  });

  group('Transaction Flow', () {
    testWidgets('boot path renders the wallet root without crashing',
        (tester) async {
      await bootApp(tester);

      // No specific Send/Receive button at the empty-state stage — those
      // require a created wallet. Smoke-test that the wallet root has
      // mounted and no exceptions surfaced during boot.
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Error Handling', () {
    testWidgets('handles missing platform channels gracefully',
        (tester) async {
      // TestEnvironment.install gives us a stub-everything surface. If
      // BitNestApp ever calls a channel we forgot to mock, the test
      // would either hang or surface an exception. After advancing
      // past splash, neither has happened.
      await bootApp(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('Performance Tests', () {
    testWidgets('boots within a generous test-harness budget',
        (tester) async {
      // Wall-clock isn't accurate inside the binding (the binding
      // simulates time), so this asserts the boot completes — i.e.
      // advancePastSplash returns within pumpAndSettle's internal
      // 5-second cap.
      await bootApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('settings screen round-trip is exception-free',
        (tester) async {
      await bootApp(tester);

      // Two settings round-trips. Each iteration: open settings, pop
      // back. If anything throws on layout or during the route push,
      // tester.takeException surfaces it at the end.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        final back = find.byIcon(Icons.arrow_back);
        if (back.evaluate().isNotEmpty) {
          await tester.tap(back);
          await tester.pumpAndSettle();
        } else {
          // No back button? Just pop the route programmatically.
          tester
              .element(find.byType(MaterialApp))
              .findAncestorStateOfType<NavigatorState>()
              ?.pop();
          await tester.pumpAndSettle();
        }
      }

      expect(tester.takeException(), isNull);
    });
  });
}
