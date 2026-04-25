import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/repositories/wallet_repository.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deterministic BIP39 test vector from the BIP39 spec.
const _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// Builds a fresh repository backed by an in-memory SharedPreferences and
/// a real HD service seeded from [_testMnemonic].
Future<({WalletRepository repo, HdWalletService hd})> _makeRepo({
  String accountId = 'acct-1',
  BitcoinNetwork network = BitcoinNetwork.mainnet,
}) async {
  final seed = Uint8List.fromList(bip39.mnemonicToSeed(_testMnemonic));
  final hd = HdWalletService.fromSeed(
    keyService: KeyService(),
    seed: seed,
    network: network,
  );
  final prefs = await SharedPreferences.getInstance();
  final repo = await WalletRepository.load(
    accountId: accountId,
    hd: hd,
    prefs: prefs,
  );
  return (repo: repo, hd: hd);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fresh, empty SharedPreferences for every test.
    SharedPreferences.setMockInitialValues({});
  });

  group('WalletRepository — index increments', () {
    test('currentReceivingIndex starts at 0 and advances on generateNext',
        () async {
      final (:repo, hd: _) = await _makeRepo();

      expect(repo.currentReceivingIndex, 0);

      await repo.generateNextReceivingAddress();
      expect(repo.currentReceivingIndex, 1);

      await repo.generateNextReceivingAddress();
      expect(repo.currentReceivingIndex, 2);
    });

    test('getFreshChangeAddress advances currentChangeIndex by one per call',
        () async {
      final (:repo, hd: _) = await _makeRepo();

      expect(repo.currentChangeIndex, 0);

      final a = await repo.getFreshChangeAddress();
      expect(repo.currentChangeIndex, 1);
      expect(repo.lastAllocatedChangeIndex, 0);

      final b = await repo.getFreshChangeAddress();
      expect(repo.currentChangeIndex, 2);
      expect(repo.lastAllocatedChangeIndex, 1);

      // Change addresses must never repeat.
      expect(a, isNot(equals(b)));
    });

    test('markReceivingAddressUsed bumps both lastUsed and current pointers',
        () async {
      final (:repo, hd: _) = await _makeRepo();

      await repo.markReceivingAddressUsed(5);

      expect(repo.lastUsedReceivingIndex, 5);
      expect(repo.currentReceivingIndex, 6,
          reason: 'UI must rotate past any index seen on chain');
    });

    test('markChangeAddressUsed bumps both lastUsed and current pointers',
        () async {
      final (:repo, hd: _) = await _makeRepo();

      await repo.markChangeAddressUsed(3);

      expect(repo.lastUsedChangeIndex, 3);
      expect(repo.currentChangeIndex, 4);
    });

    test(
        'onOutgoingTransactionSuccess advances receive and promotes change '
        'allocation to lastUsedChangeIndex', () async {
      final (:repo, hd: _) = await _makeRepo();

      await repo.getFreshChangeAddress(); // allocates index 0
      expect(repo.currentChangeIndex, 1);
      expect(repo.lastUsedChangeIndex, -1);

      final receiveBefore = repo.currentReceivingIndex;

      await repo.onOutgoingTransactionSuccess();

      expect(repo.currentReceivingIndex, receiveBefore + 1,
          reason: 'receive pointer rotates for privacy');
      expect(repo.lastUsedChangeIndex, 0,
          reason: 'allocated change index is promoted');
      expect(repo.currentChangeIndex, 1,
          reason: 'no double-advance when getFresh already bumped');
      expect(repo.lastAllocatedChangeIndex, isNull);
    });

    test(
        'onOutgoingTransactionSuccess still advances currentChangeIndex '
        'when no change allocation was made (send-all)', () async {
      final (:repo, hd: _) = await _makeRepo();

      final changeBefore = repo.currentChangeIndex;
      final receiveBefore = repo.currentReceivingIndex;

      await repo.onOutgoingTransactionSuccess();

      expect(repo.currentChangeIndex, changeBefore + 1);
      expect(repo.currentReceivingIndex, receiveBefore + 1);
    });
  });

  group('WalletRepository — deterministic derivation', () {
    test('getCurrentReceivingAddress returns the same address on repeat calls',
        () async {
      final (:repo, hd: _) = await _makeRepo();

      final first = await repo.getCurrentReceivingAddress();
      final second = await repo.getCurrentReceivingAddress();
      final third = await repo.getCurrentReceivingAddress();

      expect(first, equals(second));
      expect(second, equals(third));
      expect(repo.currentReceivingIndex, 0,
          reason: 'reading must not advance the index');
    });

    test('same receive index always derives the same address', () async {
      final (:repo, :hd) = await _makeRepo();

      final a0 = hd.deriveReceivingAddress(0);
      final a0Again = hd.deriveReceivingAddress(0);
      final a7 = hd.deriveReceivingAddress(7);
      final a7Again = hd.deriveReceivingAddress(7);

      expect(a0, equals(a0Again));
      expect(a7, equals(a7Again));
      // And via the repo's generate path.
      expect(await repo.getCurrentReceivingAddress(), equals(a0));
    });

    test('different receive indices derive different addresses', () async {
      final (repo: _, :hd) = await _makeRepo();

      final addresses = {
        for (var i = 0; i < 5; i++) i: hd.deriveReceivingAddress(i),
      };

      // All five must be distinct.
      expect(addresses.values.toSet().length, 5);
    });

    test(
        'receiving chain and change chain produce different addresses at the '
        'same index', () async {
      final (repo: _, :hd) = await _makeRepo();

      for (var i = 0; i < 3; i++) {
        final receive = hd.deriveReceivingAddress(i);
        final change = hd.deriveChangeAddress(i);
        expect(receive, isNot(equals(change)),
            reason: 'chain 0 vs chain 1 at index $i must diverge');
      }
    });

    test('generateNextReceivingAddress returns a different address each time',
        () async {
      final (:repo, hd: _) = await _makeRepo();

      final seen = <String>{};
      for (var i = 0; i < 5; i++) {
        seen.add(await repo.generateNextReceivingAddress());
      }
      expect(seen.length, 5);
    });
  });

  group('WalletRepository — persistence', () {
    test('all four counters survive repository reinstantiation', () async {
      const accountId = 'persistent-acct';

      // First session: mutate all four counters.
      {
        final (:repo, hd: _) = await _makeRepo(accountId: accountId);
        await repo.generateNextReceivingAddress(); // currentReceiving -> 1
        await repo.generateNextReceivingAddress(); // currentReceiving -> 2
        await repo.getFreshChangeAddress(); // currentChange -> 1
        await repo.getFreshChangeAddress(); // currentChange -> 2
        await repo.markReceivingAddressUsed(4); // lastUsedReceiving -> 4,
        // currentReceiving -> 5
        await repo.markChangeAddressUsed(3); // lastUsedChange -> 3,
        // currentChange stays 4 (already > 3)

        expect(repo.currentReceivingIndex, 5);
        expect(repo.currentChangeIndex, 4);
        expect(repo.lastUsedReceivingIndex, 4);
        expect(repo.lastUsedChangeIndex, 3);
      }

      // Second session: load the same accountId from the same prefs.
      {
        final (:repo, hd: _) = await _makeRepo(accountId: accountId);
        expect(repo.currentReceivingIndex, 5);
        expect(repo.currentChangeIndex, 4);
        expect(repo.lastUsedReceivingIndex, 4);
        expect(repo.lastUsedChangeIndex, 3);
      }
    });

    test('clear() wipes persisted state for an account', () async {
      const accountId = 'to-delete';
      final first = await _makeRepo(accountId: accountId);

      await first.repo.generateNextReceivingAddress();
      await first.repo.getFreshChangeAddress();

      await WalletRepository.clear(accountId: accountId);

      final second = await _makeRepo(accountId: accountId);
      expect(second.repo.currentReceivingIndex, 0);
      expect(second.repo.currentChangeIndex, 0);
      expect(second.repo.lastUsedReceivingIndex, -1);
      expect(second.repo.lastUsedChangeIndex, -1);
    });

    test('state is isolated between account IDs', () async {
      final a = await _makeRepo(accountId: 'A');
      final b = await _makeRepo(accountId: 'B');

      await a.repo.generateNextReceivingAddress();
      await a.repo.generateNextReceivingAddress();
      await a.repo.generateNextReceivingAddress();

      // B must not see A's mutations.
      expect(b.repo.currentReceivingIndex, 0);
    });
  });

  group('WalletRepository — argument validation', () {
    test('markReceivingAddressUsed rejects negative indices', () async {
      final (:repo, hd: _) = await _makeRepo();
      expect(() => repo.markReceivingAddressUsed(-1), throwsArgumentError);
    });

    test('markChangeAddressUsed rejects negative indices', () async {
      final (:repo, hd: _) = await _makeRepo();
      expect(() => repo.markChangeAddressUsed(-1), throwsArgumentError);
    });
  });
}
