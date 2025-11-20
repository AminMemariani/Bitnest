import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provider for managing app settings including theme, currency, and security preferences.
class SettingsProvider extends ChangeNotifier {
  static const String _prefsKeyTheme = 'theme_mode';
  static const String _prefsKeyCurrency = 'currency';
  static const String _prefsKeyBiometricsEnabled = 'biometrics_enabled';
  static const String _secureStorageKeyPin = 'app_pin';
  static const String _secureStorageKeyBiometricsEnabled = 'biometrics_enabled_secure';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  ThemeMode _themeMode = ThemeMode.system;
  String _currency = 'BTC';
  bool _biometricsEnabled = false;
  bool _hasPin = false;

  SettingsProvider({
    required SharedPreferences prefs,
    FlutterSecureStorage? secureStorage,
  })  : _prefs = prefs,
        _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _loadSettings();
  }

  ThemeMode get themeMode => _themeMode;
  String get currency => _currency;
  bool get biometricsEnabled => _biometricsEnabled;
  bool get hasPin => _hasPin;

  /// Loads settings from persistent storage.
  Future<void> _loadSettings() async {
    try {
      // Load theme mode
      final themeString = _prefs.getString(_prefsKeyTheme);
      if (themeString != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == themeString,
          orElse: () => ThemeMode.system,
        );
      }

      // Load currency
      _currency = _prefs.getString(_prefsKeyCurrency) ?? 'BTC';

      // Load biometrics setting
      _biometricsEnabled = _prefs.getBool(_prefsKeyBiometricsEnabled) ?? false;

      // Check if PIN exists
      final pinHash = await _secureStorage.read(key: _secureStorageKeyPin);
      _hasPin = pinHash != null && pinHash.isNotEmpty;

      notifyListeners();
    } catch (e) {
      // Use defaults if loading fails
      _themeMode = ThemeMode.system;
      _currency = 'BTC';
      _biometricsEnabled = false;
      _hasPin = false;
    }
  }

  /// Sets the theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    await _prefs.setString(_prefsKeyTheme, mode.name);
    notifyListeners();
  }

  /// Sets the currency for display.
  Future<void> setCurrency(String currency) async {
    if (_currency == currency) return;

    _currency = currency;
    await _prefs.setString(_prefsKeyCurrency, currency);
    notifyListeners();
  }

  /// Enables or disables biometric authentication.
  Future<void> setBiometricsEnabled(bool enabled) async {
    if (_biometricsEnabled == enabled) return;

    _biometricsEnabled = enabled;
    await _prefs.setBool(_prefsKeyBiometricsEnabled, enabled);
    // Also store in secure storage for additional security
    if (enabled) {
      await _secureStorage.write(
        key: _secureStorageKeyBiometricsEnabled,
        value: 'true',
      );
    } else {
      await _secureStorage.delete(key: _secureStorageKeyBiometricsEnabled);
    }
    notifyListeners();
  }

  /// Sets a PIN for the app.
  ///
  /// [pin] should be a 4-6 digit PIN.
  /// Returns true if PIN was set successfully, false otherwise.
  Future<bool> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 6) {
      return false;
    }

    try {
      // In a real app, you'd hash the PIN before storing
      // For now, we'll store a simple hash
      final pinHash = _hashPin(pin);
      await _secureStorage.write(key: _secureStorageKeyPin, value: pinHash);
      // Verify it was written by reading it back
      final stored = await _secureStorage.read(key: _secureStorageKeyPin);
      if (stored != null && stored == pinHash) {
        _hasPin = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Verifies a PIN.
  ///
  /// Returns true if the PIN is correct, false otherwise.
  Future<bool> verifyPin(String pin) async {
    try {
      final storedHash = await _secureStorage.read(key: _secureStorageKeyPin);
      if (storedHash == null) return false;

      final pinHash = _hashPin(pin);
      return storedHash == pinHash;
    } catch (e) {
      return false;
    }
  }

  /// Changes the PIN.
  ///
  /// [oldPin] is the current PIN.
  /// [newPin] is the new PIN (4-6 digits).
  /// Returns true if PIN was changed successfully, false otherwise.
  Future<bool> changePin(String oldPin, String newPin) async {
    if (newPin.length < 4 || newPin.length > 6) {
      return false;
    }

    final isValid = await verifyPin(oldPin);
    if (!isValid) {
      return false;
    }

    return await setPin(newPin);
  }

  /// Removes the PIN.
  ///
  /// [pin] is the current PIN for verification.
  /// Returns true if PIN was removed successfully, false otherwise.
  Future<bool> removePin(String pin) async {
    final isValid = await verifyPin(pin);
    if (!isValid) {
      return false;
    }

    try {
      await _secureStorage.delete(key: _secureStorageKeyPin);
      _hasPin = false;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Simple PIN hashing (in production, use a proper hashing algorithm with salt).
  String _hashPin(String pin) {
    // Simple hash for demonstration - in production use proper crypto
    return pin.codeUnits.fold<int>(0, (sum, code) => sum + code).toString();
  }
}

