import 'package:shared_preferences/shared_preferences.dart';

import '../models/utxo.dart';
import '../repositories/wallet_repository.dart';
import '../utils/networks.dart';
import 'api_service.dart';
import 'hd_wallet_service.dart';
import 'key_service.dart';
import 'utxo_scanner_service.dart';

/// Aggregate result of a recovery or rescan pass.
class RecoveryResult {
  /// The [WalletRepository] whose rotation pointers were (re)populated.
  final WalletRepository repository;

  /// The raw [ScanResult] from [UtxoScannerService]. Consumers that want
  /// per-address activity details can reach through this field.
  final ScanResult scanResult;

  /// Highest receive-chain index seen on chain, or `-1` if the wallet has
  /// no receive history at all.
  final int lastUsedReceivingIndex;

  /// Highest change-chain index seen on chain, or `-1`.
  final int lastUsedChangeIndex;

  /// The first unused receive-chain index — the index the UI will show as
  /// "current receive". Always `lastUsedReceivingIndex + 1` or greater.
  final int currentReceivingIndex;

  /// The first unused change-chain index.
  final int currentChangeIndex;

  /// Flat list of every UTXO discovered across both chains. Empty when
  /// the wallet has history but no unspent outputs remaining.
  final List<UTXO> utxos;

  /// Number of addresses the scanner visited (receive + change combined).
  /// Useful for "we checked N addresses" status messaging.
  final int addressesScanned;

  /// Total satoshi value across [utxos].
  BigInt get totalBalance =>
      utxos.fold<BigInt>(BigInt.zero, (s, u) => s + u.value);

  /// Confirmed-only subset of [utxos].
  List<UTXO> get confirmedUtxos =>
      utxos.where((u) => u.confirmations > 0).toList();

  /// Unconfirmed (mempool) subset of [utxos].
  List<UTXO> get unconfirmedUtxos =>
      utxos.where((u) => u.confirmations == 0).toList();

  /// Indices on the receiving chain that had tx history.
  List<int> get usedReceivingIndices => scanResult.usedReceivingIndices;

  /// Indices on the change chain that had tx history.
  List<int> get usedChangeIndices => scanResult.usedChangeIndices;

  const RecoveryResult({
    required this.repository,
    required this.scanResult,
    required this.lastUsedReceivingIndex,
    required this.lastUsedChangeIndex,
    required this.currentReceivingIndex,
    required this.currentChangeIndex,
    required this.utxos,
    required this.addressesScanned,
  });
}

/// One call: import a seed phrase (or reuse an existing wallet's seed) and
/// recover every piece of state the app needs to reopen that wallet:
///
///   * **Used receiving and change addresses** — via the scanner's
///     gap-limit walk of both chains. The scanner treats any address
///     with tx history as "used", even if its current balance is zero.
///     That means fully-spent addresses are correctly recovered too.
///   * **UTXOs** — from the same scan; surfaced on [RecoveryResult].
///   * **`lastUsedReceivingIndex` and `lastUsedChangeIndex`** — high
///     watermarks from the scan.
///   * **`currentReceivingIndex` and `currentChangeIndex`** — advanced to
///     the first unused index past each high watermark, so the UI's
///     "next receive" address is always fresh and `getFreshChangeAddress`
///     never collides with an on-chain index.
///
/// Gap limit defaults to 20 (BIP44). Advanced callers can override.
///
/// Progress is emitted through the optional [ScanProgress] callback,
/// one event per address queried. That's the hook the UI uses to render
/// "Scanning address N of ∞" during recovery.
///
/// The service is deliberately self-contained — no dependency on
/// `WalletProvider` — so it can be driven from a recovery wizard, a
/// background isolate, or a unit test with equal ease.
class WalletRecoveryService {
  final KeyService _keyService;
  final ApiService _apiService;
  final SharedPreferences? _prefs;
  final UtxoScannerService Function(ApiService api) _scannerFactory;

