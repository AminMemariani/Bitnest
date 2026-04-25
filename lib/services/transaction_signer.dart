import 'dart:typed_data';
import 'package:bs58check/bs58check.dart' as bs58;
import 'package:hex/hex.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import '../utils/bech32.dart';
import '../utils/networks.dart';
import 'hd_wallet_service.dart';
import 'tx_builder_service.dart';

/// Raised when signing cannot proceed (missing derivation metadata, address
/// decode failure, signature that fails post-sign verification).
class TransactionSignerException implements Exception {
  final String message;
  final int? inputIndex;
  TransactionSignerException(this.message, {this.inputIndex});
  @override
  String toString() => 'TransactionSignerException: $message';
}

/// Signs an [UnsignedTransaction] whose inputs come from HD-derived P2WPKH
/// addresses (BIP84) and returns the broadcast-ready witness-serialized
/// transaction hex.
///
/// Per input, the signer:
///   1. Reads `utxo.derivationPath` (must be non-null — task contract).
///   2. Derives the private key and public key via [HdWalletService].
///   3. Computes the BIP143 sighash (SIGHASH_ALL).
///   4. Produces an ECDSA-over-secp256k1 signature with **low-S**
///      normalisation (BIP62).
///   5. Verifies the signature against the public key BEFORE committing it
///      to the witness stack.
///   6. Zero-fills the private-key buffer.
///
/// After all inputs have valid signatures, the witness tx is serialised:
/// nVersion · marker · flag · inputs (with empty scriptSigs) · outputs ·
/// per-input witness stacks · nLockTime.
///
/// Security invariants:
///   * No `print`, `debugPrint`, or `DebugLogger` call in this file ever
///     receives the mnemonic, seed, xprv, private key bytes, or raw
///     signature material. Exceptions reference inputs by index, never by
///     key material.
///   * Private key buffers are overwritten with zeros in a `finally`, even
///     on the exception path.
class TransactionSigner {
  final HdWalletService _hd;

  TransactionSigner({required HdWalletService hd}) : _hd = hd;

  /// SIGHASH_ALL.
  static const int _sighashAll = 0x01;

  /// Signs [unsigned] and returns the final witness-serialised transaction
  /// as a lowercase hex string.
  ///
  /// [network] is used exclusively to decode recipient/change addresses
  /// into their scriptPubKey bytes — it does not alter key derivation
  /// (that's already baked into each input's derivation path).
  Future<String> sign({
    required UnsignedTransaction unsigned,
    required BitcoinNetwork network,
  }) async {
    if (unsigned.inputs.isEmpty) {
      throw TransactionSignerException('unsigned transaction has no inputs');
    }
    _requireDerivationOnEveryInput(unsigned);

    // BIP143 commitments computed once per tx.
    final hashPrevouts = _hashPrevouts(unsigned);
    final hashSequence = _hashSequence(unsigned);
    final hashOutputs = _hashOutputs(unsigned, network);

    final witnesses = <List<Uint8List>>[];
    for (var i = 0; i < unsigned.inputs.length; i++) {
      witnesses.add(_signInput(
        unsigned: unsigned,
        inputIndex: i,
        hashPrevouts: hashPrevouts,
        hashSequence: hashSequence,
        hashOutputs: hashOutputs,
      ));
    }

    final bytes = _serialize(unsigned, witnesses, network);
    return HEX.encode(bytes);
  }

