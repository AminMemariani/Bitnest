import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/models/transaction.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/services/api_service.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/services/utxo_scanner_service.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'utxo_scanner_service_test.mocks.dart';

const _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

HdWalletService _makeHd({
  BitcoinNetwork network = BitcoinNetwork.mainnet,
}) {
  final seed = Uint8List.fromList(bip39.mnemonicToSeed(_testMnemonic));
  return HdWalletService.fromSeed(
    keyService: KeyService(),
    seed: seed,
    network: network,
  );
}

UtxoScannerService _makeScanner(ApiService api, {int retries = 2}) {
  return UtxoScannerService(
    api: api,
    retries: retries,
    // Use a 1ms backoff so retry tests don't take real time.
    initialBackoff: const Duration(milliseconds: 1),
  );
}

/// Builds a minimal Transaction stub. Scanner only cares about the list
/// length, not the contents.
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
  required int vout,
  required int value,
  int confirmations = 1,
}) =>
    UTXO(
      address: address,
      txid: txid,
      vout: vout,
      value: BigInt.from(value),
      confirmations: confirmations,
      scriptPubKey: '',
    );

/// Registers default "empty" stubs and then overrides only the addresses
/// that should have activity. Every call path used by the scanner is
/// covered so Mockito's strict mode doesn't explode.
void _stubDefaults(
  MockApiService api, {
  Map<String, List<Transaction>> transactions = const {},
  Map<String, List<UTXO>> utxos = const {},
}) {
  when(api.getAddressTransactions(any)).thenAnswer((invocation) async {
    final address = invocation.positionalArguments[0] as String;
    return transactions[address] ?? <Transaction>[];
  });
  when(api.getAddressUtxos(any)).thenAnswer((invocation) async {
    final address = invocation.positionalArguments[0] as String;
    return utxos[address] ?? <UTXO>[];
  });
}

