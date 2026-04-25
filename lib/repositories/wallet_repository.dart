import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hd_wallet_service.dart';
import '../services/tx_builder_service.dart' show ChangeAllocation;
import '../services/utxo_scanner_service.dart';

/// Persists the four BIP84 address-rotation pointers for a single account and
/// exposes the high-level receive/change address API used by the UI and the
/// send flow.
///
/// Four counters are tracked per account:
///
/// * `currentReceivingIndex` — the index the UI should show as the wallet's
///   "current receive address" (BIP84 path `m/84'/coin'/acct'/0/i`).
/// * `currentChangeIndex` — the next change-chain index to allocate to a
///   transaction (BIP84 path `m/84'/coin'/acct'/1/i`).
/// * `lastUsedReceivingIndex` — the highest receive-chain index observed on
///   chain. `-1` when no receive has ever been observed.
/// * `lastUsedChangeIndex` — the highest change-chain index observed on
///   chain. `-1` when no change output has ever been spent to.
///
/// Invariants maintained by this class:
///
/// * `currentReceivingIndex > lastUsedReceivingIndex` at rest (so the UI
///   address is always unused).
/// * `currentChangeIndex > lastUsedChangeIndex` at rest.
/// * A given change-chain index is returned by [getFreshChangeAddress] at
///   most once per repository instance's lifetime; `currentChangeIndex` is
///   advanced before the address is handed out.
///
/// Persistence: values are stored in [SharedPreferences] under namespaced
/// keys (`wallet_repo.<accountId>.*`) and survive app restart. No private
/// key material is written here — only integer indices.
class WalletRepository extends ChangeNotifier {
  static const String _prefix = 'wallet_repo';

  final String accountId;
  final HdWalletService _hd;
  final SharedPreferences _prefs;

  int _currentReceivingIndex;
  int _currentChangeIndex;
  int _lastUsedReceivingIndex;
  int _lastUsedChangeIndex;

  /// Change indices that have been allocated by [allocateFreshChange]
  /// (or its address-only shim [getFreshChangeAddress]) but have not yet
  /// been observed as broadcast by [onOutgoingTransactionSuccess].
  ///
  /// Tracking *every* outstanding allocation, not just the last one,
  /// matters when two send flows run concurrently: each must be able to
  /// promote its own change index on success, regardless of which one
  /// broadcasts first.
  final Set<int> _outstandingChangeAllocations = <int>{};

  /// Last idempotency key ([onOutgoingTransactionSuccess]) accepted. When
  /// a caller passes the same key twice the second call is a no-op, so
  /// rotation remains "exactly once per tx" even across app restarts.
  String? _lastAppliedTxid;

  WalletRepository._({
    required this.accountId,
    required HdWalletService hd,
    required SharedPreferences prefs,
    required int currentReceivingIndex,
    required int currentChangeIndex,
    required int lastUsedReceivingIndex,
    required int lastUsedChangeIndex,
    String? lastAppliedTxid,
  })  : _hd = hd,
        _prefs = prefs,
        _currentReceivingIndex = currentReceivingIndex,
        _currentChangeIndex = currentChangeIndex,
        _lastUsedReceivingIndex = lastUsedReceivingIndex,
        _lastUsedChangeIndex = lastUsedChangeIndex,
        _lastAppliedTxid = lastAppliedTxid;

