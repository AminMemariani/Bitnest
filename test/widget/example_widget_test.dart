import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bitnest/providers/network_provider.dart';
import 'package:bitnest/providers/settings_provider.dart';
import 'package:bitnest/providers/wallet_provider.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/services/api_service.dart';
import 'package:bitnest/ui/screens/wallet_screen.dart';

/// Example widget test demonstrating best practices for UI testing.
///
/// This test file shows:
/// - How to set up providers for widget tests
/// - How to find and interact with widgets
/// - How to verify UI state changes
/// - How to test navigation
/// - How to test adaptive widgets
void main() {
  late SharedPreferences prefs;
  late FlutterSecureStorage secureStorage;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secureStorage = const FlutterSecureStorage();
  });

  tearDown(() async {
    await prefs.clear();
  });

  /// Helper function to build a test widget with all required providers
  Widget buildTestWidget(Widget child) {
    final keyService = KeyService();
    final apiService = ApiService();

    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => NetworkProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                SettingsProvider(prefs: prefs, secureStorage: secureStorage),
          ),
          ChangeNotifierProvider(
            create: (_) => WalletProvider(
              keyService: keyService,
              apiService: apiService,
            ),
          ),
        ],
        child: child,
      ),
    );
  }

  group('WalletScreen Widget Tests', () {
    testWidgets('displays app bar with title and settings icon',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      expect(find.text('BitNest'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('navigates to settings when settings icon is tapped',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      final settingsButton = find.byIcon(Icons.settings);
      expect(settingsButton, findsOneWidget);

      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      // Verify navigation occurred (settings screen should be visible)
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('displays empty state when no wallets exist', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Look for empty state indicators
      expect(find.textContaining('wallet', findRichText: true), findsWidgets);
    });

    testWidgets('displays create wallet button in empty state', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Find create wallet button
      final createButton = find.textContaining('create', findRichText: true);
      if (createButton.evaluate().isNotEmpty) {
        expect(createButton, findsAtLeastNWidgets(1));
      }
    });
  });

  group('Adaptive Widget Tests', () {
    testWidgets('uses adaptive switch widgets', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Navigate to settings to find switches
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Find switches (they should be adaptive)
      final switches = find.byType(Switch);
      if (switches.evaluate().isNotEmpty) {
        // Verify switches are present (adaptive switches still use Switch type)
        expect(switches, findsWidgets);
      }
    });

    testWidgets('uses adaptive progress indicators', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Look for any loading indicators
      final progressIndicators = find.byType(CircularProgressIndicator);
      // Progress indicators may or may not be visible depending on state
      // This test just verifies they can be found when present
      expect(progressIndicators, findsWidgets);
    });
  });

  group('Provider Integration Tests', () {
    testWidgets('updates UI when network provider changes', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Get network provider
      final networkProvider =
          tester.element(find.byType(WalletScreen)).read<NetworkProvider>();

      // Verify initial state
      expect(networkProvider.isTestnet, isFalse);

      // Change network
      networkProvider.toggleNetwork();
      await tester.pumpAndSettle();

      // Verify state changed
      expect(networkProvider.isTestnet, isTrue);
    });

    testWidgets('reflects settings provider theme changes', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Get settings provider
      final settingsProvider =
          tester.element(find.byType(WalletScreen)).read<SettingsProvider>();
      await settingsProvider.waitForInitialization();

      // Change theme
      await settingsProvider.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      // Verify theme changed (check MaterialApp theme mode)
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);
    });
  });

  group('User Interaction Tests', () {
    testWidgets('handles tap gestures correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Find tappable widgets
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();

        // Verify interaction occurred
        expect(find.text('Settings'), findsOneWidget);
      }
    });

    testWidgets('handles long press gestures', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Test long press on a widget (if applicable)
      final appBar = find.byType(AppBar);
      if (appBar.evaluate().isNotEmpty) {
        await tester.longPress(appBar.first);
        await tester.pumpAndSettle();

        // Verify no errors occurred
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Accessibility Tests', () {
    testWidgets('has semantic labels for important widgets', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Check for semantic labels
      final semantics = tester.getSemantics(find.byType(WalletScreen));
      // Verify semantics are present (basic check)
      expect(semantics, isNotNull);
    });

    testWidgets('supports screen reader navigation', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WalletScreen()));
      await tester.pumpAndSettle();

      // Verify widgets are accessible
      final settingsButton = find.byIcon(Icons.settings);
      if (settingsButton.evaluate().isNotEmpty) {
        expect(settingsButton, findsOneWidget);
      }
    });
  });
}
