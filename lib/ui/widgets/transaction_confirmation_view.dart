import 'package:flutter/material.dart';

import '../../services/tx_builder_service.dart';

/// Pre-broadcast confirmation card for a built [UnsignedTransaction].
///
/// Shows the four fields the user must verify before authorising:
///
///   * recipient
///   * amount (sats)
///   * network fee (sats)
///   * change amount — only when the tx has a change output
///
/// The **change address** is never shown by default. It sits inside an
/// expandable "Advanced details" section — privacy-conscious users can open
/// it to inspect the change path, but a first-time sender doesn't have to
/// see another `bc1q…` string and wonder what it is.
class TransactionConfirmationView extends StatelessWidget {
  final UnsignedTransaction unsigned;

  /// Optional callback for the "Confirm" button. If null, no button is
  /// rendered — the widget just displays the summary.
  final VoidCallback? onConfirm;

  /// Optional callback for a "Cancel" action. If null, no cancel button.
  final VoidCallback? onCancel;

  const TransactionConfirmationView({
    super.key,
    required this.unsigned,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final recipient = unsigned.recipientOutput;
    final change = unsigned.changeOutput;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confirm transaction',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _ConfirmRow(
                  key: const Key('confirm_row_recipient'),
                  label: 'Recipient',
                  value: recipient.address,
                  monospace: true,
                ),
                const SizedBox(height: 12),
                _ConfirmRow(
                  key: const Key('confirm_row_amount'),
                  label: 'Amount',
                  value: '${recipient.value} sats',
                ),
                const SizedBox(height: 12),
                _ConfirmRow(
                  key: const Key('confirm_row_fee'),
                  label: 'Network fee',
                  value:
                      '${unsigned.fee} sats (${unsigned.feeRateSatPerVbyte} sat/vB × ${unsigned.estimatedVbytes} vB)',
                ),
                if (change != null) ...[
                  const SizedBox(height: 12),
                  _ConfirmRow(
                    key: const Key('confirm_row_change_amount'),
                    label: 'Change amount',
                    value: '${change.value} sats',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (change != null)
          _AdvancedDetails(
            unsigned: unsigned,
          ),
        if (onConfirm != null || onCancel != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (onCancel != null)
                Expanded(
                  child: OutlinedButton(
                    key: const Key('confirm_cancel_button'),
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
              if (onCancel != null && onConfirm != null)
                const SizedBox(width: 12),
              if (onConfirm != null)
                Expanded(
                  child: ElevatedButton(
                    key: const Key('confirm_send_button'),
                    onPressed: onConfirm,
                    child: const Text('Confirm & send'),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const _ConfirmRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final valueStyle = monospace
        ? const TextStyle(fontFamily: 'monospace', fontSize: 14)
        : Theme.of(context).textTheme.bodyMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 2),
        SelectableText(value, style: valueStyle),
      ],
    );
  }
}

/// Expandable "Advanced details" block. The change address lives here,
/// and only here — keeping it out of the default view.
class _AdvancedDetails extends StatelessWidget {
  final UnsignedTransaction unsigned;
  const _AdvancedDetails({required this.unsigned});

  @override
  Widget build(BuildContext context) {
    final change = unsigned.changeOutput;
    if (change == null) return const SizedBox.shrink();

    return Card(
      key: const Key('confirm_advanced_card'),
      child: Theme(
        // Avoid the ExpansionTile's default divider so the card looks clean.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('confirm_advanced_tile'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Text('Advanced details'),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConfirmRow(
                  key: const Key('confirm_row_change_address'),
                  label: 'Change address',
                  value: change.address,
                  monospace: true,
                ),
                const SizedBox(height: 12),
                _ConfirmRow(
                  label: 'Inputs',
                  value: '${unsigned.inputs.length} UTXO'
                      '${unsigned.inputs.length == 1 ? '' : 's'}',
                ),
                const SizedBox(height: 12),
                _ConfirmRow(
                  label: 'Locktime',
                  value: unsigned.lockTime.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
