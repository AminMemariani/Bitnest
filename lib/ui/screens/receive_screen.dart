import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/account.dart';
import '../../utils/networks.dart';

typedef GenerateAddressCallback = Future<String> Function();

class ReceiveScreen extends StatefulWidget {
  final Account account;
  final GenerateAddressCallback onGenerateNextAddress;
  final VoidCallback? onCopy;

  const ReceiveScreen({
    super.key,
    required this.account,
    required this.onGenerateNextAddress,
    this.onCopy,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late List<String> _addresses;
  bool _isGenerating = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _addresses = List<String>.from(widget.account.addresses);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_addresses.isEmpty) {
        _generateNextAddress(showMessage: false);
      }
    });
    if (_addresses.isNotEmpty) {
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAddress = _currentAddress;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Bitcoin'),
      ),
      body: _initialized
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildAccountInfoCard(context),
                const SizedBox(height: 16),
                _buildQrCard(context, currentAddress),
                const SizedBox(height: 16),
                _buildAddressDetails(context, currentAddress),
                const SizedBox(height: 16),
                _buildActions(context),
                if (_addresses.length > 1) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Previous Addresses',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _buildAddressList(context),
                ],
              ],
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }

  Widget _buildAccountInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.account.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Derivation Path: ${widget.account.derivationPath}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Network: ${widget.account.network == BitcoinNetwork.mainnet ? 'Mainnet' : 'Testnet'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCard(BuildContext context, String address) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            QrImageView(
              data: address,
              size: 220,
              backgroundColor: Theme.of(context).colorScheme.surface,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              address,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressDetails(BuildContext context, String address) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Address',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    address,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('copy_address_button'),
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    widget.onCopy?.call();
                    await Clipboard.setData(ClipboardData(text: address));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Address copied')),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Label: ${widget.account.label} • Account #${widget.account.accountIndex + 1}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Derivation: $_currentDerivationPath',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            key: const Key('generate_address_button'),
            onPressed: _isGenerating ? null : () => _generateNextAddress(),
            icon: _isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Generate New Address'),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressList(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _addresses.length - 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final reverseIndex = _addresses.length - 2 - index;
        final address = _addresses[reverseIndex];
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(
            address,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          subtitle: Text('Derivation: ${_derivationPathForIndex(reverseIndex)}'),
        );
      },
    );
  }

  String get _currentAddress =>
      _addresses.isNotEmpty ? _addresses.last : 'Generating address...';

  String get _currentDerivationPath =>
      _derivationPathForIndex(_addresses.isNotEmpty ? _addresses.length - 1 : 0);

  String _derivationPathForIndex(int index) {
    return '${widget.account.derivationPath}/0/$index';
  }

  Future<void> _generateNextAddress({bool showMessage = true}) async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
    });
    try {
      final newAddress = await widget.onGenerateNextAddress();
      setState(() {
        _addresses.add(newAddress);
        _initialized = true;
      });
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New address generated')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialized = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate address: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }
}

