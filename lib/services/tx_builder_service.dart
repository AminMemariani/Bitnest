import '../models/utxo.dart';
import '../utils/networks.dart';

/// Strategy the [TransactionBuilder] uses to order the candidate UTXO set
/// before selecting inputs.
enum CoinSelectionStrategy {
  /// Largest value first. Minimises the number of inputs (and therefore
  /// vbytes) but tends to consolidate the wallet into fewer, bigger outputs.
  largestFirst,

  /// Smallest value first. Grinds down small UTXOs, but produces heavier
  /// transactions.
  smallestFirst,

  /// Oldest confirmations first (`blockHeight` ascending). Useful to avoid
  /// touching recently received UTXOs.
  oldestFirst,
}

/// One change-address allocation: the address itself plus the BIP32
/// child index it was derived at. The index is what lets the send
/// pipeline promote the *correct* outstanding allocation when its tx
/// successfully broadcasts — even if other concurrent sends have
/// allocated their own indices in the meantime.
class ChangeAllocation {
  final String address;
  final int index;
  const ChangeAllocation({required this.address, required this.index});
}

/// Resolves a never-before-returned change address. In production this is
/// `WalletRepository.allocateFreshChange` tear-off; tests can pass a
/// closure that returns a deterministic [ChangeAllocation].
typedef FreshChangeAddressProvider = Future<ChangeAllocation> Function();

/// One input to an [UnsignedTransaction]. Holds a reference to the source
/// UTXO so signers have access to `scriptPubKey` and the input value (needed
/// for BIP143 sighash).
class TxInput {
  final UTXO utxo;

  /// Sequence number. Default enables RBF (BIP125) and disables locktime
  /// relative behavior.
  final int sequence;

  const TxInput({required this.utxo, this.sequence = 0xFFFFFFFD});

  BigInt get value => utxo.value;
  String get txid => utxo.txid;
  int get vout => utxo.vout;
  String get scriptPubKey => utxo.scriptPubKey;
}

/// One output on an [UnsignedTransaction].
class TxOutput {
  final String address;
  final BigInt value;
  final bool isChange;

  const TxOutput({
    required this.address,
    required this.value,
    this.isChange = false,
  });
}

/// An unsigned Bitcoin transaction ready for signing. This is the plain-data
/// equivalent of a PSBT before signatures / finalizers have been applied —
/// it carries every piece of data a signer needs: inputs (with their source
/// UTXOs), outputs, version, locktime, estimated vbytes, and the absolute
/// fee.
///
/// This class performs no signing and produces no serialized tx bytes. A
/// follow-up signer (BDK / bitcoindart / in-house BIP143) is responsible
/// for turning this object into a broadcastable hex string.
class UnsignedTransaction {
  final List<TxInput> inputs;
  final List<TxOutput> outputs;
  final int version;
  final int lockTime;

  /// Estimated virtual size (vbytes) of the final witness transaction,
  /// using BIP141 weight units.
  final int estimatedVbytes;

  /// Fee rate that was requested when building this tx (sat/vB).
  final int feeRateSatPerVbyte;

  /// Absolute fee in satoshis. For the "dust-into-fee" case this is
  /// greater than `estimatedVbytes * feeRateSatPerVbyte` — the dust
  /// amount that would have been change is paid to miners instead.
  final BigInt fee;

  /// BIP32 child index of the change output, or `null` if the tx has no
  /// change output. Set by [TransactionBuilder] when it allocates change
  /// from a [WalletRepository]; read by the pipeline to promote that
  /// specific index on broadcast success.
  final int? changeIndexUsed;

  const UnsignedTransaction({
    required this.inputs,
    required this.outputs,
    this.version = 2,
    this.lockTime = 0,
    required this.estimatedVbytes,
    required this.feeRateSatPerVbyte,
    required this.fee,
    this.changeIndexUsed,
  });

  BigInt get totalInputValue =>
      inputs.fold<BigInt>(BigInt.zero, (s, i) => s + i.value);