  /// Computes the Bitcoin txid of [unsigned] without signing. For SegWit
  /// transactions the txid is a digest over the non-witness data only
  /// (version · vin-without-scriptSig · vout · locktime), so the value is
  /// fully determined by [UnsignedTransaction] and does not depend on the
  /// signatures.
  ///
  /// Returned as a lowercase hex string in the canonical block-explorer
  /// byte order (big-endian).
  String computeTxid(UnsignedTransaction unsigned, BitcoinNetwork network) {
    if (unsigned.inputs.isEmpty) {
      throw TransactionSignerException(
        'cannot compute txid of a transaction with no inputs',
      );
    }
    final b = BytesBuilder();
    b.add(_uint32LE(unsigned.version));
    b.add(_varInt(unsigned.inputs.length));
    for (final input in unsigned.inputs) {
      b.add(_reversed(_hex(input.utxo.txid)));
      b.add(_uint32LE(input.utxo.vout));
      b.add(_varInt(0));
      b.add(_uint32LE(input.sequence));
    }
    b.add(_varInt(unsigned.outputs.length));
    for (final o in unsigned.outputs) {
      b.add(_uint64LE(o.value));
      final script = _addressToScriptPubKey(o.address, network);
      b.add(_varInt(script.length));
      b.add(script);
    }
    b.add(_uint32LE(unsigned.lockTime));
    final digest = _dsha256(b.toBytes());
    // txids are displayed big-endian; the hash above is little-endian.
    return HEX.encode(_reversed(digest));
  }

  // ---- per-input signing ----

  List<Uint8List> _signInput({
    required UnsignedTransaction unsigned,
    required int inputIndex,
    required Uint8List hashPrevouts,
    required Uint8List hashSequence,
    required Uint8List hashOutputs,
  }) {
    final input = unsigned.inputs[inputIndex];
    final path = input.utxo.derivationPath!;

    // Derive the signing material. The private-key buffer is zeroed in a
    // finally no matter what happens next.
    final privKey = _hd.derivePrivateKeyForPath(path);
    try {
      final pubKey = _hd.derivePublicKeyForPath(path);

      final scriptCode = _p2wpkhScriptCode(pubKey);
      final preimage = _bip143Preimage(
        unsigned: unsigned,
        inputIndex: inputIndex,
        scriptCode: scriptCode,
        hashPrevouts: hashPrevouts,
        hashSequence: hashSequence,
        hashOutputs: hashOutputs,
      );
      final sighash = _dsha256(preimage);

      final signature = _ecdsaSignLowS(privKey, sighash);

      if (!_ecdsaVerify(pubKey, sighash, signature)) {
        throw TransactionSignerException(
          'signature failed post-sign verification',
          inputIndex: inputIndex,
        );
      }

      final der = _derEncode(signature);
      final witnessSig = Uint8List.fromList([...der, _sighashAll]);
      return [witnessSig, pubKey];
    } finally {
      _zero(privKey);
    }
  }

  // ---- BIP143 components ----

  Uint8List _hashPrevouts(UnsignedTransaction tx) {
    final b = BytesBuilder();
    for (final input in tx.inputs) {
      b.add(_reversed(_hex(input.utxo.txid)));
      b.add(_uint32LE(input.utxo.vout));
    }
    return _dsha256(b.toBytes());
  }

  Uint8List _hashSequence(UnsignedTransaction tx) {
    final b = BytesBuilder();
    for (final input in tx.inputs) {
      b.add(_uint32LE(input.sequence));
    }
    return _dsha256(b.toBytes());
  }

  Uint8List _hashOutputs(UnsignedTransaction tx, BitcoinNetwork net) {
    final b = BytesBuilder();
    for (final output in tx.outputs) {
      b.add(_uint64LE(output.value));
      final script = _addressToScriptPubKey(output.address, net);
      b.add(_varInt(script.length));
      b.add(script);
    }
    return _dsha256(b.toBytes());
  }

  Uint8List _bip143Preimage({
    required UnsignedTransaction unsigned,
    required int inputIndex,
    required Uint8List scriptCode, // length-prefixed 0x19 || script
    required Uint8List hashPrevouts,
    required Uint8List hashSequence,
    required Uint8List hashOutputs,
  }) {
    final input = unsigned.inputs[inputIndex];
    final b = BytesBuilder();
    b.add(_uint32LE(unsigned.version));
    b.add(hashPrevouts);
    b.add(hashSequence);
    b.add(_reversed(_hex(input.utxo.txid)));
    b.add(_uint32LE(input.utxo.vout));
    b.add(scriptCode);
    b.add(_uint64LE(input.utxo.value));
    b.add(_uint32LE(input.sequence));
    b.add(hashOutputs);
    b.add(_uint32LE(unsigned.lockTime));
    b.add(_uint32LE(_sighashAll));
    return b.toBytes();
  }

