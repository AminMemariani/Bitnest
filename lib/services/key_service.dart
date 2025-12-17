import 'dart:convert';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:hex/hex.dart';
import 'package:bs58check/bs58check.dart' as bs58;
import '../utils/networks.dart';
import '../utils/debug_logger.dart';

/// Derivation scheme types for Bitcoin addresses.
enum DerivationScheme {
  /// Legacy P2PKH addresses (BIP44, m/44'/coin'/account')
  legacy,

  /// P2SH-wrapped Segwit addresses (BIP49, m/49'/coin'/account')
  p2shSegwit,

  /// Native Segwit addresses (BIP84, m/84'/coin'/account')
  nativeSegwit,
}

/// Service for managing BIP39 mnemonics, BIP32 HD key derivation, and secure storage.
///
/// This service handles:
/// - BIP39 mnemonic generation and validation
/// - BIP32/BIP44/BIP49/BIP84 HD key derivation
/// - Secure encrypted storage of seeds
/// - Biometric authentication for sensitive operations
///
/// Security: Private keys are never logged or printed.
class KeyService {
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  // Fallback in-memory storage for development when Keychain fails
  final Map<String, String> _fallbackStorage = {};

  // Storage keys
  static const String _seedStorageKey = 'wallet_seed_';
  static const String _mnemonicStorageKey = 'wallet_mnemonic_';

  KeyService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  /// Generates a new BIP39 mnemonic phrase.
  ///
  /// [wordCount] must be 12 or 24 (default: 24).
  /// Returns a space-separated mnemonic phrase.
  ///
  /// Throws [ArgumentError] if wordCount is not 12 or 24.
  String generateMnemonic({int wordCount = 24}) {
    if (wordCount != 12 && wordCount != 24) {
      throw ArgumentError('wordCount must be 12 or 24, got $wordCount');
    }

    final strength = wordCount == 12 ? 128 : 256;
    return bip39.generateMnemonic(strength: strength);
  }

  /// Validates a BIP39 mnemonic phrase.
  ///
  /// Returns true if the mnemonic is valid, false otherwise.
  bool validateMnemonic(String mnemonic) {
    try {
      return bip39.validateMnemonic(mnemonic);
    } catch (e) {
      return false;
    }
  }

  /// Converts a BIP39 mnemonic to a seed.
  ///
  /// [passphrase] is optional BIP39 passphrase for additional security.
  /// Returns the 64-byte seed.
  Uint8List mnemonicToSeed(String mnemonic, {String? passphrase}) {
    if (!validateMnemonic(mnemonic)) {
      throw ArgumentError('Invalid mnemonic phrase');
    }

    return Uint8List.fromList(
      bip39.mnemonicToSeed(mnemonic, passphrase: passphrase ?? ''),
    );
  }

  /// Derives the master extended private key (xprv) from a seed.
  ///
  /// Returns the base58-encoded extended private key.
  String deriveMasterXprv(Uint8List seed, BitcoinNetwork network) {
    final masterNode = bip32.BIP32.fromSeed(seed);
    return masterNode.toBase58();
  }

  /// Derives the master extended public key (xpub) from a seed.
  ///
  /// Returns the base58-encoded extended public key.
  String deriveMasterXpub(Uint8List seed, BitcoinNetwork network) {
    final masterNode = bip32.BIP32.fromSeed(seed);
    return masterNode.neutered().toBase58();
  }

  /// Derives an extended private key (xprv) from a master key using a derivation path.
  ///
  /// [xprv] is the parent extended private key (base58).
  /// [derivationPath] follows BIP32 format (e.g., "m/84'/0'/0'").
  /// Returns the derived extended private key (base58).
  String deriveXprv(String xprv, String derivationPath) {
    final node = bip32.BIP32.fromBase58(xprv);
    final derived = node.derivePath(derivationPath);
    return derived.toBase58();
  }

  /// Derives an extended public key (xpub) from a master key using a derivation path.
  ///
  /// [xpub] is the parent extended public key (base58).
  /// [derivationPath] follows BIP32 format (e.g., "m/84'/0'/0'").
  /// Returns the derived extended public key (base58).
  String deriveXpub(String xpub, String derivationPath) {
    final node = bip32.BIP32.fromBase58(xpub);
    final derived = node.derivePath(derivationPath);
    return derived.neutered().toBase58();
  }