  BigInt get totalOutputValue =>
      outputs.fold<BigInt>(BigInt.zero, (s, o) => s + o.value);

  bool get hasChange => outputs.any((o) => o.isChange);

  TxOutput? get changeOutput {
    for (final o in outputs) {
      if (o.isChange) return o;
    }
    return null;
  }

  TxOutput get recipientOutput => outputs.firstWhere((o) => !o.isChange);
}

/// Base class for errors surfaced by [TransactionBuilder].
class TxBuilderException implements Exception {
  final String message;
  TxBuilderException(this.message);
  @override
  String toString() => 'TxBuilderException: $message';
}

/// Thrown when the candidate UTXO set cannot cover `amount + fee`.
class InsufficientBalanceException extends TxBuilderException {
  final BigInt required;
  final BigInt available;
  InsufficientBalanceException({
    required this.required,
    required this.available,
  }) : super(
          'Insufficient balance: need $required sats, have $available sats',
        );
}

/// Thrown for caller mistakes: non-positive amounts or fee rates, empty
/// recipient addresses, etc.
class InvalidTxInputException extends TxBuilderException {
  InvalidTxInputException(super.message);
}

/// Builds an [UnsignedTransaction] from a UTXO set. Does NOT sign, and does
/// not produce serialized tx bytes.
///
/// Responsibilities:
/// 1. Validate the caller's inputs (recipient, amount, fee rate, dust).
/// 2. Select enough UTXOs to cover `amount + fee` using [CoinSelectionStrategy].
/// 3. Estimate virtual size correctly for native SegWit (P2WPKH) inputs.
/// 4. Add the recipient output.
/// 5. Add a change output (from [FreshChangeAddressProvider]) iff the
///    resulting change is strictly greater than the dust threshold.
/// 6. If the change would be dust, absorb it into the miner fee.
///
/// All inputs are assumed to be P2WPKH (this is a BIP84 wallet). Output
/// sizing adapts to the recipient address type (P2WPKH / P2SH / P2PKH /
/// P2TR) so the fee estimate is accurate regardless of who you're paying.
class TransactionBuilder {
  /// nVersion(4) + marker+flag(2, witness-discounted to 0.5 vB) +
  /// input count(1) + output count(1) + nLockTime(4).
  /// 10 non-witness + 0.5 witness = 10.5 vB; rounded up to 11.
  static const int overheadVbytes = 11;

  /// vbytes for a P2WPKH-spending input (segwit-discounted witness).
  /// outpoint(36) + scriptSig len(1=0x00) + sequence(4) = 41 non-witness
  /// witness stack: 1 (count) + 1 + 72 (sig+sighash) + 1 + 33 (pubkey) ~108,
  ///   discounted to 27 vB. Total = 68 vB.
  static const int p2wpkhInputVbytes = 68;

  /// vbytes for a P2WPKH output: value(8) + len(1) + OP_0 + push20 + hash(22)
  /// = 31 vB.
  static const int p2wpkhOutputVbytes = 31;

  /// Default dust threshold used when the caller doesn't override. 546 sats
  /// is the standard conservative value (dust for a P2PKH output at
  /// 3 sat/vB relay rate). Real Bitcoin Core policy is 294 sats for a
  /// P2WPKH output, but 546 is a safe ceiling.
  static final BigInt defaultDustThresholdSats = BigInt.from(546);

  const TransactionBuilder();

