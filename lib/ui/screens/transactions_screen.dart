import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/account.dart';
import '../../models/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../widgets/transaction_list.dart';
import 'transaction_detail_screen.dart';

class TransactionsScreen extends StatefulWidget {
  final Account account;

  const TransactionsScreen({super.key, required this.account});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTransactions(force: true);
    });
  }

  Future<void> _refreshTransactions({bool force = false}) async {
    final provider = context.read<TransactionsProvider>();
    await provider.refreshTransactions(widget.account, force: force);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.account.label} Transactions'),
      ),
      body: Consumer<TransactionsProvider>(
        builder: (context, provider, _) {
          final transactions = provider.transactionsForAccount(widget.account.id);
          final isLoading = provider.isRefreshing(widget.account.id);
          final error = provider.error;

          Widget content;
          if (transactions.isEmpty && !isLoading) {
            content = _EmptyTransactionsState(
              error: error,
              onRetry: () => _refreshTransactions(force: true),
            );
          } else {
            content = TransactionList(
              transactions: transactions,
              account: widget.account,
              onTransactionTap: (transaction) => _openDetails(transaction),
            );
          }

          return RefreshIndicator.adaptive(
            onRefresh: () => _refreshTransactions(force: true),
            child: Stack(
              children: [
                Positioned.fill(child: content),
                if (isLoading)
                  const Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openDetails(Transaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionDetailScreen(
          transaction: transaction,
          account: widget.account,
        ),
      ),
    );
  }
}

class _EmptyTransactionsState extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;

  const _EmptyTransactionsState({
    this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final message = error ?? 'No transactions yet';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.3,
        ),
        Icon(
          Icons.history,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          child: FilledButton(
            onPressed: onRetry,
            child: const Text('Refresh'),
          ),
        ),
      ],
    );
  }
}

