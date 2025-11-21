import 'package:flutter_test/flutter_test.dart';
import 'package:bitnest/services/key_service.dart';
import 'package:bitnest/utils/networks.dart';
import 'package:bip39/bip39.dart' as bip39;

/// Example unit test demonstrating best practices for service layer testing.
///
/// This test file shows:
/// - How to test service methods in isolation
/// - How to verify correct behavior with different inputs
/// - How to test error conditions
/// - How to ensure proper state management
void main() {
  group('KeyService Unit Tests', () {
    late KeyService keyService;

    setUp(() {
      keyService = KeyService();
    });

    test('generates valid mnemonic phrase', () {
      final mnemonic = keyService.generateMnemonic(wordCount: 12);
      
      expect(mnemonic, isNotEmpty);
      expect(mnemonic.split(' ').length, 12); // 12-word mnemonic
      expect(bip39.validateMnemonic(mnemonic), isTrue);
    });

    test('generates valid 24-word mnemonic phrase', () {
      final mnemonic = keyService.generateMnemonic(wordCount: 24);
      
      expect(mnemonic, isNotEmpty);
      expect(mnemonic.split(' ').length, 24); // 24-word mnemonic
      expect(bip39.validateMnemonic(mnemonic), isTrue);
    });

    test('validates mnemonic correctly', () {
      const validMnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      const invalidMnemonic = 'invalid mnemonic phrase';
      
      expect(keyService.validateMnemonic(validMnemonic), isTrue);
      expect(keyService.validateMnemonic(invalidMnemonic), isFalse);
    });

    test('converts mnemonic to seed', () {
      const testMnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      
      final seed = keyService.mnemonicToSeed(testMnemonic);
      
      expect(seed, isNotNull);
      expect(seed.length, 64); // 64-byte seed
    });

    test('derives master xprv from seed', () {
      const testMnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(testMnemonic);
      
      final xprv = keyService.deriveMasterXprv(seed, BitcoinNetwork.mainnet);
      
      expect(xprv, isNotEmpty);
      expect(xprv.startsWith('xprv'), isTrue);
    });

    test('derives master xpub from seed', () {
      const testMnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(testMnemonic);
      
      final xpub = keyService.deriveMasterXpub(seed, BitcoinNetwork.mainnet);
      
      expect(xpub, isNotEmpty);
      expect(xpub.startsWith('xpub'), isTrue);
    });

    test('throws error for invalid mnemonic when converting to seed', () {
      const invalidMnemonic = 'invalid mnemonic phrase';
      
      expect(
        () => keyService.mnemonicToSeed(invalidMnemonic),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('derives different xpubs for different networks', () {
      const testMnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed = keyService.mnemonicToSeed(testMnemonic);
      
      final mainnetXpub = keyService.deriveMasterXpub(seed, BitcoinNetwork.mainnet);
      final testnetXpub = keyService.deriveMasterXpub(seed, BitcoinNetwork.testnet);
      
      // Should be different due to network-specific derivation
      expect(mainnetXpub, isNot(equals(testnetXpub)));
    });
  });

  group('Address Derivation Edge Cases', () {
    late KeyService keyService;

    setUp(() {
      keyService = KeyService();
    });

    test('handles empty mnemonic', () {
      expect(
        () => keyService.mnemonicToSeed(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects invalid word count for mnemonic generation', () {
      expect(
        () => keyService.generateMnemonic(wordCount: 10),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

