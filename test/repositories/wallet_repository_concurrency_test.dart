import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/repositories/wallet_repository.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

Future<({WalletRepository repo, HdWalletService hd})> _makeRepo() async {
  final seed = Uint8List.fromList(bip39.mnemonicToSeed(_testMnemonic));
  final hd = HdWalletService.fromSeed(
    keyService: KeyService(),
    seed: seed,
    network: BitcoinNetwork.mainnet,
  );
  final prefs = await SharedPreferences.getInstance();
  final repo = await WalletRepository.load(
    accountId: 'concurrency-acct',
    hd: hd,
    prefs: prefs,
  );
  return (repo: repo, hd: hd);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WalletRepository — outstanding change allocations', () {
    test(
        'allocateFreshChange returns the BIP32 index alongside the address, '
        'and matches the receiving-side derivation', () async {
      final (:repo, :hd) = await _makeRepo();

      final a = await repo.allocateFreshChange();
      expect(a.index, 0);
      expect(a.address, hd.deriveChangeAddress(0));

      final b = await repo.allocateFreshChange();
      expect(b.index, 1);
      expect(b.address, hd.deriveChangeAddress(1));
      expect(b.address, isNot(equals(a.address)));
    });

    test(
        'getFreshChangeAddress and allocateFreshChange share the same '
        'allocation pool', () async {
      final (:repo, hd: _) = await _makeRepo();

      final addr0 = await repo.getFreshChangeAddress();
      final allocation = await repo.allocateFreshChange();
      expect(repo.outstandingChangeAllocations, {0, 1});
      expect(allocation.index, 1);
      // back-compat getter returns the highest outstanding.
      expect(repo.lastAllocatedChangeIndex, 1);
      expect(addr0, isNotEmpty);
    });

    test(
        'two parallel allocations promote independently when the pipeline '
        'passes the precise changeIndex on success — the older allocation '
        'completing first does NOT discard the newer one', () async {
      final (:repo, hd: _) = await _makeRepo();

      // Two flows allocate concurrently. They get distinct indices
      // because allocateFreshChange advances synchronously.
      final flowA = await repo.allocateFreshChange(); // index 0
      final flowB = await repo.allocateFreshChange(); // index 1

      expect(repo.outstandingChangeAllocations, {0, 1});
      expect(repo.currentChangeIndex, 2);
      expect(repo.lastUsedChangeIndex, -1);

      // Flow A broadcasts FIRST. The pipeline knows its precise
      // change index because the builder recorded it on the
      // UnsignedTransaction.
      await repo.onOutgoingTransactionSuccess(
        idempotencyKey: 'tx-A',
        changeIndex: flowA.index,
      );
      expect(repo.lastUsedChangeIndex, 0);
      expect(repo.outstandingChangeAllocations, {1},
          reason: 'flow B\'s allocation must remain outstanding');

      // Flow B broadcasts AFTER. Its allocation is still tracked and
      // gets promoted on its own success — no silent drop.
      await repo.onOutgoingTransactionSuccess(
        idempotencyKey: 'tx-B',
        changeIndex: flowB.index,
      );
      expect(repo.lastUsedChangeIndex, 1);
      expect(repo.outstandingChangeAllocations, isEmpty);
    });

    test(
        'idempotency key blocks a duplicate success call from re-rotating, '
        'even when the change index is repeated', () async {
      final (:repo, hd: _) = await _makeRepo();

      final alloc = await repo.allocateFreshChange();
      final receiveBefore = repo.currentReceivingIndex;

      await repo.onOutgoingTransactionSuccess(
        idempotencyKey: 'tx-X',
        changeIndex: alloc.index,
      );
      expect(repo.lastUsedChangeIndex, 0);
      expect(repo.currentReceivingIndex, receiveBefore + 1);

      // Same txid replayed (e.g. from recoverPending after a torn
      // write). Must be a no-op.
      await repo.onOutgoingTransactionSuccess(
        idempotencyKey: 'tx-X',
        changeIndex: alloc.index,
      );
      expect(repo.lastUsedChangeIndex, 0);
      expect(repo.currentReceivingIndex, receiveBefore + 1);
    });

    test(
        'no-changeIndex back-compat: a single outstanding allocation is '
        'promoted by the highest-outstanding fallback', () async {
      final (:repo, hd: _) = await _makeRepo();

      await repo.allocateFreshChange(); // index 0
      await repo.onOutgoingTransactionSuccess();
      expect(repo.lastUsedChangeIndex, 0);
      expect(repo.outstandingChangeAllocations, isEmpty);
    });

    test(
        'send-all (no change at all) still advances currentChangeIndex by 1, '
        'matching the original behavior', () async {
      final (:repo, hd: _) = await _makeRepo();

      final changeBefore = repo.currentChangeIndex;
      await repo.onOutgoingTransactionSuccess();
      expect(repo.currentChangeIndex, changeBefore + 1);
      expect(repo.outstandingChangeAllocations, isEmpty);
    });

    test(
        'markChangeAddressUsed clears the matching outstanding allocation',
        () async {
      final (:repo, hd: _) = await _makeRepo();

      await repo.allocateFreshChange(); // index 0
      await repo.allocateFreshChange(); // index 1
      expect(repo.outstandingChangeAllocations, {0, 1});

      await repo.markChangeAddressUsed(0);
      expect(repo.outstandingChangeAllocations, {1},
          reason: 'observing index 0 on chain clears its outstanding entry');
    });
  });
}