  /// BIP143 scriptCode for a P2WPKH input: a length-prefixed P2PKH script
  /// over `hash160(pubkey)`.
  Uint8List _p2wpkhScriptCode(Uint8List pubKey) {
    final h = _hash160(pubKey);
    return Uint8List.fromList([
      0x19,                          // script length (25 bytes)
      0x76, 0xa9, 0x14,              // OP_DUP OP_HASH160 OP_PUSH20
      ...h,                          // 20-byte pubkey hash
      0x88, 0xac,                    // OP_EQUALVERIFY OP_CHECKSIG
    ]);
  }

  // ---- final serialization ----

  Uint8List _serialize(
    UnsignedTransaction tx,
    List<List<Uint8List>> witnesses,
    BitcoinNetwork net,
  ) {
    final b = BytesBuilder();
    b.add(_uint32LE(tx.version));
    b.addByte(0x00);                 // marker
    b.addByte(0x01);                 // flag
    b.add(_varInt(tx.inputs.length));
    for (final input in tx.inputs) {
      b.add(_reversed(_hex(input.utxo.txid)));
      b.add(_uint32LE(input.utxo.vout));
      b.add(_varInt(0));             // empty scriptSig
      b.add(_uint32LE(input.sequence));
    }
    b.add(_varInt(tx.outputs.length));
    for (final o in tx.outputs) {
      b.add(_uint64LE(o.value));
      final script = _addressToScriptPubKey(o.address, net);
      b.add(_varInt(script.length));
      b.add(script);
    }
    for (final stack in witnesses) {
      b.add(_varInt(stack.length));
      for (final item in stack) {
        b.add(_varInt(item.length));
        b.add(item);
      }
    }
    b.add(_uint32LE(tx.lockTime));
    return b.toBytes();
  }

  // ---- address → scriptPubKey ----

  Uint8List _addressToScriptPubKey(String address, BitcoinNetwork net) {
    // Native SegWit / Taproot (bech32 / bech32m).
    final lower = address.toLowerCase();
    if (lower.startsWith('bc1') || lower.startsWith('tb1')) {
      final decoded = Bech32.decodeSegwitAddress(lower);
      final expectedHrp = net == BitcoinNetwork.mainnet ? 'bc' : 'tb';
      if (decoded.hrp != expectedHrp) {
        throw TransactionSignerException(
          'address HRP mismatch: expected "$expectedHrp", got "${decoded.hrp}"',
        );
      }
      final op = decoded.witnessVersion == 0
          ? 0x00
          : (0x50 + decoded.witnessVersion); // OP_1..OP_16
      return Uint8List.fromList([
        op,
        decoded.program.length,
        ...decoded.program,
      ]);
    }

    // Base58Check: P2PKH or P2SH.
    final Uint8List raw;
    try {
      raw = bs58.decode(address);
    } catch (_) {
      throw TransactionSignerException('cannot decode address: $address');
    }
    if (raw.length != 21) {
      throw TransactionSignerException(
        'base58 address has wrong payload length (${raw.length} bytes)',
      );
    }
    final version = raw[0];
    final payload = raw.sublist(1);

    final isMainnet = net == BitcoinNetwork.mainnet;
    final pkhVersion = isMainnet ? 0x00 : 0x6f;
    final p2shVersion = isMainnet ? 0x05 : 0xc4;

    if (version == pkhVersion) {
      // OP_DUP OP_HASH160 <20> <hash> OP_EQUALVERIFY OP_CHECKSIG
      return Uint8List.fromList([
        0x76, 0xa9, 0x14, ...payload, 0x88, 0xac,
      ]);
    }
    if (version == p2shVersion) {
      // OP_HASH160 <20> <hash> OP_EQUAL
      return Uint8List.fromList([
        0xa9, 0x14, ...payload, 0x87,
      ]);
    }
    throw TransactionSignerException(
      'unsupported base58 version byte 0x${version.toRadixString(16)}',
    );
  }

  // ---- ECDSA ----

  static final ECDomainParameters _curve = ECCurve_secp256k1();
  static final BigInt _curveN = _curve.n;
  static final BigInt _halfN = _curveN >> 1;

