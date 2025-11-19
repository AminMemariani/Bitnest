import 'package:bitnest/models/account.dart';
import 'package:bitnest/models/transaction.dart';
import 'package:bitnest/providers/network_provider.dart';
import 'package:bitnest/providers/transactions_provider.dart';
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/ui/screens/transaction_detail_screen.dart';
import 'package:bitnest/ui/screens/transactions_screen.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late MockApiService mockApi;
  late Account account;
  late Transaction transaction;

  setUp(() {
    mockApi = MockApiService();
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
      txid: 'tx_sample',
      version: 1,
      locktime: 0,
      inputs: [
        TxInput(
          txid: 'prev',
          vout: 0,
          value: BigInt.from(150000),
          address: 'addr1',
        ),
      ],
      outputs: [
        TxOutput(
          index: 0,
          value: BigInt.from(100000),
          scriptPubKey: '',
          address: 'external',
        ),
      ],
      blockHeight: 1,
      blockTime: DateTime(2024, 10, 2, 12),
      confirmations: 1,
      fee: BigInt.from(500),
    );

    mockApi.setAddressTransactions('addr1', [transaction]);
    mockApi.setTransaction('tx_sample', transaction);
  });

  Widget _buildTestApp(TransactionsProvider provider, Account account) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => provider),
        ChangeNotifierProvider(create: (_) => NetworkProvider()),
      ],
      child: MaterialApp(
        home: TransactionsScreen(account: account),
        routes: {
          '/detail': (_) => TransactionDetailScreen(
                transaction: transaction,
                account: account,
              ),
        },
      ),
    );
  }

  testWidgets('TransactionsScreen loads and displays transactions', (tester) async {
    final provider = TransactionsProvider(apiService: mockApi);
    await tester.pumpWidget(_buildTestApp(provider, account));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transaction_tile_tx_sample')), findsOneWidget);

    await tester.tap(find.byKey(const Key('transaction_tile_tx_sample')));
    await tester.pumpAndSettle();

    expect(find.text('Transaction Details'), findsOneWidget);
  });

  testWidgets('TransactionsScreen shows empty state', (tester) async {
    final emptyAccount = account.copyWith(addresses: []);
    final provider = TransactionsProvider(apiService: mockApi);
    await tester.pumpWidget(_buildTestApp(provider, emptyAccount));
    await tester.pumpAndSettle();

    expect(find.text('No transactions yet'), findsOneWidget);
  });
}

