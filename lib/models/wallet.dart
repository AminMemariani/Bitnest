import 'package:uuid/uuid.dart';
import '../utils/networks.dart';

/// Wallet model representing a root wallet with mnemonic and extended keys.
class Wallet {
  final String id;
  final String? mnemonic; // BIP39 mnemonic (nullable for imported wallets)
  final String? xprv; // Extended private key (nullable for watch-only)
  final String xpub; // Extended public key
  final DateTime createdAt;
  final String label;
  final BitcoinNetwork network;
  final bool isBackedUp;
  final List<String> accountIds;

  Wallet({
    String? id,
    this.mnemonic,
    this.xprv,
    required this.xpub,
    DateTime? createdAt,
    required this.label,
    required this.network,
    this.isBackedUp = false,
    List<String>? accountIds,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        accountIds = accountIds ?? [];

  Wallet copyWith({
    String? id,
    String? mnemonic,
    String? xprv,
    String? xpub,
    DateTime? createdAt,
    String? label,
    BitcoinNetwork? network,
    bool? isBackedUp,
    List<String>? accountIds,
  }) {
    return Wallet(
      id: id ?? this.id,
      mnemonic: mnemonic ?? this.mnemonic,
      xprv: xprv ?? this.xprv,
      xpub: xpub ?? this.xpub,
      createdAt: createdAt ?? this.createdAt,
      label: label ?? this.label,
      network: network ?? this.network,
      isBackedUp: isBackedUp ?? this.isBackedUp,
      accountIds: accountIds ?? this.accountIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'xpub': xpub,
      'createdAt': createdAt.toIso8601String(),
      'label': label,
      'network': network.name,
      'isBackedUp': isBackedUp,
      'accountIds': accountIds,
    };
  }

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'] as String,
      xpub: json['xpub'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      label: json['label'] as String,
      network: BitcoinNetwork.values.firstWhere(
        (n) => n.name == json['network'],
        orElse: () => BitcoinNetwork.mainnet,
      ),
      isBackedUp: json['isBackedUp'] as bool? ?? false,
      accountIds: (json['accountIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
