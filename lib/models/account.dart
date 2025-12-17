import 'package:uuid/uuid.dart';
import '../utils/networks.dart';

/// Account model representing a BIP44 account with derivation path and balance.
class Account {
  final String id;
  final String walletId;
  final String label;
  final String derivationPath;
  final int accountIndex;
  final String xpub;
  final BitcoinNetwork network;
  final BigInt balance;
  final int lastSyncedBlock;
  final DateTime? lastSyncedAt;
  final List<String> addresses; // Generated addresses

  Account({
    String? id,
    required this.walletId,
    required this.label,
    required this.derivationPath,
    required this.accountIndex,
    required this.xpub,
    required this.network,
    BigInt? balance,
    this.lastSyncedBlock = 0,
    this.lastSyncedAt,
    List<String>? addresses,
  })  : id = id ?? const Uuid().v4(),
        balance = balance ?? BigInt.zero,
        addresses = addresses ?? [];

  Account copyWith({
    String? id,
    String? walletId,
    String? label,
    String? derivationPath,
    int? accountIndex,
    String? xpub,
    BitcoinNetwork? network,
    BigInt? balance,
    int? lastSyncedBlock,
    DateTime? lastSyncedAt,
    List<String>? addresses,
  }) {
    return Account(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      label: label ?? this.label,
      derivationPath: derivationPath ?? this.derivationPath,
      accountIndex: accountIndex ?? this.accountIndex,
      xpub: xpub ?? this.xpub,
      network: network ?? this.network,
      balance: balance ?? this.balance,
      lastSyncedBlock: lastSyncedBlock ?? this.lastSyncedBlock,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      addresses: addresses ?? this.addresses,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'walletId': walletId,
      'label': label,
      'derivationPath': derivationPath,
      'accountIndex': accountIndex,
      'xpub': xpub,
      'network': network.name,
      'balance': balance.toString(),
      'lastSyncedBlock': lastSyncedBlock,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'addresses': addresses,
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      walletId: json['walletId'] as String,
      label: json['label'] as String,
      derivationPath: json['derivationPath'] as String,
      accountIndex: json['accountIndex'] as int,
      xpub: json['xpub'] as String,
      network: BitcoinNetwork.values.firstWhere(
        (n) => n.name == json['network'],
        orElse: () => BitcoinNetwork.mainnet,
      ),
      balance: BigInt.parse(json['balance'] as String? ?? '0'),
      lastSyncedBlock: json['lastSyncedBlock'] as int? ?? 0,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.parse(json['lastSyncedAt'] as String)
          : null,
      addresses: (json['addresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
