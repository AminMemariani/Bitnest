import 'package:bitnest/models/account.dart';
import 'package:bitnest/models/transaction.dart';
import 'package:bitnest/providers/network_provider.dart';
import 'package:bitnest/providers/transactions_provider.dart';
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/ui/screens/transaction_detail_screen.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Account account;
  late Transaction transaction;
  late MockApiService mockApi;

  setUp(() {
    account = Account(
      walletId: 'wallet-1',
      label: 'Primary',
      derivationPath: "m/84'/0'/0'",
      accountIndex: 0,
      xpub: 'xpub-test',
      network: BitcoinNetwork.mainnet,
      addresses: ['addr1'],
    );

    transaction = Transaction(
      txid: 'tx_detail',
      version: 1,
      locktime: 0,
      inputs: [
        TxInput(
          txid: 'prev',
          vout: 0,
          value: BigInt.from(150000),
          address: 'external',
        ),
      ],
      outputs: [
        TxOutput(
          index: 0,
          value: BigInt.from(100000),
          scriptPubKey: '',
          address: 'addr1',
        ),
      ],
      blockHeight: 1,
      blockTime: DateTime(2024, 10, 2, 12),
      confirmations: 3,
      fee: BigInt.from(500),
    );

    mockApi = MockApiService();
    mockApi.setTransaction('tx_detail', transaction);
  });

  Widget _buildDetailScreen({String? initialHex}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NetworkProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => TransactionsProvider(apiService: mockApi),
        ),
      ],
      child: MaterialApp(
        home: TransactionDetailScreen(
          transaction: transaction,
          account: account,
          initialHex: initialHex,
        ),
      ),
    );
  }

  testWidgets('TransactionDetailScreen shows summary and hex', (tester) async {
    await tester.pumpWidget(_buildDetailScreen(initialHex: 'deadbeef'));

    expect(find.text('Transaction Details'), findsOneWidget);
    expect(find.text('Incoming Transaction'), findsOneWidget);
    expect(find.text('Raw Transaction Hex'), findsOneWidget);
    final selectableFinder = find.byType(SelectableText);
    expect(selectableFinder, findsWidgets);
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Outputs'), findsOneWidget);
  });

  testWidgets('TransactionDetailScreen loads hex when not provided',
      (tester) async {
    await tester.pumpWidget(_buildDetailScreen());
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsWidgets);
  });
}
