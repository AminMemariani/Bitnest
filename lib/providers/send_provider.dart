import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/utxo.dart';
import '../models/fee_estimate.dart';
import '../services/transaction_service.dart';
import '../services/broadcast_service.dart';
import '../services/key_service.dart';
import '../utils/networks.dart';
import '../utils/debug_logger.dart';
import 'wallet_provider.dart';

/// Provider for sending Bitcoin transactions.
///
/// This provider handles:
/// - Transaction building from selected UTXOs
/// - Fee calculation and selection
/// - Transaction signing
/// - Transaction broadcasting
/// - Change address derivation
class SendProvider extends ChangeNotifier {
  final TransactionService _transactionService;
  final BroadcastService _broadcastService;
  final KeyService _keyService;
  WalletProvider _walletProvider;

  Account? _selectedAccount;
  List<UTXO> _selectedUtxos = [];
  String? _recipientAddress;
  BigInt? _amount;
  FeePreset? _selectedFeePreset;
  int? _manualFeeRate;
  FeeEstimate? _currentFeeEstimate;
  bool _isLoading = false;
  String? _error;
  String? _txid;

  SendProvider({
    required TransactionService transactionService,
    required BroadcastService broadcastService,
    required KeyService keyService,
    required WalletProvider walletProvider,
  })  : _transactionService = transactionService,
        _broadcastService = broadcastService,
        _keyService = keyService,
        _walletProvider = walletProvider;

  void updateWalletProvider(WalletProvider provider) {
    _walletProvider = provider;
  }

  // Getters
  Account? get selectedAccount => _selectedAccount;
  List<UTXO> get selectedUtxos => List.unmodifiable(_selectedUtxos);
  String? get recipientAddress => _recipientAddress;
  BigInt? get amount => _amount;
  FeePreset? get selectedFeePreset => _selectedFeePreset;
  int? get manualFeeRate => _manualFeeRate;
  FeeEstimate? get currentFeeEstimate => _currentFeeEstimate;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get txid => _txid;

  /// Selects an account to send from.
  void selectAccount(Account account) {
    _selectedAccount = account;
    _selectedUtxos.clear();
    _error = null;
    notifyListeners();
  }

  /// Sets the recipient address.
  void setRecipientAddress(String address) {
    _recipientAddress = address;
    _error = null;
    notifyListeners();
  }

  /// Sets the amount to send (in satoshis).
  void setAmount(BigInt amount) {
    _amount = amount;
    _error = null;
    notifyListeners();
  }

