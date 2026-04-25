import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:bitnest/models/pending_transaction.dart';
import 'package:bitnest/models/utxo.dart';
import 'package:bitnest/repositories/wallet_repository.dart';
import 'package:bitnest/services/broadcast_service.dart';
import 'package:bitnest/services/hd_wallet_service.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/services/send_pipeline_service.dart';
import 'package:bitnest/services/transaction_journal.dart';
import 'package:bitnest/services/transaction_signer.dart';
import 'package:bitnest/services/tx_builder_service.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'send_pipeline_service_test.mocks.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _accountId = 'acct-1';

HdWalletService _makeHd() {
  final seed = Uint8List.fromList(bip39.mnemonicToSeed(_mnemonic));
  return HdWalletService.fromSeed(
    keyService: KeyService(),
    seed: seed,
    network: BitcoinNetwork.mainnet,
  );
}

Uint8List _hash160(Uint8List data) =>
    RIPEMD160Digest().process(SHA256Digest().process(data));

UTXO _utxoFor({
  required HdWalletService hd,
  required int index,
  required ChainType chain,
  required int satoshis,
  int vout = 0,
  String seed = 'pipeline',
}) {
  final path = chain == ChainType.receiving
      ? hd.receivingPath(index)
      : hd.changePath(index);
  final address = chain == ChainType.receiving
      ? hd.deriveReceivingAddress(index)
      : hd.deriveChangeAddress(index);
  final pub = hd.derivePublicKeyForPath(path);
  final scriptPubKey = Uint8List.fromList([0x00, 0x14, ..._hash160(pub)]);
  final txid = HEX.encode(
    SHA256Digest().process(Uint8List.fromList('$seed:$index:$vout'.codeUnits)),
  );
  return UTXO(
    txid: txid,
    vout: vout,
    address: address,
    value: BigInt.from(satoshis),
    confirmations: 6,
    scriptPubKey: HEX.encode(scriptPubKey),
    derivationPath: path,
    addressIndex: index,
    chainType: chain,
  );
}

Future<UnsignedTransaction> _buildSampleTx({
  required HdWalletService hd,
  required WalletRepository repo,
  required int inputSats,
}) async {
  final utxo = _utxoFor(
    hd: hd,
    index: 0,
    chain: ChainType.receiving,
    satoshis: inputSats,
  );
  final recipient = hd.deriveReceivingAddress(50);
  // Ask the repo to allocate a change address through the official path so
  // lastAllocatedChangeIndex is populated exactly like a real send would.
  final changeAddress = await repo.getFreshChangeAddress();
  final fee = BigInt.from(2000);
  final amount = BigInt.from(20000);
  final change = BigInt.from(inputSats) - amount - fee;
  return UnsignedTransaction(
    inputs: [TxInput(utxo: utxo)],
    outputs: [
      TxOutput(address: recipient, value: amount),
      TxOutput(address: changeAddress, value: change, isChange: true),
    ],
    estimatedVbytes: 141,
    feeRateSatPerVbyte: 15,
    fee: fee,
  );
}

Future<WalletRepository> _freshRepo(SharedPreferences prefs) async {
  return WalletRepository.load(
    accountId: _accountId,
    hd: _makeHd(),
    prefs: prefs,
  );
}

