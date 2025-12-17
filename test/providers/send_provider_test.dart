import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:bitnest/providers/send_provider.dart';
import 'package:bitnest/providers/wallet_provider.dart';
import 'package:bitnest/services/transaction_service.dart';
import 'package:bitnest/services/broadcast_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/models/account.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/models/fee_estimate.dart';
import 'package:bitnest/utils/networks.dart';
import 'send_provider_test.mocks.dart';

@GenerateMocks([
  TransactionService,
  BroadcastService,
  KeyService,
  WalletProvider,
])
void main() {
  late MockTransactionService mockTransactionService;
  late MockBroadcastService mockBroadcastService;
  late MockKeyService mockKeyService;
  late MockWalletProvider mockWalletProvider;
  late SendProvider sendProvider;

  setUp(() {
    mockTransactionService = MockTransactionService();
    mockBroadcastService = MockBroadcastService();
    mockKeyService = MockKeyService();
    mockWalletProvider = MockWalletProvider();
    sendProvider = SendProvider(
      transactionService: mockTransactionService,
      broadcastService: mockBroadcastService,
      keyService: mockKeyService,
      walletProvider: mockWalletProvider,
    );
  });

  group('SendProvider', () {
    final testAccount = Account(
      walletId: 'wallet1',
      label: 'Test Account',
      derivationPath: "m/84'/0'/0'",
      accountIndex: 0,
      xpub: 'xpub_test',
      network: BitcoinNetwork.mainnet,
    );

    final testUtxo = UTXO(
      txid: 'test_txid',
      vout: 0,
      address: 'bc1qtest',
      value: BigInt.from(100000),
      confirmations: 6,
      scriptPubKey: '0014...',
    );

    test('selects account', () {
      sendProvider.selectAccount(testAccount);
      expect(sendProvider.selectedAccount, testAccount);
    });

    test('sets recipient address', () {
      sendProvider.setRecipientAddress('bc1qrecipient');
      expect(sendProvider.recipientAddress, 'bc1qrecipient');
    });

    test('sets amount', () {
      sendProvider.setAmount(BigInt.from(50000));
      expect(sendProvider.amount, BigInt.from(50000));
    });

    test('sets fee preset', () async {
      when(mockTransactionService.getFeeEstimateForPreset(FeePreset.normal))
          .thenAnswer(
              (_) async => FeeEstimate(satPerVByte: 10, estimatedBlocks: 3));

      await sendProvider.setFeePreset(FeePreset.normal);

      expect(sendProvider.selectedFeePreset, FeePreset.normal);
      expect(sendProvider.currentFeeEstimate?.satPerVByte, 10);
    });

    test('sets manual fee rate', () {
      sendProvider.setManualFeeRate(15);
      expect(sendProvider.manualFeeRate, 15);
      expect(sendProvider.currentFeeEstimate?.satPerVByte, 15);
    });

    test('toggles UTXO selection', () {
      sendProvider.toggleUtxo(testUtxo);
      expect(sendProvider.selectedUtxos, contains(testUtxo));

      sendProvider.toggleUtxo(testUtxo);
      expect(sendProvider.selectedUtxos, isNot(contains(testUtxo)));
    });

    test('selects all UTXOs', () {
      when(mockWalletProvider.getAccountUtxos(testAccount.id))
          .thenReturn([testUtxo, testUtxo]);

      sendProvider.selectAccount(testAccount);
      sendProvider.selectAllUtxos();

      expect(sendProvider.selectedUtxos.length, 2);
    });

    test('calculates estimated fee', () {
      sendProvider.selectAccount(testAccount);
      sendProvider.setAmount(BigInt.from(50000));
      sendProvider.toggleUtxo(testUtxo);
      sendProvider.setManualFeeRate(10);

      final fee = sendProvider.calculateEstimatedFee();
      expect(fee, greaterThan(BigInt.zero));
    });

    test('calculates change', () {
      sendProvider.selectAccount(testAccount);
      sendProvider.setAmount(BigInt.from(50000));
      sendProvider.toggleUtxo(testUtxo);
      sendProvider.setManualFeeRate(10);

      final change = sendProvider.calculateChange();
      expect(change, greaterThanOrEqualTo(BigInt.zero));
    });

    test('validates transaction - missing account', () {
      final error = sendProvider.validateTransaction();
      expect(error, 'Please select an account');
    });

    test('validates transaction - missing address', () {
      sendProvider.selectAccount(testAccount);
      final error = sendProvider.validateTransaction();
      expect(error, 'Please enter a recipient address');
    });

    test('validates transaction - missing amount', () {
      sendProvider.selectAccount(testAccount);
      sendProvider.setRecipientAddress('bc1qrecipient');
      final error = sendProvider.validateTransaction();
      expect(error, 'Please enter a valid amount');
    });

    test('validates transaction - no UTXOs selected', () {
      sendProvider.selectAccount(testAccount);
      sendProvider.setRecipientAddress('bc1qrecipient');
      sendProvider.setAmount(BigInt.from(50000));
      final error = sendProvider.validateTransaction();
      expect(error, 'Please select at least one UTXO');
    });

    test('validates transaction - insufficient funds', () {
      sendProvider.selectAccount(testAccount);
      sendProvider.setRecipientAddress('bc1qrecipient');
      sendProvider.setAmount(BigInt.from(200000)); // More than UTXO value
      sendProvider.toggleUtxo(testUtxo);
      sendProvider.setManualFeeRate(10);

      final error = sendProvider.validateTransaction();
      expect(error, contains('Insufficient funds'));
    });

    test('validates transaction - success', () {
      sendProvider.selectAccount(testAccount);
      sendProvider.setRecipientAddress('bc1qrecipient');
      sendProvider.setAmount(BigInt.from(50000));
      sendProvider.toggleUtxo(testUtxo);
      sendProvider.setManualFeeRate(10);

      final error = sendProvider.validateTransaction();
      expect(error, isNull);
    });

    test('resets form', () {
      sendProvider.selectAccount(testAccount);
      sendProvider.setRecipientAddress('bc1qrecipient');
      sendProvider.setAmount(BigInt.from(50000));
      sendProvider.toggleUtxo(testUtxo);

      sendProvider.reset();

      expect(sendProvider.selectedUtxos, isEmpty);
      expect(sendProvider.recipientAddress, isNull);
      expect(sendProvider.amount, isNull);
    });
  });
}
