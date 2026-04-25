import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/account.dart';
import '../../repositories/wallet_repository.dart';
import '../../utils/networks.dart';

/// Soft cap on how many unused receive addresses the user may accumulate
/// past the last on-chain usage before the UI pushes back. BIP44's hard
/// gap-limit is 20; we warn earlier so the user doesn't silently wander
/// past a point where other wallets (and our own scanner) can still find
/// their coins on recovery.
const int kUnusedAddressWarnThreshold = 5;

/// Receive screen bound to the wallet's [WalletRepository].
///
/// The current receive address is whatever `repository.getCurrentReceivingAddress()`
/// says it is — which means:
///
///   * The screen auto-refreshes after an outgoing transaction (the
///     repo advances `currentReceivingIndex` and the UI is a listener).
///   * The QR code always encodes the same string the address card
///     displays — one source of truth, no drift.
///   * "Generate new address" is a real rotation call, not a local list
///     append.
///
/// `WalletRepository` is passed in explicitly rather than looked up from
/// a Provider so this screen stays testable without a full app scaffold.
class ReceiveScreen extends StatefulWidget {
  final Account account;
  final WalletRepository repository;
  final VoidCallback? onCopy;

  const ReceiveScreen({
    super.key,
    required this.account,
    required this.repository,
    this.onCopy,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive Bitcoin')),
      body: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) => FutureBuilder<String>(
          future: widget.repository.getCurrentReceivingAddress(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final address = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildAccountInfoCard(context),
                const SizedBox(height: 16),
                _buildQrCard(context, address),
                const SizedBox(height: 16),
                _buildAddressDetails(context, address),
                const SizedBox(height: 16),
                _buildActions(context),
                const SizedBox(height: 8),
                _buildRotationStatus(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAccountInfoCard(BuildContext context) {
    final account = widget.account;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Derivation Path: ${account.derivationPath}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Network: ${account.network == BitcoinNetwork.mainnet ? 'Mainnet' : 'Testnet'}',
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
            // Keyed by address so Flutter treats a rotated address as a
            // brand-new widget — the QR cleanly rebuilds on rotation.
            QrImageView(
              key: ValueKey('qr_$address'),
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
              key: const Key('qr_card_address_text'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressDetails(BuildContext context, String address) {
    final repo = widget.repository;
    final derivation =
        '${widget.account.derivationPath}/0/${repo.currentReceivingIndex}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Address',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    address,
                    key: const Key('current_address_text'),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 14),
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
              'Derivation: $derivation',
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
            onPressed: _isGenerating ? null : _onGeneratePressed,
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

  Widget _buildRotationStatus(BuildContext context) {
    final repo = widget.repository;
    final unusedGap = _unusedGap(repo);
    if (unusedGap <= 0) return const SizedBox.shrink();

    final warning = unusedGap >= kUnusedAddressWarnThreshold;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: warning
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        warning
            ? '$unusedGap unused addresses ahead of your last on-chain one — '
                'consider receiving at one of them before generating more.'
            : '$unusedGap unused address${unusedGap == 1 ? '' : 'es'} after your last used index.',
        key: const Key('rotation_status_text'),
        style: style,
      ),
    );
  }

  // ---- actions ----

  Future<void> _onGeneratePressed() async {
    final repo = widget.repository;
    final gap = _unusedGap(repo);
    if (gap >= kUnusedAddressWarnThreshold) {
      final confirmed = await _showGenerationWarning(gap);
      if (confirmed != true) return;
    }
    await _generate();
  }

  Future<bool?> _showGenerationWarning(int currentGap) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('excessive_generation_dialog'),
        title: const Text('Generate another unused address?'),
        content: Text(
          'You already have $currentGap unused receiving addresses past '
          'your last on-chain one. Creating more widens the gap that '
          'wallet-recovery tools need to scan — most of them stop at 20. '
          'Consider receiving at an existing address first.',
        ),
        actions: [
          TextButton(
            key: const Key('excessive_generation_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('excessive_generation_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Generate anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);
    try {
      await widget.repository.generateNextReceivingAddress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New address generated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate address: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  int _unusedGap(WalletRepository repo) {
    // How far past the last on-chain usage the UI-facing index sits.
    // A freshly-loaded wallet with no history has current=0, lastUsed=-1,
    // so the gap is 0 — nothing to warn about.
    return repo.currentReceivingIndex - (repo.lastUsedReceivingIndex + 1);
  }
}