  /// Derives an account-level extended public key (xpub) for watch-only wallets.
  ///
  /// [seed] is the wallet seed.
  /// [scheme] is the derivation scheme (legacy, p2sh-segwit, native segwit).
  /// [accountIndex] is the BIP44 account index (default: 0).
  /// [network] is the Bitcoin network (mainnet or testnet).
  ///
  /// Returns the account-level extended public key (base58).
  String deriveAccountXpub(
    Uint8List seed,
    DerivationScheme scheme,
    BitcoinNetwork network, {
    int accountIndex = 0,
  }) {
    // For hardened derivation paths, we must derive from the master private key first,
    // then extract the public key. We cannot derive hardened children from xpub.
    final derivationPath = _buildDerivationPath(scheme, network, accountIndex);
    final masterXprv = deriveMasterXprv(seed, network);
    final accountXprv = deriveXprv(masterXprv, derivationPath);
    // Extract xpub from xprv
    final accountNode = bip32.BIP32.fromBase58(accountXprv);
    return accountNode.neutered().toBase58();
  }

  /// Derives a private key for a specific address index.
  ///
  /// [xprv] is the account-level extended private key (base58).
  /// [addressIndex] is the BIP32 address index.
  /// [change] is true for change addresses (internal chain), false for receiving addresses.
  ///
  /// Returns the private key as a hex string.
  String derivePrivateKey(String xprv, int addressIndex,
      {bool change = false}) {
    final changeIndex = change ? 1 : 0;
    final derivationPath = '$changeIndex/$addressIndex';
    final node = bip32.BIP32.fromBase58(xprv);
    final derived = node.derivePath(derivationPath);
    final privateKey = derived.privateKey;
    if (privateKey == null) {
      throw Exception('Failed to derive private key');
    }
    return HEX.encode(Uint8List.fromList(privateKey));
  }

  /// Derives a public key for a specific address index.
  ///
  /// [xpub] is the account-level extended public key (base58).
  /// [addressIndex] is the BIP32 address index.
  /// [change] is true for change addresses, false for receiving addresses.
  ///
  /// Returns the public key as a hex string (compressed).
  String derivePublicKey(String xpub, int addressIndex, {bool change = false}) {
    final changeIndex = change ? 1 : 0;
    final derivationPath = '$changeIndex/$addressIndex';
    final node = bip32.BIP32.fromBase58(xpub);
    final derived = node.derivePath(derivationPath);
    return HEX.encode(Uint8List.fromList(derived.publicKey));
  }

  /// Derives a Bitcoin address for a specific index.
  ///
  /// [xpub] is the account-level extended public key (base58).
  /// [addressIndex] is the BIP32 address index.
  /// [scheme] is the derivation scheme.
  /// [network] is the Bitcoin network.
  /// [change] is true for change addresses, false for receiving addresses.
  ///
  /// Returns the Bitcoin address.
  String deriveAddress(
    String xpub,
    int addressIndex,
    DerivationScheme scheme,
    BitcoinNetwork network, {
    bool change = false,
  }) {
    final pubKeyHex = derivePublicKey(xpub, addressIndex, change: change);
    final pubKeyBytes = Uint8List.fromList(HEX.decode(pubKeyHex));

    switch (scheme) {
      case DerivationScheme.legacy:
        return _deriveP2PKHAddress(pubKeyBytes, network);
      case DerivationScheme.p2shSegwit:
        return _deriveP2SHWrappedSegwitAddress(pubKeyBytes, network);
      case DerivationScheme.nativeSegwit:
        return _deriveP2WPKHAddress(pubKeyBytes, network);
    }
  }

  /// Stores an encrypted seed in secure storage.
  ///
  /// [walletId] is the unique wallet identifier.
  /// [seed] is the 64-byte seed to store.
  /// [requireBiometric] if true, requires biometric authentication before storing.
  ///
  /// Throws [Exception] if biometric authentication fails or storage fails.
  Future<void> storeSeed(
    String walletId,
    Uint8List seed, {
    bool requireBiometric = false,
  }) async {
    if (requireBiometric) {
      final authenticated = await _authenticateWithBiometrics();
      if (!authenticated) {
        throw Exception('Biometric authentication failed');
      }
    }

    // Convert seed to base64 for storage
    final seedBase64 = _bytesToBase64(seed);
    try {
      await _storage.write(key: '$_seedStorageKey$walletId', value: seedBase64);
    } catch (e, stackTrace) {
      // Fallback to in-memory storage if Keychain access fails (development)
      if (kDebugMode) {
        DebugLogger.logException(
          e,
          stackTrace,
          context: 'KeyService.storeSeed (Keychain failed, using fallback)',
          additionalInfo: {'walletId': walletId},
        );
        _fallbackStorage['$_seedStorageKey$walletId'] = seedBase64;
      } else {
        rethrow;
      }
    }
  }

