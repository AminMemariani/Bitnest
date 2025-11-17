import 'package:flutter/foundation.dart';
import '../models/wallet.dart';
import '../models/account.dart';
import '../models/utxo.dart';
import '../services/key_service.dart';
import '../services/api_service.dart';
import '../utils/networks.dart';
import '../services/key_service.dart' as key_service;

/// Provider for managing wallets, accounts, addresses, and balances.
///
/// This provider handles:
/// - Wallet creation, import, and removal
/// - Account management (multiple accounts per wallet)
/// - Address derivation and listing
/// - UTXO fetching and balance computation
/// - Sync status tracking
class WalletProvider extends ChangeNotifier {
  final KeyService _keyService;
  final ApiService _apiService;

  List<Wallet> _wallets = [];
  Wallet? _currentWallet;
  Map<String, List<Account>> _accounts = {}; // walletId -> accounts
  Map<String, Account> _currentAccounts = {}; // accountId -> account
  Map<String, List<UTXO>> _accountUtxos = {}; // accountId -> utxos
  Map<String, BigInt> _accountBalances = {}; // accountId -> balance
  Map<String, bool> _syncStatus = {}; // accountId -> isSyncing
  bool _isLoading = false;
  String? _error;

  WalletProvider({
    required KeyService keyService,
    required ApiService apiService,
  })  : _keyService = keyService,
        _apiService = apiService;

  // Getters
  List<Wallet> get wallets => List.unmodifiable(_wallets);
  Wallet? get currentWallet => _currentWallet;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Gets accounts for the current wallet.
  List<Account> get currentAccounts {
    if (_currentWallet == null) return [];
    return List.unmodifiable(_accounts[_currentWallet!.id] ?? []);
  }

  /// Gets accounts for a specific wallet.
  List<Account> getAccountsForWallet(String walletId) {
    return List.unmodifiable(_accounts[walletId] ?? []);
  }

  /// Gets the current account (first account of current wallet).
  Account? get currentAccount {
    final accounts = currentAccounts;
    return accounts.isNotEmpty ? accounts.first : null;
  }

  /// Gets UTXOs for a specific account.
  List<UTXO> getAccountUtxos(String accountId) {
    return List.unmodifiable(_accountUtxos[accountId] ?? []);
  }

  /// Gets balance for a specific account.
  BigInt getAccountBalance(String accountId) {
    return _accountBalances[accountId] ?? BigInt.zero;
  }

  /// Gets total balance across all accounts in current wallet.
  BigInt get totalBalance {
    if (_currentWallet == null) return BigInt.zero;
    final accounts = _accounts[_currentWallet!.id] ?? [];
    return accounts.fold<BigInt>(
      BigInt.zero,
      (sum, account) => sum + getAccountBalance(account.id),
    );
  }

  /// Checks if an account is currently syncing.
  bool isAccountSyncing(String accountId) {
    return _syncStatus[accountId] ?? false;
  }

