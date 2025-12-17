import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/networks.dart';
import '../utils/debug_logger.dart';
import '../models/utxo.dart';
import '../models/transaction.dart';
import '../models/fee_estimate.dart';

/// Service for querying Esplora-style REST API endpoints.
///
/// This service provides methods to:
/// - Fetch address balance and UTXOs
/// - Fetch transaction history
/// - Fetch raw transaction by txid
/// - Get fee estimates
///
/// All methods respect the current network selection and use the appropriate endpoint.
class ApiService {
  final http.Client _client;
  BitcoinNetwork _currentNetwork;
  late String _baseUrl;

  ApiService({
    http.Client? client,
    BitcoinNetwork? initialNetwork,
  })  : _client = client ?? http.Client(),
        _currentNetwork = initialNetwork ?? BitcoinNetwork.mainnet {
    _baseUrl = NetworkConfig.getApiEndpoint(_currentNetwork);
  }

  /// Gets the current network.
  BitcoinNetwork get currentNetwork => _currentNetwork;

  /// Gets the current API base URL.
  String get baseUrl => _baseUrl;

  /// Updates the network and base URL.
  ///
  /// This should be called when the network provider changes networks.
  void setNetwork(BitcoinNetwork network) {
    _currentNetwork = network;
    _baseUrl = NetworkConfig.getApiEndpoint(network);
  }

  /// Fetches the balance for a given address.
  ///
  /// Returns the balance in satoshis.
  /// Throws [ApiException] if the request fails.
  Future<BigInt> getAddressBalance(String address) async {
    try {
      final url = Uri.parse('$_baseUrl/address/$address');
      final response = await _client.get(url);

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch address balance: ${response.statusCode}',
          response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final balance = json['chain_stats']?['funded_txo_sum'] as int? ??
          json['funded_txo_sum'] as int? ??
          json['balance'] as int? ??
          0;
      final spent = json['chain_stats']?['spent_txo_sum'] as int? ??
          json['spent_txo_sum'] as int? ??
          0;

      return BigInt.from(balance - spent);
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.getAddressBalance',
        additionalInfo: {'address': address},
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error fetching address balance: $e', 0);
    }
  }

  /// Fetches all UTXOs for a given address.
  ///
  /// Returns a list of UTXOs.
  /// Throws [ApiException] if the request fails.
  Future<List<UTXO>> getAddressUtxos(String address) async {
    try {
      final url = Uri.parse('$_baseUrl/address/$address/utxo');
      final response = await _client.get(url);

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch UTXOs: ${response.statusCode}',
          response.statusCode,
        );
      }

      final jsonList = jsonDecode(response.body) as List<dynamic>;
      return jsonList
          .map((json) => UTXO.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.getAddressUtxos',
        additionalInfo: {'address': address},
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error fetching UTXOs: $e', 0);
    }
  }

  /// Fetches transaction history for a given address.
  ///
  /// Returns a list of transactions.
  /// Throws [ApiException] if the request fails.
  Future<List<Transaction>> getAddressTransactions(String address) async {
    try {
      final url = Uri.parse('$_baseUrl/address/$address/txs');
      final response = await _client.get(url);

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch transactions: ${response.statusCode}',
          response.statusCode,
        );
      }

      final jsonList = jsonDecode(response.body) as List<dynamic>;
      return jsonList
          .map((json) => Transaction.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.getAddressTransactions',
        additionalInfo: {'address': address},
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error fetching transactions: $e', 0);
    }
  }

  /// Fetches a raw transaction by txid.
  ///
  /// Returns the transaction data.
  /// Throws [ApiException] if the request fails.
  Future<Transaction> getTransaction(String txid) async {
    try {
      final url = Uri.parse('$_baseUrl/tx/$txid');
      final response = await _client.get(url);

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch transaction: ${response.statusCode}',
          response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return Transaction.fromJson(json);
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.getTransaction',
        additionalInfo: {'txid': txid},
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error fetching transaction: $e', 0);
    }
  }

  /// Fetches the raw transaction hex by txid.
  ///
  /// Returns the transaction hex string.
  /// Throws [ApiException] if the request fails.
  Future<String> getTransactionHex(String txid) async {
    try {
      final url = Uri.parse('$_baseUrl/tx/$txid/hex');
      final response = await _client.get(url);

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch transaction hex: ${response.statusCode}',
          response.statusCode,
        );
      }

      return response.body.trim();
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.getTransactionHex',
        additionalInfo: {'txid': txid},
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error fetching transaction hex: $e', 0);
    }
  }

  /// Gets fee estimates for different confirmation targets.
  ///
  /// Returns a map of confirmation blocks to fee rate (sat/vB).
  /// Throws [ApiException] if the request fails.
  Future<Map<int, int>> getFeeEstimates() async {
    try {
      final url = Uri.parse('$_baseUrl/fee-estimates');
      final response = await _client.get(url);

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch fee estimates: ${response.statusCode}',
          response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final estimates = <int, int>{};

      json.forEach((key, value) {
        final blocks = int.tryParse(key);
        if (blocks != null && value is num) {
          // Esplora returns fee rate in sat/vB
          estimates[blocks] = value.toInt();
        }
      });

      return estimates;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.getFeeEstimates',
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error fetching fee estimates: $e', 0);
    }
  }

  /// Gets a fee estimate for a specific confirmation target.
  ///
  /// [targetBlocks] is the target number of blocks for confirmation.
  /// Returns the fee rate in sat/vB.
  /// Throws [ApiException] if the request fails.
  Future<FeeEstimate> getFeeEstimate({int targetBlocks = 6}) async {
    try {
      final estimates = await getFeeEstimates();

      // Find the closest estimate
      int? closestBlocks;
      int? closestFee;
      int minDiff = double.maxFinite.toInt();

      for (final entry in estimates.entries) {
        final diff = (entry.key - targetBlocks).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestBlocks = entry.key;
          closestFee = entry.value;
        }
      }

      if (closestFee == null) {
        // Fallback to default
        return FeeEstimate(satPerVByte: 10, estimatedBlocks: targetBlocks);
      }

      return FeeEstimate(
        satPerVByte: closestFee,
        estimatedBlocks: closestBlocks,
      );
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.getFeeEstimate',
        additionalInfo: {'targetBlocks': targetBlocks},
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error fetching fee estimate: $e', 0);
    }
  }

  /// Broadcasts a raw transaction.
  ///
  /// [txHex] is the raw transaction hex string.
  /// Returns the transaction ID if successful.
  /// Throws [ApiException] if the request fails.
  Future<String> broadcastTransaction(String txHex) async {
    try {
      final url = Uri.parse('$_baseUrl/tx');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'text/plain'},
        body: txHex,
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to broadcast transaction: ${response.statusCode} - ${response.body}',
          response.statusCode,
        );
      }

      return response.body.trim();
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'ApiService.broadcastTransaction',
        additionalInfo: {'txHexLength': txHex.length},
      );
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Error broadcasting transaction: $e', 0);
    }
  }
}

/// Exception thrown by ApiService when API calls fail.
class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}
