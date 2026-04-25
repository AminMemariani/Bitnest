import '../models/utxo.dart';
import '../models/transaction.dart';
import 'api_service.dart';
import 'hd_wallet_service.dart';

/// Per-address activity discovered during a scan.
class AddressActivity {
  /// BIP32 child index on the chain.
  final int index;

  /// The derived address string.
  final String address;

  /// `false` for receiving chain (0), `true` for change chain (1).
  final bool isChange;

  /// True when this address has at least one transaction (confirmed or
  /// unconfirmed). An address with history but no UTXOs (i.e. fully spent)
  /// still counts as used.
  final bool hasHistory;

  /// Total number of transactions touching this address.
  final int txCount;

  /// UTXOs currently owned by this address.
  final List<UTXO> utxos;

  const AddressActivity({
    required this.index,
    required this.address,
    required this.isChange,
    required this.hasHistory,
    required this.txCount,
    required this.utxos,
  });

  /// Confirmed UTXOs only (block_height present).
  List<UTXO> get confirmedUtxos =>
      utxos.where((u) => u.confirmations > 0).toList();

  /// Unconfirmed (mempool) UTXOs only.
  List<UTXO> get unconfirmedUtxos =>
      utxos.where((u) => u.confirmations == 0).toList();

  /// Sum of all UTXO values for this address.
  BigInt get balance =>
      utxos.fold<BigInt>(BigInt.zero, (s, u) => s + u.value);
}

/// Aggregated result of a full gap-limit scan.
class ScanResult {
  /// Highest used index on the receive chain, or `null` if the scan found
  /// no receiving-chain history at all.
  final int? lastUsedReceivingIndex;

  /// Highest used index on the change chain, or `null` if the scan found
  /// no change-chain history at all.
  final int? lastUsedChangeIndex;

  /// Per-index activity records for every address the scanner queried on
  /// the receiving chain.
  final Map<int, AddressActivity> receivingActivity;

  /// Per-index activity records for every address the scanner queried on
  /// the change chain.
  final Map<int, AddressActivity> changeActivity;

  const ScanResult({
    required this.lastUsedReceivingIndex,
    required this.lastUsedChangeIndex,
    required this.receivingActivity,
    required this.changeActivity,
  });

  /// All UTXOs discovered across both chains.
  List<UTXO> get allUtxos => [
        for (final a in receivingActivity.values) ...a.utxos,
        for (final a in changeActivity.values) ...a.utxos,
      ];

  /// Confirmed UTXOs across both chains.
  List<UTXO> get confirmedUtxos =>
      allUtxos.where((u) => u.confirmations > 0).toList();

  /// Unconfirmed UTXOs across both chains.
  List<UTXO> get unconfirmedUtxos =>
      allUtxos.where((u) => u.confirmations == 0).toList();

  /// Total value in satoshis of every UTXO the scan found.
  BigInt get totalBalance =>
      allUtxos.fold<BigInt>(BigInt.zero, (s, u) => s + u.value);

  /// Total addresses the scanner queried (both chains combined).
  int get addressesScanned =>
      receivingActivity.length + changeActivity.length;

  /// Receiving-chain indices marked used (had history).
  List<int> get usedReceivingIndices => [
        for (final e in receivingActivity.entries)
          if (e.value.hasHistory) e.key,
      ]..sort();

  /// Change-chain indices marked used (had history).
  List<int> get usedChangeIndices => [
        for (final e in changeActivity.entries)
          if (e.value.hasHistory) e.key,
      ]..sort();
}

/// Progress event emitted via the optional `onProgress` callback.
class ScanProgress {
  final bool isChange;
  final int currentIndex;
  final int? lastUsedIndex;
  final int consecutiveUnused;

  const ScanProgress({
    required this.isChange,
    required this.currentIndex,
    required this.lastUsedIndex,
    required this.consecutiveUnused,
  });
}

/// Raised when the scanner cannot make forward progress due to repeated
/// network failures on a single address.
class UtxoScannerException implements Exception {
  final String message;
  final Object? cause;
  final String? address;
  final int? index;
  final bool? isChange;

  UtxoScannerException(
    this.message, {
    this.cause,
    this.address,
    this.index,
    this.isChange,
  });

  @override
  String toString() => 'UtxoScannerException: $message';
}

/// Discovers used addresses and UTXOs for an [HdWalletService]-derived wallet
/// by scanning the receiving and change chains until [gapLimit] consecutive
/// unused addresses have been observed on each.
///
/// This mirrors the standard BIP44 gap-limit discovery algorithm:
///
/// 1. Start at `startIndex` on a chain (default 0).
/// 2. Derive the address, fetch its tx history and UTXOs.
/// 3. If the address has any tx history, reset the consecutive-unused
///    counter and record its index as the new high watermark for that chain.
///    An address with history but zero balance still counts as used.
/// 4. If the address has no history, increment the consecutive-unused counter.
/// 5. Stop when the counter reaches [gapLimit].
///
/// Persistent per-address failures abort the scan with a
/// [UtxoScannerException] — silently skipping a failed address would corrupt
/// the gap-limit invariant.
class UtxoScannerService {
  final ApiService _api;
  final int retries;
  final Duration initialBackoff;

