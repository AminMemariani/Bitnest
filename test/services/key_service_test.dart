import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/utils/networks.dart';

import 'key_service_test.mocks.dart';

@GenerateMocks([FlutterSecureStorage, LocalAuthentication])
void main() {
  group('KeyService - Mnemonic Generation', () {
    late KeyService keyService;

    setUp(() {
      keyService = KeyService();
    });

    test('generates 12-word mnemonic', () {
      final mnemonic = keyService.generateMnemonic(wordCount: 12);
      final words = mnemonic.split(' ');

      expect(words.length, 12);
      expect(mnemonic, isNotEmpty);
    });

    test('generates 24-word mnemonic', () {
      final mnemonic = keyService.generateMnemonic(wordCount: 24);
      final words = mnemonic.split(' ');

      expect(words.length, 24);
      expect(mnemonic, isNotEmpty);
    });

    test('throws ArgumentError for invalid word count', () {
      expect(
        () => keyService.generateMnemonic(wordCount: 15),
        throwsArgumentError,
      );
    });

    test('generates different mnemonics on each call', () {
      final mnemonic1 = keyService.generateMnemonic();
      final mnemonic2 = keyService.generateMnemonic();

      expect(mnemonic1, isNot(equals(mnemonic2)));
    });
  });

  group('KeyService - Mnemonic Validation', () {
    late KeyService keyService;

    setUp(() {
      keyService = KeyService();
    });

    test('validates correct 12-word mnemonic', () {
      // Standard test mnemonic from BIP39
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      expect(keyService.validateMnemonic(mnemonic), isTrue);
    });

    test('validates correct 24-word mnemonic', () {
      final mnemonic = keyService.generateMnemonic(wordCount: 24);

      expect(keyService.validateMnemonic(mnemonic), isTrue);
    });

    test('rejects invalid mnemonic', () {
      const invalidMnemonic = 'invalid mnemonic phrase that does not exist';

      expect(keyService.validateMnemonic(invalidMnemonic), isFalse);
    });

    test('rejects mnemonic with wrong word count', () {
      const wrongCountMnemonic = 'abandon abandon abandon';

      expect(keyService.validateMnemonic(wrongCountMnemonic), isFalse);
    });
  });

  group('KeyService - Seed Derivation', () {
    late KeyService keyService;

    setUp(() {
      keyService = KeyService();
    });

    test('converts mnemonic to seed', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      final seed = keyService.mnemonicToSeed(mnemonic);

      expect(seed.length, 64); // 512 bits = 64 bytes
      expect(seed, isA<List<int>>());
    });

    test('converts mnemonic to seed with passphrase', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      const passphrase = 'test passphrase';

      final seedWithoutPass = keyService.mnemonicToSeed(mnemonic);
      final seedWithPass =
          keyService.mnemonicToSeed(mnemonic, passphrase: passphrase);

      expect(seedWithoutPass, isNot(equals(seedWithPass)));
      expect(seedWithPass.length, 64);
    });

    test('throws ArgumentError for invalid mnemonic in mnemonicToSeed', () {
      const invalidMnemonic = 'invalid mnemonic';

      expect(
        () => keyService.mnemonicToSeed(invalidMnemonic),
        throwsArgumentError,
      );
    });
  });

  group('KeyService - HD Key Derivation', () {
    late KeyService keyService;

    setUp(() {
      keyService = KeyService();
    });

    test('derives master xprv from seed', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);

      final xprv = keyService.deriveMasterXprv(seed, BitcoinNetwork.mainnet);

      expect(xprv, isNotEmpty);
      expect(xprv.startsWith('xprv'), isTrue);
    });

    test('derives master xpub from seed', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);

      final xpub = keyService.deriveMasterXpub(seed, BitcoinNetwork.mainnet);

      expect(xpub, isNotEmpty);
      expect(xpub.startsWith('xpub'), isTrue);
    });

    test('derives account xpub for native segwit', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);

      final accountXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.mainnet,
        accountIndex: 0,
      );

      expect(accountXpub, isNotEmpty);
    });

    test('derives account xpub for legacy', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);

      final accountXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.legacy,
        BitcoinNetwork.mainnet,
        accountIndex: 0,
      );

      expect(accountXpub, isNotEmpty);
    });

    test('derives account xpub for p2sh-segwit', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);

      final accountXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.p2shSegwit,
        BitcoinNetwork.mainnet,
        accountIndex: 0,
      );

      expect(accountXpub, isNotEmpty);
    });

    test('derives different xpubs for different networks', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);

      final mainnetXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.mainnet,
      );
      final testnetXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.testnet,
      );

      expect(mainnetXpub, isNot(equals(testnetXpub)));
    });

    test('derives address for native segwit', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);
      final accountXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.mainnet,
      );

      final address = keyService.deriveAddress(
        accountXpub,
        0,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.mainnet,
      );

      expect(address, isNotEmpty);
      expect(address.startsWith('bc1'), isTrue);
    });

    test('derives address for legacy', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);
      final accountXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.legacy,
        BitcoinNetwork.mainnet,
      );

      final address = keyService.deriveAddress(
        accountXpub,
        0,
        DerivationScheme.legacy,
        BitcoinNetwork.mainnet,
      );

      expect(address, isNotEmpty);
      // Legacy addresses start with '1' for mainnet
      expect(address[0], '1');
    });

    test('derives different addresses for different indices', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(mnemonic);
      final accountXpub = keyService.deriveAccountXpub(
        seed,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.mainnet,
      );

      final address0 = keyService.deriveAddress(
        accountXpub,
        0,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.mainnet,
      );
      final address1 = keyService.deriveAddress(
        accountXpub,
        1,
        DerivationScheme.nativeSegwit,
        BitcoinNetwork.mainnet,
      );

      expect(address0, isNot(equals(address1)));
    });
  });

  group('KeyService - Secure Storage', () {
    late MockFlutterSecureStorage mockStorage;
    late KeyService keyService;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      keyService = KeyService(storage: mockStorage);
    });

    test('stores seed in secure storage', () async {
      const walletId = 'test-wallet-1';
      final seed = Uint8List.fromList(List.generate(64, (i) => i));

      when(mockStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async => {});

      await keyService.storeSeed(walletId, seed);

      verify(mockStorage.write(
        key: 'wallet_seed_$walletId',
        value: anyNamed('value'),
      )).called(1);
    });

    test('retrieves seed from secure storage', () async {
      const walletId = 'test-wallet-1';
      final originalSeed = Uint8List.fromList(List.generate(64, (i) => i));
      final seedBase64 = base64Encode(originalSeed);

      when(mockStorage.read(key: 'wallet_seed_$walletId'))
          .thenAnswer((_) async => seedBase64);

      final retrievedSeed = await keyService.retrieveSeed(walletId);

      expect(retrievedSeed, isNotNull);
      expect(retrievedSeed, equals(originalSeed));
    });

    test('returns null when seed not found', () async {
      const walletId = 'non-existent-wallet';

      when(mockStorage.read(key: 'wallet_seed_$walletId'))
          .thenAnswer((_) async => null);

      final retrievedSeed = await keyService.retrieveSeed(walletId);

      expect(retrievedSeed, isNull);
    });

    test('stores mnemonic in secure storage', () async {
      const walletId = 'test-wallet-1';
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      when(mockStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async => {});

      await keyService.storeMnemonic(walletId, mnemonic);

      verify(mockStorage.write(
        key: 'wallet_mnemonic_$walletId',
        value: mnemonic,
      )).called(1);
    });

    test('retrieves mnemonic from secure storage', () async {
      const walletId = 'test-wallet-1';
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      when(mockStorage.read(key: 'wallet_mnemonic_$walletId'))
          .thenAnswer((_) async => mnemonic);

      final retrievedMnemonic = await keyService.retrieveMnemonic(walletId);

      expect(retrievedMnemonic, equals(mnemonic));
    });

    test('deletes wallet data', () async {
      const walletId = 'test-wallet-1';

      when(mockStorage.delete(key: anyNamed('key')))
          .thenAnswer((_) async => {});

      await keyService.deleteWalletData(walletId);

      verify(mockStorage.delete(key: 'wallet_seed_$walletId')).called(1);
      verify(mockStorage.delete(key: 'wallet_mnemonic_$walletId')).called(1);
    });
  });

  group('KeyService - Biometric Authentication', () {
    late MockLocalAuthentication mockLocalAuth;
    late KeyService keyService;

    setUp(() {
      mockLocalAuth = MockLocalAuthentication();
      keyService = KeyService(localAuth: mockLocalAuth);
    });

    test('checks if biometric is available', () async {
      when(mockLocalAuth.canCheckBiometrics).thenAnswer((_) async => true);

      final isAvailable = await keyService.isBiometricAvailable();

      expect(isAvailable, isTrue);
      verify(mockLocalAuth.canCheckBiometrics).called(1);
    });

    test('gets available biometric types', () async {
      when(mockLocalAuth.getAvailableBiometrics())
          .thenAnswer((_) async => [BiometricType.fingerprint]);

      final biometrics = await keyService.getAvailableBiometrics();

      expect(biometrics, isNotEmpty);
      expect(biometrics.contains(BiometricType.fingerprint), isTrue);
    });
  });
}
