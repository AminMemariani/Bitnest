import 'package:bitnest/models/account.dart';
import 'package:bitnest/ui/screens/receive_screen.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return {'text': null};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Account buildAccount({
    List<String>? addresses,
    String label = 'Primary Account',
  }) {
    return Account(
      walletId: 'wallet1',
      label: label,
      derivationPath: "m/84'/0'/0'",
      accountIndex: 0,
      xpub: 'xpub_test',
      network: BitcoinNetwork.mainnet,
      addresses: addresses,
    );
  }

  testWidgets('ReceiveScreen displays current address and QR code', (tester) async {
    final account = buildAccount(addresses: ['bc1qsomething']);

    await tester.pumpWidget(
      MaterialApp(
        home: ReceiveScreen(
          account: account,
          onGenerateNextAddress: () async => 'bc1qnew',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('bc1qsomething'), findsWidgets);
    expect(find.text("Derivation Path: m/84'/0'/0'"), findsOneWidget);
    expect(find.text("Derivation: m/84'/0'/0'/0/0"), findsOneWidget);
  });

  testWidgets('ReceiveScreen copies address to clipboard', (tester) async {
    final account = buildAccount(addresses: ['bc1qcopy']);
    var copied = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ReceiveScreen(
          account: account,
          onGenerateNextAddress: () async => 'bc1qnew',
          onCopy: () => copied = true,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('copy_address_button')));

    await tester.tap(find.byKey(const Key('copy_address_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(copied, isTrue);
  });

  testWidgets('ReceiveScreen generates new address', (tester) async {
    final account = buildAccount(addresses: ['bc1qinitial']);
    int counter = 0;
    Future<String> generateAddress() async {
      counter++;
      return 'bc1qgenerated$counter';
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ReceiveScreen(
          account: account,
          onGenerateNextAddress: generateAddress,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(counter, 0);
    expect(find.text('bc1qinitial'), findsWidgets);
    final keyFinder = find.byKey(const Key('generate_address_button'));
    final listFinder = find.byType(ListView);

    for (var i = 0; i < 5 && keyFinder.evaluate().isEmpty; i++) {
      await tester.drag(listFinder, const Offset(0, -200));
      await tester.pumpAndSettle();
    }

    expect(keyFinder, findsOneWidget);

    // Generate another address
    await tester.tap(keyFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(counter, 1);
    expect(find.text('bc1qgenerated1'), findsWidgets);
  });
}

