import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/wallet.dart';
import '../models/account.dart';
import '../models/pending_transaction.dart';
import '../models/utxo.dart';
import '../services/key_service.dart';
import '../services/api_service.dart';
import '../services/hd_wallet_service.dart';
import '../services/utxo_scanner_service.dart';
import '../services/wallet_recovery_service.dart';
import '../services/broadcast_service.dart';
import '../services/send_pipeline_service.dart';
import '../services/transaction_journal.dart';
import '../services/transaction_signer.dart';
import '../repositories/wallet_repository.dart';
import '../utils/networks.dart';
import '../utils/debug_logger.dart';
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
  TransactionJournal? _journal;

  List<Wallet> _wallets = [];
  Wallet? _currentWallet;
  Map<String, List<Account>> _accounts = {}; // walletId -> accounts
  Map<String, Account> _currentAccounts = {}; // accountId -> account
  Map<String, List<UTXO>> _accountUtxos = {}; // accountId -> utxos
  Map<String, BigInt> _accountBalances = {}; // accountId -> balance
  Map<String, bool> _syncStatus = {}; // accountId -> isSyncing
  final Map<String, HdWalletService> _hdServices = {}; // walletId -> service
  final Map<String, WalletRepository> _repositories = {}; // accountId -> repo
  bool _isLoading = false;
  String? _error;

  WalletProvider({
    required KeyService keyService,
    required ApiService apiService,
    TransactionJournal? journal,
  })  : _keyService = keyService,
        _apiService = apiService,
        _journal = journal;

  /// Optional [TransactionJournal] used to hide UTXOs that are already
  /// committed to a `signed` or `broadcast` transaction. Wired by the
  /// app's bootstrap; absent in legacy tests, in which case no
  /// filtering occurs.
  TransactionJournal? get transactionJournal => _journal;

  /// Lazy-loads the [TransactionJournal] from `SharedPreferences` if one
  /// wasn't injected at construction. Idempotent — subsequent calls
  /// return the cached instance.
  Future<TransactionJournal> ensureJournalLoaded() async {
    return _journal ??= await TransactionJournal.load();
  }

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

  /// Gets UTXOs for a specific account, with any outpoints currently
  /// committed to a pending transaction filtered out.
  ///
  /// "Pending" means the [TransactionJournal] holds a record in
  /// `signed` or `broadcast` state that lists the outpoint as one of
  /// its inputs. The filter prevents the same UTXO from being selected
  /// twice — the in-flight tx still owns it until it confirms or
  /// definitively fails.
  List<UTXO> getAccountUtxos(String accountId) {
    final all = _accountUtxos[accountId] ?? const <UTXO>[];
    final journal = _journal;
    if (journal == null) return List.unmodifiable(all);
    final pending = journal.pendingOutpointsFor(accountId);
    if (pending.isEmpty) return List.unmodifiable(all);
    return List.unmodifiable(
      all.where((u) => !pending.contains('${u.txid}:${u.vout}')),
    );
  }

  /// All UTXOs known for the account, including ones consumed by
  /// in-flight transactions. Use this for UI views that want to show
  /// "pending" coins explicitly; coin selection should use
  /// [getAccountUtxos] instead.
  List<UTXO> getAccountUtxosIncludingPending(String accountId) {
    return List.unmodifiable(_accountUtxos[accountId] ?? const <UTXO>[]);
  }

  /// Test-only entry point to seed the in-memory UTXO cache. Lets unit
  /// tests exercise the journal-filter behavior in [getAccountUtxos]
  /// without standing up a fake scanner or mocking [ApiService].
  @visibleForTesting
  void debugSeedAccountUtxos(String accountId, List<UTXO> utxos) {
    _accountUtxos[accountId] = List.of(utxos);
    notifyListeners();
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
  /// [mnemonic] is an optional mnemonic to use instead of generating a new one.
  Future<Wallet> createWallet({
    required String label,
    required BitcoinNetwork network,
    int wordCount = 24,
    key_service.DerivationScheme derivationScheme =
        key_service.DerivationScheme.nativeSegwit,
    String? mnemonic,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Generate mnemonic if not provided
      final walletMnemonic =
          mnemonic ?? _keyService.generateMnemonic(wordCount: wordCount);

      // Derive seed
      final seed = _keyService.mnemonicToSeed(walletMnemonic);

      // Derive master keys
      final masterXpub = _keyService.deriveMasterXpub(seed, network);
      final masterXprv = _keyService.deriveMasterXprv(seed, network);

      // Create wallet
      final wallet = Wallet(
        label: label,
        network: network,
        xpub: masterXpub,
        xprv: masterXprv,
        mnemonic: walletMnemonic,
      );

      _wallets.add(wallet);

      // Store mnemonic and seed securely first
      await _keyService.storeMnemonic(wallet.id, walletMnemonic);
      await _keyService.storeSeed(wallet.id, seed);

      // Create default account (pass seed directly to avoid retrieval)
      await _createDefaultAccount(wallet, derivationScheme, seed: seed);

      _setLoading(false);
      notifyListeners();

      return wallet;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'WalletProvider.createWallet',
        additionalInfo: {
          'label': label,
          'network': network.name,
          'wordCount': wordCount,
        },
      );
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
    key_service.DerivationScheme derivationScheme =
        key_service.DerivationScheme.nativeSegwit,
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

      // Store mnemonic and seed securely first
      await _keyService.storeMnemonic(wallet.id, mnemonic);
      await _keyService.storeSeed(wallet.id, seed);

      // Create default account (pass seed directly to avoid retrieval)
      await _createDefaultAccount(wallet, derivationScheme, seed: seed);

      _setLoading(false);
      notifyListeners();

      return wallet;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'WalletProvider.importWallet',
        additionalInfo: {
          'label': label,
          'network': network.name,
        },
      );
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
    key_service.DerivationScheme derivationScheme =
        key_service.DerivationScheme.nativeSegwit,
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
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'WalletProvider.importWatchOnlyWallet',
        additionalInfo: {
          'label': label,
          'network': network.name,
        },
      );
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

      // Dispose any cached HD service (zeros in-memory seed).
      _hdServices.remove(walletId)?.dispose();

      // Clear persisted address-rotation state for each of this wallet's
      // accounts, and drop cached repositories.
      for (final accountId in accountIds) {
        _repositories.remove(accountId);
        await WalletRepository.clear(accountId: accountId);
      }

      // Delete secure storage
      await _keyService.deleteWalletData(walletId);

      _setLoading(false);
      notifyListeners();
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'WalletProvider.removeWallet',
        additionalInfo: {'walletId': walletId},
      );
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
    key_service.DerivationScheme derivationScheme =
        key_service.DerivationScheme.nativeSegwit,
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
          derivationPath: _buildDerivationPath(
              derivationScheme, wallet.network, accountIndex),
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
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'WalletProvider.createAccount',
        additionalInfo: {
          'label': label,
          'walletId': _currentWallet?.id,
        },
      );
      _setError('Failed to create account: $e');
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  /// Derives a receiving address at a specific BIP84 index without advancing
  /// the account's rotation state. Use this for lookups and gap scans.
  Future<String> deriveReceivingAddress(String accountId, int index) async {
    final account = _requireAccount(accountId);
    return _deriveAddressAt(account, index: index, change: false);
  }

  /// Derives a change address at a specific BIP84 index without advancing
  /// the account's rotation state.
  Future<String> deriveChangeAddress(String accountId, int index) async {
    final account = _requireAccount(accountId);
    return _deriveAddressAt(account, index: index, change: true);
  }

  /// Returns the account's next unused receiving address and advances the
  /// rotation index. The address is recorded on the account and future calls
  /// return the subsequent index.
  Future<String> nextReceivingAddress(String accountId) async {
    final account = _requireAccount(accountId);
    final address = await _deriveAddressAt(
      account,
      index: account.nextReceiveIndex,
      change: false,
    );

    final updated = account.copyWith(
      addresses: [...account.addresses, address],
      nextReceiveIndex: account.nextReceiveIndex + 1,
    );
    _persistAccount(updated);
    notifyListeners();
    return address;
  }

  /// Returns the account's next unused change address and advances the
  /// rotation index. Intended to be called when constructing a transaction.
  Future<String> nextChangeAddress(String accountId) async {
    final account = _requireAccount(accountId);
    final address = await _deriveAddressAt(
      account,
      index: account.nextChangeIndex,
      change: true,
    );

    final updated = account.copyWith(
      changeAddresses: [...account.changeAddresses, address],
      nextChangeIndex: account.nextChangeIndex + 1,
    );
    _persistAccount(updated);
    notifyListeners();
    return address;
  }

  /// Back-compat alias for the previous single-method API. New code should
  /// call [nextReceivingAddress] directly.
  Future<String> deriveNextReceiveAddress(
    String accountId, {
    key_service.DerivationScheme? derivationScheme,
  }) {
    return nextReceivingAddress(accountId);
  }

  /// Returns (loading if needed) the cached [HdWalletService] for [walletId].
  ///
  /// Throws [StateError] for watch-only wallets (no seed) — callers should
  /// branch on [Wallet.xprv] first if they need to support those.
  Future<HdWalletService> hdServiceFor(String walletId) async {
    final existing = _hdServices[walletId];
    if (existing != null && !existing.isDisposed) return existing;

    final wallet = _wallets.firstWhere(
      (w) => w.id == walletId,
      orElse: () => throw ArgumentError('Wallet not found: $walletId'),
    );
    if (wallet.xprv == null) {
      throw StateError(
        'Wallet "$walletId" is watch-only; no seed is available for HD key '
        'derivation.',
      );
    }

    final svc = await HdWalletService.load(
      keyService: _keyService,
      walletId: wallet.id,
      network: wallet.network,
    );
    _hdServices[walletId] = svc;
    return svc;
  }

  /// Returns (loading if needed) the persistent [WalletRepository] for the
  /// given account. The repository owns the four receiving/change index
  /// counters and persists them to [SharedPreferences] so they survive an
  /// app restart.
  ///
  /// Throws [StateError] for watch-only wallets (the repository currently
  /// derives through [HdWalletService], which requires a seed).
  Future<WalletRepository> walletRepositoryFor(String accountId) async {
    final existing = _repositories[accountId];
    if (existing != null) return existing;

    final account = _requireAccount(accountId);
    final hd = await hdServiceFor(account.walletId);
    final repo = await WalletRepository.load(
      accountId: accountId,
      hd: hd,
    );
    _repositories[accountId] = repo;
    return repo;
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
    } catch (e, stackTrace) {
      _syncStatus[accountId] = false;
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'WalletProvider.fetchAccountUtxos',
        additionalInfo: {
          'accountId': accountId,
          'addressCount': account.addresses.length,
        },
      );
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

  /// Runs a BIP44 gap-limit scan of both receive and change chains for
  /// [accountId], stores the discovered UTXOs in-memory, and folds the
  /// high watermarks into the account's [WalletRepository] (advancing
  /// lastUsed/current indices).
  ///
  /// Uses [gapLimit] consecutive unused addresses as the stopping condition
  /// (default 20 per BIP44). Watch-only wallets are not yet supported.
  Future<ScanResult> scanAccountUtxos(
    String accountId, {
    int gapLimit = 20,
    UtxoScannerService? scanner,
    void Function(ScanProgress)? onProgress,
  }) async {
    final account = _requireAccount(accountId);

    _syncStatus[accountId] = true;
    notifyListeners();

    try {
      final hd = await hdServiceFor(account.walletId);
      final repo = await walletRepositoryFor(accountId);
      final svc = scanner ?? UtxoScannerService(api: _apiService);

      final result = await svc.scan(
        hd: hd,
        gapLimit: gapLimit,
        onProgress: onProgress,
      );

      _accountUtxos[accountId] = List.of(result.allUtxos);
      _accountBalances[accountId] = result.totalBalance;

      await repo.applyScanResult(result);

      final updated = account.copyWith(
        balance: result.totalBalance,
        lastSyncedAt: DateTime.now(),
        nextReceiveIndex: repo.currentReceivingIndex,
        nextChangeIndex: repo.currentChangeIndex,
      );
      _persistAccount(updated);

      return result;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'WalletProvider.scanAccountUtxos',
        additionalInfo: {
          'accountId': accountId,
          'gapLimit': gapLimit,
        },
      );
      _setError('Scan failed: $e');
      rethrow;
    } finally {
      _syncStatus[accountId] = false;
      notifyListeners();
    }
  }

  /// Imports a wallet from [mnemonic] and immediately runs a gap-limit scan
  /// to recover used addresses, UTXOs, and the correct `currentReceiving`
  /// / `currentChange` indices. This is the entry point for the
  /// "restore from seed phrase" flow.
  ///
  /// Progress can be observed through [onProgress], one event per address
  /// queried. [gapLimit] defaults to 20 (BIP44); advanced users may raise
  /// it for wallets that accumulated a wider unused-address gap elsewhere.
  ///
  /// Returns the [RecoveryResult] so callers can display a summary.
  Future<RecoveryResult> recoverFromMnemonic({
    required String mnemonic,
    required String label,
    required BitcoinNetwork network,
    int gapLimit = 20,
    key_service.DerivationScheme derivationScheme =
        key_service.DerivationScheme.nativeSegwit,
    void Function(ScanProgress)? onProgress,
  }) async {
    // Step 1 — create the wallet record + seed storage the usual way.
    final wallet = await importWallet(
      mnemonic: mnemonic,
      label: label,
      network: network,
      derivationScheme: derivationScheme,
    );
    final account =
        _accounts[wallet.id]!.isNotEmpty ? _accounts[wallet.id]!.first : null;
    if (account == null) {
      throw StateError('Imported wallet has no default account');
    }

    // Step 2 — scan + fold into the repository. The scan runs on the HD
    // service the provider already cached for this wallet.
    _syncStatus[account.id] = true;
    notifyListeners();
    try {
      final hd = await hdServiceFor(wallet.id);
      final recovery = WalletRecoveryService(
        keyService: _keyService,
        apiService: _apiService,
      );
      final result = await recovery.rescan(
        hd: hd,
        accountId: account.id,
        gapLimit: gapLimit,
        onProgress: onProgress,
      );

      // Surface the scan output through the provider's in-memory caches
      // so any screen watching this provider sees the recovered state
      // immediately.
      _accountUtxos[account.id] = List.of(result.utxos);
      _accountBalances[account.id] = result.totalBalance;
      _repositories[account.id] = result.repository;

      _persistAccount(account.copyWith(
        balance: result.totalBalance,
        lastSyncedAt: DateTime.now(),
        nextReceiveIndex: result.currentReceivingIndex,
        nextChangeIndex: result.currentChangeIndex,
      ));
      return result;
    } catch (e, st) {
      DebugLogger.logException(
        e,
        st,
        context: 'WalletProvider.recoverFromMnemonic',
        additionalInfo: {
          'walletId': wallet.id,
          'gapLimit': gapLimit,
        },
      );
      _setError('Recovery failed: $e');
      rethrow;
    } finally {
      _syncStatus[account.id] = false;
      notifyListeners();
    }
  }

  /// Manual rescan from settings. Re-runs the gap-limit scan for
  /// [accountId], updating balances, UTXOs, and rotation pointers.
  ///
  /// Thin convenience over [scanAccountUtxos] that exposes progress
  /// reporting for UI — the two share the same underlying mechanics.
  Future<ScanResult> rescanAccount(
    String accountId, {
    int gapLimit = 20,
    void Function(ScanProgress)? onProgress,
  }) {
    return scanAccountUtxos(
      accountId,
      gapLimit: gapLimit,
      onProgress: onProgress,
    );
  }

  /// Re-broadcasts any transaction that was signed and journaled but
  /// not confirmed-broadcast — typically because the previous app
  /// session crashed (or lost network) between signing and the
  /// pipeline's success commit.
  ///
  /// Walks every full (non-watch-only) wallet's accounts and asks
  /// [SendPipelineService.recoverPending] to drive the journal's
  /// `signed` records back to `broadcast` (or `failed`). Idempotent —
  /// the pipeline's per-txid dedupe prevents double rotation, and a
  /// re-broadcast of an already-confirmed tx is a node-side no-op.
  ///
  /// [broadcastService] is the network adapter to use; in production
  /// this is the same instance threaded through [SendProvider].
  /// Returns one [BroadcastOutcome] per record processed.
  Future<List<BroadcastOutcome>> recoverPendingTransactions({
    required BroadcastService broadcastService,
  }) async {
    final journal = await ensureJournalLoaded();
    final outcomes = <BroadcastOutcome>[];

    for (final wallet in _wallets) {
      // Watch-only wallets have no seed and can't sign; skip.
      if (wallet.xprv == null) continue;

      final accounts = _accounts[wallet.id] ?? const [];
      if (accounts.isEmpty) continue;

      // Any account on this wallet might have signed records pending.
      // Resolve the HD service once per wallet, then iterate accounts.
      HdWalletService? hd;
      for (final account in accounts) {
        final accountRecords = journal
            .byAccount(account.id)
            .where((t) => t.state == PendingTxState.signed)
            .toList();
        if (accountRecords.isEmpty) continue;

        try {
          hd ??= await hdServiceFor(wallet.id);
        } catch (e, st) {
          DebugLogger.logException(
            e,
            st,
            context:
                'WalletProvider.recoverPendingTransactions (hdServiceFor)',
            additionalInfo: {'walletId': wallet.id},
          );
          continue;
        }

        final repo = await walletRepositoryFor(account.id);
        final signer = TransactionSigner(hd: hd);
        final pipeline = SendPipelineService(
          signer: signer,
          broadcast: broadcastService,
          journal: journal,
        );

        try {
          final results = await pipeline.recoverPending(
            accountId: account.id,
            repository: repo,
            network: account.network,
          );
          outcomes.addAll(results);
        } catch (e, st) {
          DebugLogger.logException(
            e,
            st,
            context: 'WalletProvider.recoverPendingTransactions',
            additionalInfo: {
              'accountId': account.id,
              'pendingCount': accountRecords.length,
            },
          );
        }
      }
    }

    return outcomes;
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
    key_service.DerivationScheme derivationScheme, {
    Uint8List? seed,
  }) async {
    Account account;

    if (wallet.xprv != null) {
      // Full wallet - derive from seed
      Uint8List? walletSeed = seed;

      // If seed not provided, retrieve from storage
      if (walletSeed == null) {
        walletSeed = await _keyService.retrieveSeed(wallet.id);
        if (walletSeed == null) {
          throw StateError('Wallet seed not found');
        }
      }

      final accountXpub = _keyService.deriveAccountXpub(
        walletSeed,
        derivationScheme,
        wallet.network,
        accountIndex: 0,
      );

      account = Account(
        walletId: wallet.id,
        label: 'Primary Account',
        derivationPath:
            _buildDerivationPath(derivationScheme, wallet.network, 0),
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
    final derivationPath =
        _buildDerivationPath(derivationScheme, wallet.network, accountIndex);
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
    return accounts.map((a) => a.accountIndex).reduce((a, b) => a > b ? a : b) +
        1;
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

  Account _requireAccount(String accountId) {
    final account = _currentAccounts[accountId];
    if (account == null) {
      throw ArgumentError('Account not found: $accountId');
    }
    return account;
  }

  /// Derives an address at [index] on the given chain, using the full HD
  /// service (seed-based BIP84) when the wallet has a seed, and falling back
  /// to account-xpub derivation for watch-only wallets.
  Future<String> _deriveAddressAt(
    Account account, {
    required int index,
    required bool change,
  }) async {
    final wallet = _wallets.firstWhere(
      (w) => w.id == account.walletId,
      orElse: () =>
          throw StateError('Wallet not found for account ${account.id}'),
    );

    final scheme = _getDerivationSchemeFromPath(account.derivationPath);

    if (wallet.xprv != null && scheme == key_service.DerivationScheme.nativeSegwit) {
      // Seed-backed BIP84 via the dedicated HD service.
      final hd = await hdServiceFor(wallet.id);
      return change
          ? hd.deriveChangeAddress(index)
          : hd.deriveReceivingAddress(index);
    }

    // Watch-only (or legacy/p2sh schemes) — derive from the stored account xpub.
    return _keyService.deriveAddress(
      account.xpub,
      index,
      scheme,
      account.network,
      change: change,
    );
  }

  void _persistAccount(Account updated) {
    _currentAccounts[updated.id] = updated;
    final walletAccounts = _accounts[updated.walletId];
    if (walletAccounts != null) {
      final i = walletAccounts.indexWhere((a) => a.id == updated.id);
      if (i != -1) walletAccounts[i] = updated;
    }
  }

  @override
  void dispose() {
    for (final svc in _hdServices.values) {
      svc.dispose();
    }
    _hdServices.clear();
    super.dispose();
  }
}
