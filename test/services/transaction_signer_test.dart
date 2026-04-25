import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/services/transaction_signer.dart';
import 'package:bitnest/services/tx_builder_service.dart';
import 'package:bitnest/utils/bech32.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';

/// BIP39 test vector.
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

HdWalletService _makeHd({
  BitcoinNetwork network = BitcoinNetwork.mainnet,
}) {
  final seed = Uint8List.fromList(bip39.mnemonicToSeed(_mnemonic));
  return HdWalletService.fromSeed(
    keyService: KeyService(),
    seed: seed,
    network: network,
  );
}

Uint8List _hash160(Uint8List data) {
  return RIPEMD160Digest().process(SHA256Digest().process(data));
}

/// Builds a synthetic UTXO whose `scriptPubKey` matches an HD-derived
/// P2WPKH address on [chainType] at [index]. Uses deterministic txid bytes.
UTXO _utxoForPath({
  required HdWalletService hd,
  required int index,
  required ChainType chainType,
  required int satoshis,
  String txidSeed = 'deadbeef',
  int vout = 0,
}) {
  final address = chainType == ChainType.receiving
      ? hd.deriveReceivingAddress(index)
      : hd.deriveChangeAddress(index);
  final path = chainType == ChainType.receiving
      ? hd.receivingPath(index)
      : hd.changePath(index);
  final pub = hd.derivePublicKeyForPath(path);
  final h160 = _hash160(pub);
  final scriptPubKey = Uint8List.fromList([0x00, 0x14, ...h160]);
  // deterministic 32-byte txid: sha256 of seed + index
  final txidBytes = SHA256Digest()
      .process(Uint8List.fromList('$txidSeed:$index:$vout'.codeUnits));
  return UTXO(
    txid: HEX.encode(txidBytes),
    vout: vout,
    address: address,
    value: BigInt.from(satoshis),
    confirmations: 6,
    scriptPubKey: HEX.encode(scriptPubKey),
    derivationPath: path,
    addressIndex: index,
    chainType: chainType,
  );
}

/// Rough sanity-check that [hex] is a witness-serialized BTC transaction:
/// `version(4) | marker(0x00) | flag(0x01) | ...`.
Map<String, dynamic> _parseWitnessHeader(String hex) {
  final bytes = Uint8List.fromList(HEX.decode(hex));
  expect(bytes.length, greaterThanOrEqualTo(10));
  final version =
      bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  expect(bytes[4], 0x00, reason: 'segwit marker byte');
  expect(bytes[5], 0x01, reason: 'segwit flag byte');
  final inputCount = bytes[6]; // assumes < 0xfd inputs
  return {
    'version': version,
    'inputCount': inputCount,
    'bytes': bytes,
  };
}

