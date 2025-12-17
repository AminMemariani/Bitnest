import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:bitnest/providers/wallet_provider.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/models/wallet.dart';
import 'package:bitnest/models/account.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/utils/networks.dart';
import 'dart:typed_data';

import 'wallet_provider_test.mocks.dart';

@GenerateMocks([KeyService])
void main() {
  group('WalletProvider', () {
    late MockKeyService mockKeyService;
    late MockApiService mockApiService;
    late WalletProvider provider;

    setUp(() {
      mockKeyService = MockKeyService();
      mockApiService = MockApiService();
      provider = WalletProvider(
        keyService: mockKeyService,
        apiService: mockApiService,
      );
    });

    group('Wallet Creation', () {
      test('creates a new wallet with mnemonic', () async {
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));
        const masterXpub = 'xpub6C...';
        const masterXprv = 'xprv...';

        when(mockKeyService.generateMnemonic(wordCount: 24))
            .thenReturn(mnemonic);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(seed, BitcoinNetwork.mainnet))
            .thenReturn(masterXpub);
        when(mockKeyService.deriveMasterXprv(seed, BitcoinNetwork.mainnet))
            .thenReturn(masterXprv);
        when(mockKeyService.deriveAccountXpub(
          any,
          any,
          any,
          accountIndex: 0,
        )).thenReturn('account_xpub');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);

        final wallet = await provider.createWallet(
          label: 'Test Wallet',
          network: BitcoinNetwork.mainnet,
        );

        expect(wallet, isNotNull);
        expect(wallet.label, 'Test Wallet');
        expect(wallet.network, BitcoinNetwork.mainnet);
        expect(wallet.xpub, masterXpub);
        expect(provider.wallets.length, 1);

        // Select wallet to access accounts
        provider.selectWallet(wallet.id);
        expect(provider.currentAccounts.length, 1);
      });

      test('imports wallet from mnemonic', () async {
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));
        const masterXpub = 'xpub6C...';
        const masterXprv = 'xprv...';

        when(mockKeyService.validateMnemonic(mnemonic)).thenReturn(true);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(seed, BitcoinNetwork.mainnet))
            .thenReturn(masterXpub);
        when(mockKeyService.deriveMasterXprv(seed, BitcoinNetwork.mainnet))
            .thenReturn(masterXprv);
        when(mockKeyService.deriveAccountXpub(
          any,
          any,
          any,
          accountIndex: 0,
        )).thenReturn('account_xpub');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);

        final wallet = await provider.importWallet(
          mnemonic: mnemonic,
          label: 'Imported Wallet',
          network: BitcoinNetwork.mainnet,
        );

        expect(wallet, isNotNull);
        expect(wallet.label, 'Imported Wallet');
        expect(provider.wallets.length, 1);
      });

      test('imports watch-only wallet from xpub', () async {
        const xpub = 'xpub6C...';

        when(mockKeyService.deriveXpub(xpub, any)).thenReturn('account_xpub');

        final wallet = await provider.importWatchOnlyWallet(
          xpub: xpub,
          label: 'Watch-Only Wallet',
          network: BitcoinNetwork.mainnet,
        );

        expect(wallet, isNotNull);
        expect(wallet.label, 'Watch-Only Wallet');
        expect(wallet.xprv, isNull);
        expect(provider.wallets.length, 1);
      });

      test('throws error for invalid mnemonic', () async {
        const invalidMnemonic = 'invalid mnemonic';

        when(mockKeyService.validateMnemonic(invalidMnemonic))
            .thenReturn(false);

        expect(
          () => provider.importWallet(
            mnemonic: invalidMnemonic,
            label: 'Invalid',
            network: BitcoinNetwork.mainnet,
          ),
          throwsArgumentError,
        );
      });
    });

    group('Wallet Management', () {
      test('removes wallet', () async {
        // Create a wallet first
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));

        when(mockKeyService.generateMnemonic(wordCount: 24))
            .thenReturn(mnemonic);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(any, any)).thenReturn('xpub');
        when(mockKeyService.deriveMasterXprv(any, any)).thenReturn('xprv');
        when(mockKeyService.deriveAccountXpub(any, any, any, accountIndex: 0))
            .thenReturn('account_xpub');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);
        when(mockKeyService.deleteWalletData(any)).thenAnswer((_) async => {});

        final wallet = await provider.createWallet(
          label: 'Test Wallet',
          network: BitcoinNetwork.mainnet,
        );

        expect(provider.wallets.length, 1);

        await provider.removeWallet(wallet.id);

        expect(provider.wallets.length, 0);
        verify(mockKeyService.deleteWalletData(wallet.id)).called(1);
      });

      test('selects wallet', () async {
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));

        when(mockKeyService.generateMnemonic(wordCount: 24))
            .thenReturn(mnemonic);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(any, any)).thenReturn('xpub1');
        when(mockKeyService.deriveMasterXprv(any, any)).thenReturn('xprv1');
        when(mockKeyService.deriveAccountXpub(any, any, any, accountIndex: 0))
            .thenReturn('account_xpub');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);

        final wallet1 = await provider.createWallet(
          label: 'Wallet 1',
          network: BitcoinNetwork.mainnet,
        );

        when(mockKeyService.deriveMasterXpub(any, any)).thenReturn('xpub2');
        when(mockKeyService.deriveMasterXprv(any, any)).thenReturn('xprv2');

        await provider.createWallet(
          label: 'Wallet 2',
          network: BitcoinNetwork.mainnet,
        );

        expect(provider.currentWallet, isNull);

        provider.selectWallet(wallet1.id);

        expect(provider.currentWallet?.id, wallet1.id);
      });
    });

    group('Account Management', () {
      late Wallet wallet;

      setUp(() async {
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));

        when(mockKeyService.generateMnemonic(wordCount: 24))
            .thenReturn(mnemonic);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(any, any)).thenReturn('xpub');
        when(mockKeyService.deriveMasterXprv(any, any)).thenReturn('xprv');
        when(mockKeyService.deriveAccountXpub(any, any, any, accountIndex: 0))
            .thenReturn('account_xpub_0');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);

        wallet = await provider.createWallet(
          label: 'Test Wallet',
          network: BitcoinNetwork.mainnet,
        );
        provider.selectWallet(wallet.id);
      });

      test('creates new account', () async {
        final seed = Uint8List.fromList(List.generate(64, (i) => i));

        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);
        when(mockKeyService.deriveAccountXpub(
          any,
          any,
          any,
          accountIndex: 1,
        )).thenReturn('account_xpub_1');

        final account = await provider.createAccount(label: 'Savings Account');

        expect(account, isNotNull);
        expect(account.label, 'Savings Account');
        expect(account.accountIndex, 1);
        expect(provider.currentAccounts.length, 2);
      });

      test('throws error when no wallet selected', () {
        provider = WalletProvider(
          keyService: mockKeyService,
          apiService: mockApiService,
        );

        expect(
          () => provider.createAccount(label: 'Account'),
          throwsStateError,
        );
      });
    });

    group('Address Management', () {
      late Wallet wallet;
      late Account account;

      setUp(() async {
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));

        when(mockKeyService.generateMnemonic(wordCount: 24))
            .thenReturn(mnemonic);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(any, any)).thenReturn('xpub');
        when(mockKeyService.deriveMasterXprv(any, any)).thenReturn('xprv');
        when(mockKeyService.deriveAccountXpub(any, any, any, accountIndex: 0))
            .thenReturn('account_xpub');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);

        wallet = await provider.createWallet(
          label: 'Test Wallet',
          network: BitcoinNetwork.mainnet,
        );
        provider.selectWallet(wallet.id);
        account = provider.currentAccounts.first;
      });

      test('derives next receive address', () async {
        when(mockKeyService.deriveAddress(
          'account_xpub',
          0,
          any,
          any,
          change: false,
        )).thenReturn('bc1qtest123');

        final address = await provider.deriveNextReceiveAddress(account.id);

        expect(address, 'bc1qtest123');
        expect(provider.listAddresses(account.id).length, 1);
        expect(provider.listAddresses(account.id).first, 'bc1qtest123');
      });

      test('lists addresses for account', () async {
        when(mockKeyService.deriveAddress(
          'account_xpub',
          any,
          any,
          any,
          change: false,
        )).thenReturn('bc1qtest');

        await provider.deriveNextReceiveAddress(account.id);
        await provider.deriveNextReceiveAddress(account.id);

        final addresses = provider.listAddresses(account.id);
        expect(addresses.length, 2);
      });
    });

    group('UTXO and Balance', () {
      late Wallet wallet;
      late Account account;

      setUp(() async {
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));

        when(mockKeyService.generateMnemonic(wordCount: 24))
            .thenReturn(mnemonic);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(any, any)).thenReturn('xpub');
        when(mockKeyService.deriveMasterXprv(any, any)).thenReturn('xprv');
        when(mockKeyService.deriveAccountXpub(any, any, any, accountIndex: 0))
            .thenReturn('account_xpub');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);
        when(mockKeyService.deriveAddress(any, any, any, any, change: false))
            .thenReturn('bc1qtest123');

        wallet = await provider.createWallet(
          label: 'Test Wallet',
          network: BitcoinNetwork.mainnet,
        );
        provider.selectWallet(wallet.id);
        account = provider.currentAccounts.first;
        await provider.deriveNextReceiveAddress(account.id);
      });

      test('fetches UTXOs for account', () async {
        final mockUtxos = [
          UTXO(
            txid: 'txid1',
            vout: 0,
            address: 'bc1qtest123',
            value: BigInt.from(100000),
            confirmations: 6,
            blockHeight: 850000,
            scriptPubKey: '0014...',
          ),
          UTXO(
            txid: 'txid2',
            vout: 1,
            address: 'bc1qtest123',
            value: BigInt.from(50000),
            confirmations: 3,
            blockHeight: 850010,
            scriptPubKey: '0014...',
          ),
        ];

        mockApiService.setAddressUtxos('bc1qtest123', mockUtxos);

        await provider.fetchAccountUtxos(account.id);

        final utxos = provider.getAccountUtxos(account.id);
        expect(utxos.length, 2);
        expect(utxos[0].txid, 'txid1');
        expect(utxos[1].txid, 'txid2');
      });

      test('computes balance from UTXOs', () async {
        final mockUtxos = [
          UTXO(
            txid: 'txid1',
            vout: 0,
            address: 'bc1qtest123',
            value: BigInt.from(100000),
            confirmations: 6,
            scriptPubKey: '0014...',
          ),
          UTXO(
            txid: 'txid2',
            vout: 1,
            address: 'bc1qtest123',
            value: BigInt.from(50000),
            confirmations: 3,
            scriptPubKey: '0014...',
          ),
        ];

        mockApiService.setAddressUtxos('bc1qtest123', mockUtxos);

        await provider.fetchAccountUtxos(account.id);

        final balance = provider.getAccountBalance(account.id);
        expect(balance, BigInt.from(150000));
      });

      test('syncs all accounts', () async {
        final mockUtxos = [
          UTXO(
            txid: 'txid1',
            vout: 0,
            address: 'bc1qtest123',
            value: BigInt.from(100000),
            confirmations: 6,
            scriptPubKey: '0014...',
          ),
        ];

        mockApiService.setAddressUtxos('bc1qtest123', mockUtxos);

        await provider.syncAllAccounts();

        final balance = provider.getAccountBalance(account.id);
        expect(balance, BigInt.from(100000));
      });

      test('tracks sync status', () async {
        final mockUtxos = [
          UTXO(
            txid: 'txid1',
            vout: 0,
            address: 'bc1qtest123',
            value: BigInt.from(100000),
            confirmations: 6,
            scriptPubKey: '0014...',
          ),
        ];

        mockApiService.setAddressUtxos('bc1qtest123', mockUtxos);

        expect(provider.isAccountSyncing(account.id), isFalse);

        final future = provider.fetchAccountUtxos(account.id);
        // Check sync status is true during fetch
        expect(provider.isAccountSyncing(account.id), isTrue);

        await future;
        expect(provider.isAccountSyncing(account.id), isFalse);
      });
    });

    group('Total Balance', () {
      test('computes total balance across all accounts', () async {
        const mnemonic =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';
        final seed = Uint8List.fromList(List.generate(64, (i) => i));

        when(mockKeyService.generateMnemonic(wordCount: 24))
            .thenReturn(mnemonic);
        when(mockKeyService.mnemonicToSeed(mnemonic)).thenReturn(seed);
        when(mockKeyService.deriveMasterXpub(any, any)).thenReturn('xpub');
        when(mockKeyService.deriveMasterXprv(any, any)).thenReturn('xprv');
        when(mockKeyService.deriveAccountXpub(any, any, any, accountIndex: 0))
            .thenReturn('account_xpub_0');
        when(mockKeyService.deriveAccountXpub(any, any, any, accountIndex: 1))
            .thenReturn('account_xpub_1');
        when(mockKeyService.storeMnemonic(any, any))
            .thenAnswer((_) async => {});
        when(mockKeyService.storeSeed(any, any)).thenAnswer((_) async => {});
        when(mockKeyService.retrieveSeed(any)).thenAnswer((_) async => seed);
        // Return different addresses for each account
        when(mockKeyService.deriveAddress('account_xpub_0', 0, any, any,
                change: false))
            .thenReturn('bc1qaccount1');
        when(mockKeyService.deriveAddress('account_xpub_1', 0, any, any,
                change: false))
            .thenReturn('bc1qaccount2');

        final wallet = await provider.createWallet(
          label: 'Test Wallet',
          network: BitcoinNetwork.mainnet,
        );
        provider.selectWallet(wallet.id);

        final account1 = provider.currentAccounts.first;
        await provider.deriveNextReceiveAddress(account1.id);

        await provider.createAccount(label: 'Account 2');
        final account2 = provider.currentAccounts.last;
        await provider.deriveNextReceiveAddress(account2.id);

        final utxos1 = [
          UTXO(
            txid: 'txid1',
            vout: 0,
            address: 'bc1qaccount1',
            value: BigInt.from(100000),
            confirmations: 6,
            scriptPubKey: '0014...',
          ),
        ];
        final utxos2 = [
          UTXO(
            txid: 'txid2',
            vout: 0,
            address: 'bc1qaccount2',
            value: BigInt.from(200000),
            confirmations: 6,
            scriptPubKey: '0014...',
          ),
        ];

        mockApiService.setAddressUtxos('bc1qaccount1', utxos1);
        mockApiService.setAddressUtxos('bc1qaccount2', utxos2);

        await provider.fetchAccountUtxos(account1.id);
        await provider.fetchAccountUtxos(account2.id);

        final totalBalance = provider.totalBalance;
        expect(totalBalance, BigInt.from(300000));
      });
    });
  });
}
