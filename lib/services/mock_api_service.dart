import '../utils/networks.dart';
import '../models/utxo.dart';
import '../models/transaction.dart';
import '../models/fee_estimate.dart';
import 'api_service.dart';

/// Mock implementation of ApiService for testing.
///
/// This mock service provides predictable responses for testing without
/// making actual network requests.
class MockApiService extends ApiService {
  final Map<String, BigInt> _balances = {};
  final Map<String, List<UTXO>> _utxos = {};
  final Map<String, List<Transaction>> _transactions = {};
  final Map<String, Transaction> _transactionMap = {};
  final Map<int, int> _feeEstimates = {};

  MockApiService({BitcoinNetwork? initialNetwork})
      : super(
          client: null,
          initialNetwork: initialNetwork ?? BitcoinNetwork.mainnet,
        );

  /// Sets a mock balance for an address.
  void setAddressBalance(String address, BigInt balance) {
    _balances[address] = balance;
  }

  /// Sets mock UTXOs for an address.
  void setAddressUtxos(String address, List<UTXO> utxos) {
    _utxos[address] = utxos;
  }

  /// Sets mock transactions for an address.
  void setAddressTransactions(String address, List<Transaction> transactions) {
    _transactions[address] = transactions;
  }

  /// Sets a mock transaction.
  void setTransaction(String txid, Transaction transaction) {
    _transactionMap[txid] = transaction;
  }

  /// Sets mock fee estimates.
  void setFeeEstimates(Map<int, int> estimates) {
    _feeEstimates.clear();
    _feeEstimates.addAll(estimates);
  }

  @override
  Future<BigInt> getAddressBalance(String address) async {
    return _balances[address] ?? BigInt.zero;
  }

  @override
  Future<List<UTXO>> getAddressUtxos(String address) async {
    return _utxos[address] ?? [];
  }

  @override
  Future<List<Transaction>> getAddressTransactions(String address) async {
    return _transactions[address] ?? [];
  }

  @override
  Future<Transaction> getTransaction(String txid) async {
    final tx = _transactionMap[txid];
    if (tx == null) {
      throw ApiException('Transaction not found: $txid', 404);
    }
    return tx;
  }

  @override
  Future<String> getTransactionHex(String txid) async {
    final tx = _transactionMap[txid];
    if (tx == null) {
      throw ApiException('Transaction not found: $txid', 404);
    }
    // Return a mock hex string
    return '0100000001${txid}00000000';
  }

  @override
  Future<Map<int, int>> getFeeEstimates() async {
    if (_feeEstimates.isEmpty) {
      // Default mock estimates
      return {
        1: 50,
        3: 20,
        6: 10,
        12: 5,
        24: 2,
      };
    }
    return Map<int, int>.from(_feeEstimates);
  }

  @override
  Future<FeeEstimate> getFeeEstimate({int targetBlocks = 6}) async {
    final estimates = await getFeeEstimates();
    final fee = estimates[targetBlocks] ?? (estimates.values.isNotEmpty ? estimates.values.first : 10);
    return FeeEstimate(
      satPerVByte: fee,
      estimatedBlocks: targetBlocks,
    );
  }

  @override
  Future<String> broadcastTransaction(String txHex) async {
    // Return a mock txid
    return 'mock_txid_${txHex.substring(0, 8)}';
  }

  /// Clears all mock data.
  void clear() {
    _balances.clear();
    _utxos.clear();
    _transactions.clear();
    _transactionMap.clear();
    _feeEstimates.clear();
  }
}

