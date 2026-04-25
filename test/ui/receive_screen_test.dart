import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/models/account.dart';
import 'package:bitnest/repositories/wallet_repository.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/ui/screens/receive_screen.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

HdWalletService _makeHd() {
  final seed = Uint8List.fromList(bip39.mnemonicToSeed(_mnemonic));
  return HdWalletService.fromSeed(
    keyService: KeyService(),
    seed: seed,
    network: BitcoinNetwork.mainnet,
  );
}

Account _account() => Account(
      walletId: 'w1',
      label: 'Primary Account',
      derivationPath: "m/84'/0'/0'",
      accountIndex: 0,
      xpub: 'xpub-unused',
      network: BitcoinNetwork.mainnet,
    );

Future<WalletRepository> _freshRepo() async {
  final prefs = await SharedPreferences.getInstance();
  return WalletRepository.load(
    accountId: 'acct-ui',
    hd: _makeHd(),
    prefs: prefs,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: child);

/// Make the test surface tall enough that the ReceiveScreen's ListView
/// renders every card — including the "Generate New Address" button — in
/// the widget tree from the first frame. Saves each test from scrolling.
void _useTallSurface(WidgetTester t) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(800, 2400);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      if (call.method == 'Clipboard.getData') return {'text': null};
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ReceiveScreen — current address from repository', () {
    testWidgets("renders the repo's current receiving address", (t) async {
      _useTallSurface(t);
      final repo = await _freshRepo();
      final expected = await repo.getCurrentReceivingAddress();

      await t.pumpWidget(
        _wrap(ReceiveScreen(account: _account(), repository: repo)),
      );
      await t.pumpAndSettle();

      expect(find.byKey(const Key('current_address_text')), findsOneWidget);
      expect(find.text(expected), findsWidgets);
    });

    testWidgets('QR rebinds to the new address on rotation', (t) async {
      _useTallSurface(t);
      final repo = await _freshRepo();
      final addr0 = await repo.getCurrentReceivingAddress();

      await t.pumpWidget(
        _wrap(ReceiveScreen(account: _account(), repository: repo)),
      );
      await t.pumpAndSettle();

      // The receive screen keys its QrImageView `ValueKey('qr_$address')`
      // — finding by that exact key is the cleanest assertion that the
      // widget is bound to the expected address.
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(ValueKey('qr_$addr0')), findsOneWidget);

      // Externally rotate (as would happen on a successful outgoing tx).
      await repo.onOutgoingTransactionSuccess(idempotencyKey: 'test-tx');
      await t.pumpAndSettle();

      final addr1 = await repo.getCurrentReceivingAddress();
      expect(addr1, isNot(equals(addr0)));

      expect(find.byKey(ValueKey('qr_$addr0')), findsNothing,
          reason: 'old QR widget should be discarded');
      expect(find.byKey(ValueKey('qr_$addr1')), findsOneWidget,
          reason: 'QR must rebind to the new current receiving address');
    });
  });

  group('ReceiveScreen — Generate New Address', () {
    testWidgets('rotates forward when the gap is small', (t) async {
      _useTallSurface(t);
      final repo = await _freshRepo();
      final before = await repo.getCurrentReceivingAddress();

      await t.pumpWidget(
        _wrap(ReceiveScreen(account: _account(), repository: repo)),
      );
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('generate_address_button')));
      await t.pumpAndSettle();

      final after = await repo.getCurrentReceivingAddress();
      expect(after, isNot(equals(before)));
      expect(repo.currentReceivingIndex, 1);
    });

    testWidgets(
        'shows the "excessive generation" warning once the unused gap '
        'reaches the threshold, and cancelling does NOT rotate further',
        (t) async {
      _useTallSurface(t);
      final repo = await _freshRepo();
      // Push the unused-gap to exactly the warn threshold.
      for (var i = 0; i < kUnusedAddressWarnThreshold; i++) {
        await repo.generateNextReceivingAddress();
      }
      final indexBefore = repo.currentReceivingIndex;
      expect(indexBefore, kUnusedAddressWarnThreshold);

      await t.pumpWidget(
        _wrap(ReceiveScreen(account: _account(), repository: repo)),
      );
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('generate_address_button')));
      await t.pumpAndSettle();

      expect(
          find.byKey(const Key('excessive_generation_dialog')), findsOneWidget);

      await t.tap(find.byKey(const Key('excessive_generation_cancel')));
      await t.pumpAndSettle();

      expect(repo.currentReceivingIndex, indexBefore,
          reason: 'cancelling must not rotate');
    });

    testWidgets('confirming the warning proceeds with rotation', (t) async {
      _useTallSurface(t);
      final repo = await _freshRepo();
      for (var i = 0; i < kUnusedAddressWarnThreshold; i++) {
        await repo.generateNextReceivingAddress();
      }
      final before = repo.currentReceivingIndex;

      await t.pumpWidget(
        _wrap(ReceiveScreen(account: _account(), repository: repo)),
      );
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('generate_address_button')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('excessive_generation_confirm')));
      await t.pumpAndSettle();

      expect(repo.currentReceivingIndex, before + 1);
    });
  });

  group('ReceiveScreen — reactive to outgoing transactions', () {
    testWidgets(
        'the displayed address changes after repo.onOutgoingTransactionSuccess',
        (t) async {
      _useTallSurface(t);
      final repo = await _freshRepo();
      final addr0 = await repo.getCurrentReceivingAddress();

      await t.pumpWidget(
        _wrap(ReceiveScreen(account: _account(), repository: repo)),
      );
      await t.pumpAndSettle();
      expect(find.text(addr0), findsWidgets);

      await repo.onOutgoingTransactionSuccess(idempotencyKey: 'tx-42');
      await t.pumpAndSettle();

      final addr1 = await repo.getCurrentReceivingAddress();
      expect(find.text(addr1), findsWidgets,
          reason: 'UI must swap to the new index without a manual refresh');
      expect(find.text(addr0), findsNothing);
    });
  });
}
