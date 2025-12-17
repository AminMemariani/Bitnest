import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/send_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../models/account.dart';
import '../../services/transaction_service.dart';
import '../../services/key_service.dart';

class SendScreen extends StatefulWidget {
  final Account account;

  const SendScreen({
    super.key,
    required this.account,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _manualFeeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showManualFee = false;

  @override
  void initState() {
    super.initState();
    final sendProvider = Provider.of<SendProvider>(context, listen: false);
    sendProvider.selectAccount(widget.account);
    sendProvider.setFeePreset(FeePreset.normal);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _manualFeeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Bitcoin'),
      ),
      body: Consumer2<SendProvider, WalletProvider>(
        builder: (context, sendProvider, walletProvider, _) {
          if (sendProvider.isLoading && sendProvider.txid == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (sendProvider.txid != null) {
            return _buildSuccessView(context, sendProvider);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Account info
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'From Account',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.account.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatBalance(walletProvider
                                .getAccountBalance(widget.account.id)),
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Recipient address
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Recipient Address',
                      hintText: 'bc1q...',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a recipient address';
                      }
                      return null;
                    },
                    onChanged: (value) =>
                        sendProvider.setRecipientAddress(value),
                  ),
                  const SizedBox(height: 16),

                  // Amount
                  TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount (BTC)',
                      hintText: '0.00000000',
                      border: OutlineInputBorder(),
                      prefixText: '₿ ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an amount';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      final amount = double.tryParse(value);
                      if (amount != null && amount > 0) {
                        final satoshis =
                            BigInt.from((amount * 100000000).round());
                        sendProvider.setAmount(satoshis);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Fee selection
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transaction Fee',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          if (!_showManualFee) ...[
                            Row(
                              children: FeePreset.values.map((preset) {
                                final isSelected =
                                    sendProvider.selectedFeePreset == preset;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          sendProvider.setFeePreset(preset),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                            : null,
                                      ),
                                      child: Column(
                                        children: [
                                          Text(preset.label),
                                          if (sendProvider.currentFeeEstimate !=
                                                  null &&
                                              isSelected)
                                            Text(
                                              '${sendProvider.currentFeeEstimate!.satPerVByte} sat/vB',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _showManualFee = true),
                              icon: const Icon(Icons.tune),
                              label: const Text('Manual Fee'),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _manualFeeController,
                                    decoration: const InputDecoration(
                                      labelText: 'Fee Rate (sat/vB)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) {
                                      final feeRate = int.tryParse(value);
                                      if (feeRate != null && feeRate > 0) {
                                        sendProvider.setManualFeeRate(feeRate);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _showManualFee = false),
                                  child: const Text('Presets'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // UTXO selection
                  _buildUtxoSelection(context, sendProvider, walletProvider),
                  const SizedBox(height: 16),

                  // Transaction summary
                  if (sendProvider.amount != null &&
                      sendProvider.selectedUtxos.isNotEmpty)
                    _buildTransactionSummary(context, sendProvider),
                  const SizedBox(height: 16),

                  // Error display
                  if (sendProvider.error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sendProvider.error!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => sendProvider.clearError(),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Send button
                  ElevatedButton(
                    onPressed: sendProvider.isLoading
                        ? null
                        : () => _handleSend(context, sendProvider),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: sendProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send Transaction'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUtxoSelection(
    BuildContext context,
    SendProvider sendProvider,
    WalletProvider walletProvider,
  ) {
    final utxos = walletProvider.getAccountUtxos(widget.account.id);

    if (utxos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, size: 48),
              const SizedBox(height: 8),
              Text(
                'No UTXOs available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    walletProvider.fetchAccountUtxos(widget.account.id),
                child: const Text('Sync Account'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select UTXOs to Spend',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: sendProvider.selectAllUtxos,
                      child: const Text('Select All'),
                    ),
                    TextButton(
                      onPressed: sendProvider.clearUtxoSelection,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...utxos.map((utxo) => CheckboxListTile(
                  title: Text(
                    utxo.address.substring(0, 16) + '...',
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  subtitle: Text(_formatBalance(utxo.value)),
                  value: sendProvider.selectedUtxos.contains(utxo),
                  onChanged: (_) => sendProvider.toggleUtxo(utxo),
                  dense: true,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionSummary(
    BuildContext context,
    SendProvider sendProvider,
  ) {
    final fee = sendProvider.calculateEstimatedFee();
    final change = sendProvider.calculateChange();
    final totalInput = sendProvider.selectedUtxos.fold<BigInt>(
      BigInt.zero,
      (sum, utxo) => sum + utxo.value,
    );

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transaction Summary',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            _buildSummaryRow('Amount', _formatBalance(sendProvider.amount!)),
            _buildSummaryRow('Fee', _formatBalance(fee)),
            if (change > BigInt.zero)
              _buildSummaryRow('Change', _formatBalance(change)),
            const Divider(),
            _buildSummaryRow(
              'Total Input',
              _formatBalance(totalInput),
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context, SendProvider sendProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            Text(
              'Transaction Sent!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Transaction ID:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              sendProvider.txid!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                sendProvider.reset();
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSend(
      BuildContext context, SendProvider sendProvider) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Require biometric authentication
    final keyService = KeyService();
    bool authenticated = false;
    try {
      final isAvailable = await keyService.isBiometricAvailable();
      if (isAvailable) {
        authenticated = await keyService.authenticateWithBiometrics(
          reason: 'Authenticate to send Bitcoin transaction',
        );
      } else {
        // If biometric not available, show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Biometric authentication is required but not available'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    } catch (e) {
      authenticated = false;
    }

    if (!authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication required to send transaction'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      await sendProvider.sendTransaction(authenticated: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatBalance(BigInt balance) {
    if (balance == BigInt.zero) {
      return '0.00000000 BTC';
    }
    final btc = balance / BigInt.from(100000000);
    final sats = balance % BigInt.from(100000000);
    return '${btc.toString()}.${sats.toString().padLeft(8, '0')} BTC';
  }
}
