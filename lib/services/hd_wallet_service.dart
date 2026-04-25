import 'dart:typed_data';
import 'package:bip32/bip32.dart' as bip32;
import '../utils/networks.dart';
import 'key_service.dart';

/// BIP84 (native SegWit) HD wallet service, scoped to a single wallet & network.
///
/// The seed is loaded once from the app's existing secure-storage layer
/// ([KeyService]) and cached in memory for the lifetime of the service. Call
/// [dispose] to zero the seed buffer and drop the cached master node.
///
/// Derivation paths (where `a` is the account index and `i` the address index):
///   Mainnet receiving: `m/84'/0'/a'/0/i`
///   Mainnet change:    `m/84'/0'/a'/1/i`
///   Testnet receiving: `m/84'/1'/a'/0/i`
///   Testnet change:    `m/84'/1'/a'/1/i`
///
/// Security:
/// - Private keys are returned as raw 32-byte arrays from
///   [derivePrivateKeyForPath] only.
/// - This class never logs, prints, or serializes key material. Callers MUST
///   uphold the same invariant — do not pass the returned bytes to `print`,
///   `debugPrint`, logging frameworks, crash reporters, or `toString`.
class HdWalletService {
  final KeyService _keyService;

  /// The wallet id whose seed backs this service (matches [Wallet.id]).
  final String walletId;

  /// The Bitcoin network this service derives for.
  final BitcoinNetwork network;

  /// BIP44 account index (default: 0, i.e. the first account).
  final int accountIndex;

  Uint8List? _seed;
  bip32.BIP32? _master;

  HdWalletService._({
    required KeyService keyService,
    required this.walletId,
    required this.network,
    required this.accountIndex,
    required Uint8List seed,
  })  : _keyService = keyService,
        _seed = seed,
        _master = bip32.BIP32.fromSeed(seed);

  /// Loads the wallet's seed from secure storage and returns a ready HD service.
  ///
  /// Throws [StateError] if no seed is stored for [walletId] (e.g. watch-only).
  static Future<HdWalletService> load({
    required KeyService keyService,
    required String walletId,
    required BitcoinNetwork network,
    int accountIndex = 0,
    bool requireBiometric = false,
  }) async {
    final seed = await keyService.retrieveSeed(
      walletId,
      requireBiometric: requireBiometric,
    );
    if (seed == null) {
      throw StateError(
        'No seed found for wallet "$walletId" — cannot derive HD keys.',
      );
    }
    return HdWalletService._(
      keyService: keyService,
      walletId: walletId,
      network: network,
      accountIndex: accountIndex,
      seed: seed,
    );
  }

  /// Constructs an HD service directly from an in-hand seed, bypassing secure
  /// storage. Useful for tests and for flows where the seed was just derived
  /// and hasn't been persisted yet. Callers are responsible for the seed's
  /// lifetime; the service copies the bytes internally.
  factory HdWalletService.fromSeed({
    required KeyService keyService,
    required Uint8List seed,
    required BitcoinNetwork network,
    String walletId = '',
    int accountIndex = 0,
  }) {
    return HdWalletService._(
      keyService: keyService,
      walletId: walletId,
      network: network,
      accountIndex: accountIndex,
      seed: Uint8List.fromList(seed),
    );
  }

  /// Zeroes the in-memory seed and drops the cached master node. After this
  /// call all derive* methods will throw [StateError].
  void dispose() {
    final s = _seed;
    if (s != null) {
      for (var i = 0; i < s.length; i++) {
        s[i] = 0;
      }
    }
    _seed = null;
    _master = null;
  }

  bool get isDisposed => _master == null;

  /// BIP44 coin type (0 for mainnet, 1 for testnet).
  int get coinType => NetworkConfig.getCoinType(network);

  /// Account-level path, e.g. `m/84'/0'/0'`.
  String get accountPath => "m/84'/$coinType'/$accountIndex'";

  /// Receiving-chain path prefix, e.g. `m/84'/0'/0'/0`.
  String get receivingChainPath => "$accountPath/0";

  /// Change-chain path prefix, e.g. `m/84'/0'/0'/1`.
  String get changeChainPath => "$accountPath/1";

  /// Full receiving path for [index], e.g. `m/84'/0'/0'/0/5`.
  String receivingPath(int index) {
    _assertNonHardenedIndex(index);
    return "$receivingChainPath/$index";
  }

  /// Full change path for [index], e.g. `m/84'/0'/0'/1/5`.
  String changePath(int index) {
    _assertNonHardenedIndex(index);
    return "$changeChainPath/$index";
  }

  /// Derives the BIP84 receiving address at [index].
  ///
  /// Returns a native-SegWit (P2WPKH) address — `bc1…` on mainnet or
  /// `tb1…` on testnet.
  String deriveReceivingAddress(int index) {
    final pubKey = derivePublicKeyForPath(receivingPath(index));
    return _keyService.encodeP2wpkhAddress(pubKey, network);
  }

  /// Derives the BIP84 change address at [index].
  String deriveChangeAddress(int index) {
    final pubKey = derivePublicKeyForPath(changePath(index));
    return _keyService.encodeP2wpkhAddress(pubKey, network);
  }

  /// Derives the raw 32-byte private key at [path].
  ///
  /// MUST NOT be logged by callers. This service never logs the return value.
  /// Throws [StateError] if the node at [path] has no private key
  /// (e.g. a neutered/public-only node), or if the service is disposed.
  Uint8List derivePrivateKeyForPath(String path) {
    final node = _deriveNode(path);
    final priv = node.privateKey;
    if (priv == null) {
      throw StateError(
        'No private key available at "$path" (neutered node).',
      );
    }
    return Uint8List.fromList(priv);
  }

  /// Derives the compressed (33-byte) secp256k1 public key at [path].
  Uint8List derivePublicKeyForPath(String path) {
    final node = _deriveNode(path);
    return Uint8List.fromList(node.publicKey);
  }

  // ---- internals ----

  bip32.BIP32 _deriveNode(String rawPath) {
    final master = _master;
    if (master == null) {
      throw StateError('HdWalletService has been disposed.');
    }
    final normalized = _normalizePath(rawPath);
    if (normalized == 'm') return master;
    return master.derivePath(normalized);
  }

  static String _normalizePath(String path) {
    final p = path.trim();
    if (p.isEmpty || p == 'm' || p == 'm/') return 'm';
    if (!p.startsWith('m/')) {
      throw ArgumentError.value(
        path,
        'path',
        'Derivation path must start with "m/".',
      );
    }
    return p;
  }

  static void _assertNonHardenedIndex(int index) {
    if (index < 0 || index >= 0x80000000) {
      throw ArgumentError.value(
        index,
        'index',
        'Non-hardened BIP32 index must be in [0, 2^31).',
      );
    }
  }
}
