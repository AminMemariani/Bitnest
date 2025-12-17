/// Transaction model for API responses.
class Transaction {
  final String txid;
  final int version;
  final int locktime;
  final List<TxInput> inputs;
  final List<TxOutput> outputs;
  final int? blockHeight;
  final DateTime? blockTime;
  final int confirmations;
  final BigInt fee;

  Transaction({
    required this.txid,
    required this.version,
    required this.locktime,
    required this.inputs,
    required this.outputs,
    this.blockHeight,
    this.blockTime,
    this.confirmations = 0,
    required this.fee,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final inputs = (json['vin'] as List<dynamic>?)
            ?.map((v) => TxInput.fromJson(v as Map<String, dynamic>))
            .toList() ??
        [];
    final outputs = (json['vout'] as List<dynamic>?)
            ?.map((v) => TxOutput.fromJson(v as Map<String, dynamic>))
            .toList() ??
        [];

    // Calculate fee from inputs and outputs
    BigInt fee = BigInt.zero;
    if (inputs.isNotEmpty && outputs.isNotEmpty) {
      final inputSum = inputs.fold<BigInt>(
        BigInt.zero,
        (sum, input) => sum + input.value,
      );
      final outputSum = outputs.fold<BigInt>(
        BigInt.zero,
        (sum, output) => sum + output.value,
      );
      fee = inputSum - outputSum;
    }

    return Transaction(
      txid: json['txid'] as String,
      version: json['version'] as int? ?? 1,
      locktime: json['locktime'] as int? ?? 0,
      inputs: inputs,
      outputs: outputs,
      blockHeight: json['status']?['block_height'] as int? ??
          json['block_height'] as int?,
      blockTime: json['status']?['block_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['status']?['block_time'] as int) * 1000)
          : (json['block_time'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (json['block_time'] as int) * 1000)
              : null),
      confirmations: json['status']?['block_height'] != null
          ? (json['status']?['confirmed'] == true ? 1 : 0)
          : (json['confirmations'] as int? ?? 0),
      fee: fee,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'txid': txid,
      'version': version,
      'locktime': locktime,
      'vin': inputs.map((v) => v.toJson()).toList(),
      'vout': outputs.map((v) => v.toJson()).toList(),
      'block_height': blockHeight,
      'block_time': blockTime?.millisecondsSinceEpoch,
      'confirmations': confirmations,
      'fee': fee.toInt(),
    };
  }
}

/// Transaction input model.
class TxInput {
  final String txid;
  final int vout;
  final BigInt value;
  final String? scriptSig;
  final String? address;

  TxInput({
    required this.txid,
    required this.vout,
    required this.value,
    this.scriptSig,
    this.address,
  });

  factory TxInput.fromJson(Map<String, dynamic> json) {
    final prevoutValue = json['prevout']?['value'];
    final value = prevoutValue is int
        ? prevoutValue
        : ((prevoutValue as num?)?.toInt() ?? 0);

    return TxInput(
      txid: json['txid'] as String,
      vout: json['vout'] as int,
      value: BigInt.from(value),
      scriptSig: json['scriptsig'] as String? ?? json['scriptSig'] as String?,
      address: json['prevout']?['scriptpubkey_address'] as String? ??
          json['prevout']?['address'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'txid': txid,
      'vout': vout,
      'value': value.toInt(),
      'scriptsig': scriptSig,
      'address': address,
    };
  }
}

/// Transaction output model.
class TxOutput {
  final int index;
  final BigInt value;
  final String scriptPubKey;
  final String? address;

  TxOutput({
    required this.index,
    required this.value,
    required this.scriptPubKey,
    this.address,
  });

  factory TxOutput.fromJson(Map<String, dynamic> json) {
    return TxOutput(
      index: json['vout'] as int? ?? json['n'] as int? ?? 0,
      value: BigInt.from(json['value'] is int
          ? json['value']
          : ((json['value'] as num?)?.toInt() ?? 0)),
      scriptPubKey: json['scriptpubkey'] as String? ??
          json['scriptPubKey'] as String? ??
          '',
      address: (json['scriptpubkey_address'] as String?) ??
          (json['address'] as String?) ??
          (json['scriptPubKeyAddress'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vout': index,
      'value': value.toInt(),
      'scriptpubkey': scriptPubKey,
      'address': address,
    };
  }
}
