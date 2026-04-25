import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/utxo.dart';
import '../models/fee_estimate.dart';
import '../services/transaction_service.dart';
import '../services/broadcast_service.dart';
import '../services/key_service.dart';
import '../services/hd_wallet_service.dart';
import '../services/transaction_journal.dart';
import '../services/transaction_signer.dart';
import '../services/send_pipeline_service.dart';
import '../services/tx_builder_service.dart';
import '../utils/debug_logger.dart';
import 'wallet_provider.dart';

/// Upper bound on how far the legacy-UTXO locator will scan when a
/// selected UTXO arrives without derivation metadata. Walking 50 indices
/// per chain costs nothing on a real device but covers any wallet that
/// hasn't crossed BIP44's gap limit.
const int _kAddressLocatorMaxIndex = 50;

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
  // ignore: unused_field
  final KeyService _keyService; // retained for backwards-compatible ctor
  WalletProvider _walletProvider;
  final TransactionBuilder _txBuilder;
  TransactionJournal? _journal;

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
    TransactionBuilder? txBuilder,
    TransactionJournal? journal,
  })  : _transactionService = transactionService,
        _broadcastService = broadcastService,
        _keyService = keyService,
        _walletProvider = walletProvider,
        _txBuilder = txBuilder ?? const TransactionBuilder(),
        _journal = journal;

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
      _currentFeeEstimate =
          await _transactionService.getFeeEstimateForPreset(preset);
    } catch (e, stackTrace) {
      DebugLogger.logException(e, stackTrace,
          context: 'SendProvider.setFeePreset');
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
    final estimatedSize =
        10 + (_selectedUtxos.length * 148) + (2 * 34); // inputs + outputs
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
  ///
  /// All real outgoing transactions go through this single path:
  ///
  ///   1. [TransactionBuilder.build] selects inputs, computes the fee, and
  ///      — if change is above dust — calls
  ///      [WalletRepository.getFreshChangeAddress] to allocate a NEW BIP32
  ///      derivation index for the change output. The change output's key
  ///      is freshly derived from the wallet seed at that new index; this
  ///      method never re-uses a previously seen change address and never
  ///      attempts the (mathematically impossible) trick of producing a
  ///      different public key for an existing private key.
  ///
  ///   2. [SendPipelineService.signAndBroadcast] journals the signed tx,
  ///      hands it to the network, and on success calls
  ///      [WalletRepository.onOutgoingTransactionSuccess] with the txid as
  ///      idempotency key. That call advances `currentReceivingIndex`,
  ///      which is what the user sees as "the wallet's current receiving
  ///      address" — so the displayed address rotates after every
  ///      successful outgoing transaction.
  ///
  /// On broadcast failure: the journal records `failed`, NO rotation
  /// occurs, and the exception is rethrown.
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
      final wallet = _walletProvider.currentWallet;
      if (wallet == null || wallet.xprv == null) {
        throw Exception('Wallet not found or is watch-only');
      }

      // Resolve the cached HD service (seed-backed) and the persisted
      // address-rotation repository for this account. Both are owned by
      // WalletProvider so the same instances are reused across screens.
      final hd = await _walletProvider.hdServiceFor(wallet.id);
      final repo = await _walletProvider.walletRepositoryFor(account.id);

      // Make sure every selected UTXO has the derivation metadata the
      // signer needs. Newly-scanned UTXOs already do; legacy ones from
      // the older sync path get back-filled here.
      final annotatedUtxos =
          _annotateSelectedUtxos(_selectedUtxos, hd, account);

      // Build the unsigned transaction. TransactionBuilder will call
      // repo.getFreshChangeAddress() if and only if change is above the
      // dust threshold — which is exactly the "new change address per
      // tx with change" rule.
      final unsigned = await _txBuilder.build(
        recipientAddress: _recipientAddress!,
        amountSats: _amount!,
        feeRateSatPerVbyte: getCurrentFeeRate(),
        availableUtxos: annotatedUtxos,
        // allocateFreshChange returns the BIP32 child index alongside
        // the address; the builder records the index on the resulting
        // UnsignedTransaction so the pipeline can promote that exact
        // allocation on broadcast success — independent of any other
        // sends happening concurrently.
        getFreshChangeAddress: repo.allocateFreshChange,
        network: account.network,
      );

      // Drive the journal-backed pipeline: sign, persist, broadcast,
      // and on success rotate the rotation pointers exactly once.
      // Single shared journal across SendProvider and WalletProvider —
      // the provider's pending-UTXO filter and the pipeline's writes
      // must observe the same in-memory state.
      final journal = _journal ??=
          await _walletProvider.ensureJournalLoaded();
      final signer = TransactionSigner(hd: hd);
      final pipeline = SendPipelineService(
        signer: signer,
        broadcast: _broadcastService,
        journal: journal,
      );
      final outcome = await pipeline.signAndBroadcast(
        unsigned: unsigned,
        network: account.network,
        repository: repo,
        accountId: account.id,
      );

      switch (outcome.kind) {
        case BroadcastOutcomeKind.success:
        case BroadcastOutcomeKind.alreadyBroadcast:
          _txid = outcome.txid;
        case BroadcastOutcomeKind.failed:
          final err = outcome.error;
          if (err is Exception) throw err;
          throw Exception(err?.toString() ?? 'Broadcast failed');
      }

      // Clear the form. The receive-side rotation has already been
      // applied inside the pipeline; any UI listening to `repo` will
      // rebuild on its own.
      _selectedUtxos.clear();
      _recipientAddress = null;
      _amount = null;

      _isLoading = false;
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

  /// Returns a copy of [utxos] with derivation metadata filled in for
  /// every UTXO that lacks it. Newly-scanned UTXOs are pass-through;
  /// legacy ones get back-filled by matching the address against the
  /// account's derived addresses.
  List<UTXO> _annotateSelectedUtxos(
    List<UTXO> utxos,
    HdWalletService hd,
    Account account,
  ) {
    return [
      for (final u in utxos)
        if (u.derivationPath != null) u else _locateOrThrow(u, hd, account),
    ];
  }

  UTXO _locateOrThrow(UTXO utxo, HdWalletService hd, Account account) {
    // Cheap path: the account's known address lists.
    final ridx = account.addresses.indexOf(utxo.address);
    if (ridx >= 0) {
      return utxo.withDerivation(
        derivationPath: hd.receivingPath(ridx),
        addressIndex: ridx,
        chainType: ChainType.receiving,
      );
    }
    final cidx = account.changeAddresses.indexOf(utxo.address);
    if (cidx >= 0) {
      return utxo.withDerivation(
        derivationPath: hd.changePath(cidx),
        addressIndex: cidx,
        chainType: ChainType.change,
      );
    }
    // Slow path: walk derivations up to a small ceiling. Comparing
    // strings on a single device is cheap; this covers UTXOs the
    // wallet hasn't tracked in `addresses` / `changeAddresses` yet.
    for (var i = 0; i < _kAddressLocatorMaxIndex; i++) {
      if (hd.deriveReceivingAddress(i) == utxo.address) {
        return utxo.withDerivation(
          derivationPath: hd.receivingPath(i),
          addressIndex: i,
          chainType: ChainType.receiving,
        );
      }
      if (hd.deriveChangeAddress(i) == utxo.address) {
        return utxo.withDerivation(
          derivationPath: hd.changePath(i),
          addressIndex: i,
          chainType: ChainType.change,
        );
      }
    }
    throw Exception(
      'UTXO ${utxo.txid}:${utxo.vout} (${utxo.address}) cannot be matched '
      'to a derivation path within the first $_kAddressLocatorMaxIndex '
      'indices on either chain. Run a wallet rescan to repopulate '
      'derivation metadata.',
    );
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

}
