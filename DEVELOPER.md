# BitNest Developer Documentation

This document provides comprehensive guidance for developers working on the BitNest Bitcoin wallet application.

## Table of Contents

1. [Local Development Environment Setup](#local-development-environment-setup)
2. [Running on Emulators](#running-on-emulators)
3. [Testing](#testing)
4. [Using the Mock API](#using-the-mock-api)
5. [Extending the Wallet: Adding Derivation Paths and Coin Types](#extending-the-wallet)
6. [Security Considerations](#security-considerations)
7. [API Endpoint Management](#api-endpoint-management)
8. [Project Structure](#project-structure)
9. [Code Style and Conventions](#code-style-and-conventions)
10. [Troubleshooting](#troubleshooting)

---

## Local Development Environment Setup

### Prerequisites

Before you begin, ensure you have the following installed:

#### Required Software

1. **Flutter SDK** (stable channel, version 3.24.0 or later)
   ```bash
   # Check Flutter installation
   flutter --version
   
   # If not installed, follow: https://docs.flutter.dev/get-started/install
   ```

2. **Dart SDK** (included with Flutter)
   ```bash
   dart --version
   ```

3. **Git**
   ```bash
   git --version
   ```

#### Platform-Specific Requirements

**For Android Development:**
- Android Studio (latest stable)
- Android SDK (API level 21+)
- Android SDK Platform-Tools
- Java Development Kit (JDK) 17 or later

**For iOS Development (macOS only):**
- Xcode (latest stable, 14.0+)
- Xcode Command Line Tools
- CocoaPods (for iOS dependencies)
  ```bash
  sudo gem install cocoapods
  ```

**For macOS Development:**
- Xcode (latest stable)
- macOS SDK

**For Linux Development:**
- CMake
- Ninja
- GTK 3 development libraries
- Clang

**For Windows Development:**
- Visual Studio 2022 with C++ development tools
- Windows SDK

### Initial Setup

1. **Clone the Repository**
   ```bash
   git clone <repository-url>
   cd bitnest
   ```

2. **Install Flutter Dependencies**
   ```bash
   flutter pub get
   ```

3. **Verify Installation**
   ```bash
   # Check Flutter doctor for any missing dependencies
   flutter doctor -v
   
   # Run Flutter analyze to check for issues
   flutter analyze
   ```

4. **Generate Mock Files (if using Mockito)**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

### IDE Setup

#### VS Code

1. Install the Flutter extension
2. Install the Dart extension
3. Configure settings:
   ```json
   {
     "dart.lineLength": 80,
     "editor.formatOnSave": true,
     "dart.enableSdkFormatter": true
   }
   ```

#### Android Studio / IntelliJ IDEA

1. Install Flutter and Dart plugins
2. Configure Flutter SDK path in settings
3. Enable Dart analysis

---

## Running on Emulators

### Android Emulator

#### 1. Create an Android Virtual Device (AVD)

**Using Android Studio:**
1. Open Android Studio
2. Go to **Tools > Device Manager**
3. Click **Create Device**
4. Select a device (e.g., Pixel 5)
5. Select a system image (API 33+ recommended)
6. Click **Finish**

**Using Command Line:**
```bash
# List available system images
flutter emulators

# Create an emulator (if using avdmanager)
avdmanager create avd -n bitnest_emulator -k "system-images;android-33;google_apis;x86_64"
```

#### 2. Start the Android Emulator

**Using Android Studio:**
- Open Device Manager and click the play button next to your AVD

**Using Command Line:**
```bash
# List available emulators
flutter emulators

# Launch a specific emulator
flutter emulators --launch <emulator_id>

# Or use emulator command directly
emulator -avd bitnest_emulator
```

#### 3. Run the App

```bash
# Run on the connected emulator/device
flutter run

# Run on a specific device
flutter devices  # List available devices
flutter run -d <device_id>

# Run in release mode
flutter run --release

# Run with hot reload enabled (default)
flutter run --hot
```

### iOS Simulator (macOS only)

#### 1. List Available Simulators

```bash
# List all available simulators
xcrun simctl list devices

# Or use Flutter command
flutter emulators
```

#### 2. Launch iOS Simulator

**Using Xcode:**
1. Open Xcode
2. Go to **Xcode > Open Developer Tool > Simulator**
3. Select a device from **File > Open Simulator**

**Using Command Line:**
```bash
# Launch default simulator
open -a Simulator

# Launch specific simulator
xcrun simctl boot "iPhone 15 Pro"

# Or use Flutter
flutter emulators --launch apple_ios_simulator
```

#### 3. Run the App

```bash
# Run on iOS simulator
flutter run -d ios

# Run on specific simulator
flutter run -d <simulator_id>

# Run in release mode
flutter run --release -d ios
```

### macOS Desktop

```bash
# Run on macOS
flutter run -d macos

# Build for macOS
flutter build macos
```

### Linux Desktop

```bash
# Run on Linux
flutter run -d linux

# Build for Linux
flutter build linux
```

### Windows Desktop

```bash
# Run on Windows
flutter run -d windows

# Build for Windows
flutter build windows
```

### Useful Flutter Run Options

```bash
# Run with verbose logging
flutter run -v

# Run with specific flavor (if configured)
flutter run --flavor dev

# Run with specific entry point
flutter run -t lib/main_dev.dart

# Run with debugging enabled
flutter run --debug

# Profile mode (for performance testing)
flutter run --profile

# Release mode (optimized)
flutter run --release
```

---

## Testing

### Test Structure

The test suite is organized into three categories:

```
test/
├── unit/              # Unit tests for services and utilities
├── widget/            # Widget tests for UI components
├── integration/       # Integration tests for end-to-end flows
├── providers/         # Provider state management tests
├── services/          # Service layer tests
└── ui/                # UI screen and widget tests
```

### Running Tests

#### Run All Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# View coverage report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

#### Run Specific Test Files

```bash
# Run a specific test file
flutter test test/services/key_service_test.dart

# Run tests matching a pattern
flutter test test/services/

# Run a specific test by name
flutter test --name "test mnemonic generation"
```

#### Run Tests with Verbose Output

```bash
flutter test --verbose
```

#### Run Tests in Watch Mode

```bash
# Automatically re-run tests on file changes
flutter test --watch
```

### Writing Tests

#### Unit Test Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bitnest/services/key_service.dart';

void main() {
  group('KeyService', () {
    test('generates valid 24-word mnemonic', () {
      final service = KeyService();
      final mnemonic = service.generateMnemonic(wordCount: 24);
      
      expect(mnemonic.split(' ').length, 24);
      expect(service.validateMnemonic(mnemonic), isTrue);
    });
  });
}
```

#### Widget Test Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bitnest/ui/screens/receive_screen.dart';

void main() {
  testWidgets('ReceiveScreen displays address', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiveScreen(
          account: mockAccount,
          onGenerateNextAddress: () {},
        ),
      ),
    );
    
    expect(find.text('Receive Bitcoin'), findsOneWidget);
  });
}
```

#### Integration Test Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  testWidgets('wallet creation flow', (tester) async {
    // Test end-to-end wallet creation
  });
}
```

### Mock API in Tests

See [Using the Mock API](#using-the-mock-api) section for details on using `MockApiService` in tests.

### Test Coverage

The project aims for 80%+ code coverage. Generate coverage reports:

```bash
# Generate coverage
flutter test --coverage

# View HTML report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Using the Mock API

The `MockApiService` class provides a mock implementation of `ApiService` for testing without making actual network requests.

### Location

`lib/services/mock_api_service.dart`

### Basic Usage

```dart
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/models/utxo.dart';

void main() {
  test('test with mock API', () async {
    // Create mock service
    final mockApi = MockApiService();
    
    // Set up mock data
    final address = 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh';
    mockApi.setAddressBalance(address, BigInt.from(100000)); // 0.001 BTC
    
    // Use in your test
    final balance = await mockApi.getAddressBalance(address);
    expect(balance, BigInt.from(100000));
  });
}
```

### Available Mock Methods

#### Setting Address Balance

```dart
mockApi.setAddressBalance('bc1q...', BigInt.from(1000000));
final balance = await mockApi.getAddressBalance('bc1q...');
```

#### Setting UTXOs

```dart
final utxos = [
  UTXO(
    txid: 'abc123...',
    vout: 0,
    value: BigInt.from(500000),
    scriptPubKey: '0014...',
  ),
];
mockApi.setAddressUtxos('bc1q...', utxos);
final fetchedUtxos = await mockApi.getAddressUtxos('bc1q...');
```

#### Setting Transactions

```dart
final transactions = [
  Transaction(
    txid: 'def456...',
    status: TransactionStatus.confirmed,
    confirmations: 6,
    // ... other fields
  ),
];
mockApi.setAddressTransactions('bc1q...', transactions);
final fetched = await mockApi.getAddressTransactions('bc1q...');
```

#### Setting Fee Estimates

```dart
mockApi.setFeeEstimates({
  1: 50,   // 50 sat/vB for 1 block
  3: 20,   // 20 sat/vB for 3 blocks
  6: 10,   // 10 sat/vB for 6 blocks
});
final estimates = await mockApi.getFeeEstimates();
```

#### Setting Individual Transactions

```dart
final tx = Transaction(/* ... */);
mockApi.setTransaction('txid123', tx);
final fetched = await mockApi.getTransaction('txid123');
```

### Using Mock API in Provider Tests

```dart
import 'package:bitnest/providers/wallet_provider.dart';
import 'package:bitnest/services/mock_api_service.dart';
import 'package:bitnest/services/key_service.dart';

void main() {
  test('WalletProvider fetches balance', () async {
    final mockApi = MockApiService();
    final keyService = KeyService();
    
    final provider = WalletProvider(
      keyService: keyService,
      apiService: mockApi,
    );
    
    // Set up mock data
    mockApi.setAddressBalance('bc1q...', BigInt.from(1000000));
    
    // Test provider behavior
    await provider.fetchAccountUtxos('account-id');
    // ... assertions
  });
}
```

### Clearing Mock Data

```dart
// Clear all mock data between tests
mockApi.clear();
```

### Network Switching

```dart
// Mock API respects network switching
final mockApi = MockApiService(initialNetwork: BitcoinNetwork.testnet);
mockApi.setNetwork(BitcoinNetwork.mainnet);
```

### Default Mock Responses

If no mock data is set, `MockApiService` returns:
- **Balance**: `BigInt.zero`
- **UTXOs**: Empty list
- **Transactions**: Empty list
- **Fee Estimates**: Default values (1: 50, 3: 20, 6: 10, 12: 5, 24: 2)
- **Transaction**: Throws `ApiException` with 404 status

---

## Extending the Wallet: Adding Derivation Paths and Coin Types

BitNest is designed to be extensible. This section explains how to add new derivation paths and coin types.

### Architecture Overview

The wallet uses a hierarchical structure:

1. **Network Configuration** (`lib/utils/networks.dart`): Defines coin types and default paths
2. **Derivation Scheme** (`lib/services/key_service.dart`): Defines address types (Legacy, P2SH-Segwit, Native Segwit)
3. **Account Derivation** (`lib/providers/wallet_provider.dart`): Builds full derivation paths

### Derivation Path Format

BitNest follows BIP44/BIP49/BIP84 standards:

```
m / purpose' / coin_type' / account' / change / address_index
```

- **purpose**: 44 (Legacy), 49 (P2SH-Segwit), 84 (Native Segwit)
- **coin_type**: 0 (Bitcoin Mainnet), 1 (Bitcoin Testnet), etc.
- **account**: Account index (0, 1, 2, ...)
- **change**: 0 (external/receive), 1 (internal/change)
- **address_index**: Address index within account

### Adding a New Coin Type

#### Step 1: Define Network Configuration

Edit `lib/utils/networks.dart`:

```dart
/// Bitcoin network types supported by the application.
enum BitcoinNetwork {
  mainnet,
  testnet,
  // Add your new network
  regtest,  // Example: Bitcoin Regtest
}

/// Network configuration constants for Bitcoin Regtest.
class RegtestConfig {
  static const String name = 'Bitcoin Regtest';
  static const String networkId = 'regtest';
  static const int coinType = 1;  // Same as testnet for regtest
  static const String defaultDerivationPath = "m/84'/1'/0'";
  static const String apiEndpoint = 'http://localhost:3000';  // Local node
  static const int magicBytes = 0xDAB5BFFA;
  static const int defaultPort = 18444;
}
```

#### Step 2: Update NetworkConfig Helper

In `lib/utils/networks.dart`, update `NetworkConfig`:

```dart
class NetworkConfig {
  static int getCoinType(BitcoinNetwork network) {
    switch (network) {
      case BitcoinNetwork.mainnet:
        return MainnetConfig.coinType;
      case BitcoinNetwork.testnet:
        return TestnetConfig.coinType;
      case BitcoinNetwork.regtest:  // Add case
        return RegtestConfig.coinType;
    }
  }
  
  // Update other methods similarly...
}
```

#### Step 3: Update Network Provider

The `NetworkProvider` should automatically handle the new network if it's added to the enum. Update UI if needed:

```dart
// In settings_screen.dart or network selection UI
ListTile(
  title: Text('Network'),
  trailing: PopupMenuButton<BitcoinNetwork>(
    onSelected: (network) {
      networkProvider.switchNetwork(network);
    },
    itemBuilder: (context) => [
      PopupMenuItem(value: BitcoinNetwork.mainnet, child: Text('Mainnet')),
      PopupMenuItem(value: BitcoinNetwork.testnet, child: Text('Testnet')),
      PopupMenuItem(value: BitcoinNetwork.regtest, child: Text('Regtest')),  // Add
    ],
  ),
)
```

### Adding a New Derivation Path (Purpose)

#### Step 1: Add to DerivationScheme Enum

Edit `lib/services/key_service.dart`:

```dart
enum DerivationScheme {
  legacy,        // BIP44: m/44'/coin'/account'
  p2shSegwit,    // BIP49: m/49'/coin'/account'
  nativeSegwit,  // BIP84: m/84'/coin'/account'
  // Add new scheme
  taproot,       // BIP86: m/86'/coin'/account'
}
```

#### Step 2: Update Derivation Logic

In `lib/services/key_service.dart`, add address generation logic:

```dart
String deriveAddress(
  String xpub,
  String derivationPath,
  DerivationScheme scheme,
) {
  switch (scheme) {
    case DerivationScheme.legacy:
      return _deriveLegacyAddress(xpub, derivationPath);
    case DerivationScheme.p2shSegwit:
      return _deriveP2shSegwitAddress(xpub, derivationPath);
    case DerivationScheme.nativeSegwit:
      return _deriveNativeSegwitAddress(xpub, derivationPath);
    case DerivationScheme.taproot:  // Add case
      return _deriveTaprootAddress(xpub, derivationPath);
  }
}

String _deriveTaprootAddress(String xpub, String path) {
  // Implement Taproot (BIP86) address derivation
  // This requires additional cryptographic operations
  // See BIP86 specification for details
}
```

#### Step 3: Update Wallet Provider

In `lib/providers/wallet_provider.dart`, update path building:

```dart
int _getPurposeForScheme(DerivationScheme scheme) {
  switch (scheme) {
    case DerivationScheme.legacy:
      return 44;
    case DerivationScheme.p2shSegwit:
      return 49;
    case DerivationScheme.nativeSegwit:
      return 84;
    case DerivationScheme.taproot:  // Add case
      return 86;
  }
}

DerivationScheme _getDerivationSchemeFromPath(String path) {
  if (path.contains("44'")) {
    return DerivationScheme.legacy;
  } else if (path.contains("49'")) {
    return DerivationScheme.p2shSegwit;
  } else if (path.contains("84'")) {
    return DerivationScheme.nativeSegwit;
  } else if (path.contains("86'")) {  // Add case
    return DerivationScheme.taproot;
  }
  return DerivationScheme.nativeSegwit;  // Default
}
```

#### Step 4: Update Transaction Service

If the new derivation scheme requires different transaction building:

```dart
// In lib/services/transaction_service.dart
// Update transaction building logic to support new address type
```

### Testing New Derivation Paths

```dart
test('Taproot address derivation', () {
  final service = KeyService();
  final mnemonic = service.generateMnemonic();
  final xprv = service.deriveMasterXprv(mnemonic);
  final xpub = service.deriveMasterXpub(xprv);
  
  final address = service.deriveAddress(
    xpub,
    "m/86'/0'/0'/0/0",
    DerivationScheme.taproot,
  );
  
  expect(address, startsWith('bc1p'));  // Taproot addresses start with bc1p
});
```

### Best Practices

1. **Follow BIP Standards**: Always follow the relevant BIP (BIP44, BIP49, BIP84, BIP86, etc.)
2. **Test Thoroughly**: Write comprehensive tests for new derivation paths
3. **Update Documentation**: Document new coin types and derivation paths
4. **Backward Compatibility**: Ensure existing wallets continue to work
5. **Security Review**: Have new cryptographic code reviewed

---

## Security Considerations

### Secure Storage

BitNest uses `flutter_secure_storage` for sensitive data:

- **Private Keys**: Never stored in plain text
- **Mnemonics**: Encrypted using platform keychain/keystore
- **PINs**: Hashed using SHA-256 before storage

### Key Management

1. **Never Log Private Keys**: Private keys are never logged or printed
2. **Memory Safety**: Keys are cleared from memory when possible
3. **Secure Random**: Uses cryptographically secure random number generation

### API Security

1. **HTTPS Only**: All API endpoints must use HTTPS
2. **Certificate Pinning**: Consider implementing certificate pinning for production
3. **Rate Limiting**: Be aware of API rate limits
4. **Error Handling**: Don't expose sensitive information in error messages

### Biometric Authentication

- Uses `local_auth` package for platform-native biometrics
- Falls back to PIN if biometrics unavailable
- Requires authentication for:
  - Viewing mnemonics
  - Sending transactions
  - Exporting private keys

### Code Security

1. **No Hardcoded Secrets**: Never commit API keys or secrets
2. **Dependency Updates**: Regularly update dependencies for security patches
3. **Code Review**: All security-related code must be reviewed
4. **Static Analysis**: Run `flutter analyze` before committing

### Best Practices

1. **Principle of Least Privilege**: Request only necessary permissions
2. **Input Validation**: Validate all user inputs
3. **Output Sanitization**: Sanitize data before displaying
4. **Error Messages**: Don't leak sensitive information in errors

---

## API Endpoint Management

### Current Endpoints

Endpoints are defined in `lib/utils/networks.dart`:

```dart
class MainnetConfig {
  static const String apiEndpoint = 'https://bitcoin-rpc.publicnode.com';
}

class TestnetConfig {
  static const String apiEndpoint = 'https://bitcoin-testnet-rpc.publicnode.com';
}
```

### Rotating API Endpoints

#### Option 1: Update Network Configuration

Edit `lib/utils/networks.dart`:

```dart
class MainnetConfig {
  // Old endpoint
  // static const String apiEndpoint = 'https://bitcoin-rpc.publicnode.com';
  
  // New endpoint
  static const String apiEndpoint = 'https://blockstream.info/api';
}
```

**Note**: This requires a code change and app update. For production apps, consider using a configuration file or remote config.

#### Option 2: Environment-Based Configuration

Create `lib/config/api_config.dart`:

```dart
class ApiConfig {
  static String getMainnetEndpoint() {
    // Check environment variable or config file
    const envEndpoint = String.fromEnvironment('MAINNET_API_ENDPOINT');
    if (envEndpoint.isNotEmpty) {
      return envEndpoint;
    }
    // Default fallback
    return 'https://bitcoin-rpc.publicnode.com';
  }
  
  static String getTestnetEndpoint() {
    const envEndpoint = String.fromEnvironment('TESTNET_API_ENDPOINT');
    if (envEndpoint.isNotEmpty) {
      return envEndpoint;
    }
    return 'https://bitcoin-testnet-rpc.publicnode.com';
  }
}
```

Update `NetworkConfig`:

```dart
static String getApiEndpoint(BitcoinNetwork network) {
  switch (network) {
    case BitcoinNetwork.mainnet:
      return ApiConfig.getMainnetEndpoint();
    case BitcoinNetwork.testnet:
      return ApiConfig.getTestnetEndpoint();
  }
}
```

Build with custom endpoint:

```bash
flutter build apk --dart-define=MAINNET_API_ENDPOINT=https://blockstream.info/api
```

#### Option 3: Runtime Configuration (Advanced)

For production apps, consider:

1. **Remote Config**: Fetch endpoints from a remote configuration service
2. **Multiple Endpoints**: Implement failover to backup endpoints
3. **Endpoint Health Checks**: Monitor endpoint availability

Example implementation:

```dart
class ApiEndpointManager {
  final List<String> mainnetEndpoints = [
    'https://blockstream.info/api',
    'https://mempool.space/api',
    'https://bitcoin-rpc.publicnode.com',
  ];
  
  String? _currentEndpoint;
  int _currentIndex = 0;
  
  String getCurrentEndpoint() {
    return _currentEndpoint ?? mainnetEndpoints[0];
  }
  
  Future<void> rotateEndpoint() async {
    _currentIndex = (_currentIndex + 1) % mainnetEndpoints.length;
    _currentEndpoint = mainnetEndpoints[_currentIndex];
  }
  
  Future<bool> healthCheck(String endpoint) async {
    try {
      final response = await http.get(Uri.parse('$endpoint/blocks/tip/height'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
```

### Adding New Endpoints

1. **Update Network Config**: Add endpoint to appropriate config class
2. **Update Tests**: Ensure tests work with new endpoint
3. **Update Documentation**: Document endpoint changes
4. **Monitor**: Monitor endpoint performance and availability

### Endpoint Requirements

API endpoints must support Esplora-style REST API:

- `GET /address/{address}` - Address info
- `GET /address/{address}/utxo` - UTXOs
- `GET /address/{address}/txs` - Transactions
- `GET /tx/{txid}` - Transaction details
- `GET /tx/{txid}/hex` - Raw transaction hex
- `GET /fee-estimates` - Fee estimates
- `POST /tx` - Broadcast transaction

### Testing Endpoint Changes

```dart
test('API endpoint rotation', () async {
  final service = ApiService();
  expect(service.baseUrl, 'https://bitcoin-rpc.publicnode.com');
  
  // Simulate endpoint change
  // (In real implementation, this would update NetworkConfig)
  service.setNetwork(BitcoinNetwork.testnet);
  expect(service.baseUrl, 'https://bitcoin-testnet-rpc.publicnode.com');
});
```

---

## Project Structure

```
bitnest/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── models/                   # Data models
│   │   ├── wallet.dart
│   │   ├── account.dart
│   │   ├── transaction.dart
│   │   └── utxo.dart
│   ├── providers/                # State management
│   │   ├── wallet_provider.dart
│   │   ├── network_provider.dart
│   │   ├── settings_provider.dart
│   │   └── send_provider.dart
│   ├── services/                 # Business logic
│   │   ├── key_service.dart
│   │   ├── api_service.dart
│   │   ├── mock_api_service.dart
│   │   ├── transaction_service.dart
│   │   └── broadcast_service.dart
│   ├── ui/
│   │   ├── screens/             # Full-screen views
│   │   │   ├── wallet_screen.dart
│   │   │   ├── send_screen.dart
│   │   │   ├── receive_screen.dart
│   │   │   └── settings_screen.dart
│   │   └── widgets/             # Reusable components
│   │       └── transaction_list.dart
│   └── utils/
│       ├── networks.dart        # Network configuration
│       ├── responsive.dart      # Responsive utilities
│       └── debug_logger.dart    # Logging utilities
├── test/
│   ├── unit/                    # Unit tests
│   ├── widget/                  # Widget tests
│   ├── integration/             # Integration tests
│   ├── providers/               # Provider tests
│   └── services/                # Service tests
├── android/                     # Android-specific code
├── ios/                         # iOS-specific code
├── macos/                       # macOS-specific code
├── linux/                       # Linux-specific code
├── windows/                     # Windows-specific code
├── web/                         # Web-specific code
├── pubspec.yaml                 # Dependencies
└── README.md                    # User-facing documentation
```

---

## Code Style and Conventions

### Dart Style Guide

Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide:

1. **Naming**: Use `camelCase` for variables, `PascalCase` for classes
2. **Line Length**: Maximum 80 characters
3. **Formatting**: Use `dart format` before committing

### Flutter Conventions

1. **Widget Composition**: Prefer composition over large widgets
2. **State Management**: Use Provider for app-wide state
3. **Adaptive Widgets**: Use `.adaptive()` constructors where available
4. **Semantic Labels**: Always add semantic labels for accessibility

### Code Organization

1. **One Class Per File**: Each class in its own file
2. **Group Related Code**: Keep related functionality together
3. **Private by Default**: Make classes and methods private unless needed publicly

### Documentation

1. **Document Public APIs**: Use dartdoc comments for public classes/methods
2. **Explain Complex Logic**: Add comments for non-obvious code
3. **Update README**: Keep documentation current

### Git Workflow

1. **Feature Branches**: Create branches for features
2. **Descriptive Commits**: Write clear commit messages
3. **Pull Requests**: Submit PRs for review before merging

---

## Troubleshooting

### Common Issues

#### Flutter Doctor Issues

```bash
# Run Flutter doctor to identify issues
flutter doctor -v

# Common fixes:
# - Install missing Android SDK components
# - Accept Android licenses: flutter doctor --android-licenses
# - Update Xcode command line tools
```

#### Build Failures

**Android:**
```bash
# Clean build
flutter clean
flutter pub get
flutter build apk

# Check Gradle version
cd android && ./gradlew --version
```

**iOS:**
```bash
# Clean build
flutter clean
cd ios && pod deintegrate && pod install
flutter build ios
```

#### Test Failures

```bash
# Clear test cache
flutter test --reporter expanded

# Run specific test with verbose output
flutter test test/services/key_service_test.dart -v
```

#### Emulator Issues

**Android Emulator Not Starting:**
```bash
# Check available emulators
flutter emulators

# Start emulator manually
emulator -avd <avd_name> -verbose

# Check Android SDK path
echo $ANDROID_HOME
```

**iOS Simulator Issues:**
```bash
# Reset simulator
xcrun simctl erase all

# List available simulators
xcrun simctl list devices
```

### Getting Help

1. **Check Logs**: Review Flutter and platform-specific logs
2. **Flutter Issues**: Search [Flutter GitHub Issues](https://github.com/flutter/flutter/issues)
3. **Stack Overflow**: Search for Flutter-specific questions
4. **Documentation**: Review [Flutter Documentation](https://docs.flutter.dev)

---

## Additional Resources

- [Flutter Documentation](https://docs.flutter.dev)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Provider Package](https://pub.dev/packages/provider)
- [BIP32 Specification](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
- [BIP39 Specification](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [BIP44 Specification](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki)

---

**Last Updated**: 2024

For questions or contributions, please refer to the project's contribution guidelines.