@GenerateMocks([ApiService])
void main() {
  group('UtxoScannerService — gap-limit stopping', () {
    test('stops after exactly gapLimit addresses per chain when none are used',
        () async {
      final api = MockApiService();
      _stubDefaults(api);
      final hd = _makeHd();
      final scanner = _makeScanner(api);

      final result = await scanner.scan(hd: hd, gapLimit: 20);

      expect(result.lastUsedReceivingIndex, isNull);
      expect(result.lastUsedChangeIndex, isNull);
      expect(result.receivingActivity.length, 20);
      expect(result.changeActivity.length, 20);
      expect(result.addressesScanned, 40);
      expect(result.allUtxos, isEmpty);
      expect(result.totalBalance, BigInt.zero);
    });

    test(
        'keeps scanning past a used index and stops gapLimit addresses after '
        'the last one with history', () async {
      final api = MockApiService();
      final hd = _makeHd();
      // Place history on receiving index 3.
      final usedAddr = hd.deriveReceivingAddress(3);
      _stubDefaults(api, transactions: {
        usedAddr: [_tx('tx-3')],
      });
      final scanner = _makeScanner(api);

      final result = await scanner.scan(hd: hd, gapLimit: 5);

      expect(result.lastUsedReceivingIndex, 3);
      // Receiving scanned indices 0..3 (used) + 5 more unused (4..8) = 9 total.
      expect(result.receivingActivity.length, 9);
      expect(
        result.receivingActivity.keys.toList()..sort(),
        [0, 1, 2, 3, 4, 5, 6, 7, 8],
      );
      expect(result.usedReceivingIndices, [3]);
    });

    test('receiving and change chains are tracked independently', () async {
      final api = MockApiService();
      final hd = _makeHd();
      final receiveAddr = hd.deriveReceivingAddress(2);
      final changeAddr = hd.deriveChangeAddress(4);
      _stubDefaults(api, transactions: {
        receiveAddr: [_tx('r2')],
        changeAddr: [_tx('c4')],
      });
      final scanner = _makeScanner(api);

      final result = await scanner.scan(hd: hd, gapLimit: 5);

      expect(result.lastUsedReceivingIndex, 2);
      expect(result.lastUsedChangeIndex, 4);

      // At receiving index 2 the record must show history; at change
      // index 2 there must be no history — same index, different chain.
      expect(result.receivingActivity[2]!.hasHistory, isTrue);
      expect(result.changeActivity[2]!.hasHistory, isFalse);

      // Used sets are disjoint.
      expect(result.usedReceivingIndices, [2]);
      expect(result.usedChangeIndices, [4]);
    });

    test('respects a custom gap limit of 3', () async {
      final api = MockApiService();
      _stubDefaults(api);
      final hd = _makeHd();
      final scanner = _makeScanner(api);

      final result = await scanner.scan(hd: hd, gapLimit: 3);

      expect(result.receivingActivity.length, 3);
      expect(result.changeActivity.length, 3);
    });

    test('rejects non-positive gapLimit', () async {
      final api = MockApiService();
      _stubDefaults(api);
      final hd = _makeHd();
      final scanner = _makeScanner(api);

      expect(
        () => scanner.scan(hd: hd, gapLimit: 0),
        throwsArgumentError,
      );
      expect(
        () => scanner.scan(hd: hd, gapLimit: -1),
        throwsArgumentError,
      );
    });
  });

  group('UtxoScannerService — address classification', () {
    test('an address with tx history but zero UTXOs still counts as used',
        () async {
      final api = MockApiService();
      final hd = _makeHd();
      final fullySpentAddr = hd.deriveReceivingAddress(1);
      _stubDefaults(api, transactions: {
        // History exists…
        fullySpentAddr: [_tx('spent-1'), _tx('spent-2')],
      }, utxos: const {
        // …but no UTXOs (fully spent).
      });
      final scanner = _makeScanner(api);

      final result = await scanner.scan(hd: hd, gapLimit: 5);

      expect(result.lastUsedReceivingIndex, 1,
          reason: 'history alone makes it used');
      expect(result.receivingActivity[1]!.hasHistory, isTrue);
      expect(result.receivingActivity[1]!.txCount, 2);
      expect(result.receivingActivity[1]!.utxos, isEmpty);
      expect(result.receivingActivity[1]!.balance, BigInt.zero);
      expect(result.allUtxos, isEmpty);
    });

    test('surfaces confirmed and unconfirmed UTXOs separately', () async {
      final api = MockApiService();
      final hd = _makeHd();
      final confirmedAddr = hd.deriveReceivingAddress(0);
      final mempoolAddr = hd.deriveReceivingAddress(1);
      _stubDefaults(api, transactions: {
        confirmedAddr: [_tx('conf-1')],
        mempoolAddr: [_tx('unconf-1')],
      }, utxos: {
        confirmedAddr: [
          _utxo(
              address: confirmedAddr,
              txid: 'conf-1',
              vout: 0,
              value: 100000,
              confirmations: 6),
        ],
        mempoolAddr: [
          _utxo(
              address: mempoolAddr,
              txid: 'unconf-1',
              vout: 0,
              value: 50000,
              confirmations: 0),
        ],
      });
      final scanner = _makeScanner(api);

      final result = await scanner.scan(hd: hd, gapLimit: 5);

      expect(result.confirmedUtxos.map((u) => u.txid), ['conf-1']);
      expect(result.unconfirmedUtxos.map((u) => u.txid), ['unconf-1']);
      expect(result.totalBalance, BigInt.from(150000));
    });

    test('UTXOs without any cached tx history still mark the address used',
        () async {
      final api = MockApiService();
      final hd = _makeHd();
      final addr = hd.deriveReceivingAddress(1);
      _stubDefaults(api, utxos: {
        addr: [
          _utxo(address: addr, txid: 'u', vout: 0, value: 777),
        ],
      });
      final scanner = _makeScanner(api);

      final result = await scanner.scan(hd: hd, gapLimit: 3);

      expect(result.lastUsedReceivingIndex, 1);
      expect(result.receivingActivity[1]!.hasHistory, isTrue);
    });
  });

  group('UtxoScannerService — error handling', () {
    test('recovers from a transient failure via retry', () async {
      final api = MockApiService();
      final hd = _makeHd();
      final addr = hd.deriveReceivingAddress(0);

      // UTXO lookups always return empty.
      when(api.getAddressUtxos(any)).thenAnswer((_) async => <UTXO>[]);
      // First call for addr throws; second succeeds.
      var calls = 0;
      when(api.getAddressTransactions(any)).thenAnswer((invocation) async {
        final a = invocation.positionalArguments[0] as String;
        if (a == addr) {
          calls++;
          if (calls == 1) {
            throw ApiException('transient', 503);
          }
        }
        return <Transaction>[];
      });

      final scanner = _makeScanner(api);
      final result = await scanner.scan(hd: hd, gapLimit: 3);

      expect(calls, greaterThanOrEqualTo(2),
          reason: 'scanner must retry after the first failure');
      expect(result.receivingActivity.length, 3);
    });

    test(
        'aborts the scan with UtxoScannerException when an address fails '
        'past the retry budget', () async {
      final api = MockApiService();
      final hd = _makeHd();
      final addr = hd.deriveReceivingAddress(0);

      when(api.getAddressUtxos(any)).thenAnswer((_) async => <UTXO>[]);
      when(api.getAddressTransactions(any)).thenAnswer((invocation) async {
        final a = invocation.positionalArguments[0] as String;
        if (a == addr) {
          throw ApiException('down', 500);
        }
        return <Transaction>[];
      });

      final scanner = _makeScanner(api, retries: 2);

      await expectLater(
        scanner.scan(hd: hd, gapLimit: 3),
        throwsA(isA<UtxoScannerException>()
            .having((e) => e.address, 'address', addr)
            .having((e) => e.index, 'index', 0)
            .having((e) => e.isChange, 'isChange', false)),
      );
      // retries=2 means 3 total attempts.
      verify(api.getAddressTransactions(addr)).called(3);
    });
  });

  group('UtxoScannerService — progress callback', () {
    test('fires progress events for every address queried', () async {
      final api = MockApiService();
      _stubDefaults(api);
      final hd = _makeHd();
      final scanner = _makeScanner(api);

      final events = <ScanProgress>[];
      await scanner.scan(
        hd: hd,
        gapLimit: 3,
        onProgress: events.add,
      );

      // 3 receiving + 3 change = 6 events.
      expect(events.length, 6);
      expect(events.take(3).every((e) => e.isChange == false), isTrue);
      expect(events.skip(3).every((e) => e.isChange == true), isTrue);
      // Last event on each chain should report consecutiveUnused == gapLimit.
      expect(events[2].consecutiveUnused, 3);
      expect(events[5].consecutiveUnused, 3);
    });
  });
}
