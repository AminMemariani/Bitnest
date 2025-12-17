/// Network configuration constants for Bitcoin mainnet and testnet.
///
/// This file contains network-specific constants used throughout the application
/// for address generation, transaction building, and API endpoint selection.
library;

/// Bitcoin network types supported by the application.
enum BitcoinNetwork {
  /// Bitcoin mainnet - production network with real BTC
  mainnet,

  /// Bitcoin testnet - testing network with test BTC
  testnet,
}

/// Network configuration constants for Bitcoin mainnet.
class MainnetConfig {
  /// Human-readable network name
  static const String name = 'Bitcoin Mainnet';

  /// Network identifier
  static const String networkId = 'mainnet';

  /// BIP44 coin type for Bitcoin mainnet (0)
  static const int coinType = 0;

  /// Default derivation path for Bitcoin mainnet accounts
  /// Format: m/84'/0'/0' (BIP84 - Native Segwit)
  static const String defaultDerivationPath = "m/84'/0'/0'";

  /// API endpoint for Bitcoin mainnet
  static const String apiEndpoint = 'https://bitcoin-rpc.publicnode.com';

  /// Network magic bytes (for P2P protocol)
  static const int magicBytes = 0xD9B4BEF9;

  /// Default port for Bitcoin mainnet
  static const int defaultPort = 8333;
}

/// Network configuration constants for Bitcoin testnet.
class TestnetConfig {
  /// Human-readable network name
  static const String name = 'Bitcoin Testnet';

  /// Network identifier
  static const String networkId = 'testnet';

  /// BIP44 coin type for Bitcoin testnet (1)
  static const int coinType = 1;

  /// Default derivation path for Bitcoin testnet accounts
  /// Format: m/84'/1'/0' (BIP84 - Native Segwit on testnet)
  static const String defaultDerivationPath = "m/84'/1'/0'";

  /// API endpoint for Bitcoin testnet
  static const String apiEndpoint =
      'https://bitcoin-testnet-rpc.publicnode.com';

  /// Network magic bytes (for P2P protocol)
  static const int magicBytes = 0x0709110B;

  /// Default port for Bitcoin testnet
  static const int defaultPort = 18333;
}

/// Helper class to get network configuration based on network type.
class NetworkConfig {
  /// Get the coin type for the specified network.
  static int getCoinType(BitcoinNetwork network) {
    switch (network) {
      case BitcoinNetwork.mainnet:
        return MainnetConfig.coinType;
      case BitcoinNetwork.testnet:
        return TestnetConfig.coinType;
    }
  }

  /// Get the default derivation path for the specified network.
  static String getDerivationPath(BitcoinNetwork network) {
    switch (network) {
      case BitcoinNetwork.mainnet:
        return MainnetConfig.defaultDerivationPath;
      case BitcoinNetwork.testnet:
        return TestnetConfig.defaultDerivationPath;
    }
  }

  /// Get the API endpoint for the specified network.
  static String getApiEndpoint(BitcoinNetwork network) {
    switch (network) {
      case BitcoinNetwork.mainnet:
        return MainnetConfig.apiEndpoint;
      case BitcoinNetwork.testnet:
        return TestnetConfig.apiEndpoint;
    }
  }

  /// Get the network name for the specified network.
  static String getNetworkName(BitcoinNetwork network) {
    switch (network) {
      case BitcoinNetwork.mainnet:
        return MainnetConfig.name;
      case BitcoinNetwork.testnet:
        return TestnetConfig.name;
    }
  }
}

/// Utility helpers for constructing explorer URLs.
class NetworkExplorer {
  static String transactionUrl(BitcoinNetwork network, String txid) {
    final base = switch (network) {
      BitcoinNetwork.mainnet => 'https://mempool.space/tx/',
      BitcoinNetwork.testnet => 'https://mempool.space/testnet/tx/',
    };
    return '$base$txid';
  }
}
