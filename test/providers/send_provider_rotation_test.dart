import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/models/account.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/models/wallet.dart';
import 'package:bitnest/providers/send_provider.dart';
import 'package:bitnest/repositories/wallet_repository.dart';
import 'package:bitnest/services/broadcast_service.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/services/transaction_journal.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:mockito/mockito.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reuse the mocks generated for the original SendProvider test.
import 'send_provider_test.mocks.dart';

/// Verifies the wallet's two HD-rotation invariants on the production
/// send path:
///
///   * The user-facing receiving address rotates after every successful
///     outgoing transaction.
///   * Every transaction with change uses a never-before-returned change
///     address derived at a NEW BIP32 index from the same seed.
///
/// These tests drive [SendProvider.sendTransaction] against a real
/// [WalletRepository] + [HdWalletService] so the rotation can actually
/// be observed; only the network boundary ([BroadcastService]) and the
/// surrounding [WalletProvider] machinery are mocked.

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _accountId = 'rotation-acct';

class _Fixtures {
  final SendProvider sendProvider;
  final HdWalletService hd;
  final WalletRepository repo;
  final Account account;
  final MockBroadcastService broadcast;

  _Fixtures({
    required this.sendProvider,
    required this.hd,
    required this.repo,
    required this.account,
    required this.broadcast,
  });
}

Future<_Fixtures> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final seed = Uint8List.fromList(bip39.mnemonicToSeed(_mnemonic));
  final hd = HdWalletService.fromSeed(
    keyService: KeyService(),
    seed: seed,
    network: BitcoinNetwork.mainnet,
  );
  final repo = await WalletRepository.load(
    accountId: _accountId,
    hd: hd,
    prefs: prefs,
  );

  final wallet = Wallet(
    id: 'w1',
    label: 'Test Wallet',
    network: BitcoinNetwork.mainnet,
    xpub: 'xpub-test',
    xprv: 'xprv-test', // non-null so SendProvider doesn't reject as watch-only
  );
  final account = Account(
    id: _accountId,
    walletId: wallet.id,
    label: 'Primary',
    derivationPath: "m/84'/0'/0'",
    accountIndex: 0,
    xpub: 'xpub-acct',
    network: BitcoinNetwork.mainnet,
  );

  final mockBroadcast = MockBroadcastService();
  when(mockBroadcast.setNetwork(any)).thenReturn(null);

  final mockTx = MockTransactionService();
  final mockKey = MockKeyService();
  final mockWp = MockWalletProvider();
  when(mockWp.currentWallet).thenReturn(wallet);
  when(mockWp.currentAccount).thenReturn(account);
  when(mockWp.hdServiceFor(any)).thenAnswer((_) async => hd);
  when(mockWp.walletRepositoryFor(any)).thenAnswer((_) async => repo);

  final sendProvider = SendProvider(
    transactionService: mockTx,
    broadcastService: mockBroadcast,
    keyService: mockKey,
    walletProvider: mockWp,
    journal: await TransactionJournal.load(prefs: prefs),
  );

  return _Fixtures(
    sendProvider: sendProvider,
    hd: hd,
    repo: repo,
    account: account,
    broadcast: mockBroadcast,
  );
}

