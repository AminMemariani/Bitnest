import 'package:bitnest/models/account.dart';
import 'package:bitnest/models/transaction.dart';
import 'package:bitnest/ui/widgets/transaction_list.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final account = Account(
    walletId: 'wallet-1',
    label: 'Primary',
    derivationPath: "m/84'/0'/0'",
    accountIndex: 0,
    xpub: 'xpub-test',
    network: BitcoinNetwork.mainnet,
    addresses: ['addr1', 'addr2'],
  );

  Transaction buildTransaction({
    required String txid,
    required BigInt inputValue,
    required BigInt outputValue,
    DateTime? time,
  }) {
    return Transaction(
      txid: txid,
      version: 1,
      locktime: 0,
      inputs: [
        TxInput(
          txid: 'prev',
          vout: 0,
          value: inputValue,
          address: 'addr1',
        ),
      ],
      outputs: [
        TxOutput(
          index: 0,
          value: outputValue,
          scriptPubKey: '',
          address: 'addr2',
        ),
      ],
      blockHeight: 1,
      blockTime: time ?? DateTime.now(),
      confirmations: 2,
      fee: BigInt.from(100),
    );
  }

  testWidgets('TransactionList groups and displays transactions',
      (tester) async {
    final transactions = [
      buildTransaction(
        txid: 'tx1',
        inputValue: BigInt.from(200000),
        outputValue: BigInt.from(150000),
        time: DateTime(2024, 10, 2, 12),
      ),
      buildTransaction(
        txid: 'tx2',
        inputValue: BigInt.from(100000),
        outputValue: BigInt.from(120000),
        time: DateTime(2024, 10, 3, 9),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionList(
            transactions: transactions,
            account: account,
            onTransactionTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('October'), findsWidgets);
    expect(find.byType(Card), findsWidgets);
  });

  testWidgets('TransactionList invokes callback on tap', (tester) async {
    bool tapped = false;
    final tx = buildTransaction(
      txid: 'tap_tx',
      inputValue: BigInt.from(100000),
      outputValue: BigInt.from(150000),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionList(
            transactions: [tx],
            account: account,
            onTransactionTap: (_) {
              tapped = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('transaction_tile_tap_tx')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
