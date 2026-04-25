import 'dart:typed_data';

import 'package:bitnest/models/pending_transaction.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/providers/wallet_provider.dart';
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/services/transaction_journal.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallet_provider_test.mocks.dart';

/// Verifies the audit's F-3 fix: WalletProvider.getAccountUtxos must
/// hide UTXOs that are already committed to a `signed` or `broadcast`
/// transaction in the journal, so coin selection cannot double-spend.

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

UTXO _utxo({
  required String txid,
  required int vout,
  required int sats,
}) =>
    UTXO(
      txid: txid,
      vout: vout,
      address: 'bc1qfake$txid',
      value: BigInt.from(sats),
      confirmations: 6,
      scriptPubKey: '0014${'00' * 20}',
    );

PendingTransaction _entry({
  required String txid,
  required String accountId,
  required List<String> outpoints,
  required PendingTxState state,
}) =>
    PendingTransaction(
      txid: txid,
      signedHex: 'deadbeef',
      accountId: accountId,
      changeIndexUsed: 0,
      spentOutpoints: outpoints,
      state: state,
      createdAt: DateTime.utc(2025, 1, 1),
    );

MockKeyService _stubbedKeyService(Uint8List seed) {
  final k = MockKeyService();
  when(k.generateMnemonic(wordCount: 24)).thenReturn(_mnemonic);
  when(k.mnemonicToSeed(any)).thenReturn(seed);
  when(k.deriveMasterXpub(any, any)).thenReturn('xpub');
  when(k.deriveMasterXprv(any, any)).thenReturn('xprv');
  when(k.deriveAccountXpub(any, any, any, accountIndex: 0))
      .thenReturn('account_xpub');
  when(k.storeMnemonic(any, any)).thenAnswer((_) async => {});
  when(k.storeSeed(any, any)).thenAnswer((_) async => {});
  when(k.retrieveSeed(any)).thenAnswer((_) async => seed);
  return k;
}

Future<
    ({
      WalletProvider provider,
      String accountId,
      TransactionJournal journal
    })> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final seed = Uint8List.fromList(List.generate(64, (i) => i));

  final journal = await TransactionJournal.load(prefs: prefs);
  final provider = WalletProvider(
    keyService: _stubbedKeyService(seed),
    apiService: MockApiService(),
    journal: journal,
  );

  final wallet = await provider.createWallet(
    label: 'Test Wallet',
    network: BitcoinNetwork.mainnet,
  );
  provider.selectWallet(wallet.id);

  return (
    provider: provider,
    accountId: provider.currentAccounts.first.id,
    journal: journal,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalletProvider.getAccountUtxos — pending-spent filter', () {
    test(
        'a UTXO listed in a signed-state journal entry is filtered out of '
        'the result', () async {
      final s = await _setup();

      s.provider.debugSeedAccountUtxos(s.accountId, [
        _utxo(txid: 'tx-A', vout: 0, sats: 10000),
        _utxo(txid: 'tx-A', vout: 1, sats: 20000),
        _utxo(txid: 'tx-B', vout: 1, sats: 30000),
        _utxo(txid: 'tx-C', vout: 0, sats: 40000),
      ]);
      expect(s.provider.getAccountUtxos(s.accountId).length, 4);

      await s.journal.upsert(_entry(
        txid: 'pending-1',
        accountId: s.accountId,
        outpoints: ['tx-A:0', 'tx-B:1'],
        state: PendingTxState.signed,
      ));

      final filtered = s.provider.getAccountUtxos(s.accountId);
      expect(filtered.map((u) => '${u.txid}:${u.vout}').toSet(),
          {'tx-A:1', 'tx-C:0'},
          reason: 'tx-A:0 and tx-B:1 are in flight; coin selection must '
              'not see them');
      expect(s.provider.getAccountUtxosIncludingPending(s.accountId).length, 4,
          reason: 'the unfiltered view stays available for diagnostics');
    });

    test('a UTXO listed in a broadcast-state journal entry is also filtered',
        () async {
      final s = await _setup();
      s.provider.debugSeedAccountUtxos(s.accountId, [
        _utxo(txid: 'tx-X', vout: 0, sats: 50000),
      ]);
      await s.journal.upsert(_entry(
        txid: 'broadcast-tx',
        accountId: s.accountId,
        outpoints: ['tx-X:0'],
        state: PendingTxState.broadcast,
      ));

      expect(s.provider.getAccountUtxos(s.accountId), isEmpty);
    });

    test(
        'a UTXO listed in a FAILED journal entry is NOT filtered '
        '(retryable input is free again)', () async {
      final s = await _setup();
      s.provider.debugSeedAccountUtxos(s.accountId, [
        _utxo(txid: 'tx-Y', vout: 0, sats: 60000),
      ]);
      await s.journal.upsert(_entry(
        txid: 'failed-tx',
        accountId: s.accountId,
        outpoints: ['tx-Y:0'],
        state: PendingTxState.failed,
      ));

      expect(s.provider.getAccountUtxos(s.accountId).length, 1,
          reason: 'a failed broadcast releases the input back to the pool');
    });

    test('filtering only applies to the matching account', () async {
      final s = await _setup();
      s.provider.debugSeedAccountUtxos(s.accountId, [
        _utxo(txid: 'tx-Z', vout: 0, sats: 70000),
      ]);
      await s.journal.upsert(_entry(
        txid: 'unrelated-tx',
        accountId: 'someone-elses-account',
        outpoints: ['tx-Z:0'],
        state: PendingTxState.signed,
      ));

      expect(s.provider.getAccountUtxos(s.accountId).length, 1,
          reason: 'pending journal entries scope by accountId');
    });

    test('with no journal injected, filtering is a no-op (back-compat)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final seed = Uint8List.fromList(List.generate(64, (i) => i));

      final provider = WalletProvider(
        keyService: _stubbedKeyService(seed),
        apiService: MockApiService(),
        // intentionally no journal
      );
      final wallet = await provider.createWallet(
        label: 'No-journal Wallet',
        network: BitcoinNetwork.mainnet,
      );
      provider.selectWallet(wallet.id);
      final accountId = provider.currentAccounts.first.id;

      provider.debugSeedAccountUtxos(accountId, [
        _utxo(txid: 'tx-N', vout: 0, sats: 80000),
      ]);
      expect(provider.getAccountUtxos(accountId).length, 1);
      expect(provider.transactionJournal, isNull);
    });
  });
}
