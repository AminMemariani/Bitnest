/// Unspent Transaction Output (UTXO) model.
class UTXO {
  final String txid;
  final int vout;
  final String address;
  final BigInt value;
  final int confirmations;
  final int? blockHeight;
  final String scriptPubKey;

  UTXO({
    required this.txid,
    required this.vout,
    required this.address,
    required this.value,
    this.confirmations = 0,
    this.blockHeight,
    required this.scriptPubKey,
  });

  factory UTXO.fromJson(Map<String, dynamic> json) {
    return UTXO(
      txid: json['txid'] as String,
      vout: json['vout'] as int,
      address: json['address'] as String? ?? '',
      value: BigInt.from(json['value'] is int ? json['value'] : (json['value'] as num).toInt()),
      confirmations: json['status']?['block_height'] != null
          ? (json['status']?['confirmed'] == true ? 1 : 0)
          : (json['confirmations'] as int? ?? 0),
      blockHeight: json['status']?['block_height'] as int? ?? json['block_height'] as int?,
      scriptPubKey: json['scriptpubkey'] as String? ?? json['scriptPubKey'] as String? ?? '',
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
    };
  }
}