  /// Sets the fee preset.
  Future<void> setFeePreset(FeePreset preset) async {
    _selectedFeePreset = preset;
    _manualFeeRate = null;
    _isLoading = true;
    notifyListeners();

    try {
      _currentFeeEstimate = await _transactionService.getFeeEstimateForPreset(preset);
    } catch (e, stackTrace) {
      DebugLogger.logException(e, stackTrace, context: 'SendProvider.setFeePreset');
      _error = 'Failed to get fee estimate: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets manual fee rate (in sat/vB).
  void setManualFeeRate(int feeRate) {
    _manualFeeRate = feeRate;
    _selectedFeePreset = null;
    _currentFeeEstimate = FeeEstimate(satPerVByte: feeRate);
    _error = null;
    notifyListeners();
  }

  /// Toggles UTXO selection.
  void toggleUtxo(UTXO utxo) {
    if (_selectedUtxos.contains(utxo)) {
      _selectedUtxos.remove(utxo);
    } else {
      _selectedUtxos.add(utxo);
    }
    _error = null;
    notifyListeners();
  }

  /// Selects all UTXOs.
  void selectAllUtxos() {
    if (_selectedAccount == null) return;
    final utxos = _walletProvider.getAccountUtxos(_selectedAccount!.id);
    _selectedUtxos = List.from(utxos);
    notifyListeners();
  }

  /// Clears all UTXO selections.
  void clearUtxoSelection() {
    _selectedUtxos.clear();
    notifyListeners();
  }

  /// Gets the current fee rate (from preset or manual).
  int getCurrentFeeRate() {
    if (_manualFeeRate != null) {
      return _manualFeeRate!;
    }
    if (_currentFeeEstimate != null) {
      return _currentFeeEstimate!.satPerVByte;
    }
    return 10; // Default fallback
  }

  /// Calculates the estimated fee for the transaction.
  BigInt calculateEstimatedFee() {
    if (_selectedUtxos.isEmpty || _amount == null) {
      return BigInt.zero;
    }

    final feeRate = getCurrentFeeRate();
    // Simplified fee calculation
    final estimatedSize = 10 + (_selectedUtxos.length * 148) + (2 * 34); // inputs + outputs
    return BigInt.from(estimatedSize * feeRate);
  }

  /// Calculates the change amount.
  BigInt calculateChange() {
    if (_selectedUtxos.isEmpty || _amount == null) {
      return BigInt.zero;
    }

    final totalInput = _selectedUtxos.fold<BigInt>(
      BigInt.zero,
      (sum, utxo) => sum + utxo.value,
    );

    final fee = calculateEstimatedFee();
    final change = totalInput - _amount! - fee;

    return change > BigInt.zero ? change : BigInt.zero;
  }

  /// Validates the transaction before sending.
  String? validateTransaction() {
    if (_selectedAccount == null) {
      return 'Please select an account';
    }
    if (_recipientAddress == null || _recipientAddress!.isEmpty) {
      return 'Please enter a recipient address';
    }
    if (_amount == null || _amount! <= BigInt.zero) {
      return 'Please enter a valid amount';
    }
    if (_selectedUtxos.isEmpty) {
      return 'Please select at least one UTXO';
    }

    final totalInput = _selectedUtxos.fold<BigInt>(
      BigInt.zero,
      (sum, utxo) => sum + utxo.value,
    );

    final fee = calculateEstimatedFee();
    final totalNeeded = _amount! + fee;

    if (totalInput < totalNeeded) {
      return 'Insufficient funds. Need ${totalNeeded - totalInput} more satoshis';
    }

    return null;
  }

  /// Sends the transaction (requires biometric authentication).
  Future<String> sendTransaction({required bool authenticated}) async {
    if (!authenticated) {
      throw Exception('Biometric authentication required');
    }

    final validationError = validateTransaction();
    if (validationError != null) {
      throw Exception(validationError);
    }

    _isLoading = true;
    _error = null;
    _txid = null;
    notifyListeners();

    try {
      final account = _selectedAccount!;
      
      // Get account xprv
      final wallet = _walletProvider.currentWallet;
      if (wallet == null || wallet.xprv == null) {
        throw Exception('Wallet not found or is watch-only');
      }

      final seed = await _keyService.retrieveSeed(wallet.id);
      if (seed == null) {
        throw Exception('Wallet seed not found');
      }

      // Derive account xprv
      final scheme = _getDerivationSchemeFromPath(account.derivationPath);
      final derivationPath = _buildDerivationPath(scheme, account.network, account.accountIndex);
      final masterXprv = _keyService.deriveMasterXprv(seed, account.network);
      final accountXprv = _keyService.deriveXprv(masterXprv, derivationPath);

      // Create input info for each UTXO
      final inputs = <TxInputInfo>[];
      for (final utxo in _selectedUtxos) {
        // Find address index for this UTXO
        final addressIndex = account.addresses.indexOf(utxo.address);
        if (addressIndex == -1) {
          throw Exception('Address not found in account: ${utxo.address}');
        }

        final inputInfo = await _transactionService.createInputInfo(
          utxo: utxo,
          accountXprv: accountXprv,
          addressIndex: addressIndex,
          isChange: false, // TODO: detect change addresses
          scheme: scheme,
        );
        inputs.add(inputInfo);
      }

      // Create output
      final outputs = [
        TxOutputInfo(
          address: _recipientAddress!,
          value: _amount!,
        ),
      ];

      // Derive change address if needed
      String? changeAddress;
      final change = calculateChange();
      if (change > BigInt.from(546)) {
        // Get current change index (simplified - would track this properly)
        final changeIndex = 0; // TODO: track change address index
        changeAddress = _transactionService.deriveChangeAddress(
          accountXpub: account.xpub,
          currentChangeIndex: changeIndex,
          scheme: scheme,
          network: account.network,
        );
      }

      // Build and sign transaction
      final feeRate = getCurrentFeeRate();
      final txHex = await _transactionService.buildTransaction(
        inputs: inputs,
        outputs: outputs,
        feeRate: feeRate,
        changeAddress: changeAddress,
      );

      // Broadcast transaction
      _broadcastService.setNetwork(account.network);
      _txid = await _broadcastService.broadcastTransaction(txHex);

      // Clear form
      _selectedUtxos.clear();
      _recipientAddress = null;
      _amount = null;

      notifyListeners();
      return _txid!;
    } catch (e, stackTrace) {
      DebugLogger.logException(
        e,
        stackTrace,
        context: 'SendProvider.sendTransaction',
      );
      _error = 'Failed to send transaction: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Clears the error.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Resets the send form.
  void reset() {
    _selectedUtxos.clear();
    _recipientAddress = null;
    _amount = null;
    _selectedFeePreset = null;
    _manualFeeRate = null;
    _currentFeeEstimate = null;
    _error = null;
    _txid = null;
    notifyListeners();
  }

  DerivationScheme _getDerivationSchemeFromPath(String path) {
    if (path.contains("44'")) {
      return DerivationScheme.legacy;
    } else if (path.contains("49'")) {
      return DerivationScheme.p2shSegwit;
    } else {
      return DerivationScheme.nativeSegwit;
    }
  }

  String _buildDerivationPath(
    DerivationScheme scheme,
    BitcoinNetwork network,
    int accountIndex,
  ) {
    final coinType = NetworkConfig.getCoinType(network);
    final purpose = _getPurposeForScheme(scheme);
    return "m/$purpose'/$coinType'/$accountIndex'";
  }

  int _getPurposeForScheme(DerivationScheme scheme) {
    switch (scheme) {
      case DerivationScheme.legacy:
        return 44;
      case DerivationScheme.p2shSegwit:
        return 49;
      case DerivationScheme.nativeSegwit:
        return 84;
    }
  }
}

