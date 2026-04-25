/// Lifecycle of a transaction tracked by the app's send-pipeline journal.
enum PendingTxState {
  /// Signed locally, persisted, but not yet successfully broadcast.
  /// Eligible for [broadcast] or [failed] on the next attempt.
  signed,

  /// Accepted by the network at least once. Rotation has been applied.
  /// This state is terminal; the record sticks around as a ledger entry
  /// until the caller purges it.
  broadcast,

  /// The most recent broadcast attempt failed. Eligible to retry, which
  /// moves the record back to [signed] before the next attempt or straight
  /// to [broadcast] on success.
  failed,
}

/// One record in the transaction journal. Uniquely keyed by [txid]; same
/// txid across attempts means same tx (Bitcoin txid is deterministic over
/// non-witness data, so retries stay stable).
class PendingTransaction {
  /// Hex-encoded txid (big-endian, the form used everywhere in Bitcoin
  /// block explorers).
  final String txid;

  /// Witness-serialized signed transaction hex, ready for re-broadcast.
  final String signedHex;

  /// Account whose UTXOs were consumed. Needed to scope rotation + UTXO
  /// filtering to the right wallet account.
  final String accountId;

  /// Change-chain index this tx allocated, or `null` if no change output
  /// was built (exact-spend / dust-absorbed).
  final int? changeIndexUsed;

  /// "txid:vout" strings for every UTXO the tx spends. Used to hide spent
  /// UTXOs from the rest of the app until the tx confirms.
  final List<String> spentOutpoints;

  final PendingTxState state;
  final DateTime createdAt;
  final DateTime? broadcastAt;

  /// Last broadcast error, populated when [state] == [PendingTxState.failed].
  /// The same string is returned to callers; we do not include raw key
  /// material because broadcast exceptions don't carry any.
  final String? error;

  const PendingTransaction({
    required this.txid,
    required this.signedHex,
    required this.accountId,
    required this.changeIndexUsed,
    required this.spentOutpoints,
    required this.state,
    required this.createdAt,
    this.broadcastAt,
    this.error,
  });

  PendingTransaction copyWith({
    String? txid,
    String? signedHex,
    String? accountId,
    int? changeIndexUsed,
    List<String>? spentOutpoints,
    PendingTxState? state,
    DateTime? createdAt,
    DateTime? broadcastAt,
    String? error,
  }) {
    return PendingTransaction(
      txid: txid ?? this.txid,
      signedHex: signedHex ?? this.signedHex,
      accountId: accountId ?? this.accountId,
      changeIndexUsed: changeIndexUsed ?? this.changeIndexUsed,
      spentOutpoints: spentOutpoints ?? this.spentOutpoints,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      broadcastAt: broadcastAt ?? this.broadcastAt,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'txid': txid,
      'signedHex': signedHex,
      'accountId': accountId,
      'changeIndexUsed': changeIndexUsed,
      'spentOutpoints': spentOutpoints,
      'state': state.name,
      'createdAt': createdAt.toIso8601String(),
      if (broadcastAt != null) 'broadcastAt': broadcastAt!.toIso8601String(),
      if (error != null) 'error': error,
    };
  }

  factory PendingTransaction.fromJson(Map<String, dynamic> json) {
    return PendingTransaction(
      txid: json['txid'] as String,
      signedHex: json['signedHex'] as String,
      accountId: json['accountId'] as String,
      changeIndexUsed: json['changeIndexUsed'] as int?,
      spentOutpoints: (json['spentOutpoints'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      state: PendingTxState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => PendingTxState.failed,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      broadcastAt: json['broadcastAt'] != null
          ? DateTime.parse(json['broadcastAt'] as String)
          : null,
      error: json['error'] as String?,
    );
  }
}
