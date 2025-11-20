# BitNest UI Flow Diagram

## Navigation Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                         App Launch                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌────────────────┐
                    │  SplashScreen   │
                    │  (1.5s delay)   │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌────────────────┐
                    │ Check App State │
                    │ - Onboarding?   │
                    │ - Has Wallets?  │
                    └────────┬─────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
    ┌──────────────────────┐   ┌──────────────────┐
    │  OnboardingScreen     │   │   WalletScreen   │
    │  (First Run Only)     │   │   (Main App)     │
    └───────────┬───────────┘   └────────┬─────────┘
                │                        │
                │                        │
                ▼                        │
    ┌──────────────────────┐            │
    │  Welcome Page        │            │
    │  - App intro         │            │
    │  - Get Started btn   │            │
    └───────────┬───────────┘            │
                │                        │
                ▼                        │
    ┌──────────────────────┐            │
    │  Create/Import Page   │            │
    │  - Create Wallet      │            │
    │  - Import Wallet      │            │
    └───────────┬───────────┘            │
                │                        │
                └──────────┬─────────────┘
                           │
                           ▼
                ┌──────────────────┐
                │   WalletScreen   │
                │   (Main App)     │
                └─────────┬─────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Empty State  │  │ Wallet List  │  │ Wallet View  │
│ - Welcome    │  │ - Select     │  │ - Accounts   │
│ - Create Btn │  │   Wallet     │  │ - Balance    │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                  │
       │                 │                  │
       └─────────────────┴──────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   Account Actions     │
              └───────┬───────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ SendScreen  │ │ReceiveScreen│ │Transactions │
│ - Address   │ │ - QR Code   │ │ - History   │
│ - Amount    │ │ - Address   │ │ - Details   │
│ - Fee       │ │ - Copy      │ │             │
│ - UTXOs     │ │             │ │             │
└──────┬──────┘ └─────────────┘ └──────┬──────┘
       │                                │
       │                                │
       ▼                                ▼
┌─────────────┐                ┌─────────────┐
│ Transaction │                │ Transaction │
│ Detail      │                │ Detail      │
│ Screen      │                │ Screen      │
└─────────────┘                └─────────────┘
```

## Screen Details

### 1. SplashScreen
- **Purpose**: Show during app initialization
- **Duration**: Minimum 1.5 seconds
- **Features**:
  - App logo/icon
  - App name
  - Loading indicator (adaptive)
  - Gradient background

### 2. OnboardingScreen
- **Purpose**: First-time user experience
- **Flow**:
  1. Welcome Page
     - App introduction
     - "Get Started" button
  2. Create/Import Page
     - Create new wallet option
     - Import existing wallet option
- **Completion**: After wallet creation/import, navigates to WalletScreen

### 3. WalletScreen (Main App)
- **Purpose**: Primary interface for wallet management
- **States**:
  - **Empty State**: No wallets
    - Welcome message
    - "Create Wallet" button
  - **Wallet List**: Multiple wallets
    - List of wallets
    - Select wallet to view
  - **Wallet View**: Selected wallet
    - Account list
    - Balance display
    - Account actions (Send, Receive, Transactions)
- **Navigation**:
  - Settings icon → SettingsScreen
  - Account actions → SendScreen, ReceiveScreen, TransactionsScreen

### 4. SendScreen
- **Purpose**: Send Bitcoin transactions
- **Features**:
  - Recipient address input
  - Amount input
  - Fee selection (preset or manual)
  - UTXO selection
  - Transaction summary
  - Biometric authentication before sending

### 5. ReceiveScreen
- **Purpose**: Receive Bitcoin
- **Features**:
  - QR code display
  - Address display (selectable)
  - Copy address button
  - Generate new address option
  - Address details (derivation path, account info)

### 6. TransactionsScreen
- **Purpose**: View transaction history
- **Features**:
  - Transaction list
  - Pull-to-refresh (adaptive)
  - Transaction details on tap
  - Empty state handling

### 7. TransactionDetailScreen
- **Purpose**: View detailed transaction information
- **Features**:
  - Transaction summary
  - Inputs/outputs
  - Transaction hex
  - Status indicators

### 8. SettingsScreen
- **Purpose**: App settings and wallet management
- **Sections**:
  - **Network**: Toggle mainnet/testnet
  - **Display**: Theme, Currency
  - **Wallet**: Export xpub, Backup mnemonic
  - **Security**: Biometrics, PIN, Wipe wallet

## Navigation Patterns

### Adaptive Navigation
- **Android**: Material Design transitions (FadeUpwards)
- **iOS/macOS**: Cupertino transitions
- **Other platforms**: Material Design fallback

### Responsive Design
- Text scaling clamped between 0.8x and 1.2x
- Adaptive widgets used throughout:
  - `CircularProgressIndicator.adaptive()`
  - `Switch.adaptive()`
  - `RefreshIndicator.adaptive()`
  - `CupertinoPageTransitionsBuilder()` for iOS/macOS

### State Management
- **Providers**: All state managed via Provider pattern
  - NetworkProvider: Network selection
  - SettingsProvider: App settings
  - WalletProvider: Wallet/account management
  - SendProvider: Transaction sending
  - TransactionsProvider: Transaction history

## Provider Dependencies

```
NetworkProvider (no dependencies)
    │
SettingsProvider (depends on SharedPreferences)
    │
WalletProvider (depends on KeyService, ApiService)
    │
    ├─── SendProvider (depends on WalletProvider, TransactionService, BroadcastService, KeyService)
    │
    └─── TransactionsProvider (depends on ApiService)
```

## Key Navigation Points

1. **App Launch** → SplashScreen → Check state → OnboardingScreen or WalletScreen
2. **WalletScreen** → SendScreen, ReceiveScreen, TransactionsScreen, SettingsScreen
3. **TransactionsScreen** → TransactionDetailScreen
4. **SettingsScreen** → Export/Backup dialogs, PIN dialogs

## First Run Flow

```
App Launch
    ↓
SplashScreen (1.5s)
    ↓
Check: has_completed_onboarding?
    ├─ No → OnboardingScreen
    │         ↓
    │    Welcome Page
    │         ↓
    │    Create/Import Page
    │         ↓
    │    Wallet Created/Imported
    │         ↓
    │    Mark onboarding complete
    │         ↓
    └─ Yes → WalletScreen
```

## Return Navigation

- All screens use standard Material/Cupertino navigation
- Back button/gesture returns to previous screen
- SettingsScreen accessible from WalletScreen app bar
- TransactionDetailScreen accessible from TransactionsScreen

