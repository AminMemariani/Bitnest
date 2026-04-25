import '../models/pending_transaction.dart';
import '../repositories/wallet_repository.dart';
import '../utils/networks.dart';
import 'broadcast_service.dart';
import 'transaction_journal.dart';
import 'transaction_signer.dart';
import 'tx_builder_service.dart';

/// What happened when the pipeline tried to broadcast a tx.
enum BroadcastOutcomeKind {
  /// Newly broadcast. Rotation was applied this call.
  success,

  /// The same txid was already on file as `broadcast`. Rotation was
  /// already applied at that earlier call; this invocation made no
  /// on-chain or index changes.
  alreadyBroadcast,

  /// Broadcast failed (network error, node rejection, etc). Rotation
  /// was NOT applied; the journal records the error so the caller can
  /// retry.
  failed,
}

/// Result object returned by [SendPipelineService.signAndBroadcast] and
/// [SendPipelineService.recoverPending].
class BroadcastOutcome {
  final String txid;
  final BroadcastOutcomeKind kind;

  /// Present only when [kind] is [BroadcastOutcomeKind.failed].
  final Object? error;

  const BroadcastOutcome._(this.txid, this.kind, this.error);

  factory BroadcastOutcome.success(String txid) =>
      BroadcastOutcome._(txid, BroadcastOutcomeKind.success, null);
  factory BroadcastOutcome.alreadyBroadcast(String txid) =>
      BroadcastOutcome._(txid, BroadcastOutcomeKind.alreadyBroadcast, null);
  factory BroadcastOutcome.failed(String txid, Object error) =>
      BroadcastOutcome._(txid, BroadcastOutcomeKind.failed, error);

  bool get isSuccess =>
      kind == BroadcastOutcomeKind.success ||
      kind == BroadcastOutcomeKind.alreadyBroadcast;
}

/// End-to-end orchestrator for outgoing transactions.
///
/// The pipeline is the single place where a tx:
///
///  1. is signed (via [TransactionSigner]),
///  2. gets its txid computed deterministically,
///  3. is persisted into the [TransactionJournal] BEFORE any broadcast
///     attempt (so a crash right after signing leaves a recoverable
///     trace on disk),
///  4. is broadcast via [BroadcastService],
///  5. on success, atomically advances [WalletRepository] rotation
///     pointers and flips the journal entry to `broadcast`.
///
/// Properties the design gives you for free:
///
/// * **Duplicate-broadcast prevention.** Txid is the journal key, and
///   a second send with the same inputs/outputs short-circuits with
///   [BroadcastOutcomeKind.alreadyBroadcast].
/// * **Crash recovery.** [recoverPending] re-broadcasts every record
///   still in `signed` state.
/// * **Rotation is exactly-once.** The repo's
///   `onOutgoingTransactionSuccess` takes the txid as an idempotency
///   key; even if the "crash recovery" path re-broadcasts an already-
///   rotated tx, the index counters do not move again.
class SendPipelineService {
  final TransactionSigner _signer;
  final BroadcastService _broadcast;
  final TransactionJournal _journal;

  SendPipelineService({
    required TransactionSigner signer,
    required BroadcastService broadcast,
    required TransactionJournal journal,
  })  : _signer = signer,
        _broadcast = broadcast,
        _journal = journal;

  TransactionJournal get journal => _journal;

