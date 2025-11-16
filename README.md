# BitNest

A Bitcoin wallet application built with Flutter, supporting both mainnet and testnet networks.

## Purpose

BitNest is a mobile Bitcoin wallet application that provides secure key management, HD wallet functionality, and a user-friendly interface for managing Bitcoin addresses and transactions. The app supports both Bitcoin mainnet (production) and testnet (testing) networks.

## Features

- **HD Wallet Support**: Hierarchical Deterministic (HD) wallet following BIP32/BIP44 standards
- **BIP39 Mnemonic Phrases**: Generate and restore wallets using 12/24-word mnemonic phrases
- **Multi-Network Support**: Switch between Bitcoin mainnet and testnet
- **Secure Storage**: Sensitive data encrypted using Flutter Secure Storage
- **QR Code Support**: Generate and scan QR codes for addresses and payment requests
- **Adaptive UI**: Platform-aware widgets that adapt to iOS and Android design guidelines
- **Responsive Design**: Supports devices from small phones to tablets

## Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (included with Flutter)
- Android Studio / Xcode (for mobile development)
- Git

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd bitnest
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the Application

```bash
# Run on connected device/emulator
flutter run

# Run on specific platform
flutter run -d ios
flutter run -d android
```

### 4. Run Tests

```bash
# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage
```

## Project Structure

```
lib/
├── main.dart                 # Application entry point
├── models/                   # Data models (Wallet, Transaction, etc.)
├── providers/                # ChangeNotifier-based state management
├── services/                 # Business logic (wallet, blockchain API)
├── ui/
│   ├── screens/             # Full-screen views
│   └── widgets/             # Reusable UI components
└── utils/
    └── networks.dart        # Network configuration (mainnet/testnet)

test/                         # Unit and widget tests
```

## State Management

The app uses **Provider** for state management, following the ChangeNotifier pattern. All state providers are located in `lib/providers/`.

## Network Configuration

Network-specific constants are defined in `lib/utils/networks.dart`. The app supports:

- **Mainnet**: Production Bitcoin network (coin type: 0)
- **Testnet**: Testing Bitcoin network (coin type: 1)

Switch between networks using the `BitcoinNetwork` enum.

## Adaptive UI Approach

The application uses adaptive widgets wherever possible to provide a native look and feel on both iOS and Android:

### Adaptive Widgets Used

- `Switch.adaptive()` - Platform-native switch controls
- `CupertinoSwitch.adaptive()` - iOS-style switches (when available)
- `Material` widgets with platform-aware theming

### Responsive Design Strategy

The UI is designed to be responsive across different screen sizes:

1. **Layout Breakpoints**:
   - Small phones: < 600dp width
   - Large phones: 600-840dp width
   - Tablets: > 840dp width

2. **Techniques Used**:
   - `LayoutBuilder` for responsive layouts
   - `MediaQuery` for screen size detection
   - Flexible/Expanded widgets for adaptive sizing
   - Grid layouts that adjust column count based on screen width
   - ConstrainedBox and SizedBox for consistent spacing

3. **Platform Fallbacks**:
   - Where adaptive constructors don't exist, we use `Platform.isIOS` / `Platform.isAndroid` checks
   - Material widgets styled to match platform conventions
   - Custom widgets that adapt based on `Theme.of(context).platform`

## Dependencies

### Core Dependencies

- **provider** (^6.1.2): State management using ChangeNotifier pattern
- **flutter_secure_storage** (^9.2.2): Encrypted storage for sensitive data (keys, mnemonics)
- **bip39** (^1.0.6): BIP39 mnemonic phrase generation and validation
- **bitcoin_dart** (^0.5.0): Bitcoin HD wallet operations, key derivation, address generation
- **qr_flutter** (^4.1.0): QR code generation for addresses and payment requests
- **http** (^1.2.2): HTTP client for blockchain API calls
- **intl** (^0.19.0): Internationalization and localization support
- **flutter_localizations**: Built-in Flutter localization support

### Development Dependencies

- **flutter_test**: Flutter testing framework
- **mockito** (^5.4.4): Mocking framework for unit tests
- **flutter_lints** (^5.0.0): Recommended linting rules

## Development Notes

- All UI widgets that support an `adaptive()` constructor must use it
- Where no adaptive constructor exists, use platform-aware fallbacks (documented in code)
- Network configuration is centralized in `lib/utils/networks.dart`
- State management follows Provider pattern with ChangeNotifier

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]