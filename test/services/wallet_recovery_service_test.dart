import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/models/transaction.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/services/api_service.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/services/utxo_scanner_service.dart';
import 'package:bitnest/services/wallet_recovery_service.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:mockito/mockito.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reuse the MockApiService generated for the scanner tests.
import 'utxo_scanner_service_test.mocks.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _accountId = 'recovery-acct';

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

/// Mimics an Esplora-style response for a used address: a Transaction list
/// with one element is enough for the scanner to mark the address used.
Transaction _tx(String id) => Transaction(
      txid: id,
      version: 2,
      locktime: 0,
      inputs: const [],
      outputs: const [],
      fee: BigInt.zero,
    );

UTXO _utxo({
  required String address,
  required String txid,
  required int value,
  int vout = 0,
  int confirmations = 6,
}) =>
    UTXO(
      address: address,
      txid: txid,
      vout: vout,
      value: BigInt.from(value),
      confirmations: confirmations,
      scriptPubKey:
          '0014${HEX.encode(_hash160(Uint8List.fromList(address.codeUnits)))}',
    );

Uint8List _hash160(Uint8List data) =>
    RIPEMD160Digest().process(SHA256Digest().process(data));

void _stubDefaults(
  MockApiService api, {
  Map<String, List<Transaction>> transactions = const {},
  Map<String, List<UTXO>> utxos = const {},
}) {
  when(api.getAddressTransactions(any)).thenAnswer((invocation) async {
    return transactions[invocation.positionalArguments[0] as String] ??
        <Transaction>[];
  });
  when(api.getAddressUtxos(any)).thenAnswer((invocation) async {
    return utxos[invocation.positionalArguments[0] as String] ?? <UTXO>[];
  });
}