void main() {
  group('TransactionSigner — single input', () {
    test('signs a P2WPKH UTXO on the receiving chain and returns witness hex',
        () async {
      final hd = _makeHd();
      final signer = TransactionSigner(hd: hd);

      final input = _utxoForPath(
        hd: hd,
        index: 3,
        chainType: ChainType.receiving,
        satoshis: 100000,
      );
      // Derive a recipient bech32 address from the same wallet for simplicity.
      final recipient = hd.deriveReceivingAddress(50);
      final changeAddr = hd.deriveChangeAddress(7);

      final unsigned = UnsignedTransaction(
        inputs: [TxInput(utxo: input)],
        outputs: [
          TxOutput(address: recipient, value: BigInt.from(80000)),
          TxOutput(
            address: changeAddr,
            value: BigInt.from(18000),
            isChange: true,
          ),
        ],
        estimatedVbytes: 141,
        feeRateSatPerVbyte: 10,
        fee: BigInt.from(2000),
      );

      final hex = await signer.sign(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
      );

      expect(hex, isNotEmpty);
      expect(HEX.decode(hex), isA<List<int>>());
      final parsed = _parseWitnessHeader(hex);
      expect(parsed['version'], 2);
      expect(parsed['inputCount'], 1);
    });

    test('signs a UTXO on the change chain', () async {
      final hd = _makeHd();
      final signer = TransactionSigner(hd: hd);

      final input = _utxoForPath(
        hd: hd,
        index: 2,
        chainType: ChainType.change,
        satoshis: 50000,
      );
      final recipient = hd.deriveReceivingAddress(0);

      final unsigned = UnsignedTransaction(
        inputs: [TxInput(utxo: input)],
        outputs: [
          TxOutput(address: recipient, value: BigInt.from(49000)),
        ],
        estimatedVbytes: 110,
        feeRateSatPerVbyte: 10,
        fee: BigInt.from(1000),
      );

      final hex = await signer.sign(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
      );

      expect(hex, isNotEmpty);
      final parsed = _parseWitnessHeader(hex);
      expect(parsed['inputCount'], 1);
    });
  });

  group('TransactionSigner — multiple inputs from different paths', () {
    test('signs three inputs spanning both chains', () async {
      final hd = _makeHd();
      final signer = TransactionSigner(hd: hd);

      final inputs = [
        _utxoForPath(
            hd: hd,
            index: 0,
            chainType: ChainType.receiving,
            satoshis: 30000),
        _utxoForPath(
            hd: hd,
            index: 5,
            chainType: ChainType.receiving,
            satoshis: 40000),
        _utxoForPath(
            hd: hd, index: 1, chainType: ChainType.change, satoshis: 20000),
      ];
      // Sanity: all three derivation paths are distinct.
      final paths = inputs.map((u) => u.derivationPath).toSet();
      expect(paths.length, 3);

      final recipient = hd.deriveReceivingAddress(10);

      final unsigned = UnsignedTransaction(
        inputs: [for (final u in inputs) TxInput(utxo: u)],
        outputs: [
          TxOutput(address: recipient, value: BigInt.from(85000)),
        ],
        estimatedVbytes: 11 + 3 * 68 + 31,
        feeRateSatPerVbyte: 10,
        fee: BigInt.from(5000),
      );

      final hex = await signer.sign(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
      );

      final parsed = _parseWitnessHeader(hex);
      expect(parsed['inputCount'], 3);

      // The serialized tx must carry three distinct txids in the input
      // section. Grab bytes 7..7+3*41 (outpoint+scriptlen+seq per input
      // = 41 bytes) and check each 32-byte txid is different.
      final body = parsed['bytes'] as Uint8List;
      final offset = 7; // version(4) + marker(1) + flag(1) + inCount(1)
      final txids = <String>{};
      for (var i = 0; i < 3; i++) {
        final start = offset + i * 41;
        txids.add(HEX.encode(body.sublist(start, start + 32)));
      }
      expect(txids.length, 3,
          reason: 'each input commits to a different outpoint');
    });
  });

  group('TransactionSigner — input validation', () {
    test('throws when any input lacks a derivationPath', () async {
      final hd = _makeHd();
      final signer = TransactionSigner(hd: hd);

      final good = _utxoForPath(
        hd: hd,
        index: 0,
        chainType: ChainType.receiving,
        satoshis: 20000,
      );
      // Same on-chain data, derivation stripped.
      final bad = UTXO(
        txid: good.txid,
        vout: good.vout,
        address: good.address,
        value: good.value,
        confirmations: good.confirmations,
        scriptPubKey: good.scriptPubKey,
        // derivationPath, addressIndex, chainType omitted.
      );
      final recipient = hd.deriveReceivingAddress(9);

      final unsigned = UnsignedTransaction(
        inputs: [TxInput(utxo: good), TxInput(utxo: bad)],
        outputs: [TxOutput(address: recipient, value: BigInt.from(35000))],
        estimatedVbytes: 11 + 2 * 68 + 31,
        feeRateSatPerVbyte: 10,
        fee: BigInt.from(5000),
      );

      await expectLater(
        signer.sign(
          unsigned: unsigned,
          network: BitcoinNetwork.mainnet,
        ),
        throwsA(isA<TransactionSignerException>()
            .having((e) => e.inputIndex, 'inputIndex', 1)
            .having((e) => e.message, 'message', contains('derivationPath'))),
      );
    });

    test('throws when the input list is empty', () async {
      final hd = _makeHd();
      final signer = TransactionSigner(hd: hd);
      final recipient = hd.deriveReceivingAddress(0);

      final unsigned = UnsignedTransaction(
        inputs: const [],
        outputs: [TxOutput(address: recipient, value: BigInt.from(1000))],
        estimatedVbytes: 42,
        feeRateSatPerVbyte: 1,
        fee: BigInt.zero,
      );

      await expectLater(
        signer.sign(
          unsigned: unsigned,
          network: BitcoinNetwork.mainnet,
        ),
        throwsA(isA<TransactionSignerException>()),
      );
    });
  });

  group('TransactionSigner — witness & signature structure', () {
    test(
        'witness section carries two items per input: DER sig || sighashAll, '
        'and the compressed pubkey', () async {
      final hd = _makeHd();
      final signer = TransactionSigner(hd: hd);

      final input = _utxoForPath(
        hd: hd,
        index: 4,
        chainType: ChainType.receiving,
        satoshis: 100000,
      );
      final recipient = hd.deriveReceivingAddress(40);
      final unsigned = UnsignedTransaction(
        inputs: [TxInput(utxo: input)],
        outputs: [
          TxOutput(address: recipient, value: BigInt.from(95000)),
        ],
        estimatedVbytes: 110,
        feeRateSatPerVbyte: 10,
        fee: BigInt.from(5000),
      );

      final hex = await signer.sign(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
      );
      final bytes = Uint8List.fromList(HEX.decode(hex));

      // Skip version(4) + marker(1) + flag(1) + inCount(1) = 7.
      // Input: 32 (txid) + 4 (vout) + 1 (scriptSig len = 0) + 4 (seq) = 41.
      // Output count varint (1) + output: 8 + 1 + 22 = 31 bytes.
      final outStart = 7 + 41;
      expect(bytes[outStart], 1, reason: 'one output');
      // value(8) + scriptLen(1) + script(22)
      final witnessStart = outStart + 1 + 31;

      final witnessStackCount = bytes[witnessStart];
      expect(witnessStackCount, 2,
          reason: 'P2WPKH witness stack: [sig, pubkey]');

      // First stack item: DER signature + sighash byte.
      var cur = witnessStart + 1;
      final sigLen = bytes[cur];
      cur += 1;
      final sigWithSighash = bytes.sublist(cur, cur + sigLen);
      cur += sigLen;
      expect(sigWithSighash[0], 0x30, reason: 'DER sequence tag');
      expect(sigWithSighash.last, 0x01, reason: 'SIGHASH_ALL byte');

      // Second stack item: compressed pubkey.
      final pubLen = bytes[cur];
      cur += 1;
      expect(pubLen, 33);
      final pub = bytes.sublist(cur, cur + pubLen);
      expect(pub[0] == 0x02 || pub[0] == 0x03, isTrue,
          reason: 'compressed pubkey prefix');

      // The signer commits to the same pubkey that the derivation path
      // produces. Re-derive and compare.
      final expectedPub = hd.derivePublicKeyForPath(input.derivationPath!);
      expect(pub, expectedPub);

      // And the P2WPKH output script in the body pays hash160(pub) of the
      // recipient — decode the bech32 recipient and compare.
      final decoded = Bech32.decodeSegwitAddress(recipient.toLowerCase());
      expect(decoded.witnessVersion, 0);
      final outputScript = bytes.sublist(
          outStart + 1 + 8 + 1, outStart + 1 + 8 + 1 + 22);
      // scriptPubKey = OP_0 || 0x14 || 20-byte-hash
      expect(outputScript[0], 0x00);
      expect(outputScript[1], 0x14);
      expect(outputScript.sublist(2), decoded.program);
    });
  });
}