  /// Retrieves and decrypts a seed from secure storage.
  ///
  /// [walletId] is the unique wallet identifier.
  /// [requireBiometric] if true, requires biometric authentication before retrieval.
  ///
  /// Returns the seed, or null if not found.
  /// Throws [Exception] if biometric authentication fails.
  Future<Uint8List?> retrieveSeed(
    String walletId, {
    bool requireBiometric = false,
  }) async {
    if (requireBiometric) {
      final authenticated = await _authenticateWithBiometrics();
      if (!authenticated) {
        throw Exception('Biometric authentication failed');
      }
    }

    String? seedBase64;
    try {
      seedBase64 = await _storage.read(key: '$_seedStorageKey$walletId');
    } catch (e, stackTrace) {
      // Fallback to in-memory storage if Keychain access fails (development)
      if (kDebugMode) {
        DebugLogger.logException(
          e,
          stackTrace,
          context: 'KeyService.retrieveSeed (Keychain failed, using fallback)',
          additionalInfo: {'walletId': walletId},
        );
        seedBase64 = _fallbackStorage['$_seedStorageKey$walletId'];
      } else {
        rethrow;
      }
    }
    if (seedBase64 == null) {
      return null;
    }

    return _base64ToBytes(seedBase64);
  }

  /// Stores an encrypted mnemonic in secure storage.
  ///
  /// [walletId] is the unique wallet identifier.
  /// [mnemonic] is the BIP39 mnemonic phrase.
  /// [requireBiometric] if true, requires biometric authentication.
  ///
  /// Throws [Exception] if biometric authentication fails or storage fails.
  Future<void> storeMnemonic(
    String walletId,
    String mnemonic, {
    bool requireBiometric = false,
  }) async {
    if (requireBiometric) {
      final authenticated = await _authenticateWithBiometrics();
      if (!authenticated) {
        throw Exception('Biometric authentication failed');
      }
    }

    try {
      await _storage.write(
        key: '$_mnemonicStorageKey$walletId',
        value: mnemonic,
      );
    } catch (e, stackTrace) {
      // Fallback to in-memory storage if Keychain access fails (development)
      if (kDebugMode) {
        DebugLogger.logException(
          e,
          stackTrace,
          context: 'KeyService.storeMnemonic (Keychain failed, using fallback)',
          additionalInfo: {'walletId': walletId},
        );
        _fallbackStorage['$_mnemonicStorageKey$walletId'] = mnemonic;
      } else {
        rethrow;
      }
    }
  }

  /// Retrieves and decrypts a mnemonic from secure storage.
  ///
  /// [walletId] is the unique wallet identifier.
  /// [requireBiometric] if true, requires biometric authentication.
  ///
  /// Returns the mnemonic, or null if not found.
  /// Throws [Exception] if biometric authentication fails.
  Future<String?> retrieveMnemonic(
    String walletId, {
    bool requireBiometric = false,
  }) async {
    if (requireBiometric) {
      final authenticated = await _authenticateWithBiometrics();
      if (!authenticated) {
        throw Exception('Biometric authentication failed');
      }
    }

    try {
      return await _storage.read(key: '$_mnemonicStorageKey$walletId');
    } catch (e, stackTrace) {
      // Fallback to in-memory storage if Keychain access fails (development)
      if (kDebugMode) {
        DebugLogger.logException(
          e,
          stackTrace,
          context:
              'KeyService.retrieveMnemonic (Keychain failed, using fallback)',
          additionalInfo: {'walletId': walletId},
        );
        return _fallbackStorage['$_mnemonicStorageKey$walletId'];
      } else {
        rethrow;
      }
    }
  }

  /// Deletes stored seed and mnemonic for a wallet.
  ///
  /// [walletId] is the unique wallet identifier.
  Future<void> deleteWalletData(String walletId) async {
    try {
      await _storage.delete(key: '$_seedStorageKey$walletId');
      await _storage.delete(key: '$_mnemonicStorageKey$walletId');
    } catch (e, stackTrace) {
      // Fallback: remove from in-memory storage if Keychain access fails (development)
      if (kDebugMode) {
        DebugLogger.logException(
          e,
          stackTrace,
          context:
              'KeyService.deleteWalletData (Keychain failed, using fallback)',
          additionalInfo: {'walletId': walletId},
        );
        _fallbackStorage.remove('$_seedStorageKey$walletId');
        _fallbackStorage.remove('$_mnemonicStorageKey$walletId');
      } else {
        rethrow;
      }
    }
  }