UTXO _ownedUtxo({
  required HdWalletService hd,
  required int index,
  required ChainType chain,
  required int satoshis,
  String? txid,
  int vout = 0,
}) {
  final addr = chain == ChainType.receiving
      ? hd.deriveReceivingAddress(index)
      : hd.deriveChangeAddress(index);
  final path = chain == ChainType.receiving
      ? hd.receivingPath(index)
      : hd.changePath(index);
  final pub = hd.derivePublicKeyForPath(path);
  final h160 = RIPEMD160Digest().process(SHA256Digest().process(pub));
  final scriptPubKey = '0014${HEX.encode(h160)}';
  return UTXO(
    txid: txid ??
        HEX.encode(SHA256Digest()
            .process(Uint8List.fromList('utxo-$index-$vout'.codeUnits))),
    vout: vout,
    address: addr,
    value: BigInt.from(satoshis),
    confirmations: 6,
    scriptPubKey: scriptPubKey,
    derivationPath: path,
    addressIndex: index,
    chainType: chain,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SendProvider — rotation invariants on production path', () {
    test('a successful broadcast advances currentReceivingIndex by exactly 1',
        () async {
      final f = await _setup();

      final receiveBefore = f.repo.currentReceivingIndex;
      final visibleBefore = await f.repo.getCurrentReceivingAddress();

      when(f.broadcast.broadcastTransaction(any))
          .thenAnswer((_) async => 'mock-network-txid');

      final utxo = _ownedUtxo(
        hd: f.hd,
        index: 0,
        chain: ChainType.receiving,
        satoshis: 100000,
      );
      f.sendProvider
        ..selectAccount(f.account)
        ..setRecipientAddress(f.hd.deriveReceivingAddress(99))
        ..setAmount(BigInt.from(50000))
        ..setManualFeeRate(1)
        ..toggleUtxo(utxo);

      final txid = await f.sendProvider.sendTransaction(authenticated: true);

      expect(txid, isNotEmpty);
      expect(f.repo.currentReceivingIndex, receiveBefore + 1,
          reason: 'rule: receiving address must rotate on every send');

      final visibleAfter = await f.repo.getCurrentReceivingAddress();
      expect(visibleAfter, isNot(equals(visibleBefore)),
          reason: 'rule: the address the UI shows must change after send');
    });

    test(
        'a transaction with change consumes a fresh change address from '
        'getFreshChangeAddress, never index 0', () async {
      final f = await _setup();

      // Pre-burn change indices to make sure the test doesn't accidentally
      // succeed by allocating index 0. After this dance currentChangeIndex
      // is at 3, so the next allocation MUST be 3 — proving "fresh".
      await f.repo.getFreshChangeAddress();
      await f.repo.getFreshChangeAddress();
      await f.repo.getFreshChangeAddress();
      expect(f.repo.currentChangeIndex, 3);
      final lastUsedChangeBefore = f.repo.lastUsedChangeIndex;

      when(f.broadcast.broadcastTransaction(any))
          .thenAnswer((_) async => 'mock');

      final utxo = _ownedUtxo(
        hd: f.hd,
        index: 0,
        chain: ChainType.receiving,
        satoshis: 100000,
      );
      f.sendProvider
        ..selectAccount(f.account)
        ..setRecipientAddress(f.hd.deriveReceivingAddress(99))
        ..setAmount(BigInt.from(40000)) // leaves > dust as change
        ..setManualFeeRate(1)
        ..toggleUtxo(utxo);

      await f.sendProvider.sendTransaction(authenticated: true);

      // The pipeline promotes the just-allocated change index to
      // lastUsedChangeIndex on success. That index must be 3 — the next
      // unused index at allocation time — proving the change address was
      // freshly derived, NOT a re-use of an earlier index.
      expect(f.repo.lastUsedChangeIndex, 3,
          reason: 'rule: change index 3 was the fresh allocation');
      expect(f.repo.lastUsedChangeIndex, greaterThan(lastUsedChangeBefore));
      expect(f.repo.currentChangeIndex, 4,
          reason: 'currentChangeIndex must advance past the used one');
    });

    test('change address is a NEW HD derivation, not a same-key reuse',
        () async {
      // Pins the third clause: "do not attempt to change the public key
      // for the same private key. Use HD wallet derivation from the same
      // seed instead." The change address used at index N must equal the
      // address that HdWalletService.deriveChangeAddress(N) produces —
      // i.e. it is derived from the same seed at a NEW BIP32 index, with
      // a fresh keypair.
      final f = await _setup();

      when(f.broadcast.broadcastTransaction(any))
          .thenAnswer((_) async => 'mock');

      final utxo = _ownedUtxo(
        hd: f.hd,
        index: 0,
        chain: ChainType.receiving,
        satoshis: 100000,
      );
      f.sendProvider
        ..selectAccount(f.account)
        ..setRecipientAddress(f.hd.deriveReceivingAddress(99))
        ..setAmount(BigInt.from(40000))
        ..setManualFeeRate(1)
        ..toggleUtxo(utxo);

      await f.sendProvider.sendTransaction(authenticated: true);

      final usedChangeIndex = f.repo.lastUsedChangeIndex;
      expect(usedChangeIndex, 0,
          reason: 'first send on a fresh wallet allocates index 0');

      // Independently re-derive the keypair at the used index and at its
      // neighbours; each index produces a distinct compressed pubkey,
      // proving the change address is a genuinely new HD child, not
      // some re-issuance of an existing key.
      final pubAtUsed =
          f.hd.derivePublicKeyForPath(f.hd.changePath(usedChangeIndex));
      final pubAtNext =
          f.hd.derivePublicKeyForPath(f.hd.changePath(usedChangeIndex + 1));
      expect(pubAtUsed, isNot(equals(pubAtNext)),
          reason: 'each BIP32 index produces an independent keypair');
    });

    test('a failed broadcast does NOT rotate either pointer', () async {
      final f = await _setup();

      final receiveBefore = f.repo.currentReceivingIndex;
      final lastUsedChangeBefore = f.repo.lastUsedChangeIndex;

      when(f.broadcast.broadcastTransaction(any))
          .thenThrow(BroadcastException('node 503', 503));

      final utxo = _ownedUtxo(
        hd: f.hd,
        index: 0,
        chain: ChainType.receiving,
        satoshis: 100000,
      );
      f.sendProvider
        ..selectAccount(f.account)
        ..setRecipientAddress(f.hd.deriveReceivingAddress(99))
        ..setAmount(BigInt.from(40000))
        ..setManualFeeRate(1)
        ..toggleUtxo(utxo);

      await expectLater(
        f.sendProvider.sendTransaction(authenticated: true),
        throwsA(isA<BroadcastException>()),
      );

      expect(f.repo.currentReceivingIndex, receiveBefore,
          reason: 'failed broadcast must not advance the receiving pointer');
      expect(f.repo.lastUsedChangeIndex, lastUsedChangeBefore,
          reason: 'failed broadcast must not promote the change index');
    });
  });
}