  /// Builds an unsigned transaction.
  ///
  /// [availableUtxos] is the pool the builder may draw from; it is not
  /// mutated. Coin selection runs in-memory.
  ///
  /// [getFreshChangeAddress] is invoked at most once — only when a change
  /// output is actually added. Dust-change scenarios do NOT burn a change
  /// address.
  ///
  /// Throws:
  ///   * [InvalidTxInputException] for caller validation errors.
  ///   * [InsufficientBalanceException] when the UTXO pool is too small.
  Future<UnsignedTransaction> build({
    required String recipientAddress,
    required BigInt amountSats,
    required int feeRateSatPerVbyte,
    required List<UTXO> availableUtxos,
    required FreshChangeAddressProvider getFreshChangeAddress,
    CoinSelectionStrategy strategy = CoinSelectionStrategy.largestFirst,
    BigInt? dustThresholdSats,
    BitcoinNetwork? network,
  }) async {
    if (recipientAddress.trim().isEmpty) {
      throw InvalidTxInputException('recipientAddress is empty');
    }
    if (amountSats <= BigInt.zero) {
      throw InvalidTxInputException(
        'amountSats must be > 0, got $amountSats',
      );
    }
    if (feeRateSatPerVbyte <= 0) {
      throw InvalidTxInputException(
        'feeRateSatPerVbyte must be > 0, got $feeRateSatPerVbyte',
      );
    }
    if (network != null) {
      _assertAddressOnNetwork(recipientAddress, network);
    }

    final dust = dustThresholdSats ?? defaultDustThresholdSats;
    if (amountSats < dust) {
      throw InvalidTxInputException(
        'amountSats ($amountSats) is below dust threshold ($dust)',
      );
    }
    if (availableUtxos.isEmpty) {
      throw InsufficientBalanceException(
        required: amountSats,
        available: BigInt.zero,
      );
    }

    final recipientVb = _outputVbytes(recipientAddress);
    const changeVb = p2wpkhOutputVbytes;

    final sorted = _sortUtxos(availableUtxos, strategy);
    final selected = <UTXO>[];
    BigInt totalIn = BigInt.zero;

    for (final utxo in sorted) {
      selected.add(utxo);
      totalIn += utxo.value;

      final inCount = selected.length;

      // Try with a change output.
      final vbWithChange =
          overheadVbytes + inCount * p2wpkhInputVbytes + recipientVb + changeVb;
      final feeWithChange = BigInt.from(vbWithChange * feeRateSatPerVbyte);

      if (totalIn >= amountSats + feeWithChange) {
        final change = totalIn - amountSats - feeWithChange;
        if (change > dust) {
          final allocation = await getFreshChangeAddress();
          return UnsignedTransaction(
            inputs: [for (final u in selected) TxInput(utxo: u)],
            outputs: [
              TxOutput(address: recipientAddress, value: amountSats),
              TxOutput(
                address: allocation.address,
                value: change,
                isChange: true,
              ),
            ],
            estimatedVbytes: vbWithChange,
            feeRateSatPerVbyte: feeRateSatPerVbyte,
            fee: feeWithChange,
            changeIndexUsed: allocation.index,
          );
        }
        // Change would be dust — drop into the miner fee. The "true" vbyte
        // count is without the change output; the effective fee is whatever
        // is left over.
        final vbNoChange =
            overheadVbytes + inCount * p2wpkhInputVbytes + recipientVb;
        final feeAbsorbed = totalIn - amountSats;
        return UnsignedTransaction(
          inputs: [for (final u in selected) TxInput(utxo: u)],
          outputs: [TxOutput(address: recipientAddress, value: amountSats)],
          estimatedVbytes: vbNoChange,
          feeRateSatPerVbyte: feeRateSatPerVbyte,
          fee: feeAbsorbed,
        );
      }

      // Can we satisfy without ever adding a change output? (The
      // "exact spend" / single-output case.)
      final vbNoChange =
          overheadVbytes + inCount * p2wpkhInputVbytes + recipientVb;
      final feeNoChange = BigInt.from(vbNoChange * feeRateSatPerVbyte);
      if (totalIn >= amountSats + feeNoChange) {
        return UnsignedTransaction(
          inputs: [for (final u in selected) TxInput(utxo: u)],
          outputs: [TxOutput(address: recipientAddress, value: amountSats)],
          estimatedVbytes: vbNoChange,
          feeRateSatPerVbyte: feeRateSatPerVbyte,
          fee: totalIn - amountSats,
        );
      }

      // Need more inputs.
    }

    // Ran out of UTXOs.
    final bestVb =
        overheadVbytes + selected.length * p2wpkhInputVbytes + recipientVb;
    final minExpectedFee = BigInt.from(bestVb * feeRateSatPerVbyte);
    throw InsufficientBalanceException(
      required: amountSats + minExpectedFee,
      available: totalIn,
    );
  }