  /// Checks if biometric authentication is available on the device.
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Gets available biometric types on the device.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  // Private helper methods

  /// Builds a BIP32 derivation path for the given scheme, network, and account.
  String _buildDerivationPath(
    DerivationScheme scheme,
    BitcoinNetwork network,
    int accountIndex,
  ) {
    final coinType = NetworkConfig.getCoinType(network);
    final purpose = _getPurposeForScheme(scheme);
    return "m/$purpose'/$coinType'/$accountIndex'";
  }

  /// Gets the BIP purpose number for a derivation scheme.
  int _getPurposeForScheme(DerivationScheme scheme) {
    switch (scheme) {
      case DerivationScheme.legacy:
        return 44; // BIP44
      case DerivationScheme.p2shSegwit:
        return 49; // BIP49
      case DerivationScheme.nativeSegwit:
        return 84; // BIP84
    }
  }

  /// Derives a P2PKH (legacy) address from a public key.
  String _deriveP2PKHAddress(Uint8List pubKey, BitcoinNetwork network) {
    final hash160 = _hash160(pubKey);
    final version = network == BitcoinNetwork.mainnet ? 0x00 : 0x6f;
    return _base58CheckEncode(hash160, version);
  }

  /// Derives a P2SH-wrapped Segwit address from a public key.
  String _deriveP2SHWrappedSegwitAddress(
      Uint8List pubKey, BitcoinNetwork network) {
    final hash160 = _hash160(pubKey);
    // P2WPKH witness program: 0x00 + 20-byte hash160
    final witnessProgram = Uint8List(21);
    witnessProgram[0] = 0x00;
    witnessProgram.setRange(1, 21, hash160);

    final scriptHash = _hash160(witnessProgram);
    final version = network == BitcoinNetwork.mainnet ? 0x05 : 0xc4;
    return _base58CheckEncode(scriptHash, version);
  }

  /// Derives a P2WPKH (native Segwit) address from a public key.
  String _deriveP2WPKHAddress(Uint8List pubKey, BitcoinNetwork network) {
    final hash160 = _hash160(pubKey);
    final hrp = network == BitcoinNetwork.mainnet ? 'bc' : 'tb';
    return _bech32Encode(hrp, 0, hash160);
  }

  /// Computes RIPEMD160(SHA256(data)).
  Uint8List _hash160(Uint8List data) {
    final sha256 = SHA256Digest();
    final ripemd160 = RIPEMD160Digest();

    final sha256Hash = sha256.process(data);
    final ripemd160Hash = ripemd160.process(sha256Hash);
    return Uint8List.fromList(ripemd160Hash);
  }

  /// Base58Check encodes data with a version byte.
  String _base58CheckEncode(Uint8List data, int version) {
    final versioned = Uint8List(data.length + 1);
    versioned[0] = version;
    versioned.setRange(1, versioned.length, data);
    return bs58.encode(versioned);
  }

  /// Bech32 encodes data for P2WPKH addresses (simplified implementation).
  ///
  /// Note: This is a simplified bech32 encoder. For production use, consider
  /// using a dedicated bech32 library for full BIP173 compliance.
  String _bech32Encode(String hrp, int witnessVersion, Uint8List data) {
    // Convert data to 5-bit groups
    final values = <int>[witnessVersion];

    var bits = 0;
    var value = 0;
    for (var byte in data) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        values.add((value >> (bits - 5)) & 31);
        bits -= 5;
      }
    }
    if (bits > 0) {
      values.add((value << (5 - bits)) & 31);
    }

    // Bech32 charset
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    final encoded = values.map((v) => charset[v]).join();

    // Simple bech32 encoding (full implementation would include checksum)
    // For production, use a proper bech32 library
    return '${hrp}1$encoded';
  }

  /// Authenticates the user with biometrics (public method).
  Future<bool> authenticateWithBiometrics({
    String reason = 'Please authenticate',
  }) async {
    return await _authenticateWithBiometrics(reason: reason);
  }

  Future<bool> _authenticateWithBiometrics({
    String reason = 'Authenticate to access wallet',
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  /// Converts bytes to base64 string.
  String _bytesToBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }

  /// Converts base64 string to bytes.
  Uint8List _base64ToBytes(String base64) {
    try {
      return Uint8List.fromList(base64Decode(base64));
    } catch (e) {
      throw ArgumentError('Invalid base64 string: $e');
    }
  }
}
