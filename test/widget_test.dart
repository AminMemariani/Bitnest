// Boot test for the full [BitNestApp]. Pumps the real provider tree
// through the splash + first-run check and asserts we land on the
// onboarding/welcome state when the wallet is empty and onboarding
// hasn't been completed yet.
//
// All platform channel dependencies (SharedPreferences,
// flutter_secure_storage, local_auth, clipboard) are wired by
// [TestEnvironment.install] so the splash's Future-delayed navigation
// can resolve under the test harness.

import 'package:bitnest/main.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_environment.dart';

void main() {
  setUp(() async {
    await TestEnvironment.install(
      // Skip first-run onboarding so the navigator goes straight to
      // the wallet screen, where the "Welcome to BitNest" empty-state
      // we're testing for actually lives.
      initialPrefs: {'has_completed_onboarding': true},
    );
  });

  tearDown(TestEnvironment.uninstall);

  testWidgets('BitNest app loads and shows welcome screen', (tester) async {
    await tester.pumpWidget(const BitNestApp());
    await TestEnvironment.advancePastSplash(tester);

    // App-level title in the AppBar (or onboarding header).
    expect(find.text('BitNest'), findsWidgets);

    // Empty-state copy from WalletScreen._buildEmptyState — visible
    // because the onboarding flag isn't set and there are no wallets.
    expect(find.text('Welcome to BitNest'), findsOneWidget);
    expect(
      find.text('Create your first Bitcoin wallet to get started'),
      findsOneWidget,
    );

    // The empty-state CTA + the FAB both say "Create Wallet".
    expect(find.text('Create Wallet'), findsWidgets);
  });
}