  /// Signs [unsigned] and attempts to broadcast.
  ///
  /// The tx is persisted to the journal in `signed` state BEFORE the
  /// broadcast call. If broadcast throws, the record is marked `failed`
  /// (never `broadcast`), rotation is NOT applied, and the exception is
  /// returned inside [BroadcastOutcome].
  ///
  /// If an earlier send with identical inputs/outputs has already
  /// completed, this call short-circuits with
  /// [BroadcastOutcomeKind.alreadyBroadcast].
  Future<BroadcastOutcome> signAndBroadcast({
    required UnsignedTransaction unsigned,
    required BitcoinNetwork network,
    required WalletRepository repository,
    required String accountId,
  }) async {
    final txid = _signer.computeTxid(unsigned, network);

    // Duplicate-broadcast guard: if the journal already has this txid in
    // broadcast state, rotation has already been performed and any further
    // network chatter would be wasted.
    final prior = _journal.get(txid);
    if (prior != null && prior.state == PendingTxState.broadcast) {
      return BroadcastOutcome.alreadyBroadcast(txid);
    }

    // Sign. The signer never logs key material.
    final signedHex = await _signer.sign(
      unsigned: unsigned,
      network: network,
    );

    // Persist BEFORE hitting the network. If the process dies between
    // this write and the broadcast call, recoverPending() will find the
    // record on next launch.
    final spent = [
      for (final i in unsigned.inputs) '${i.utxo.txid}:${i.utxo.vout}',
    ];
    // Prefer the precise index recorded by the builder when allocating
    // change; fall back to the repo's "highest outstanding" view for
    // hand-built UnsignedTransactions in tests.
    final changeIdx = unsigned.changeIndexUsed ??
        (unsigned.hasChange ? repository.lastAllocatedChangeIndex : null);

    final record = (prior ?? PendingTransaction(
      txid: txid,
      signedHex: signedHex,
      accountId: accountId,
      changeIndexUsed: changeIdx,
      spentOutpoints: spent,
      state: PendingTxState.signed,
      createdAt: DateTime.now(),
    )).copyWith(
      signedHex: signedHex,
      state: PendingTxState.signed,
      error: null,
    );
    await _journal.upsert(record);

    return _attemptBroadcast(record, repository, network);
  }

  /// Re-broadcasts every journal record for [accountId] still in
  /// `signed` state. Call on app startup to finish any sends that were
  /// interrupted by a crash.
  ///
  /// Rotation is NOT re-applied for any record whose idempotency key
  /// has already been consumed by [repository] — so a partial-commit
  /// crash (journal flipped but pointers not yet moved, or vice-versa)
  /// converges to the intended state without double-counting.
  Future<List<BroadcastOutcome>> recoverPending({
    required String accountId,
    required WalletRepository repository,
    required BitcoinNetwork network,
  }) async {
    final pending = _journal
        .byAccount(accountId)
        .where((t) => t.state == PendingTxState.signed)
        .toList();

    final outcomes = <BroadcastOutcome>[];
    for (final record in pending) {
      outcomes.add(await _attemptBroadcast(record, repository, network));
    }
    return outcomes;
  }

  /// Actually hits the network for [record] and transitions the journal
  /// plus rotation on success. Idempotent: a second call with the same
  /// record produces [BroadcastOutcomeKind.alreadyBroadcast].
  Future<BroadcastOutcome> _attemptBroadcast(
    PendingTransaction record,
    WalletRepository repository,
    BitcoinNetwork network,
  ) async {
    // Fast path: someone else committed this record between enqueue and
    // broadcast (e.g. two recoverPending calls racing).
    final current = _journal.get(record.txid);
    if (current != null && current.state == PendingTxState.broadcast) {
      return BroadcastOutcome.alreadyBroadcast(record.txid);
    }

    try {
      _broadcast.setNetwork(network);
      await _broadcast.broadcastTransaction(record.signedHex);
    } catch (e) {
      await _journal.markFailed(record.txid, error: e.toString());
      return BroadcastOutcome.failed(record.txid, e);
    }

    // Network accepted. Commit journal + rotate the repo. The rotation
    // uses txid as an idempotency key so a crash between these two
    // writes converges on the next invocation. The exact change index
    // captured at build time is passed through so the right
    // outstanding allocation is promoted, even if other sends are in
    // flight.
    final transitioned = await _journal.markBroadcast(record.txid);
    if (transitioned) {
      await repository.onOutgoingTransactionSuccess(
        idempotencyKey: record.txid,
        changeIndex: record.changeIndexUsed,
      );
    } else {
      // markBroadcast returned false — means state was already broadcast.
      // Still invoke rotation with the idempotency key in case the
      // previous run crashed after journal flip but before rotation.
      await repository.onOutgoingTransactionSuccess(
        idempotencyKey: record.txid,
        changeIndex: record.changeIndexUsed,
      );
      return BroadcastOutcome.alreadyBroadcast(record.txid);
    }
    return BroadcastOutcome.success(record.txid);
  }
}
