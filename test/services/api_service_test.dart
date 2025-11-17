import 'package:flutter_test/flutter_test.dart';
import 'package:bitnest/services/api_service.dart';
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/models/transaction.dart';

void main() {
  group('ApiService - Network Switching', () {
    test('initializes with mainnet by default', () {
      final service = MockApiService();
      expect(service.currentNetwork, BitcoinNetwork.mainnet);
      expect(service.baseUrl, 'https://blockstream.info/api');
    });

    test('initializes with specified network', () {
      final service = MockApiService(initialNetwork: BitcoinNetwork.testnet);
      expect(service.currentNetwork, BitcoinNetwork.testnet);
      expect(service.baseUrl, 'https://blockstream.info/testnet/api');
    });

    test('switches network and updates base URL', () {
      final service = MockApiService();
      expect(service.baseUrl, 'https://blockstream.info/api');

      service.setNetwork(BitcoinNetwork.testnet);
      expect(service.currentNetwork, BitcoinNetwork.testnet);
      expect(service.baseUrl, 'https://blockstream.info/testnet/api');

      service.setNetwork(BitcoinNetwork.mainnet);
      expect(service.currentNetwork, BitcoinNetwork.mainnet);
      expect(service.baseUrl, 'https://blockstream.info/api');
    });
  });

  group('MockApiService - Address Balance', () {
    late MockApiService service;

    setUp(() {
      service = MockApiService();
    });

    test('returns zero balance for unknown address', () async {
      final balance = await service.getAddressBalance('unknown_address');
      expect(balance, BigInt.zero);
    });

    test('returns set balance for address', () async {
      const address = 'bc1qtest123';
      final expectedBalance = BigInt.from(1000000); // 0.01 BTC

      service.setAddressBalance(address, expectedBalance);
      final balance = await service.getAddressBalance(address);

      expect(balance, expectedBalance);
    });
  });

  group('MockApiService - UTXOs', () {
    late MockApiService service;

    setUp(() {
      service = MockApiService();
    });

    test('returns empty list for unknown address', () async {
      final utxos = await service.getAddressUtxos('unknown_address');
      expect(utxos, isEmpty);
    });

    test('returns set UTXOs for address', () async {
      const address = 'bc1qtest123';
      final mockUtxos = [
        UTXO(
          txid: 'txid1',
          vout: 0,
          address: address,
          value: BigInt.from(500000),
          confirmations: 6,
          blockHeight: 850000,
          scriptPubKey: '0014...',
        ),
        UTXO(
          txid: 'txid2',
          vout: 1,
          address: address,
          value: BigInt.from(300000),
          confirmations: 3,
          blockHeight: 850010,
          scriptPubKey: '0014...',
        ),
      ];

      service.setAddressUtxos(address, mockUtxos);
      final utxos = await service.getAddressUtxos(address);

      expect(utxos.length, 2);
      expect(utxos[0].txid, 'txid1');
      expect(utxos[1].txid, 'txid2');
    });
  });

  group('MockApiService - Transactions', () {
    late MockApiService service;

    setUp(() {
      service = MockApiService();
    });

    test('returns empty list for unknown address', () async {
      final transactions = await service.getAddressTransactions(
        'unknown_address',
      );
      expect(transactions, isEmpty);
    });

    test('returns set transactions for address', () async {
      const address = 'bc1qtest123';
      final mockTransactions = [
        Transaction(
          txid: 'txid1',
          version: 1,
          locktime: 0,
          inputs: [],
          outputs: [
            TxOutput(
              index: 0,
              value: BigInt.from(1000000),
              scriptPubKey: '0014...',
              address: address,
            ),
          ],
          confirmations: 6,
          fee: BigInt.zero,
        ),
      ];

      service.setAddressTransactions(address, mockTransactions);
      final transactions = await service.getAddressTransactions(address);

      expect(transactions.length, 1);
      expect(transactions[0].txid, 'txid1');
    });

    test('returns transaction by txid', () async {
      const txid = 'test_txid_123';
      final mockTransaction = Transaction(
        txid: txid,
        version: 1,
        locktime: 0,
        inputs: [],
        outputs: [],
        confirmations: 6,
        fee: BigInt.from(1000),
      );

      service.setTransaction(txid, mockTransaction);
      final transaction = await service.getTransaction(txid);

      expect(transaction.txid, txid);
      expect(transaction.fee, BigInt.from(1000));
    });

    test('throws exception for unknown txid', () async {
      expect(
        () => service.getTransaction('unknown_txid'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('MockApiService - Fee Estimates', () {
    late MockApiService service;

    setUp(() {
      service = MockApiService();
    });

    test('returns default fee estimates when none set', () async {
      final estimates = await service.getFeeEstimates();

      expect(estimates, isNotEmpty);
      expect(estimates[6], 10); // Default for 6 blocks
    });

    test('returns custom fee estimates', () async {
      final customEstimates = {1: 50, 3: 20, 6: 10, 12: 5};

      service.setFeeEstimates(customEstimates);
      final estimates = await service.getFeeEstimates();

      expect(estimates, customEstimates);
    });

    test('returns fee estimate for target blocks', () async {
      service.setFeeEstimates({1: 50, 6: 10, 12: 5});

      final estimate = await service.getFeeEstimate(targetBlocks: 6);

      expect(estimate.satPerVByte, 10);
      expect(estimate.estimatedBlocks, 6);
    });

    test('returns closest fee estimate when exact match not found', () async {
      service.setFeeEstimates({1: 50, 3: 20, 12: 5});

      final estimate = await service.getFeeEstimate(targetBlocks: 6);

      // Should find closest (3 or 12)
      expect(estimate.satPerVByte, isNotNull);
    });
  });

  group('MockApiService - Transaction Broadcasting', () {
    late MockApiService service;

    setUp(() {
      service = MockApiService();
    });

    test('broadcasts transaction and returns mock txid', () async {
      const txHex = '0100000001...';
      final txid = await service.broadcastTransaction(txHex);

      expect(txid, isNotEmpty);
      expect(txid, contains('mock_txid_'));
    });
  });

  group('ApiService Integration - Network Switching', () {
    test('switching network changes all subsequent API calls', () {
      final service = MockApiService();

      // Set up data for mainnet address
      const mainnetAddress = 'bc1qmainnet123';
      service.setAddressBalance(mainnetAddress, BigInt.from(1000000));

      // Switch to testnet
      service.setNetwork(BitcoinNetwork.testnet);
      expect(service.baseUrl, 'https://blockstream.info/testnet/api');

      // Set up data for testnet address
      const testnetAddress = 'tb1qtestnet123';
      service.setAddressBalance(testnetAddress, BigInt.from(500000));

      // Switch back to mainnet
      service.setNetwork(BitcoinNetwork.mainnet);
      expect(service.baseUrl, 'https://blockstream.info/api');
    });
  });
}