  /// Creates a new wallet with a generated mnemonic.
  ///
  /// [label] is the wallet name.
  /// [network] is the Bitcoin network (mainnet/testnet).
  /// [wordCount] is the mnemonic word count (12 or 24, default: 24).
  /// [derivationScheme] is the derivation scheme (default: nativeSegwit).
  Future<Wallet> createWallet({
    required String label,
    required BitcoinNetwork network,
    int wordCount = 24,
    key_service.DerivationScheme derivationScheme = key_service.DerivationScheme.nativeSegwit,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Generate mnemonic
      final mnemonic = _keyService.generateMnemonic(wordCount: wordCount);
      
      // Derive seed
      final seed = _keyService.mnemonicToSeed(mnemonic);
      
      // Derive master keys
      final masterXpub = _keyService.deriveMasterXpub(seed, network);
      final masterXprv = _keyService.deriveMasterXprv(seed, network);
      
      // Create wallet
      final wallet = Wallet(
        label: label,
        network: network,
        xpub: masterXpub,
        xprv: masterXprv,
        mnemonic: mnemonic,
      );
      
      _wallets.add(wallet);
      
      // Create default account
      await _createDefaultAccount(wallet, derivationScheme);
      
      // Store mnemonic securely
      await _keyService.storeMnemonic(wallet.id, mnemonic);
      await _keyService.storeSeed(wallet.id, seed);
      
      _setLoading(false);
      notifyListeners();
      
      return wallet;
    } catch (e) {
      _setError('Failed to create wallet: $e');
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  /// Imports a wallet from a mnemonic phrase.
  ///
  /// [mnemonic] is the BIP39 mnemonic phrase.
  /// [label] is the wallet name.
  /// [network] is the Bitcoin network.
  /// [derivationScheme] is the derivation scheme (default: nativeSegwit).
  Future<Wallet> importWallet({
    required String mnemonic,
    required String label,
    required BitcoinNetwork network,
    key_service.DerivationScheme derivationScheme = key_service.DerivationScheme.nativeSegwit,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      if (!_keyService.validateMnemonic(mnemonic)) {
        throw ArgumentError('Invalid mnemonic phrase');
      }
      
      // Derive seed
      final seed = _keyService.mnemonicToSeed(mnemonic);
      
      // Derive master keys
      final masterXpub = _keyService.deriveMasterXpub(seed, network);
      final masterXprv = _keyService.deriveMasterXprv(seed, network);
      
      // Create wallet
      final wallet = Wallet(
        label: label,
        network: network,
        xpub: masterXpub,
        xprv: masterXprv,
        mnemonic: mnemonic,
      );
      
      _wallets.add(wallet);
      
      // Create default account
      await _createDefaultAccount(wallet, derivationScheme);
      
      // Store mnemonic securely
      await _keyService.storeMnemonic(wallet.id, mnemonic);
      await _keyService.storeSeed(wallet.id, seed);
      
      _setLoading(false);
      notifyListeners();
      
      return wallet;
    } catch (e) {
      _setError('Failed to import wallet: $e');
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  /// Imports a watch-only wallet from an extended public key.
  ///
  /// [xpub] is the extended public key.
  /// [label] is the wallet name.
  /// [network] is the Bitcoin network.
  /// [derivationScheme] is the derivation scheme (default: nativeSegwit).
  Future<Wallet> importWatchOnlyWallet({
    required String xpub,
    required String label,
    required BitcoinNetwork network,
    key_service.DerivationScheme derivationScheme = key_service.DerivationScheme.nativeSegwit,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Create watch-only wallet (no xprv/mnemonic)
      final wallet = Wallet(
        label: label,
        network: network,
        xpub: xpub,
      );
      
      _wallets.add(wallet);
      
      // Create default account from xpub
      await _createAccountFromXpub(wallet, xpub, derivationScheme, 0);
      
      _setLoading(false);
      notifyListeners();
      
      return wallet;
    } catch (e) {
      _setError('Failed to import watch-only wallet: $e');
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  /// Removes a wallet and all associated data.
  Future<void> removeWallet(String walletId) async {
    _setLoading(true);
    _clearError();

    try {
      // Remove from list
      _wallets.removeWhere((w) => w.id == walletId);
      
      // Remove accounts
      _accounts.remove(walletId);
      final accountIds = _currentAccounts.values
          .where((a) => a.walletId == walletId)
          .map((a) => a.id)
          .toList();
      for (final accountId in accountIds) {
        _currentAccounts.remove(accountId);
        _accountUtxos.remove(accountId);
        _accountBalances.remove(accountId);
        _syncStatus.remove(accountId);
      }
      
      // Clear current wallet if it was removed
      if (_currentWallet?.id == walletId) {
        _currentWallet = null;
      }
      
      // Delete secure storage
      await _keyService.deleteWalletData(walletId);
      
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError('Failed to remove wallet: $e');
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  /// Selects a wallet as the current wallet.
  void selectWallet(String walletId) {
    final wallet = _wallets.firstWhere(
      (w) => w.id == walletId,
      orElse: () => throw ArgumentError('Wallet not found: $walletId'),
    );
    
    _currentWallet = wallet;
    notifyListeners();
  }

  /// Deselects the current wallet (shows wallet list).
  void deselectWallet() {
    _currentWallet = null;
    notifyListeners();
  }

  /// Creates a new account for the current wallet.
  ///
  /// [label] is the account name.
  /// [derivationScheme] is the derivation scheme (default: nativeSegwit).
  Future<Account> createAccount({
    required String label,
    key_service.DerivationScheme derivationScheme = key_service.DerivationScheme.nativeSegwit,
  }) async {
    if (_currentWallet == null) {
      throw StateError('No wallet selected');
    }

    _setLoading(true);
    _clearError();

    try {
      final wallet = _currentWallet!;
      final accountIndex = _getNextAccountIndex(wallet.id);
      
      Account account;
      
      if (wallet.xprv != null) {
        // Full wallet - derive from seed
        final seed = await _keyService.retrieveSeed(wallet.id);
        if (seed == null) {
          throw StateError('Wallet seed not found');
        }
        
        final accountXpub = _keyService.deriveAccountXpub(
          seed,
          derivationScheme,
          wallet.network,
          accountIndex: accountIndex,
        );
        
        account = Account(
          walletId: wallet.id,
          label: label,
          derivationPath: _buildDerivationPath(derivationScheme, wallet.network, accountIndex),
          accountIndex: accountIndex,
          xpub: accountXpub,
          network: wallet.network,
        );
      } else {
        // Watch-only wallet - derive from xpub
        account = await _createAccountFromXpub(
          wallet,
          wallet.xpub,
          derivationScheme,
          accountIndex,
          label: label,
        );
      }
      
      // Add to accounts
      if (_accounts[wallet.id] == null) {
        _accounts[wallet.id] = [];
      }
      _accounts[wallet.id]!.add(account);
      _currentAccounts[account.id] = account;
      
      // Update wallet accountIds
      final walletIndex = _wallets.indexWhere((w) => w.id == wallet.id);
      if (walletIndex != -1) {
        _wallets[walletIndex] = wallet.copyWith(
          accountIds: [...wallet.accountIds, account.id],
        );
        _currentWallet = _wallets[walletIndex];
      }
      
      _setLoading(false);
      notifyListeners();
      
      return account;
    } catch (e) {
      _setError('Failed to create account: $e');
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  /// Derives the next receive address for an account.
  ///
  /// [accountId] is the account ID.
  /// [derivationScheme] is the derivation scheme.
  Future<String> deriveNextReceiveAddress(
    String accountId, {
    key_service.DerivationScheme? derivationScheme,
  }) async {
    final account = _currentAccounts[accountId];
    if (account == null) {
      throw ArgumentError('Account not found: $accountId');
    }

    // Determine derivation scheme from account derivation path
    final scheme = derivationScheme ?? _getDerivationSchemeFromPath(account.derivationPath);
    
    // Get next address index
    final nextIndex = account.addresses.length;
    
    // Derive address
    final address = _keyService.deriveAddress(
      account.xpub,
      nextIndex,
      scheme,
      account.network,
      change: false,
    );
    
    // Add to account addresses
    final updatedAccount = account.copyWith(
      addresses: [...account.addresses, address],
    );
    _currentAccounts[accountId] = updatedAccount;
    
    // Update in accounts list
    final walletAccounts = _accounts[account.walletId];
    if (walletAccounts != null) {
      final index = walletAccounts.indexWhere((a) => a.id == accountId);
      if (index != -1) {
        walletAccounts[index] = updatedAccount;
      }
    }
    
    notifyListeners();
    
    return address;
  }

  /// Lists all addresses for an account.
  List<String> listAddresses(String accountId) {
    final account = _currentAccounts[accountId];
    if (account == null) {
      return [];
    }
    return List.unmodifiable(account.addresses);
  }

  /// Fetches UTXOs for an account and updates balance.
  ///
  /// [accountId] is the account ID.
  Future<void> fetchAccountUtxos(String accountId) async {
    final account = _currentAccounts[accountId];
    if (account == null) {
      throw ArgumentError('Account not found: $accountId');
    }

    _syncStatus[accountId] = true;
    notifyListeners();

    try {
      // Fetch UTXOs for all addresses in the account
      final allUtxos = <UTXO>[];
      
      for (final address in account.addresses) {
        try {
          final utxos = await _apiService.getAddressUtxos(address);
          allUtxos.addAll(utxos);
        } catch (e) {
          // Log error but continue with other addresses
          debugPrint('Error fetching UTXOs for address $address: $e');
        }
      }
      
      // Store UTXOs
      _accountUtxos[accountId] = allUtxos;
      
      // Compute balance
      final balance = allUtxos.fold<BigInt>(
        BigInt.zero,
        (sum, utxo) => sum + utxo.value,
      );
      _accountBalances[accountId] = balance;
      
      // Update account
      final updatedAccount = account.copyWith(
        balance: balance,
        lastSyncedAt: DateTime.now(),
      );
      _currentAccounts[accountId] = updatedAccount;
      
      // Update in accounts list
      final walletAccounts = _accounts[account.walletId];
      if (walletAccounts != null) {
        final index = walletAccounts.indexWhere((a) => a.id == accountId);
        if (index != -1) {
          walletAccounts[index] = updatedAccount;
        }
      }
      
      _syncStatus[accountId] = false;
      notifyListeners();
    } catch (e) {
      _syncStatus[accountId] = false;
      _setError('Failed to fetch UTXOs: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Fetches UTXOs for all accounts in the current wallet.
  Future<void> syncAllAccounts() async {
    if (_currentWallet == null) return;
    
    final accounts = _accounts[_currentWallet!.id] ?? [];
    for (final account in accounts) {
      await fetchAccountUtxos(account.id);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Private helper methods

  void _setLoading(bool loading) {
    _isLoading = loading;
  }

  void _setError(String error) {
    _error = error;
  }

  void _clearError() {
    _error = null;
  }

  Future<void> _createDefaultAccount(
    Wallet wallet,
    key_service.DerivationScheme derivationScheme,
  ) async {
    Account account;
    
    if (wallet.xprv != null) {
      // Full wallet - derive from seed
      final seed = await _keyService.retrieveSeed(wallet.id);
      if (seed == null) {
        throw StateError('Wallet seed not found');
      }
      
      final accountXpub = _keyService.deriveAccountXpub(
        seed,
        derivationScheme,
        wallet.network,
        accountIndex: 0,
      );
      
      account = Account(
        walletId: wallet.id,
        label: 'Primary Account',
        derivationPath: _buildDerivationPath(derivationScheme, wallet.network, 0),
        accountIndex: 0,
        xpub: accountXpub,
        network: wallet.network,
      );
    } else {
      // Watch-only wallet
      account = await _createAccountFromXpub(
        wallet,
        wallet.xpub,
        derivationScheme,
        0,
      );
    }
    
    _accounts[wallet.id] = [account];
    _currentAccounts[account.id] = account;
    
    // Update wallet
    final walletIndex = _wallets.indexWhere((w) => w.id == wallet.id);
    if (walletIndex != -1) {
      _wallets[walletIndex] = wallet.copyWith(
        accountIds: [account.id],
      );
      if (_currentWallet?.id == wallet.id) {
        _currentWallet = _wallets[walletIndex];
      }
    }
  }

  Future<Account> _createAccountFromXpub(
    Wallet wallet,
    String xpub,
    key_service.DerivationScheme derivationScheme,
    int accountIndex, {
    String? label,
  }) async {
    // For watch-only, we need to derive the account xpub from master xpub
    final derivationPath = _buildDerivationPath(derivationScheme, wallet.network, accountIndex);
    final accountXpub = _keyService.deriveXpub(xpub, derivationPath);
    
    return Account(
      walletId: wallet.id,
      label: label ?? 'Account ${accountIndex + 1}',
      derivationPath: derivationPath,
      accountIndex: accountIndex,
      xpub: accountXpub,
      network: wallet.network,
    );
  }

  int _getNextAccountIndex(String walletId) {
    final accounts = _accounts[walletId] ?? [];
    if (accounts.isEmpty) return 0;
    return accounts.map((a) => a.accountIndex).reduce((a, b) => a > b ? a : b) + 1;
  }

  String _buildDerivationPath(
    key_service.DerivationScheme scheme,
    BitcoinNetwork network,
    int accountIndex,
  ) {
    final coinType = NetworkConfig.getCoinType(network);
    final purpose = _getPurposeForScheme(scheme);
    return "m/$purpose'/$coinType'/$accountIndex'";
  }

  int _getPurposeForScheme(key_service.DerivationScheme scheme) {
    switch (scheme) {
      case key_service.DerivationScheme.legacy:
        return 44;
      case key_service.DerivationScheme.p2shSegwit:
        return 49;
      case key_service.DerivationScheme.nativeSegwit:
        return 84;
    }
  }

  key_service.DerivationScheme _getDerivationSchemeFromPath(String path) {
    if (path.contains("44'")) {
      return key_service.DerivationScheme.legacy;
    } else if (path.contains("49'")) {
      return key_service.DerivationScheme.p2shSegwit;
    } else {
      return key_service.DerivationScheme.nativeSegwit;
    }
  }
}