  UtxoScannerService({
    required ApiService api,
    this.retries = 3,
    this.initialBackoff = const Duration(milliseconds: 200),
  }) : _api = api;

  /// Runs a full scan across the receiving and change chains.
  ///
  /// [gapLimit] — number of consecutive unused addresses that must be seen
  /// on a chain before the scanner gives up on it. Defaults to 20 (BIP44).
  ///
  /// [startReceivingIndex] / [startChangeIndex] — let callers resume a scan
  /// from a known offset (e.g. the repo's last high watermark minus
  /// gapLimit). Defaults to 0, which is always correct if a bit wasteful.
  ///
  /// [onProgress] — fires after every address query for progress UI. Must
  /// not throw.
  ///
  /// Throws [ArgumentError] if [gapLimit] is not positive.
  /// Throws [UtxoScannerException] if the API fails for the same address
  /// more than [retries] times.
  Future<ScanResult> scan({
    required HdWalletService hd,
    int gapLimit = 20,
    int startReceivingIndex = 0,
    int startChangeIndex = 0,
    void Function(ScanProgress progress)? onProgress,
  }) async {
    if (gapLimit <= 0) {
      throw ArgumentError.value(gapLimit, 'gapLimit', 'must be > 0');
    }
    if (startReceivingIndex < 0) {
      throw ArgumentError.value(
        startReceivingIndex,
        'startReceivingIndex',
        'must be >= 0',
      );
    }
    if (startChangeIndex < 0) {
      throw ArgumentError.value(
        startChangeIndex,
        'startChangeIndex',
        'must be >= 0',
      );
    }

    final receiving = await _scanChain(
      hd: hd,
      isChange: false,
      gapLimit: gapLimit,
      startIndex: startReceivingIndex,
      onProgress: onProgress,
    );
    final change = await _scanChain(
      hd: hd,
      isChange: true,
      gapLimit: gapLimit,
      startIndex: startChangeIndex,
      onProgress: onProgress,
    );

    return ScanResult(
      lastUsedReceivingIndex: receiving.lastUsedIndex,
      lastUsedChangeIndex: change.lastUsedIndex,
      receivingActivity: receiving.activity,
      changeActivity: change.activity,
    );
  }

  Future<_ChainScanResult> _scanChain({
    required HdWalletService hd,
    required bool isChange,
    required int gapLimit,
    required int startIndex,
    void Function(ScanProgress)? onProgress,
  }) async {
    final activity = <int, AddressActivity>{};
    int? lastUsedIndex;
    var consecutiveUnused = 0;
    var index = startIndex;

    while (consecutiveUnused < gapLimit) {
      final address = isChange
          ? hd.deriveChangeAddress(index)
          : hd.deriveReceivingAddress(index);

      final List<Transaction> txs;
      final List<UTXO> rawUtxos;
      try {
        txs = await _withRetry(
          () => _api.getAddressTransactions(address),
          address: address,
          index: index,
          isChange: isChange,
          op: 'getAddressTransactions',
        );
        rawUtxos = await _withRetry(
          () => _api.getAddressUtxos(address),
          address: address,
          index: index,
          isChange: isChange,
          op: 'getAddressUtxos',
        );
      } on UtxoScannerException {
        rethrow;
      }

      // Stamp each UTXO with the derivation it was discovered on so the
      // signer can locate the right private key later.
      final path = isChange ? hd.changePath(index) : hd.receivingPath(index);
      final chain = isChange ? ChainType.change : ChainType.receiving;
      final utxos = [
        for (final u in rawUtxos)
          u.withDerivation(
            derivationPath: path,
            addressIndex: index,
            chainType: chain,
          ),
      ];

      final hasHistory = txs.isNotEmpty || utxos.isNotEmpty;
      activity[index] = AddressActivity(
        index: index,
        address: address,
        isChange: isChange,
        hasHistory: hasHistory,
        txCount: txs.length,
        utxos: utxos,
      );

      if (hasHistory) {
        lastUsedIndex = index;
        consecutiveUnused = 0;
      } else {
        consecutiveUnused++;
      }

      onProgress?.call(ScanProgress(
        isChange: isChange,
        currentIndex: index,
        lastUsedIndex: lastUsedIndex,
        consecutiveUnused: consecutiveUnused,
      ));

      index++;
    }

    return _ChainScanResult(
      lastUsedIndex: lastUsedIndex,
      activity: activity,
    );
  }

  Future<T> _withRetry<T>(
    Future<T> Function() fn, {
    required String address,
    required int index,
    required bool isChange,
    required String op,
  }) async {
    var backoff = initialBackoff;
    Object? lastErr;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        lastErr = e;
        if (attempt == retries) break;
        await Future.delayed(backoff);
        backoff *= 2;
      }
    }
    throw UtxoScannerException(
      '$op failed after ${retries + 1} attempts for ${isChange ? "change" : "receive"}/$index',
      cause: lastErr,
      address: address,
      index: index,
      isChange: isChange,
    );
  }
}

class _ChainScanResult {
  final int? lastUsedIndex;
  final Map<int, AddressActivity> activity;

  _ChainScanResult({required this.lastUsedIndex, required this.activity});
}
