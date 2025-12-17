import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/account.dart';
import '../../models/transaction.dart';

typedef TransactionTapCallback = void Function(Transaction transaction);

/// Displays a grouped list of transactions for an account.
class TransactionList extends StatelessWidget {
  final List<Transaction> transactions;
  final Account account;
  final TransactionTapCallback? onTransactionTap;

  const TransactionList({
    super.key,
    required this.transactions,
    required this.account,
    this.onTransactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _groupTransactions(transactions);
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    for (final group in groups) {
      children.add(_buildDateHeader(context, group.date));
      children.addAll(
        group.transactions.map(
          (tx) => _TransactionTile(
            key: Key('transaction_tile_${tx.txid}'),
            transaction: tx,
            account: account,
            onTap: () => onTransactionTap?.call(tx),
          ),
        ),
      );
    }

    return Scrollbar(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: children,
      ),
    );
  }

  Widget _buildDateHeader(BuildContext context, DateTime date) {
    final formatted = DateFormat.yMMMMd().format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        formatted,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  List<_TransactionGroup> _groupTransactions(List<Transaction> txs) {
    final map = <DateTime, List<Transaction>>{};
    for (final tx in txs) {
      final ts = tx.blockTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final key = DateTime(ts.year, ts.month, ts.day);
      map.putIfAbsent(key, () => []).add(tx);
    }

    final groups = map.entries
        .map(
          (entry) => _TransactionGroup(
            date: entry.key,
            transactions: entry.value
              ..sort(
                (a, b) => _txTimestamp(b).compareTo(_txTimestamp(a)),
              ),
          ),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return groups;
  }

  DateTime _txTimestamp(Transaction tx) {
    return tx.blockTime ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _TransactionGroup {
  final DateTime date;
  final List<Transaction> transactions;

  _TransactionGroup({
    required this.date,
    required this.transactions,
  });
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final Account account;
  final VoidCallback? onTap;

  const _TransactionTile({
    super.key,
    required this.transaction,
    required this.account,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = _TransactionMeta.fromTransaction(transaction, account);

    final indicatorColor =
        meta.isIncoming ? theme.colorScheme.primary : theme.colorScheme.error;

    final subtitle = Text(
      '${meta.statusLabel} • ${meta.confirmationsLabel}',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: meta.statusColor(theme.colorScheme),
      ),
    );

    final leadingIcon = Icon(
      meta.directionIcon(theme.platform),
      color: indicatorColor,
    );

    final trailingText = Text(
      meta.formattedAmount,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: indicatorColor,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Theme.of(context).platform == TargetPlatform.iOS ||
              Theme.of(context).platform == TargetPlatform.macOS
          ? CupertinoListTile(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: leadingIcon,
              title: Text(meta.title),
              subtitle: subtitle,
              additionalInfo: trailingText,
              onTap: onTap,
            )
          : Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: leadingIcon,
                title: Text(meta.title),
                subtitle: subtitle,
                trailing: trailingText,
                onTap: onTap,
              ),
            ),
    );
  }
}

class _TransactionMeta {
  final bool isIncoming;
  final BigInt netAmount;
  final int confirmations;
  final DateTime timestamp;

  _TransactionMeta({
    required this.isIncoming,
    required this.netAmount,
    required this.confirmations,
    required this.timestamp,
  });

  factory _TransactionMeta.fromTransaction(
    Transaction tx,
    Account account,
  ) {
    final addressSet = account.addresses.toSet();
    final received = tx.outputs
        .where((output) =>
            output.address != null && addressSet.contains(output.address))
        .fold<BigInt>(BigInt.zero, (sum, output) => sum + output.value);
    final spent = tx.inputs
        .where((input) =>
            input.address != null && addressSet.contains(input.address))
        .fold<BigInt>(BigInt.zero, (sum, input) => sum + input.value);

    final net = received - spent;
    return _TransactionMeta(
      isIncoming: net >= BigInt.zero,
      netAmount: net == BigInt.zero ? received : net,
      confirmations: tx.confirmations,
      timestamp: tx.blockTime ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String get title => isIncoming ? 'Received' : 'Sent';

  String get statusLabel {
    if (confirmations <= 0) {
      return 'Pending';
    }
    if (confirmations == 1) {
      return '1 confirmation';
    }
    if (confirmations >= 6) {
      return 'Finalized';
    }
    return '$confirmations confirmations';
  }

  String get confirmationsLabel {
    final formattedDate = DateFormat.Hm().format(timestamp);
    return formattedDate;
  }

  String get formattedAmount {
    final absolute = netAmount.abs();
    final sign = netAmount.isNegative ? '-' : '+';
    final value = _formatSats(absolute);
    return '$sign$value BTC';
  }

  IconData directionIcon(TargetPlatform platform) {
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return isIncoming
          ? CupertinoIcons.arrow_down_left
          : CupertinoIcons.arrow_up_right;
    }
    return isIncoming ? Icons.call_received : Icons.call_made;
  }

  Color statusColor(ColorScheme scheme) {
    if (confirmations <= 0) {
      return scheme.tertiary;
    }
    if (confirmations >= 6) {
      return scheme.secondary;
    }
    return scheme.primary;
  }

  String _formatSats(BigInt value) {
    final padded = value.toString().padLeft(9, '0');
    final integerPart = padded.substring(0, padded.length - 8);
    final decimalPart = padded.substring(padded.length - 8);
    final trimmedInteger = integerPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return '${trimmedInteger.isEmpty ? '0' : trimmedInteger}.$decimalPart';
  }
}
