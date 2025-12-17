import 'dart:typed_data';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/api.dart';
import 'package:hex/hex.dart';
import '../models/utxo.dart';
import '../models/fee_estimate.dart';
import '../services/key_service.dart';
import '../services/api_service.dart';
import '../utils/networks.dart';
import '../utils/debug_logger.dart';

/// Fee preset options for transaction fees.
enum FeePreset {
  slow(6, 'Slow'),
  normal(3, 'Normal'),
  fast(1, 'Fast');

  final int targetBlocks;
  final String label;
  const FeePreset(this.targetBlocks, this.label);
}

/// Transaction input with signing information.
class TxInputInfo {
  final UTXO utxo;
  final String privateKeyHex;
  final int addressIndex;
  final bool isChange;
  final DerivationScheme scheme;

  TxInputInfo({
    required this.utxo,
    required this.privateKeyHex,
    required this.addressIndex,
    required this.isChange,
    required this.scheme,
  });
}

/// Transaction output information.
class TxOutputInfo {
  final String address;
  final BigInt value;

  TxOutputInfo({required this.address, required this.value});
}

/// Service for building and signing Bitcoin transactions.
///
/// This service handles:
/// - Transaction construction from UTXOs
/// - Fee calculation and change output creation
/// - Transaction signing with private keys
/// - Change address derivation
class TransactionService {
  final KeyService _keyService;
  final ApiService _apiService;

  TransactionService({KeyService? keyService, ApiService? apiService})
      : _keyService = keyService ?? KeyService(),
        _apiService = apiService ?? ApiService();