  ECSignature _ecdsaSignLowS(Uint8List privKey, Uint8List hash) {
    final d = _bytesToBigInt(privKey);
    final pk = ECPrivateKey(d, _curve);
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(pk));
    final raw = signer.generateSignature(hash) as ECSignature;
    final s = raw.s > _halfN ? _curveN - raw.s : raw.s;
    return ECSignature(raw.r, s);
  }

  bool _ecdsaVerify(Uint8List pubKey, Uint8List hash, ECSignature sig) {
    final q = _curve.curve.decodePoint(pubKey);
    if (q == null) return false;
    final pk = ECPublicKey(q, _curve);
    final verifier = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(false, PublicKeyParameter<ECPublicKey>(pk));
    return verifier.verifySignature(hash, sig);
  }

  Uint8List _derEncode(ECSignature sig) {
    final r = _positiveMagnitude(sig.r);
    final s = _positiveMagnitude(sig.s);
    final body = <int>[0x02, r.length, ...r, 0x02, s.length, ...s];
    return Uint8List.fromList([0x30, body.length, ...body]);
  }

  /// Produces the minimal DER big-endian magnitude with the high-bit rule:
  /// if the top bit would be set (interpreted as negative), prepend 0x00.
  Uint8List _positiveMagnitude(BigInt n) {
    var hex = n.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    var bytes = Uint8List.fromList(HEX.decode(hex));
    // Strip leading zeros except the one required by sign-bit rule.
    var i = 0;
    while (i + 1 < bytes.length && bytes[i] == 0x00 && (bytes[i + 1] & 0x80) == 0) {
      i++;
    }
    bytes = bytes.sublist(i);
    if (bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0x00, ...bytes]);
    }
    return bytes;
  }

  // ---- validation ----

  void _requireDerivationOnEveryInput(UnsignedTransaction tx) {
    for (var i = 0; i < tx.inputs.length; i++) {
      final u = tx.inputs[i].utxo;
      final path = u.derivationPath;
      if (path == null || path.isEmpty) {
        throw TransactionSignerException(
          'input $i (${u.txid}:${u.vout}) is missing derivationPath',
          inputIndex: i,
        );
      }
    }
  }

  // ---- byte helpers ----

  static Uint8List _uint32LE(int v) {
    final b = Uint8List(4);
    b[0] = v & 0xff;
    b[1] = (v >> 8) & 0xff;
    b[2] = (v >> 16) & 0xff;
    b[3] = (v >> 24) & 0xff;
    return b;
  }

  static Uint8List _uint64LE(BigInt v) {
    final b = Uint8List(8);
    var x = v;
    final mask = BigInt.from(0xff);
    for (var i = 0; i < 8; i++) {
      b[i] = (x & mask).toInt();
      x = x >> 8;
    }
    return b;
  }

  static Uint8List _varInt(int v) {
    if (v < 0xfd) return Uint8List.fromList([v]);
    if (v <= 0xffff) {
      return Uint8List.fromList([0xfd, v & 0xff, (v >> 8) & 0xff]);
    }
    if (v <= 0xffffffff) {
      return Uint8List.fromList([
        0xfe,
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
    }
    final b = Uint8List(9);
    b[0] = 0xff;
    var x = v;
    for (var i = 1; i < 9; i++) {
      b[i] = x & 0xff;
      x = x >> 8;
    }
    return b;
  }

  static Uint8List _reversed(List<int> bytes) =>
      Uint8List.fromList(bytes.reversed.toList());

  static Uint8List _hex(String s) => Uint8List.fromList(HEX.decode(s));

  static Uint8List _dsha256(Uint8List data) {
    final first = SHA256Digest().process(data);
    return SHA256Digest().process(first);
  }

  static Uint8List _hash160(Uint8List data) {
    final sha = SHA256Digest().process(data);
    return RIPEMD160Digest().process(sha);
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    return BigInt.parse(HEX.encode(bytes), radix: 16);
  }

  static void _zero(Uint8List b) {
    for (var i = 0; i < b.length; i++) {
      b[i] = 0;
    }
  }
}