WalletRecoveryService _recoveryWith(MockApiService api) {
  return WalletRecoveryService(
    keyService: KeyService(),
    apiService: api,
    scannerFactory: (a) => UtxoScannerService(
      api: a,
      retries: 0,
      initialBackoff: const Duration(milliseconds: 1),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('recoverFromMnemonic — used receiving addresses', () {
    test(
        'detects used receiving indices, advances currentReceivingIndex, '
        'surfaces their UTXOs', () async {
      final api = MockApiService();
      final hd = _makeHd();
      final usedIdx = [0, 2, 5];
      final txs = <String, List<Transaction>>{
        for (final i in usedIdx) hd.deriveReceivingAddress(i): [_tx('rx-$i')],
      };
      final utxos = <String, List<UTXO>>{
        for (final i in usedIdx)
          hd.deriveReceivingAddress(i): [
            _utxo(
              address: hd.deriveReceivingAddress(i),
              txid: 'rx-$i',
              value: 10000 * (i + 1),
            ),
          ],
      };
      _stubDefaults(api, transactions: txs, utxos: utxos);

      final result = await _recoveryWith(api).recoverFromMnemonic(
        mnemonic: _mnemonic,
        network: BitcoinNetwork.mainnet,
        accountId: _accountId,
        gapLimit: 5,
      );

      expect(result.lastUsedReceivingIndex, 5);
      expect(result.currentReceivingIndex, 6,
          reason: 'current = lastUsed + 1 after recovery');
      expect(result.usedReceivingIndices, usedIdx);
      expect(result.utxos.length, 3);
      // 10k * (i+1) for i ∈ {0, 2, 5} = 10 000 + 30 000 + 60 000
      expect(result.totalBalance, BigInt.from(100000));
    });
  });

  group('recoverFromMnemonic — used change addresses', () {
    test(
        'detects used change-chain indices independently from receiving, '
        'advances currentChangeIndex', () async {
      final api = MockApiService();
      final hd = _makeHd();
      final usedChange = [0, 3];
      final txs = <String, List<Transaction>>{
        for (final i in usedChange) hd.deriveChangeAddress(i): [_tx('ch-$i')],
      };
      final utxos = <String, List<UTXO>>{
        for (final i in usedChange)
          hd.deriveChangeAddress(i): [
            _utxo(
              address: hd.deriveChangeAddress(i),
              txid: 'ch-$i',
              value: 5000,
            ),
          ],
      };
      _stubDefaults(api, transactions: txs, utxos: utxos);

      final result = await _recoveryWith(api).recoverFromMnemonic(
        mnemonic: _mnemonic,
        network: BitcoinNetwork.mainnet,
        accountId: _accountId,
        gapLimit: 5,
      );

      // Change chain is tracked.
      expect(result.lastUsedChangeIndex, 3);
      expect(result.currentChangeIndex, 4);
      expect(result.usedChangeIndices, usedChange);

      // Receive chain should be clean — we didn't stub any receive txs.
      expect(result.lastUsedReceivingIndex, -1);
      expect(result.currentReceivingIndex, 0);

      // The change UTXOs must not be missed.
      expect(result.utxos.length, 2);
      expect(result.totalBalance, BigInt.from(10000));
    });
  });

  group('recoverFromMnemonic — history without UTXOs', () {
    test(
        'addresses with tx history but no UTXOs (fully spent) are still '
        'treated as used, and their indices advance the rotation pointer',
        () async {
      final api = MockApiService();
      final hd = _makeHd();
      // Index 1 on the receive chain has two transactions but no coins left.
      final spentAddr = hd.deriveReceivingAddress(1);
      _stubDefaults(api, transactions: {
        spentAddr: [_tx('spent-a'), _tx('spent-b')],
      }); // no utxos entry ⇒ empty list

      final result = await _recoveryWith(api).recoverFromMnemonic(
        mnemonic: _mnemonic,
        network: BitcoinNetwork.mainnet,
        accountId: _accountId,
        gapLimit: 5,
      );

      expect(result.lastUsedReceivingIndex, 1,
          reason: 'history alone promotes the index to used');
      expect(result.currentReceivingIndex, 2);
      expect(result.utxos, isEmpty);
      expect(result.totalBalance, BigInt.zero);

      final activity = result.scanResult.receivingActivity[1]!;
      expect(activity.hasHistory, isTrue);
      expect(activity.txCount, 2);
      expect(activity.balance, BigInt.zero);
    });
  });

  group('recoverFromMnemonic — next fresh address after recovery', () {
    test(
        'repository.getCurrentReceivingAddress returns an unused address; '
        'repository.getFreshChangeAddress allocates past the last used '
        'change index', () async {
      final api = MockApiService();
      final hd = _makeHd();

      // Mixed state: receive used up to index 4, change used up to 2.
      final recvUsed = [2, 4];
      final chgUsed = [0, 2];
      _stubDefaults(
        api,
        transactions: {
          for (final i in recvUsed) hd.deriveReceivingAddress(i): [_tx('r$i')],
          for (final i in chgUsed) hd.deriveChangeAddress(i): [_tx('c$i')],
        },
      );

      final result = await _recoveryWith(api).recoverFromMnemonic(
        mnemonic: _mnemonic,
        network: BitcoinNetwork.mainnet,
        accountId: _accountId,
        gapLimit: 5,
      );
      final repo = result.repository;

      // Receiving side.
      expect(repo.currentReceivingIndex, 5);
      final nextReceive = await repo.getCurrentReceivingAddress();
      expect(nextReceive, hd.deriveReceivingAddress(5),
          reason: 'UI-facing next receive lands on the first unused index');
      expect(
        recvUsed.map(hd.deriveReceivingAddress).toSet().contains(nextReceive),
        isFalse,
        reason: 'current receive must never collide with a used index',
      );

      // Change side.
      expect(repo.currentChangeIndex, 3);
      final freshChange = await repo.getFreshChangeAddress();
      expect(freshChange, hd.deriveChangeAddress(3),
          reason: 'fresh change allocates past the last used change index');
      expect(
        chgUsed.map(hd.deriveChangeAddress).toSet().contains(freshChange),
        isFalse,
      );
      // getFreshChangeAddress advanced the pointer.
      expect(repo.currentChangeIndex, 4);
    });

    test('reports progress events for every address queried', () async {
      final api = MockApiService();
      _stubDefaults(api);

      final events = <ScanProgress>[];
      await _recoveryWith(api).recoverFromMnemonic(
        mnemonic: _mnemonic,
        network: BitcoinNetwork.mainnet,
        accountId: _accountId,
        gapLimit: 3,
        onProgress: events.add,
      );

      // gapLimit=3 on a fully-empty wallet => 3 addresses per chain = 6 events.
      expect(events.length, 6);
      expect(events.take(3).every((e) => e.isChange == false), isTrue);
      expect(events.skip(3).every((e) => e.isChange == true), isTrue);
    });
  });

  group('recoverFromMnemonic — input validation', () {
    test('rejects an invalid mnemonic', () async {
      final api = MockApiService();
      _stubDefaults(api);
      final recovery = _recoveryWith(api);

      expect(
        () => recovery.recoverFromMnemonic(
          mnemonic: 'not a real mnemonic',
          network: BitcoinNetwork.mainnet,
          accountId: _accountId,
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive gap limits', () async {
      final api = MockApiService();
      _stubDefaults(api);
      final recovery = _recoveryWith(api);

      expect(
        () => recovery.recoverFromMnemonic(
          mnemonic: _mnemonic,
          network: BitcoinNetwork.mainnet,
          accountId: _accountId,
          gapLimit: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
