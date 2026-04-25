import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../models/pending_transaction.dart';

/// Persistent, txid-keyed journal of transactions the app has signed or
/// broadcast.
///
/// The journal is the source of truth for:
///
///   * **Duplicate-broadcast prevention.** Every send looks up its txid
///     before broadcasting; if the journal already has that txid in
///     `broadcast` state, the caller short-circuits.
///   * **Pending-UTXO bookkeeping.** `pendingOutpointsFor(accountId)` gives
///     the set of `"txid:vout"` strings the UI should hide as
///     "pending spent".
///   * **Crash recovery.** If the app is killed between signing and
///     broadcast confirmation, the `signed` record on disk lets the next
///     launch re-broadcast the same bytes.
///
/// Storage: a single `transaction_journal` key in [SharedPreferences]
/// holding a JSON-encoded list of records. Simple, atomic-per-write, good
/// enough for the low write rate of outgoing txs.
class TransactionJournal {
  static const String _storageKey = 'transaction_journal';

  final SharedPreferences _prefs;
  final Map<String, PendingTransaction> _records;

  TransactionJournal._(this._prefs, this._records);

  /// Loads the journal from [SharedPreferences]. Returns an empty journal
  /// if no prior data exists or the stored blob fails to parse.
  static Future<TransactionJournal> load({
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final blob = store.getString(_storageKey);
    final records = <String, PendingTransaction>{};
    if (blob != null && blob.isNotEmpty) {
      try {
        final list = jsonDecode(blob) as List<dynamic>;
        for (final item in list) {
          final tx = PendingTransaction.fromJson(item as Map<String, dynamic>);
          records[tx.txid] = tx;
        }
      } catch (_) {
        // Corrupt blob — treat as empty; a later write will overwrite it.
      }
    }
    return TransactionJournal._(store, records);
  }

  // ---- queries ----

  PendingTransaction? get(String txid) => _records[txid];

  List<PendingTransaction> all() => List.unmodifiable(_records.values);

  List<PendingTransaction> byAccount(String accountId) => _records.values
      .where((t) => t.accountId == accountId)
      .toList(growable: false);

  /// Outpoints (`"txid:vout"`) that the app considers spent or in-flight
  /// for [accountId]. A UI that filters its available UTXOs against this
  /// set will never show a double-spend candidate.
  Set<String> pendingOutpointsFor(String accountId) {
    final result = <String>{};
    for (final tx in _records.values) {
      if (tx.accountId != accountId) continue;
      if (tx.state == PendingTxState.failed) continue;
      result.addAll(tx.spentOutpoints);
    }
    return result;
  }

  /// `true` if the [outpoint] (`"txid:vout"` string) is currently spent or
  /// in-flight from [accountId]'s perspective.
  bool isOutpointPending({
    required String accountId,
    required String outpoint,
  }) {
    for (final tx in _records.values) {
      if (tx.accountId != accountId) continue;
      if (tx.state == PendingTxState.failed) continue;
      if (tx.spentOutpoints.contains(outpoint)) return true;
    }
    return false;
  }

  // ---- mutations ----

  /// Inserts or updates a record by txid. Callers use this for the initial
  /// pre-broadcast persistence; later lifecycle transitions use the named
  /// mutators below so the state machine stays explicit.
  Future<void> upsert(PendingTransaction tx) async {
    _records[tx.txid] = tx;
    await _save();
  }

  /// Transition `signed|failed → broadcast`. Idempotent: calling this on
  /// an already-broadcast record is a no-op.
  ///
  /// Returns `true` when the call actually changed state (i.e. the caller
  /// holds the "exactly once" moment and should perform side-effects like
  /// index rotation); `false` when the record was already `broadcast`.
  Future<bool> markBroadcast(String txid, {DateTime? at}) async {
    final current = _records[txid];
    if (current == null) return false;
    if (current.state == PendingTxState.broadcast) return false;
    _records[txid] = current.copyWith(
      state: PendingTxState.broadcast,
      broadcastAt: at ?? DateTime.now(),
      error: null,
    );
    await _save();
    return true;
  }

  /// Transition `signed → failed`. Never overwrites a `broadcast` record
  /// (a failed retry doesn't undo a prior success).
  Future<void> markFailed(String txid, {required String error}) async {
    final current = _records[txid];
    if (current == null) return;
    if (current.state == PendingTxState.broadcast) return;
    _records[txid] = current.copyWith(
      state: PendingTxState.failed,
      error: error,
    );
    await _save();
  }

  /// Moves a `failed` record back to `signed` so the pipeline will attempt
  /// another broadcast. No-op if the record is missing or already in a
  /// later state.
  Future<void> markRetrying(String txid) async {
    final current = _records[txid];
    if (current == null) return;
    if (current.state != PendingTxState.failed) return;
    _records[txid] = current.copyWith(
      state: PendingTxState.signed,
      error: null,
    );
    await _save();
  }

  /// Removes [txid] from the journal. Intended for after a tx has
  /// confirmed on chain, or for administrative clean-up.
  Future<void> remove(String txid) async {
    if (_records.remove(txid) != null) {
      await _save();
    }
  }

  /// Removes every record. Primarily for tests.
  Future<void> clear() async {
    _records.clear();
    await _prefs.remove(_storageKey);
  }

  Future<void> _save() async {
    final list = _records.values.map((t) => t.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(list));
  }
}