@GenerateMocks([BroadcastService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late TransactionJournal journal;
  late MockBroadcastService broadcast;
  late TransactionSigner signer;
  late HdWalletService hd;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    journal = await TransactionJournal.load(prefs: prefs);
    broadcast = MockBroadcastService();
    when(broadcast.setNetwork(any)).thenReturn(null);
    hd = _makeHd();
    signer = TransactionSigner(hd: hd);
  });

  group('successful broadcast rotates address', () {
    test(
        'receiving index advances and the journal flips to broadcast on '
        'success', () async {
      final repo = await _freshRepo(prefs);
      final unsigned = await _buildSampleTx(
        hd: hd,
        repo: repo,
        inputSats: 100000,
      );
      final txidBefore = signer.computeTxid(unsigned, BitcoinNetwork.mainnet);

      when(broadcast.broadcastTransaction(any))
          .thenAnswer((_) async => txidBefore);

      final receiveBefore = repo.currentReceivingIndex;

      final pipeline = SendPipelineService(
        signer: signer,
        broadcast: broadcast,
        journal: journal,
      );
      final outcome = await pipeline.signAndBroadcast(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
        repository: repo,
        accountId: _accountId,
      );

      expect(outcome.kind, BroadcastOutcomeKind.success);
      expect(outcome.txid, txidBefore);
      expect(repo.currentReceivingIndex, receiveBefore + 1,
          reason: 'UI-facing receiving index must advance on success');
      expect(journal.get(txidBefore)?.state, PendingTxState.broadcast);
      verify(broadcast.broadcastTransaction(any)).called(1);
    });

    test('UI receiving address changes after a successful outgoing tx',
        () async {
      final repo = await _freshRepo(prefs);
      final before = await repo.getCurrentReceivingAddress();

      final unsigned = await _buildSampleTx(
        hd: hd,
        repo: repo,
        inputSats: 100000,
      );
      final txid = signer.computeTxid(unsigned, BitcoinNetwork.mainnet);
      when(broadcast.broadcastTransaction(any)).thenAnswer((_) async => txid);

      final pipeline = SendPipelineService(
        signer: signer,
        broadcast: broadcast,
        journal: journal,
      );
      await pipeline.signAndBroadcast(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
        repository: repo,
        accountId: _accountId,
      );

      final after = await repo.getCurrentReceivingAddress();
      expect(after, isNot(equals(before)),
          reason: 'next receive address must rotate after send');
    });
  });

  group('failed broadcast does not rotate address', () {
    test('pointers unchanged and journal in failed state when broadcast throws',
        () async {
      final repo = await _freshRepo(prefs);
      final unsigned = await _buildSampleTx(
        hd: hd,
        repo: repo,
        inputSats: 100000,
      );
      final txid = signer.computeTxid(unsigned, BitcoinNetwork.mainnet);
      final changeIndexAllocated = repo.lastAllocatedChangeIndex;
      expect(changeIndexAllocated, 0);

      when(broadcast.broadcastTransaction(any))
          .thenThrow(BroadcastException('503 bad gateway', 503));

      final receiveBefore = repo.currentReceivingIndex;
      final changeBefore = repo.currentChangeIndex;
      final lastUsedChangeBefore = repo.lastUsedChangeIndex;

      final pipeline = SendPipelineService(
        signer: signer,
        broadcast: broadcast,
        journal: journal,
      );
      final outcome = await pipeline.signAndBroadcast(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
        repository: repo,
        accountId: _accountId,
      );

      expect(outcome.kind, BroadcastOutcomeKind.failed);
      expect(outcome.txid, txid);
      expect(repo.currentReceivingIndex, receiveBefore);
      expect(repo.currentChangeIndex, changeBefore);
      expect(repo.lastUsedChangeIndex, lastUsedChangeBefore,
          reason: 'no change index should be promoted to used on failure');
      expect(journal.get(txid)?.state, PendingTxState.failed);
      expect(journal.get(txid)?.error, contains('503'));
    });
  });

  group('pending transaction state survives restart', () {
    test(
        'signed record on disk is re-broadcast by recoverPending on next launch',
        () async {
      // First "session" — only signing and journaling, no successful broadcast.
      {
        final repo = await _freshRepo(prefs);
        final unsigned = await _buildSampleTx(
          hd: hd,
          repo: repo,
          inputSats: 100000,
        );
        when(broadcast.broadcastTransaction(any))
            .thenThrow(BroadcastException('connection reset', 0));

        final pipeline = SendPipelineService(
          signer: signer,
          broadcast: broadcast,
          journal: journal,
        );
        final outcome = await pipeline.signAndBroadcast(
          unsigned: unsigned,
          network: BitcoinNetwork.mainnet,
          repository: repo,
          accountId: _accountId,
        );
        expect(outcome.kind, BroadcastOutcomeKind.failed);
        // At this point the journal has a signed-then-failed record. Set it
        // back to signed to mimic "crash after signing, never saw the error".
        await journal.markRetrying(outcome.txid);
        expect(journal.get(outcome.txid)?.state, PendingTxState.signed);
      }

      // --- simulate app restart: rebuild journal from disk ---
      final journal2 = await TransactionJournal.load(prefs: prefs);
      expect(journal2.all().length, 1,
          reason: 'journal must survive restart');
      final pendingRecord = journal2.all().single;
      expect(pendingRecord.state, PendingTxState.signed);

      // Second "session" — the network is healthy now. recoverPending
      // should re-broadcast and rotate.
      final broadcast2 = MockBroadcastService();
      when(broadcast2.setNetwork(any)).thenReturn(null);
      when(broadcast2.broadcastTransaction(any))
          .thenAnswer((_) async => pendingRecord.txid);

      final repo2 = await _freshRepo(prefs);
      final receiveBefore = repo2.currentReceivingIndex;

      final pipeline2 = SendPipelineService(
        signer: signer,
        broadcast: broadcast2,
        journal: journal2,
      );
      final outcomes = await pipeline2.recoverPending(
        accountId: _accountId,
        repository: repo2,
        network: BitcoinNetwork.mainnet,
      );

      expect(outcomes.length, 1);
      expect(outcomes.single.kind, BroadcastOutcomeKind.success);
      expect(journal2.get(pendingRecord.txid)?.state,
          PendingTxState.broadcast);
      expect(repo2.currentReceivingIndex, receiveBefore + 1);
    });
  });

  group('duplicate-broadcast prevention', () {
    test(
        'calling signAndBroadcast a second time with the same inputs '
        'short-circuits with alreadyBroadcast and does NOT re-rotate',
        () async {
      final repo = await _freshRepo(prefs);
      final unsigned = await _buildSampleTx(
        hd: hd,
        repo: repo,
        inputSats: 100000,
      );
      final txid = signer.computeTxid(unsigned, BitcoinNetwork.mainnet);
      when(broadcast.broadcastTransaction(any)).thenAnswer((_) async => txid);

      final pipeline = SendPipelineService(
        signer: signer,
        broadcast: broadcast,
        journal: journal,
      );

      final first = await pipeline.signAndBroadcast(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
        repository: repo,
        accountId: _accountId,
      );
      expect(first.kind, BroadcastOutcomeKind.success);
      final receiveAfterFirst = repo.currentReceivingIndex;

      // Second call with the same tx.
      final second = await pipeline.signAndBroadcast(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
        repository: repo,
        accountId: _accountId,
      );
      expect(second.kind, BroadcastOutcomeKind.alreadyBroadcast);
      expect(second.txid, first.txid);
      expect(repo.currentReceivingIndex, receiveAfterFirst,
          reason: 'rotation must be exactly-once per txid');

      // Broadcast network call happened exactly once across the two sends.
      verify(broadcast.broadcastTransaction(any)).called(1);
    });

    test('recoverPending on an already-rotated tx does not re-rotate',
        () async {
      final repo = await _freshRepo(prefs);
      final unsigned = await _buildSampleTx(
        hd: hd,
        repo: repo,
        inputSats: 100000,
      );
      final txid = signer.computeTxid(unsigned, BitcoinNetwork.mainnet);
      when(broadcast.broadcastTransaction(any)).thenAnswer((_) async => txid);

      final pipeline = SendPipelineService(
        signer: signer,
        broadcast: broadcast,
        journal: journal,
      );
      await pipeline.signAndBroadcast(
        unsigned: unsigned,
        network: BitcoinNetwork.mainnet,
        repository: repo,
        accountId: _accountId,
      );
      final receiveAfterFirst = repo.currentReceivingIndex;

      // Simulate a torn write: rotation already committed in the repo, but
      // the journal entry reverted to `signed` (e.g. a crash between repo
      // save and journal save). recoverPending must still converge — and
      // must NOT rotate again because the txid idempotency key is set.
      final broadcastRecord = journal.get(txid)!;
      await journal.upsert(broadcastRecord.copyWith(
        state: PendingTxState.signed,
        broadcastAt: null,
      ));

      final outcomes = await pipeline.recoverPending(
        accountId: _accountId,
        repository: repo,
        network: BitcoinNetwork.mainnet,
      );
      expect(outcomes, hasLength(1));
      expect(outcomes.single.isSuccess, isTrue);
      expect(repo.currentReceivingIndex, receiveAfterFirst,
          reason: 'txid idempotency key must block re-rotation');
      expect(journal.get(txid)?.state, PendingTxState.broadcast);
    });
  });

  group('TransactionJournal persistence', () {
    test('pending outpoints are returned per account', () async {
      await journal.upsert(PendingTransaction(
        txid: 'abc',
        signedHex: 'deadbeef',
        accountId: _accountId,
        changeIndexUsed: 0,
        spentOutpoints: const ['tx1:0', 'tx2:1'],
        state: PendingTxState.signed,
        createdAt: _epoch,
      ));

      expect(
        journal.pendingOutpointsFor(_accountId),
        containsAll(['tx1:0', 'tx2:1']),
      );
      expect(
        journal.isOutpointPending(accountId: _accountId, outpoint: 'tx1:0'),
        isTrue,
      );
      expect(
        journal
            .isOutpointPending(accountId: _accountId, outpoint: 'unrelated:0'),
        isFalse,
      );
    });

    test('failed records do not contribute to pending outpoints', () async {
      await journal.upsert(PendingTransaction(
        txid: 'abc',
        signedHex: 'deadbeef',
        accountId: _accountId,
        changeIndexUsed: 0,
        spentOutpoints: const ['tx-old:0'],
        state: PendingTxState.failed,
        createdAt: _epoch,
      ));
      expect(journal.pendingOutpointsFor(_accountId), isEmpty);
    });
  });
}

final DateTime _epoch = DateTime.utc(2025, 1, 1);