  /// Builds a transaction from UTXOs and outputs.
  ///
  /// [inputs] are the UTXOs to spend with their signing info.
  /// [outputs] are the recipient outputs.
  /// [feeRate] is the fee rate in sat/vB.
  /// [changeAddress] is the address to send change to (optional).
  ///
  /// Returns the raw transaction hex.
  Future<String> buildTransaction({
    required List<TxInputInfo> inputs,
    required List<TxOutputInfo> outputs,
    required int feeRate,
    String? changeAddress,
  }) async {
    try {
      // Calculate total input value
      final totalInput = inputs.fold<BigInt>(
        BigInt.zero,
        (sum, input) => sum + input.utxo.value,
      );

      // Calculate total output value
      final totalOutput = outputs.fold<BigInt>(
        BigInt.zero,
        (sum, output) => sum + output.value,
      );

      // Estimate transaction size (simplified)
      // Base size: version (4) + locktime (4) + input count (1-9) + output count (1-9)
      // Each input: ~148 bytes (P2WPKH) or ~180 bytes (P2PKH)
      // Each output: ~34 bytes (P2WPKH) or ~34 bytes (P2PKH)
      int estimatedSize = 10; // Base
      for (final input in inputs) {
        estimatedSize += input.scheme == DerivationScheme.legacy ? 180 : 148;
      }
      estimatedSize += outputs.length * 34;

      // Calculate fee
      final estimatedFee = BigInt.from(estimatedSize * feeRate);

      // Calculate change
      final change = totalInput - totalOutput - estimatedFee;

      // Add change output if change is above dust threshold (546 satoshis)
      final dustThreshold = BigInt.from(546);
      final finalOutputs = List<TxOutputInfo>.from(outputs);
      if (change > dustThreshold && changeAddress != null) {
        finalOutputs.add(TxOutputInfo(address: changeAddress, value: change));
      } else if (change < BigInt.zero) {
        throw Exception('Insufficient funds: need ${-change} more satoshis');
      }

      // Build raw transaction
      final txHex = await _buildRawTransaction(
        inputs: inputs,
        outputs: finalOutputs,
      );

      return txHex;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'TransactionService.buildTransaction',
        additionalInfo: {
          'inputCount': inputs.length,
          'outputCount': outputs.length,
          'feeRate': feeRate,
        },
      );
      rethrow;
    }
  }

  /// Gets fee estimate for a preset.
  Future<FeeEstimate> getFeeEstimateForPreset(FeePreset preset) async {
    return await _apiService.getFeeEstimate(targetBlocks: preset.targetBlocks);
  }

  /// Creates transaction input info from UTXO.
  ///
  /// [utxo] is the UTXO to spend.
  /// [accountXprv] is the account-level extended private key.
  /// [addressIndex] is the address index for this UTXO.
  /// [isChange] indicates if this is a change address.
  /// [scheme] is the derivation scheme.
  Future<TxInputInfo> createInputInfo({
    required UTXO utxo,
    required String accountXprv,
    required int addressIndex,
    required bool isChange,
    required DerivationScheme scheme,
  }) async {
    final privateKeyHex = _keyService.derivePrivateKey(
      accountXprv,
      addressIndex,
      change: isChange,
    );

    return TxInputInfo(
      utxo: utxo,
      privateKeyHex: privateKeyHex,
      addressIndex: addressIndex,
      isChange: isChange,
      scheme: scheme,
    );
  }

  /// Derives the next change address for an account.
  ///
  /// [accountXpub] is the account-level extended public key.
  /// [currentChangeIndex] is the current change address index.
  /// [scheme] is the derivation scheme.
  /// [network] is the Bitcoin network.
  String deriveChangeAddress({
    required String accountXpub,
    required int currentChangeIndex,
    required DerivationScheme scheme,
    required BitcoinNetwork network,
  }) {
    return _keyService.deriveAddress(
      accountXpub,
      currentChangeIndex,
      scheme,
      network,
      change: true,
    );
  }

  /// Builds a raw transaction hex string with signatures.
  Future<String> _buildRawTransaction({
    required List<TxInputInfo> inputs,
    required List<TxOutputInfo> outputs,
  }) async {
    final buffer = BytesBuilder();

    // Version (4 bytes, little-endian)
    buffer.addByte(0x01);
    buffer.addByte(0x00);
    buffer.addByte(0x00);
    buffer.addByte(0x00);

    // Input count (varint)
    buffer.add(_encodeVarInt(inputs.length));

    // Inputs (unsigned - will add signatures later)
    for (final input in inputs) {
      // Previous txid (32 bytes, reversed)
      final txidBytes = HEX.decode(input.utxo.txid);
      buffer.add(Uint8List.fromList(txidBytes.reversed.toList()));

      // Previous vout (4 bytes, little-endian)
      buffer.add(_uint32ToBytes(input.utxo.vout));

      // ScriptSig placeholder (will be filled after signing)
      buffer.addByte(0x00); // Empty for now

      // Sequence (4 bytes, 0xFFFFFFFF for replace-by-fee)
      buffer.addByte(0xFF);
      buffer.addByte(0xFF);
      buffer.addByte(0xFF);
      buffer.addByte(0xFF);
    }

    // Output count (varint)
    buffer.add(_encodeVarInt(outputs.length));

    // Outputs
    for (final output in outputs) {
      // Value (8 bytes, little-endian)
      buffer.add(_uint64ToBytes(output.value));

      // ScriptPubKey length and script
      final scriptPubKey = _addressToScriptPubKey(output.address);
      buffer.add(_encodeVarInt(scriptPubKey.length));
      buffer.add(scriptPubKey);
    }

    // Locktime (4 bytes, little-endian, 0 for now)
    buffer.addByte(0x00);
    buffer.addByte(0x00);
    buffer.addByte(0x00);
    buffer.addByte(0x00);

    // Now sign all inputs
    final unsignedTx = buffer.toBytes();
    final signedTx = await _signTransaction(unsignedTx, inputs);

    return HEX.encode(signedTx);
  }

  /// Signs a transaction with all inputs.
  Future<Uint8List> _signTransaction(
    Uint8List unsignedTx,
    List<TxInputInfo> inputs,
  ) async {
    final signedTx = Uint8List.fromList(unsignedTx);

    for (int i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      final signature = await _signInput(
        unsignedTx: unsignedTx,
        inputIndex: i,
        privateKeyHex: input.privateKeyHex,
        utxo: input.utxo,
        scheme: input.scheme,
      );

      // Insert signature into ScriptSig
      // This is simplified - in production, you'd properly serialize the script
      final scriptSig = _buildScriptSig(signature, input);
      _insertScriptSig(signedTx, i, scriptSig);
    }

    return signedTx;
  }

  /// Signs a transaction input.
  Future<Uint8List> _signInput({
    required Uint8List unsignedTx,
    required int inputIndex,
    required String privateKeyHex,
    required UTXO utxo,
    required DerivationScheme scheme,
  }) async {
    try {
      // Create signature hash (SIGHASH_ALL)
      final hash = _createSignatureHash(unsignedTx, inputIndex, utxo, scheme);

      // Sign with ECDSA
      final privateKeyBytes = HEX.decode(privateKeyHex);
      final privateKey = ECPrivateKey(
        BigInt.parse(HEX.encode(privateKeyBytes), radix: 16),
        ECCurve_secp256k1(),
      );

      final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64));
      signer.init(true, PrivateKeyParameter(privateKey));

      final signature = signer.generateSignature(hash) as ECSignature;

      // Encode signature in DER format with SIGHASH_ALL
      final derSignature = _encodeDERSignature(signature, 0x01); // SIGHASH_ALL

      return derSignature;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'TransactionService._signInput',
        additionalInfo: {'inputIndex': inputIndex, 'utxo': utxo.txid},
      );
      rethrow;
    }
  }

  /// Creates a signature hash for signing.
  Uint8List _createSignatureHash(
    Uint8List tx,
    int inputIndex,
    UTXO utxo,
    DerivationScheme scheme,
  ) {
    // Simplified signature hash creation
    // In production, this should follow BIP143 for Segwit
    final hash = SHA256Digest();
    final doubleHash = SHA256Digest();

    final firstHash = hash.process(tx);
    final secondHash = doubleHash.process(firstHash);

    return Uint8List.fromList(secondHash);
  }

  /// Encodes a signature in DER format.
  Uint8List _encodeDERSignature(ECSignature signature, int sighashType) {
    final r = signature.r;
    final s = signature.s;

    // Convert to bytes
    final rBytes = _bigIntToBytes(r);
    final sBytes = _bigIntToBytes(s);

    // DER encoding: 0x30 [length] 0x02 [r-length] [r] 0x02 [s-length] [s] [sighash]
    final buffer = BytesBuilder();
    buffer.addByte(0x30);
    buffer.addByte(4 + rBytes.length + sBytes.length);
    buffer.addByte(0x02);
    buffer.addByte(rBytes.length);
    buffer.add(rBytes);
    buffer.addByte(0x02);
    buffer.addByte(sBytes.length);
    buffer.add(sBytes);
    buffer.addByte(sighashType);

    return buffer.toBytes();
  }

  /// Builds ScriptSig for an input.
  Uint8List _buildScriptSig(Uint8List signature, TxInputInfo input) {
    // Simplified - in production, properly build script based on scheme
    final buffer = BytesBuilder();
    buffer.addByte(signature.length);
    buffer.add(signature);
    // Add public key (would need to derive from private key)
    return buffer.toBytes();
  }

  /// Inserts ScriptSig into transaction at input index.
  void _insertScriptSig(Uint8List tx, int inputIndex, Uint8List scriptSig) {
    // Find the position after vout in the input
    // This is simplified - proper implementation would parse and rebuild
    int offset = 4; // Version
    final inputCountVarInt = _encodeVarInt(
      1,
    ); // Simplified - assume 1 input for now
    offset += inputCountVarInt.length; // Skip input count

    for (int i = 0; i < inputIndex; i++) {
      offset += 32 + 4 + 1 + 4; // Skip previous inputs
    }
    offset += 32 + 4; // Skip txid and vout

    // Insert script length and script
    final newTx = BytesBuilder();
    newTx.add(tx.sublist(0, offset));
    newTx.add(_encodeVarInt(scriptSig.length));
    newTx.add(scriptSig);
    newTx.add(tx.sublist(offset + 1)); // Skip old empty script byte

    // Copy back to original
    final newBytes = newTx.toBytes();
    for (int i = 0; i < newBytes.length && i < tx.length; i++) {
      tx[i] = newBytes[i];
    }
  }

  /// Converts address to ScriptPubKey.
  Uint8List _addressToScriptPubKey(String address) {
    // Simplified - would need to decode address and build proper script
    // For now, return placeholder
    return Uint8List(25); // P2PKH script length
  }

  // Utility functions
  Uint8List _encodeVarInt(int value) {
    if (value < 0xFD) {
      return Uint8List.fromList([value]);
    } else if (value <= 0xFFFF) {
      return Uint8List.fromList([0xFD, value & 0xFF, (value >> 8) & 0xFF]);
    } else if (value <= 0xFFFFFFFF) {
      final bytes = Uint8List(5);
      bytes[0] = 0xFE;
      bytes[1] = value & 0xFF;
      bytes[2] = (value >> 8) & 0xFF;
      bytes[3] = (value >> 16) & 0xFF;
      bytes[4] = (value >> 24) & 0xFF;
      return bytes;
    } else {
      final bytes = Uint8List(9);
      bytes[0] = 0xFF;
      for (int i = 0; i < 8; i++) {
        bytes[i + 1] = (value >> (i * 8)) & 0xFF;
      }
      return bytes;
    }
  }

  Uint8List _uint32ToBytes(int value) {
    return Uint8List.fromList([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  Uint8List _uint64ToBytes(BigInt value) {
    final bytes = Uint8List(8);
    var v = value;
    for (int i = 0; i < 8; i++) {
      bytes[i] = (v & BigInt.from(0xFF)).toInt();
      v = v >> 8;
    }
    return bytes;
  }

  Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List.fromList([0]);
    }

    final hex = value.toRadixString(16);
    final hexPadded = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList(HEX.decode(hexPadded));
  }
}
