import '../services/api_service.dart';
import '../utils/debug_logger.dart';
import '../utils/networks.dart';
import 'api_service.dart' show ApiException;

/// Service for broadcasting Bitcoin transactions.
///
/// This service wraps ApiService's broadcast functionality
/// and provides additional error handling and logging.
class BroadcastService {
  final ApiService _apiService;

  BroadcastService({
    ApiService? apiService,
  }) : _apiService = apiService ?? ApiService();

  /// Broadcasts a signed transaction to the network.
  ///
  /// [txHex] is the raw signed transaction in hex format.
  /// Returns the transaction ID (txid) if successful.
  ///
  /// Throws [BroadcastException] if broadcasting fails.
  Future<String> broadcastTransaction(String txHex) async {
    try {
      DebugLogger.logError(
        'Broadcasting transaction',
        context: 'BroadcastService.broadcastTransaction',
        additionalInfo: {'txHexLength': txHex.length},
      );

      final txid = await _apiService.broadcastTransaction(txHex);

      DebugLogger.logError(
        'Transaction broadcast successful',
        context: 'BroadcastService.broadcastTransaction',
        additionalInfo: {'txid': txid},
      );

      return txid;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'BroadcastService.broadcastTransaction',
        additionalInfo: {'txHexLength': txHex.length},
      );

      if (e is ApiException) {
        throw BroadcastException(
          'Failed to broadcast transaction: ${e.message}',
          e.statusCode,
        );
      }

      throw BroadcastException('Failed to broadcast transaction: $e', 0);
    }
  }

  /// Updates the network for the underlying API service.
  void setNetwork(BitcoinNetwork network) {
    _apiService.setNetwork(network);
  }
}

/// Exception thrown by BroadcastService when broadcasting fails.
class BroadcastException implements Exception {
  final String message;
  final int statusCode;

  BroadcastException(this.message, this.statusCode);

  @override
  String toString() => 'BroadcastException: $message (status: $statusCode)';
}
