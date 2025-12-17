import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/networks.dart';

/// Provider for managing Bitcoin network selection (mainnet/testnet).
///
/// This provider:
/// - Manages the current network selection
/// - Persists the choice in app settings
/// - Notifies listeners when the network changes
class NetworkProvider extends ChangeNotifier {
  static const String _prefsKey = 'selected_network';
  BitcoinNetwork _currentNetwork = BitcoinNetwork.mainnet;
  bool _isLoading = false;

  BitcoinNetwork get currentNetwork => _currentNetwork;
  bool get isLoading => _isLoading;

  /// Gets the current API endpoint based on selected network.
  String get apiEndpoint => NetworkConfig.getApiEndpoint(_currentNetwork);

  /// Gets the current network name.
  String get networkName => NetworkConfig.getNetworkName(_currentNetwork);

  NetworkProvider() {
    _loadNetworkPreference();
  }

  /// Loads the network preference from persistent storage.
  Future<void> _loadNetworkPreference() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final networkString = prefs.getString(_prefsKey);

      if (networkString != null) {
        _currentNetwork = networkString == 'testnet'
            ? BitcoinNetwork.testnet
            : BitcoinNetwork.mainnet;
      }
    } catch (e) {
      // If loading fails, use default (mainnet)
      _currentNetwork = BitcoinNetwork.mainnet;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switches to the specified network.
  ///
  /// [network] is the network to switch to (mainnet or testnet).
  /// Persists the choice and notifies listeners.
  Future<void> switchNetwork(BitcoinNetwork network) async {
    if (_currentNetwork == network) {
      return; // No change needed
    }

    _isLoading = true;
    notifyListeners();

    try {
      _currentNetwork = network;

      // Persist the choice
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        network == BitcoinNetwork.testnet ? 'testnet' : 'mainnet',
      );
    } catch (e) {
      // If persistence fails, revert the change
      _currentNetwork = _currentNetwork == BitcoinNetwork.mainnet
          ? BitcoinNetwork.testnet
          : BitcoinNetwork.mainnet;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles between mainnet and testnet.
  Future<void> toggleNetwork() async {
    final newNetwork = _currentNetwork == BitcoinNetwork.mainnet
        ? BitcoinNetwork.testnet
        : BitcoinNetwork.mainnet;
    await switchNetwork(newNetwork);
  }

  /// Checks if currently on mainnet.
  bool get isMainnet => _currentNetwork == BitcoinNetwork.mainnet;

  /// Checks if currently on testnet.
  bool get isTestnet => _currentNetwork == BitcoinNetwork.testnet;
}
