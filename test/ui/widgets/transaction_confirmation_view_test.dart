import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/services/tx_builder_service.dart';
import 'package:bitnest/ui/widgets/transaction_confirmation_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _txid32 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _zero20 = '0000000000000000000000000000000000000000';

UTXO _fakeUtxo({int value = 100000, String? txid}) => UTXO(
      txid: txid ?? _txid32,
      vout: 0,
      address: 'bc1q_source',
      value: BigInt.from(value),
      confirmations: 6,
      scriptPubKey: '0014$_zero20',
      derivationPath: "m/84'/0'/0'/0/0",
      addressIndex: 0,
      chainType: ChainType.receiving,
    );

UnsignedTransaction _txWithChange() => UnsignedTransaction(
      inputs: [TxInput(utxo: _fakeUtxo())],
      outputs: [
        TxOutput(
            address: 'bc1qrecipienthook',
            value: BigInt.from(50000),
            isChange: false),
        TxOutput(
            address: 'bc1qchangeaddr',
            value: BigInt.from(48500),
            isChange: true),
      ],
      estimatedVbytes: 141,
      feeRateSatPerVbyte: 10,
      fee: BigInt.from(1410),
    );

UnsignedTransaction _txWithoutChange() => UnsignedTransaction(
      inputs: [TxInput(utxo: _fakeUtxo(value: 10000))],
      outputs: [
        TxOutput(
            address: 'bc1qrecipienthook',
            value: BigInt.from(9890),
            isChange: false),
      ],
      estimatedVbytes: 110,
      feeRateSatPerVbyte: 1,
      fee: BigInt.from(110),
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

void main() {
  group('TransactionConfirmationView — required fields', () {
    testWidgets('shows recipient, amount, network fee, and change amount',
        (t) async {
      await t.pumpWidget(_wrap(
        TransactionConfirmationView(unsigned: _txWithChange()),
      ));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('confirm_row_recipient')), findsOneWidget);
      expect(find.byKey(const Key('confirm_row_amount')), findsOneWidget);
      expect(find.byKey(const Key('confirm_row_fee')), findsOneWidget);
      expect(find.byKey(const Key('confirm_row_change_amount')),
          findsOneWidget);

      expect(find.text('bc1qrecipienthook'), findsOneWidget);
      expect(find.textContaining('50000 sats'), findsOneWidget);
      expect(find.textContaining('48500 sats'), findsOneWidget);
      expect(find.textContaining('1410 sats'), findsOneWidget);
    });

    testWidgets('omits the change-amount row when the tx has no change',
        (t) async {
      await t.pumpWidget(_wrap(
        TransactionConfirmationView(unsigned: _txWithoutChange()),
      ));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('confirm_row_change_amount')),
          findsNothing);
      expect(find.byKey(const Key('confirm_advanced_card')), findsNothing,
          reason:
              'no change ⇒ no advanced block (change address is the only '
              'advanced field today)');
    });
  });

  group('TransactionConfirmationView — change address in advanced only', () {
    testWidgets('change address is NOT visible until the user expands advanced',
        (t) async {
      await t.pumpWidget(_wrap(
        TransactionConfirmationView(unsigned: _txWithChange()),
      ));
      await t.pumpAndSettle();

      // Before expansion: advanced card exists but children are hidden,
      // so the change address text must not be findable.
      expect(find.text('bc1qchangeaddr'), findsNothing,
          reason: 'change address must not leak into the default view');

      expect(find.byKey(const Key('confirm_advanced_card')), findsOneWidget);
      await t.tap(find.byKey(const Key('confirm_advanced_tile')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('confirm_row_change_address')),
          findsOneWidget);
      expect(find.text('bc1qchangeaddr'), findsOneWidget);
    });
  });

  group('TransactionConfirmationView — actions', () {
    testWidgets('renders Confirm/Cancel only when callbacks are provided',
        (t) async {
      await t.pumpWidget(_wrap(
        TransactionConfirmationView(unsigned: _txWithChange()),
      ));
      expect(find.byKey(const Key('confirm_send_button')), findsNothing);
      expect(find.byKey(const Key('confirm_cancel_button')), findsNothing);

      var confirmed = false;
      var cancelled = false;
      await t.pumpWidget(_wrap(
        TransactionConfirmationView(
          unsigned: _txWithChange(),
          onConfirm: () => confirmed = true,
          onCancel: () => cancelled = true,
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm_send_button')));
      expect(confirmed, isTrue);
      await t.tap(find.byKey(const Key('confirm_cancel_button')));
      expect(cancelled, isTrue);
    });
  });
}
