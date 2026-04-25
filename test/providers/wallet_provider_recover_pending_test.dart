import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/models/pending_transaction.dart';
import 'package:bitnest/providers/wallet_provider.dart';
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/services/transaction_journal.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'send_provider_test.mocks.dart' show MockBroadcastService;
import 'wallet_provider_test.mocks.dart';

/// Verifies the audit's F-2 fix: WalletProvider.recoverPendingTransactions
/// re-broadcasts any signed-but-not-broadcast tx left behind by a
/// previous session. This is the boot-time crash-recovery hook.

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

MockKeyService _stubbedKeyService(Uint8List seed) {
  final k = MockKeyService();
  when(k.generateMnemonic(wordCount: 24)).thenReturn(_mnemonic);
  when(k.validateMnemonic(any)).thenReturn(true);
  when(k.mnemonicToSeed(any, passphrase: anyNamed('passphrase')))
      .thenReturn(seed);
  when(k.mnemonicToSeed(any)).thenReturn(seed);
  when(k.deriveMasterXpub(any, any)).thenReturn('xpub');
  when(k.deriveMasterXprv(any, any)).thenReturn('xprv');
  when(k.deriveAccountXpub(any, any, any, accountIndex: 0))
      .thenReturn('account_xpub');
  when(k.deriveXpub(any, any)).thenReturn('account_xpub');
  when(k.storeMnemonic(any, any)).thenAnswer((_) async => {});
  when(k.storeSeed(any, any)).thenAnswer((_) async => {});
  when(k.retrieveSeed(any)).thenAnswer((_) async => seed);
  return k;
}

PendingTransaction _signedRecord({
  required String txid,
  required String accountId,
}) =>
    PendingTransaction(
      txid: txid,
      signedHex: 'deadbeef',
      accountId: accountId,
      changeIndexUsed: 0,
      spentOutpoints: const ['some-prev:0'],
      state: PendingTxState.signed,
      createdAt: DateTime.utc(2025, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalletProvider.recoverPendingTransactions', () {
    test(
        'on boot, signed-state journal records get re-broadcast and the '
        'pipeline marks them broadcast', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final seed = Uint8List.fromList(bip39.mnemonicToSeed(_mnemonic));

      final journal = await TransactionJournal.load(prefs: prefs);
      final provider = WalletProvider(
        keyService: _stubbedKeyService(seed),
        apiService: MockApiService(),
        journal: journal,
      );

      // Bring up a wallet so there's an account for recovery to walk.
      final wallet = await provider.createWallet(
        label: 'Recovery Test',
        network: BitcoinNetwork.mainnet,
      );
      provider.selectWallet(wallet.id);
      final accountId = provider.currentAccounts.first.id;

      // Plant a signed-but-not-broadcast record, simulating a prior
      // session that crashed mid-pipeline.
      final pendingTxid = 'a' * 64;
      await journal.upsert(_signedRecord(
        txid: pendingTxid,
        accountId: accountId,
      ));

      // Network is healthy now.
      final broadcaster = MockBroadcastService();
      when(broadcaster.setNetwork(any)).thenReturn(null);
      when(broadcaster.broadcastTransaction(any))
          .thenAnswer((_) async => 'mock-network-id');

      final outcomes = await provider.recoverPendingTransactions(
        broadcastService: broadcaster,
      );

      expect(outcomes, hasLength(1));
      expect(journal.get(pendingTxid)?.state, PendingTxState.broadcast);
      verify(broadcaster.broadcastTransaction(any)).called(1);
    });

    test(
        'a fresh install with no wallets and no journal entries is a clean '
        'no-op (no crashes, no broadcasts)', () async {
      SharedPreferences.setMockInitialValues({});
      final seed = Uint8List.fromList(bip39.mnemonicToSeed(_mnemonic));

      final provider = WalletProvider(
        keyService: _stubbedKeyService(seed),
        apiService: MockApiService(),
      );

      final broadcaster = MockBroadcastService();
      when(broadcaster.setNetwork(any)).thenReturn(null);
      when(broadcaster.broadcastTransaction(any))
          .thenAnswer((_) async => 'should-never-be-called');

      final outcomes = await provider.recoverPendingTransactions(
        broadcastService: broadcaster,
      );

      expect(outcomes, isEmpty);
      verifyNever(broadcaster.broadcastTransaction(any));
    });

    test('watch-only wallets are skipped — no seed available to sign with',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final seed = Uint8List.fromList(bip39.mnemonicToSeed(_mnemonic));

      final journal = await TransactionJournal.load(prefs: prefs);
      final provider = WalletProvider(
        keyService: _stubbedKeyService(seed),
        apiService: MockApiService(),
        journal: journal,
      );

      // Watch-only wallet (xprv == null is enforced internally by
      // importWatchOnlyWallet). The recovery sweep walks every wallet
      // and skips ones with no xprv before touching any HD service.
      await provider.importWatchOnlyWallet(
        xpub: 'xpub-watch-only',
        label: 'Watch-only',
        network: BitcoinNetwork.mainnet,
      );

      // Even if SOME journal record exists for SOME other account,
      // the watch-only sweep mustn't try to broadcast it.
      await journal.upsert(_signedRecord(
        txid: 'b' * 64,
        accountId: 'unrelated-account',
      ));

      final broadcaster = MockBroadcastService();
      when(broadcaster.setNetwork(any)).thenReturn(null);
      when(broadcaster.broadcastTransaction(any))
          .thenAnswer((_) async => 'should-never-be-called');

      final outcomes = await provider.recoverPendingTransactions(
        broadcastService: broadcaster,
      );

      expect(outcomes, isEmpty);
      verifyNever(broadcaster.broadcastTransaction(any));
    });
  });
}
