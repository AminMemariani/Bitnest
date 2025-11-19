import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../utils/debug_logger.dart';

/// Provider responsible for loading and caching transactions per account.
class TransactionsProvider extends ChangeNotifier {
  final ApiService _apiService;

  final Map<String, List<Transaction>> _accountTransactions = {};
  final Map<String, bool> _isRefreshing = {};
  String? _error;

  TransactionsProvider({
    ApiService? apiService,
  }) : _apiService = apiService ?? ApiService();

  /// Returns cached transactions for the given account.
  List<Transaction> transactionsForAccount(String accountId) {
    return List.unmodifiable(_accountTransactions[accountId] ?? []);
  }

  /// Indicates whether the provider is currently refreshing transactions for the account.
  bool isRefreshing(String accountId) => _isRefreshing[accountId] ?? false;

  /// Returns the last error message, if any.
  String? get error => _error;

  /// Refreshes the transactions for the supplied account.
  Future<void> refreshTransactions(
    Account account, {
    bool force = false,
  }) async {
    final accountId = account.id;
    if (!force && (_accountTransactions[accountId]?.isNotEmpty ?? false)) {
      return;
    }

    if (account.addresses.isEmpty) {
      _accountTransactions[accountId] = [];
      notifyListeners();
      return;
    }

    _isRefreshing[accountId] = true;
    notifyListeners();

    try {
      final txMap = <String, Transaction>{
        for (final tx in _accountTransactions[accountId] ?? []) tx.txid: tx,
      };

      for (final address in account.addresses) {
        try {
          final addressTransactions = await _apiService.getAddressTransactions(address);
          for (final tx in addressTransactions) {
            final existing = txMap[tx.txid];
            if (existing == null || _txTimestamp(tx).isAfter(_txTimestamp(existing))) {
              txMap[tx.txid] = tx;
            }
          }
        } catch (e, stackTrace) {
          DebugLogger.logException(
            e,
            stackTrace,
            context: 'TransactionsProvider.refreshTransactions (address)',
            additionalInfo: {'address': address},
          );
        }
      }

      final transactions = txMap.values.toList()
        ..sort(
          (a, b) => _txTimestamp(b).compareTo(_txTimestamp(a)),
        );

      _accountTransactions[accountId] = transactions;
      _error = null;
    } catch (e, stackTrace) {
      _error = 'Failed to load transactions';
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'TransactionsProvider.refreshTransactions',
        additionalInfo: {'accountId': account.id},
      );
    } finally {
      _isRefreshing[accountId] = false;
      notifyListeners();
    }
  }

  /// Returns the raw transaction hex.
  Future<String> fetchTransactionHex(String txid) {
    return _apiService.getTransactionHex(txid);
  }

  /// Clears cached transactions for a specific account.
  void clearAccount(String accountId) {
    _accountTransactions.remove(accountId);
    notifyListeners();
  }

  DateTime _txTimestamp(Transaction tx) {
    return tx.blockTime ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}

