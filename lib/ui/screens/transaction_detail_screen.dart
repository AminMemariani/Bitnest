import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/account.dart';
import '../../models/transaction.dart';
import '../../providers/network_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/networks.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Transaction transaction;
  final Account account;
  final String? initialHex;

  const TransactionDetailScreen({
    super.key,
    required this.transaction,
    required this.account,
    this.initialHex,
  });

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  String? _rawHex;
  bool _isLoadingHex = false;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _rawHex = widget.initialHex;
    if (_rawHex == null) {
      _loadRawHex();
    }
  }

  Future<void> _loadRawHex() async {
    setState(() {
      _isLoadingHex = true;
      _hexError = null;
    });
    try {
      final provider = context.read<TransactionsProvider>();
      final hex = await provider.fetchTransactionHex(widget.transaction.txid);
      setState(() {
        _rawHex = hex;
      });
    } catch (e) {
      setState(() {
        _hexError = 'Failed to load raw transaction';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHex = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final theme = Theme.of(context);
    final meta = _TransactionMeta.fromTransaction(transaction, widget.account);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openInExplorer(context),
            tooltip: 'View in explorer',
          ),
        ],
      ),
      body: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.directionLabel,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        meta.formattedAmount,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: meta.indicatorColor(theme.colorScheme),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Confirmations', meta.confirmationsLabel),
                      _buildInfoRow('Status', meta.statusLabel),
                      _buildInfoRow('Fee', '${meta.formattedFee} BTC'),
                      _buildInfoRow('TxID', transaction.txid),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: transaction.txid));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('TxID copied to clipboard')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy TxID'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildIoSection(
                title: 'Inputs',
                entries: transaction.inputs
                    .map(
                      (input) => _IoEntry(
                        label: input.address ?? 'Unknown input',
                        amount: input.value,
                        isIncoming: false,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              _buildIoSection(
                title: 'Outputs',
                entries: transaction.outputs
                    .map(
                      (output) => _IoEntry(
                        label: output.address ?? 'Unknown output',
                        amount: output.value,
                        isIncoming: true,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              _buildRawHexSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIoSection({
    required String title,
    required List<_IoEntry> entries,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text(
                'None',
                style: TextStyle(color: Colors.grey[600]),
              )
            else
              ...entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: SelectableText(
                    entry.label,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: Text(
                    '${entry.sign}${entry.formattedAmount} BTC',
                    style: TextStyle(
                      color: entry.isIncoming ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawHexSection() {
    if (_isLoadingHex) {
      return const Center(
        child: CircularProgressIndicator.adaptive(),
      );
    }

    if (_hexError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_hexError!, style: const TextStyle(color: Colors.red)),
          TextButton(
            onPressed: _loadRawHex,
            child: const Text('Retry'),
          ),
        ],
      );
    }

    final hex = _rawHex ?? 'Unavailable';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Raw Transaction Hex',
              key: Key('raw_tx_hex_label'),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(
              hex,
              key: const Key('raw_tx_hex_value'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInExplorer(BuildContext context) async {
    final network = context.read<NetworkProvider>().currentNetwork;
    final url = NetworkExplorer.transactionUrl(network, widget.transaction.txid);
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open explorer')),
      );
    }
  }
}

class _TransactionMeta {
  final bool isIncoming;
  final BigInt netAmount;
  final BigInt fee;
  final int confirmations;

  _TransactionMeta({
    required this.isIncoming,
    required this.netAmount,
    required this.fee,
    required this.confirmations,
  });

  factory _TransactionMeta.fromTransaction(
    Transaction transaction,
    Account account,
  ) {
    final addressSet = account.addresses.toSet();
    final inputs = transaction.inputs
        .where((input) => input.address != null && addressSet.contains(input.address))
        .fold<BigInt>(BigInt.zero, (sum, input) => sum + input.value);
    final outputs = transaction.outputs
        .where((output) => output.address != null && addressSet.contains(output.address))
        .fold<BigInt>(BigInt.zero, (sum, output) => sum + output.value);

    final net = outputs - inputs;
    return _TransactionMeta(
      isIncoming: net >= BigInt.zero,
      netAmount: net.abs(),
      fee: transaction.fee,
      confirmations: transaction.confirmations,
    );
  }

  String get directionLabel => isIncoming ? 'Incoming Transaction' : 'Outgoing Transaction';

  String get formattedAmount => _formatSats(netAmount);

  String get formattedFee => _formatSats(fee);

  String get statusLabel {
    if (confirmations <= 0) return 'Pending';
    if (confirmations == 1) return '1 confirmation';
    if (confirmations >= 6) return 'Finalized';
    return '$confirmations confirmations';
  }

  String get confirmationsLabel {
    if (confirmations <= 0) return '0';
    return confirmations.toString();
  }

  Color indicatorColor(ColorScheme scheme) {
    return isIncoming ? scheme.primary : scheme.error;
  }

  static String _formatSats(BigInt value) {
    final padded = value.toString().padLeft(9, '0');
    final integerPart = padded.substring(0, padded.length - 8);
    final decimalPart = padded.substring(padded.length - 8);
    final trimmedInteger = integerPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return '${trimmedInteger.isEmpty ? '0' : trimmedInteger}.$decimalPart';
  }
}

class _IoEntry {
  final String label;
  final BigInt amount;
  final bool isIncoming;

  _IoEntry({
    required this.label,
    required this.amount,
    required this.isIncoming,
  });

  String get formattedAmount {
    final padded = amount.toString().padLeft(9, '0');
    final integerPart = padded.substring(0, padded.length - 8);
    final decimalPart = padded.substring(padded.length - 8);
    final trimmedInteger = integerPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return '${trimmedInteger.isEmpty ? '0' : trimmedInteger}.$decimalPart';
  }

  String get sign => isIncoming ? '+' : '-';
}

