/// Which BIP84 sub-chain an address was derived from.
enum ChainType {
  /// External / receiving chain: `m/84'/coin'/account'/0/i`.
  receiving,

  /// Internal / change chain: `m/84'/coin'/account'/1/i`.
  change,
}

/// Unspent Transaction Output (UTXO) model.
///
/// API-derived fields ([txid], [vout], [value], [address], [scriptPubKey],
/// [confirmations], [blockHeight]) are populated by the Esplora-style REST
/// client.
///
/// Wallet-derivation fields ([derivationPath], [addressIndex], [chainType])
/// are populated by the wallet's own components — most commonly by the UTXO
/// scanner that matched this output to a derived address. Signers require
/// these to locate the private key.
class UTXO {
  final String txid;
  final int vout;
  final String address;
  final BigInt value;
  final int confirmations;
  final int? blockHeight;
  final String scriptPubKey;

  /// Full BIP32 path that derives the private key controlling this UTXO,
  /// e.g. `m/84'/0'/0'/0/5`. `null` for UTXOs the wallet has not matched
  /// to a derivation (e.g. watch-only lookups).
  final String? derivationPath;

  /// The last component of [derivationPath] (the child index on the chain).
  /// `null` if [derivationPath] is null.
  final int? addressIndex;

  /// Which sub-chain the address is on.
  /// `null` if [derivationPath] is null.
  final ChainType? chainType;

  UTXO({
    required this.txid,
    required this.vout,
    required this.address,
    required this.value,
    this.confirmations = 0,
    this.blockHeight,
    required this.scriptPubKey,
    this.derivationPath,
    this.addressIndex,
    this.chainType,
  });

  /// Alias for [value]. Callers using the task's terminology can say
  /// `utxo.amountSats` instead of `utxo.value`; both return the same
  /// [BigInt].
  BigInt get amountSats => value;

  /// Returns a copy of this UTXO with derivation metadata attached.
  /// Used by the scanner to annotate freshly-fetched UTXOs with the
  /// derivation they were discovered on.
  UTXO withDerivation({
    required String derivationPath,
    required int addressIndex,
    required ChainType chainType,
  }) {
    return UTXO(
      txid: txid,
      vout: vout,
      address: address,
      value: value,
      confirmations: confirmations,
      blockHeight: blockHeight,
      scriptPubKey: scriptPubKey,
      derivationPath: derivationPath,
      addressIndex: addressIndex,
      chainType: chainType,
    );
  }

  factory UTXO.fromJson(Map<String, dynamic> json) {
    return UTXO(
      txid: json['txid'] as String,
      vout: json['vout'] as int,
      address: json['address'] as String? ?? '',
      value: BigInt.from(json['value'] is int
          ? json['value']
          : (json['value'] as num).toInt()),
      confirmations: json['status']?['block_height'] != null
          ? (json['status']?['confirmed'] == true ? 1 : 0)
          : (json['confirmations'] as int? ?? 0),
      blockHeight: json['status']?['block_height'] as int? ??
          json['block_height'] as int?,
      scriptPubKey: json['scriptpubkey'] as String? ??
          json['scriptPubKey'] as String? ??
          '',
      derivationPath: json['derivationPath'] as String?,
      addressIndex: json['addressIndex'] as int?,
      chainType: _parseChainType(json['chainType'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'txid': txid,
      'vout': vout,
      'address': address,
      'value': value.toInt(),
      'confirmations': confirmations,
      'block_height': blockHeight,
      'scriptpubkey': scriptPubKey,
      if (derivationPath != null) 'derivationPath': derivationPath,
      if (addressIndex != null) 'addressIndex': addressIndex,
      if (chainType != null) 'chainType': chainType!.name,
    };
  }

  static ChainType? _parseChainType(String? name) {
    if (name == null) return null;
    for (final c in ChainType.values) {
      if (c.name == name) return c;
    }
    return null;
  }
}
