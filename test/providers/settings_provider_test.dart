import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bitnest/providers/settings_provider.dart';

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

  group('SettingsProvider', () {
    test('initializes with default values', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100)); // Allow async load

      expect(provider.themeMode, ThemeMode.system);
      expect(provider.currency, 'BTC');
      expect(provider.biometricsEnabled, false);
      expect(provider.hasPin, false);
    });

    test('loads theme mode from preferences', () async {
      await prefs.setString('theme_mode', 'dark');
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      // Wait for async _loadSettings to complete
      // Since _loadSettings is called in constructor, we need to wait
      await Future.delayed(const Duration(milliseconds: 500));

      expect(provider.themeMode, ThemeMode.dark);
    });

    test('sets and persists theme mode', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, ThemeMode.dark);

      // Verify persistence
      final savedValue = prefs.getString('theme_mode');
      expect(savedValue, 'dark');
    });

    test('loads currency from preferences', () async {
      await prefs.setString('currency', 'USD');
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      // Wait for async _loadSettings to complete
      await Future.delayed(const Duration(milliseconds: 500));

      expect(provider.currency, 'USD');
    });

    test('sets and persists currency', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setCurrency('USD');
      expect(provider.currency, 'USD');

      // Verify persistence
      final savedValue = prefs.getString('currency');
      expect(savedValue, 'USD');
    });

    test('sets and persists biometrics enabled', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setBiometricsEnabled(true);
      expect(provider.biometricsEnabled, true);

      // Verify persistence
      final savedValue = prefs.getBool('biometrics_enabled');
      expect(savedValue, true);
    }, skip: 'FlutterSecureStorage not available in unit tests');

    test('sets PIN successfully', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await provider.setPin('1234');
      expect(result, true);
      expect(provider.hasPin, true);
    }, skip: 'FlutterSecureStorage not available in unit tests');

    test('rejects PIN that is too short', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await provider.setPin('123');
      expect(result, false);
      expect(provider.hasPin, false);
    });

    test('rejects PIN that is too long', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await provider.setPin('1234567');
      expect(result, false);
      expect(provider.hasPin, false);
    });

    test('verifies PIN correctly', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setPin('1234');
      final isValid = await provider.verifyPin('1234');
      expect(isValid, true);

      final isInvalid = await provider.verifyPin('5678');
      expect(isInvalid, false);
    }, skip: 'FlutterSecureStorage not available in unit tests');

    test('changes PIN successfully', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setPin('1234');
      final result = await provider.changePin('1234', '5678');
      expect(result, true);

      final isValid = await provider.verifyPin('5678');
      expect(isValid, true);
    });

    test('fails to change PIN with wrong old PIN', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setPin('1234');
      final result = await provider.changePin('9999', '5678');
      expect(result, false);

      // Old PIN should still work
      final isValid = await provider.verifyPin('1234');
      expect(isValid, true);
    });

    test('removes PIN successfully', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setPin('1234');
      expect(provider.hasPin, true);

      final result = await provider.removePin('1234');
      expect(result, true);
      expect(provider.hasPin, false);
    });

    test('fails to remove PIN with wrong PIN', () async {
      final provider = SettingsProvider(prefs: prefs, secureStorage: secureStorage);
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setPin('1234');
      final result = await provider.removePin('9999');
      expect(result, false);
      expect(provider.hasPin, true);
    });
  });
}

