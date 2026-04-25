import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared bring-up for tests that pump anything which talks to the
/// platform — `flutter_secure_storage`, `local_auth`, clipboard,
/// `shared_preferences`, etc. Without these mock handlers the
/// underlying MethodChannel calls hang silently in the test harness,
/// which is exactly what was happening to the integration scaffolds
/// and the SettingsProvider initialisation test.
///
/// Usage in `setUp`:
///
/// ```dart
/// setUp(() async {
///   await TestEnvironment.install();
/// });
///
/// tearDown(TestEnvironment.uninstall);
/// ```
class TestEnvironment {
  static const MethodChannel _secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  static const MethodChannel _localAuthChannel =
      MethodChannel('plugins.flutter.io/local_auth');

  /// In-memory backing store for [FlutterSecureStorage] under tests.
  /// Cleared on each [install].
  static final Map<String, String> _secureStore = {};

  /// Set true after install; uninstall clears it. Lets tests assert
  /// they're running under the mocked harness.
  static bool installed = false;

  /// Wires every mock handler the app needs and seeds an empty
  /// [SharedPreferences]. Idempotent.
  static Future<void> install({
    Map<String, Object> initialPrefs = const {},
    Map<String, String>? initialSecureStorage,
    bool biometricsAvailable = false,
    bool biometricAuthSucceeds = true,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    SharedPreferences.setMockInitialValues(initialPrefs);

    _secureStore
      ..clear()
      ..addAll(initialSecureStorage ?? const {});

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // ---- flutter_secure_storage ---------------------------------------
    messenger.setMockMethodCallHandler(_secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return _secureStore[call.arguments['key'] as String];
        case 'readAll':
          return Map<String, String>.from(_secureStore);
        case 'write':
          _secureStore[call.arguments['key'] as String] =
              call.arguments['value'] as String;
          return null;
        case 'delete':
          _secureStore.remove(call.arguments['key'] as String);
          return null;
        case 'deleteAll':
          _secureStore.clear();
          return null;
        case 'containsKey':
          return _secureStore.containsKey(call.arguments['key'] as String);
      }
      return null;
    });

    // ---- local_auth ---------------------------------------------------
    messenger.setMockMethodCallHandler(_localAuthChannel, (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
        case 'deviceSupportsBiometrics':
          return biometricsAvailable;
        case 'getAvailableBiometrics':
          return biometricsAvailable ? <String>['fingerprint'] : <String>[];
        case 'authenticate':
        case 'authenticateWithBiometrics':
          return biometricAuthSucceeds;
        case 'stopAuthentication':
          return true;
      }
      return null;
    });

    // ---- clipboard ---------------------------------------------------
    // SystemChannels.platform is shared across many things; only set
    // the clipboard-relevant fallbacks. Tests that need other
    // platform calls (e.g. UrlLauncher) can layer their own handlers.
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          return null;
        case 'Clipboard.getData':
          return {'text': null};
      }
      return null;
    });

    installed = true;
  }

  /// Removes every handler [install] wired. Call from `tearDown` so
  /// state doesn't leak between tests.
  static void uninstall() {
    if (!installed) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorageChannel, null);
    messenger.setMockMethodCallHandler(_localAuthChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    _secureStore.clear();
    installed = false;
  }

  /// Pumps the [BitNestApp]'s 1.5s splash + post-splash transition.
  /// Use after `pumpWidget(const BitNestApp())` to land on the
  /// onboarding or wallet screen.
  static Future<void> advancePastSplash(WidgetTester tester) async {
    // First frame to mount the FutureBuilder.
    await tester.pump();
    // Drain SharedPreferences.getInstance + the 1500ms delayed Future
    // inside _AppNavigator._checkFirstRun. pumpAndSettle won't advance
    // wall-clock-style timers, but it WILL drain microtasks and short
    // periodic callbacks; calling pump with explicit durations advances
    // the test clock past Future.delayed.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }
}
