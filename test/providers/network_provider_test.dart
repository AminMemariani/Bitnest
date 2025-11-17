import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitnest/providers/network_provider.dart';
import 'package:bitnest/utils/networks.dart';

void main() {
  group('NetworkProvider', () {
    late NetworkProvider provider;

    setUp(() {
      // Clear shared preferences before each test
      SharedPreferences.setMockInitialValues({});
      provider = NetworkProvider();
    });

    test('initializes with mainnet by default', () {
      expect(provider.currentNetwork, BitcoinNetwork.mainnet);
      expect(provider.isMainnet, isTrue);
      expect(provider.isTestnet, isFalse);
    });

    test('provides correct API endpoint for mainnet', () {
      expect(
        provider.apiEndpoint,
        'https://bitcoin-rpc.publicnode.com',
      );
    });

    test('switches to testnet', () async {
      await provider.switchNetwork(BitcoinNetwork.testnet);

      expect(provider.currentNetwork, BitcoinNetwork.testnet);
      expect(provider.isMainnet, isFalse);
      expect(provider.isTestnet, isTrue);
      expect(
        provider.apiEndpoint,
        'https://bitcoin-testnet-rpc.publicnode.com',
      );
    });

    test('switches back to mainnet', () async {
      await provider.switchNetwork(BitcoinNetwork.testnet);
      await provider.switchNetwork(BitcoinNetwork.mainnet);

      expect(provider.currentNetwork, BitcoinNetwork.mainnet);
      expect(provider.isMainnet, isTrue);
    });

    test('toggles network from mainnet to testnet', () async {
      await provider.toggleNetwork();

      expect(provider.currentNetwork, BitcoinNetwork.testnet);
    });

    test('toggles network from testnet to mainnet', () async {
      await provider.switchNetwork(BitcoinNetwork.testnet);
      await provider.toggleNetwork();

      expect(provider.currentNetwork, BitcoinNetwork.mainnet);
    });

    test('persists network choice', () async {
      await provider.switchNetwork(BitcoinNetwork.testnet);

      // Verify the preference was saved
      final prefs = await SharedPreferences.getInstance();
      final savedNetwork = prefs.getString('selected_network');
      expect(savedNetwork, 'testnet');
    });

    test('does not switch if already on target network', () async {
      final initialNetwork = provider.currentNetwork;
      await provider.switchNetwork(BitcoinNetwork.mainnet);

      expect(provider.currentNetwork, initialNetwork);
    });

    test('provides correct network name', () {
      expect(provider.networkName, 'Bitcoin Mainnet');

      provider.switchNetwork(BitcoinNetwork.testnet).then((_) {
        expect(provider.networkName, 'Bitcoin Testnet');
      });
    });
  });
}