  List<UTXO> _sortUtxos(
    List<UTXO> utxos,
    CoinSelectionStrategy strategy,
  ) {
    final sorted = [...utxos];
    switch (strategy) {
      case CoinSelectionStrategy.largestFirst:
        sorted.sort((a, b) => b.value.compareTo(a.value));
      case CoinSelectionStrategy.smallestFirst:
        sorted.sort((a, b) => a.value.compareTo(b.value));
      case CoinSelectionStrategy.oldestFirst:
        sorted.sort(
          (a, b) =>
              (a.blockHeight ?? 1 << 31).compareTo(b.blockHeight ?? 1 << 31),
        );
    }
    return sorted;
  }

  /// Cheap address validation: rejects sending mainnet funds to a `tb1…`
  /// (testnet) recipient and vice-versa, plus base58 version-byte
  /// mismatches. The signer enforces the same rule, but doing it here
  /// means the user finds out before authorising — they don't see the
  /// confirmation dialog or burn the change-index allocation.
  static void _assertAddressOnNetwork(String address, BitcoinNetwork network) {
    final lower = address.toLowerCase();
    final isMainnet = network == BitcoinNetwork.mainnet;
    final mainnetBech32 = lower.startsWith('bc1') /* p2wpkh / p2wsh / p2tr */;
    final testnetBech32 = lower.startsWith('tb1') /* p2wpkh / p2wsh / p2tr */;
    if (mainnetBech32 || testnetBech32) {
      if (isMainnet && !mainnetBech32) {
        throw InvalidTxInputException(
          'Recipient address looks like testnet (tb1…) but the wallet is '
          'on mainnet.',
        );
      }
      if (!isMainnet && !testnetBech32) {
        throw InvalidTxInputException(
          'Recipient address looks like mainnet (bc1…) but the wallet is '
          'on testnet.',
        );
      }
      return;
    }
    // Base58: P2PKH starts with 1 (mainnet) / m or n (testnet);
    // P2SH starts with 3 (mainnet) / 2 (testnet). Reject the obvious
    // cross-network cases. Anything else (unknown prefix) is left for
    // the signer to deal with; we don't want to over-reject.
    final firstChar = address.isNotEmpty ? address[0] : '';
    final mainnetBase58 = firstChar == '1' || firstChar == '3';
    final testnetBase58 =
        firstChar == 'm' || firstChar == 'n' || firstChar == '2';
    if (mainnetBase58 || testnetBase58) {
      if (isMainnet && testnetBase58) {
        throw InvalidTxInputException(
          'Recipient address looks like testnet but the wallet is on mainnet.',
        );
      }
      if (!isMainnet && mainnetBase58) {
        throw InvalidTxInputException(
          'Recipient address looks like mainnet but the wallet is on testnet.',
        );
      }
    }
  }

  /// vbytes of an output that pays to [address], derived from the address
  /// prefix.
  static int _outputVbytes(String address) {
    final lower = address.toLowerCase();
    // Taproot (P2TR): OP_1 + push32 + 32B = 34B + 8 value + 1 len = 43 vB
    if (lower.startsWith('bc1p') || lower.startsWith('tb1p')) return 43;
    // Native SegWit (P2WPKH/P2WSH): OP_0 + push20 + 20B = 22B + 8 + 1 = 31 vB
    if (lower.startsWith('bc1') || lower.startsWith('tb1')) return 31;
    // P2SH: OP_HASH160 + push20 + 20B + OP_EQUAL = 23B + 8 + 1 = 32 vB
    if (address.startsWith('3') || address.startsWith('2')) return 32;
    // P2PKH / unknown: 25B script + 8 + 1 = 34 vB
    return 34;
  }
}