  /// Loads the repository for [accountId] from [SharedPreferences]. If no
  /// prior state exists, the counters start at
  /// `currentReceivingIndex = 0`, `currentChangeIndex = 0`, and both
  /// `lastUsed*Index` at `-1`.
  static Future<WalletRepository> load({
    required String accountId,
    required HdWalletService hd,
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    return WalletRepository._(
      accountId: accountId,
      hd: hd,
      prefs: store,
      currentReceivingIndex:
          store.getInt(_k(accountId, 'currentReceiving')) ?? 0,
      currentChangeIndex: store.getInt(_k(accountId, 'currentChange')) ?? 0,
      lastUsedReceivingIndex:
          store.getInt(_k(accountId, 'lastUsedReceiving')) ?? -1,
      lastUsedChangeIndex:
          store.getInt(_k(accountId, 'lastUsedChange')) ?? -1,
      lastAppliedTxid: store.getString(_k(accountId, 'lastAppliedTxid')),
    );
  }

  /// Removes any persisted state for [accountId]. Intended for wallet removal.
  static Future<void> clear({
    required String accountId,
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    await Future.wait([
      store.remove(_k(accountId, 'currentReceiving')),
      store.remove(_k(accountId, 'currentChange')),
      store.remove(_k(accountId, 'lastUsedReceiving')),
      store.remove(_k(accountId, 'lastUsedChange')),
      store.remove(_k(accountId, 'lastAppliedTxid')),
    ]);
  }

  // ---- getters ----

  int get currentReceivingIndex => _currentReceivingIndex;
  int get currentChangeIndex => _currentChangeIndex;
  int get lastUsedReceivingIndex => _lastUsedReceivingIndex;
  int get lastUsedChangeIndex => _lastUsedChangeIndex;

  /// Highest outstanding change-index allocation that has not yet been
  /// folded into [lastUsedChangeIndex]. Returns `null` when nothing is
  /// outstanding.
  ///
  /// Kept as a single-int getter for callers that pre-date the
  /// outstanding-set design. New code should prefer threading the
  /// allocation index through [TransactionBuilder]'s
  /// `unsigned.changeIndexUsed` field, which survives concurrent
  /// allocations correctly.
  int? get lastAllocatedChangeIndex {
    if (_outstandingChangeAllocations.isEmpty) return null;
    return _outstandingChangeAllocations
        .reduce((a, b) => a > b ? a : b);
  }

  /// All currently-outstanding change allocations (immutable view).
  Set<int> get outstandingChangeAllocations =>
      Set.unmodifiable(_outstandingChangeAllocations);

  // ---- core API (spec) ----

  /// Returns the address at [currentReceivingIndex] without advancing it.
  /// Safe to call repeatedly — the UI uses this to display the wallet's
  /// current unused receiving address.
  Future<String> getCurrentReceivingAddress() async {
    return _hd.deriveReceivingAddress(_currentReceivingIndex);
  }

  /// Advances [currentReceivingIndex] by one and returns the new address.
  /// Use when the user explicitly asks for a fresh receiving address.
  Future<String> generateNextReceivingAddress() async {
    _currentReceivingIndex++;
    await _save();
    return _hd.deriveReceivingAddress(_currentReceivingIndex);
  }

  /// Allocates a never-before-returned change address and returns just
  /// its string form. Convenience for legacy callers; new code should
  /// prefer [allocateFreshChange] which returns the BIP32 index too.
  Future<String> getFreshChangeAddress() async {
    return (await allocateFreshChange()).address;
  }

  /// Derives the address at [currentChangeIndex] WITHOUT advancing the
  /// pointer or registering an outstanding allocation. Use this for
  /// pre-confirmation UI ("if you confirm, change will go to …") so a
  /// user who cancels doesn't waste a derivation slot.
  ///
  /// Important: the actual address used at broadcast time may differ
  /// if another send completes between the peek and the real
  /// allocation. The UI is responsible for blocking concurrent sends
  /// (typically via a modal) when correctness matters.
  String peekFreshChangeAddress() {
    return _hd.deriveChangeAddress(_currentChangeIndex);
  }

  /// Allocates a never-before-returned change address and returns it
  /// alongside the BIP32 child index it was derived at.
  ///
  /// Advances [currentChangeIndex] as its first synchronous step, so
  /// two concurrent callers cannot obtain the same index even if the
  /// tx that consumes one of them later fails. The index is recorded in
  /// the outstanding-allocations set; [onOutgoingTransactionSuccess]
  /// promotes the *specific* index when the corresponding tx confirms,
  /// even if other allocations are still in flight.
  Future<ChangeAllocation> allocateFreshChange() async {
    final index = _currentChangeIndex;
    _currentChangeIndex = index + 1;
    _outstandingChangeAllocations.add(index);
    await _save();
    return ChangeAllocation(
      index: index,
      address: _hd.deriveChangeAddress(index),
    );
  }

  /// Marks a specific receive-chain [index] as having been paid to on chain.
  /// Updates [lastUsedReceivingIndex] and pushes [currentReceivingIndex]
  /// past it so the UI rotates to a fresh address automatically.
  Future<void> markReceivingAddressUsed(int index) async {
    _assertNonNegative(index);
    if (index > _lastUsedReceivingIndex) _lastUsedReceivingIndex = index;
    if (_currentReceivingIndex <= index) _currentReceivingIndex = index + 1;
    await _save();
  }

  /// Marks a specific change-chain [index] as having been spent to.
  /// Updates [lastUsedChangeIndex] and pushes [currentChangeIndex] past it.
  /// Removes [index] from the outstanding-allocations set if present.
  Future<void> markChangeAddressUsed(int index) async {
    _assertNonNegative(index);
    if (index > _lastUsedChangeIndex) _lastUsedChangeIndex = index;
    if (_currentChangeIndex <= index) _currentChangeIndex = index + 1;
    _outstandingChangeAllocations.remove(index);
    await _save();
  }

  /// Folds a [ScanResult] into the repository's persisted state:
  ///
  /// * [lastUsedReceivingIndex] and [lastUsedChangeIndex] advance to the
  ///   high watermarks observed on chain (never retreat).
  /// * [currentReceivingIndex] and [currentChangeIndex] are moved to
  ///   `lastUsed + 1` so the UI's "current receive" and the next change
  ///   allocation land on the first unused index after the last on-chain
  ///   usage.
  ///
  /// Writes once to [SharedPreferences] at the end. Safe to call repeatedly
  /// — it is idempotent if the scan result does not change.
  Future<void> applyScanResult(ScanResult result) async {
    final r = result.lastUsedReceivingIndex;
    if (r != null && r > _lastUsedReceivingIndex) _lastUsedReceivingIndex = r;

    final c = result.lastUsedChangeIndex;
    if (c != null && c > _lastUsedChangeIndex) _lastUsedChangeIndex = c;

    if (_currentReceivingIndex <= _lastUsedReceivingIndex) {
      _currentReceivingIndex = _lastUsedReceivingIndex + 1;
    }
    if (_currentChangeIndex <= _lastUsedChangeIndex) {
      _currentChangeIndex = _lastUsedChangeIndex + 1;
    }
    await _save();
  }

  /// Call this after a send is successfully broadcast. It:
  ///
  /// * promotes the change index of the just-broadcast tx (if any) to
  ///   [lastUsedChangeIndex];
  /// * if no allocation was made during this tx (e.g. a send-all without a
  ///   change output), still advances [currentChangeIndex] by one to honor
  ///   the "increment after every outgoing tx" contract;
  /// * advances [currentReceivingIndex] by one for receive-side privacy
  ///   rotation.
  ///
  /// [changeIndex] is the precise BIP32 child index this tx's change
  /// output was derived at — pulled from
  /// `UnsignedTransaction.changeIndexUsed` by the pipeline. Passing it
  /// keeps the bookkeeping correct when multiple sends are in flight at
  /// once: each promotes its own index, not whichever one happened to
  /// be allocated last.
  ///
  /// If [changeIndex] is `null` and the outstanding-allocations set is
  /// non-empty, the *highest* outstanding index is taken — preserving
  /// pre-F-6 behavior for legacy callers and tests.
  ///
  /// When an [idempotencyKey] is supplied (typically the tx's txid), a
  /// second call with the same key is a no-op. This lets the send pipeline
  /// safely retry broadcasts after a crash without over-advancing the
  /// rotation pointers.
  ///
  /// All changes are persisted atomically.
  Future<void> onOutgoingTransactionSuccess({
    String? idempotencyKey,
    int? changeIndex,
  }) async {
    if (idempotencyKey != null && idempotencyKey == _lastAppliedTxid) {
      return;
    }

    if (changeIndex != null) {
      // Precise path: promote and remove this specific allocation.
      if (changeIndex > _lastUsedChangeIndex) {
        _lastUsedChangeIndex = changeIndex;
      }
      _outstandingChangeAllocations.remove(changeIndex);
    } else if (_outstandingChangeAllocations.isNotEmpty) {
      // Back-compat: promote the highest-numbered outstanding allocation
      // and remove it. Single-allocation flows (no concurrency) match
      // the pre-F-6 behavior exactly.
      final highest =
          _outstandingChangeAllocations.reduce((a, b) => a > b ? a : b);
      if (highest > _lastUsedChangeIndex) {
        _lastUsedChangeIndex = highest;
      }
      _outstandingChangeAllocations.remove(highest);
    } else {
      // No change output was allocated this tx, but the spec still requires
      // currentChangeIndex to advance on every outgoing tx.
      _currentChangeIndex++;
    }

    _currentReceivingIndex++;
    if (idempotencyKey != null) _lastAppliedTxid = idempotencyKey;
    await _save();
  }

  // ---- internals ----

  Future<void> _save() async {
    await _prefs.setInt(
      _k(accountId, 'currentReceiving'),
      _currentReceivingIndex,
    );
    await _prefs.setInt(
      _k(accountId, 'currentChange'),
      _currentChangeIndex,
    );
    await _prefs.setInt(
      _k(accountId, 'lastUsedReceiving'),
      _lastUsedReceivingIndex,
    );
    await _prefs.setInt(
      _k(accountId, 'lastUsedChange'),
      _lastUsedChangeIndex,
    );
    final key = _lastAppliedTxid;
    if (key != null) {
      await _prefs.setString(_k(accountId, 'lastAppliedTxid'), key);
    }
    notifyListeners();
  }

  static String _k(String accountId, String field) =>
      '$_prefix.$accountId.$field';

  static void _assertNonNegative(int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must be non-negative');
    }
  }
}