  /// [scannerFactory] is injectable so tests can hand in a scanner with a
  /// tight retry budget (or a pre-stubbed one). Defaults to the standard
  /// [UtxoScannerService] with a 50 ms initial backoff so real recoveries
  /// don't feel sluggish on lossy networks.
  WalletRecoveryService({
    required KeyService keyService,
    required ApiService apiService,
    SharedPreferences? prefs,
    UtxoScannerService Function(ApiService api)? scannerFactory,
  })  : _keyService = keyService,
        _apiService = apiService,
        _prefs = prefs,
        _scannerFactory = scannerFactory ??
            ((api) => UtxoScannerService(
                  api: api,
                  initialBackoff: const Duration(milliseconds: 50),
                ));

  /// Recovers a wallet from a BIP39 mnemonic phrase.
  ///
  /// If [storeSeed] is true and [walletId] is supplied, the derived seed is
  /// persisted via [KeyService.storeSeed]. That matches the "import a seed
  /// and keep using the wallet" flow. Leave both defaults when you only
  /// want to recover state without touching secure storage (e.g. a dry-run
  /// recovery preview).
  Future<RecoveryResult> recoverFromMnemonic({
    required String mnemonic,
    required BitcoinNetwork network,
    required String accountId,
    int gapLimit = 20,
    int accountIndex = 0,
    String? passphrase,
    String? walletId,
    bool storeSeed = false,
    void Function(ScanProgress progress)? onProgress,
  }) async {
    if (gapLimit <= 0) {
      throw ArgumentError.value(gapLimit, 'gapLimit', 'must be > 0');
    }
    if (!_keyService.validateMnemonic(mnemonic)) {
      throw ArgumentError.value(
        mnemonic,
        'mnemonic',
        'invalid BIP39 mnemonic',
      );
    }

    final seed = _keyService.mnemonicToSeed(mnemonic, passphrase: passphrase);
    if (storeSeed && walletId != null) {
      await _keyService.storeSeed(walletId, seed);
      await _keyService.storeMnemonic(walletId, mnemonic);
    }

    final hd = HdWalletService.fromSeed(
      keyService: _keyService,
      seed: seed,
      network: network,
      walletId: walletId ?? '',
      accountIndex: accountIndex,
    );
    // NOTE: the returned [RecoveryResult.repository] derives addresses
    // through [hd], so ownership passes to the caller. Disposing here
    // would make later calls like `getCurrentReceivingAddress` throw.
    return _runScan(
      hd: hd,
      accountId: accountId,
      gapLimit: gapLimit,
      onProgress: onProgress,
    );
  }

  /// Re-runs the gap-limit scan against an existing [HdWalletService]. The
  /// HD service is not disposed by this method — the caller owns its
  /// lifetime (typically `WalletProvider`, which caches one HD per wallet).
  ///
  /// This is the entry point behind "Rescan wallet" in settings.
  Future<RecoveryResult> rescan({
    required HdWalletService hd,
    required String accountId,
    int gapLimit = 20,
    void Function(ScanProgress progress)? onProgress,
  }) async {
    if (gapLimit <= 0) {
      throw ArgumentError.value(gapLimit, 'gapLimit', 'must be > 0');
    }
    return _runScan(
      hd: hd,
      accountId: accountId,
      gapLimit: gapLimit,
      onProgress: onProgress,
    );
  }

  // ---- internals ----

  Future<RecoveryResult> _runScan({
    required HdWalletService hd,
    required String accountId,
    required int gapLimit,
    void Function(ScanProgress)? onProgress,
  }) async {
    final scanner = _scannerFactory(_apiService);
    final scan = await scanner.scan(
      hd: hd,
      gapLimit: gapLimit,
      onProgress: onProgress,
    );

    final repo = await WalletRepository.load(
      accountId: accountId,
      hd: hd,
      prefs: _prefs,
    );
    await repo.applyScanResult(scan);

    return RecoveryResult(
      repository: repo,
      scanResult: scan,
      lastUsedReceivingIndex: scan.lastUsedReceivingIndex ?? -1,
      lastUsedChangeIndex: scan.lastUsedChangeIndex ?? -1,
      currentReceivingIndex: repo.currentReceivingIndex,
      currentChangeIndex: repo.currentChangeIndex,
      utxos: scan.allUtxos,
      addressesScanned: scan.addressesScanned,
    );
  }
}
