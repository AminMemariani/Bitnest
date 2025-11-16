# BitNest Architecture Document

## Overview

BitNest follows a layered architecture pattern with clear separation of concerns: UI, State Management (Providers), Business Logic (Services), Storage, and External APIs.

## Architecture Layers

```
┌─────────────────────────────────────────┐
│              UI Layer                    │
│  (Screens, Widgets, Adaptive UI)       │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         Provider Layer                   │
│  (State Management, ChangeNotifiers)    │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│          Service Layer                   │
│  (Business Logic, Wallet Operations)    │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         Storage Layer                    │
│  (Secure Storage, Encrypted Data)       │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│       External API Layer                 │
│  (Blockchain APIs, Esplora/Blockstream) │
└─────────────────────────────────────────┘
```

### Layer Responsibilities

- **UI Layer**: Presentation, user interaction, adaptive widgets, responsive layouts
- **Provider Layer**: State management, reactive updates, business logic coordination
- **Service Layer**: Wallet operations, key derivation, transaction building, API communication
- **Storage Layer**: Encrypted persistence of sensitive data (keys, mnemonics, preferences)
- **External API Layer**: Blockchain data fetching, transaction broadcasting, network communication

---

## Models

### Wallet Model

Represents the root wallet containing mnemonic and extended keys.

```dart
class Wallet {
  final String id;                    // UUID
  final String? mnemonic;            // BIP39 mnemonic (12/24 words) - nullable for imported wallets
  final String? xprv;                // Extended private key (encrypted) - nullable
  final String xpub;                 // Extended public key
  final DateTime createdAt;          // Wallet creation timestamp
  final String label;                // User-defined wallet name
  final BitcoinNetwork network;      // mainnet or testnet
  final bool isBackedUp;             // Whether mnemonic has been backed up
  final List<String> accountIds;     // Associated account IDs

  Wallet({
    required this.id,
    this.mnemonic,
    this.xprv,
    required this.xpub,
    required this.createdAt,
    required this.label,
    required this.network,
    this.isBackedUp = false,
    this.accountIds = const [],
  });

  // Example instance
  // Wallet(
  //   id: '550e8400-e29b-41d4-a716-446655440000',
  //   mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  //   xpub: 'xpub6C...',
  //   createdAt: DateTime(2024, 1, 1),
  //   label: 'My Bitcoin Wallet',
  //   network: BitcoinNetwork.mainnet,
  //   isBackedUp: true,
  //   accountIds: ['acc-001'],
  // );
}
```

### Account Model

Represents a single account (BIP44 account level) with derivation path and balance.

```dart
class Account {
  final String id;                   // UUID
  final String walletId;             // Parent wallet ID
  final String label;                // User-defined account name
  final String derivationPath;       // e.g., "m/84'/0'/0'" (BIP84 Native Segwit)
  final int accountIndex;            // BIP44 account index
  final String xpub;                 // Account-level extended public key
  final BitcoinNetwork network;     // mainnet or testnet
  final BigInt balance;              // Total balance in satoshis
  final int lastSyncedBlock;         // Last synced block height
  final DateTime? lastSyncedAt;      // Last sync timestamp
  final List<String> addressIds;     // Generated address IDs

  Account({
    required this.id,
    required this.walletId,
    required this.label,
    required this.derivationPath,
    required this.accountIndex,
    required this.xpub,
    required this.network,
    this.balance = BigInt.zero,
    this.lastSyncedBlock = 0,
    this.lastSyncedAt,
    this.addressIds = const [],
  });

  // Example instance
  // Account(
  //   id: 'acc-001',
  //   walletId: '550e8400-e29b-41d4-a716-446655440000',
  //   label: 'Primary Account',
  //   derivationPath: "m/84'/0'/0'",
  //   accountIndex: 0,
  //   xpub: 'zpub6...',
  //   network: BitcoinNetwork.mainnet,
  //   balance: BigInt.from(1000000), // 0.01 BTC
  //   lastSyncedBlock: 850000,
  //   lastSyncedAt: DateTime.now(),
  //   addressIds: ['addr-001', 'addr-002'],
  // );
}
```

### Transaction Model

Represents a Bitcoin transaction with inputs, outputs, and metadata.

```dart
class Transaction {
  final String id;                   // Transaction ID (txid)
  final String accountId;            // Associated account ID
  final TransactionType type;       // sent, received, or internal
  final BigInt amount;               // Transaction amount in satoshis (positive for received, negative for sent)
  final BigInt fee;                  // Transaction fee in satoshis
  final int confirmations;          // Number of confirmations
  final int blockHeight;             // Block height (0 if unconfirmed)
  final DateTime? blockTime;         // Block timestamp
  final DateTime firstSeen;          // First seen timestamp
  final String txid;                 // Transaction hash
  final List<TxInput> inputs;        // Transaction inputs
  final List<TxOutput> outputs;      // Transaction outputs
  final TransactionStatus status;    // pending, confirmed, failed

  Transaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.fee,
    this.confirmations = 0,
    this.blockHeight = 0,
    this.blockTime,
    required this.firstSeen,
    required this.txid,
    required this.inputs,
    required this.outputs,
    this.status = TransactionStatus.pending,
  });

  // Example instance
  // Transaction(
  //   id: 'tx-001',
  //   accountId: 'acc-001',
  //   type: TransactionType.received,
  //   amount: BigInt.from(500000), // 0.005 BTC
  //   fee: BigInt.zero,
  //   confirmations: 6,
  //   blockHeight: 850000,
  //   blockTime: DateTime(2024, 1, 15, 10, 30),
  //   firstSeen: DateTime(2024, 1, 15, 10, 25),
  //   txid: 'a1b2c3d4e5f6...',
  //   inputs: [...],
  //   outputs: [...],
  //   status: TransactionStatus.confirmed,
  // );
}

enum TransactionType { sent, received, internal }
enum TransactionStatus { pending, confirmed, failed }

class TxInput {
  final String txid;                 // Previous transaction ID
  final int vout;                    // Output index
  final String? address;             // Input address (if known)
  final BigInt value;                // Input value in satoshis

  TxInput({
    required this.txid,
    required this.vout,
    this.address,
    required this.value,
  });
}

class TxOutput {
  final int index;                   // Output index
  final String? address;            // Output address (null for OP_RETURN)
  final BigInt value;                // Output value in satoshis
  final bool isMine;                 // Whether this output belongs to wallet

  TxOutput({
    required this.index,
    this.address,
    required this.value,
    this.isMine = false,
  });
}
```

### UTXO Model

Represents an unspent transaction output available for spending.

```dart
class UTXO {
  final String id;                   // UUID
  final String accountId;            // Associated account ID
  final String txid;                 // Transaction ID
  final int vout;                    // Output index
  final String address;              // Address that owns this UTXO
  final BigInt value;                // Value in satoshis
  final String scriptPubKey;         // Script public key (hex)
  final int confirmations;          // Number of confirmations
  final int? blockHeight;            // Block height (null if unconfirmed)
  final bool isSpent;                // Whether this UTXO has been spent
  final String? spentByTxid;         // Transaction that spent this UTXO

  UTXO({
    required this.id,
    required this.accountId,
    required this.txid,
    required this.vout,
    required this.address,
    required this.value,
    required this.scriptPubKey,
    this.confirmations = 0,
    this.blockHeight,
    this.isSpent = false,
    this.spentByTxid,
  });

  // Example instance
  // UTXO(
  //   id: 'utxo-001',
  //   accountId: 'acc-001',
  //   txid: 'a1b2c3d4e5f6...',
  //   vout: 0,
  //   address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
  //   value: BigInt.from(100000), // 0.001 BTC
  //   scriptPubKey: '0014...',
  //   confirmations: 6,
  //   blockHeight: 850000,
  //   isSpent: false,
  // );
}
```

---

## Providers (State Management)

### WalletProvider

Manages wallet state, creation, import, and selection.

```dart
class WalletProvider extends ChangeNotifier {
  Wallet? _currentWallet;
  List<Wallet> _wallets = [];
  bool _isLoading = false;
  String? _error;

  Wallet? get currentWallet => _currentWallet;
  List<Wallet> get wallets => _wallets;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Methods:
  // - Future<void> createWallet(String label, BitcoinNetwork network)
  // - Future<void> importWallet(String mnemonic, String label, BitcoinNetwork network)
  // - Future<void> importXpub(String xpub, String label, BitcoinNetwork network)
  // - Future<void> selectWallet(String walletId)
  // - Future<void> deleteWallet(String walletId)
  // - Future<void> backupWallet(String walletId)
  // - void clearError()
}
```

### NetworkProvider

Manages network selection (mainnet/testnet) and network-specific configuration.

```dart
class NetworkProvider extends ChangeNotifier {
  BitcoinNetwork _currentNetwork = BitcoinNetwork.mainnet;
  String? _customApiEndpoint;

  BitcoinNetwork get currentNetwork => _currentNetwork;
  String get apiEndpoint => _customApiEndpoint ?? NetworkConfig.getApiEndpoint(_currentNetwork);

  // Methods:
  // - Future<void> switchNetwork(BitcoinNetwork network)
  // - void setCustomApiEndpoint(String endpoint)
  // - void resetToDefaultEndpoint()
}
```

### SyncProvider

Manages blockchain synchronization status and progress.

```dart
class SyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  int _currentBlock = 0;
  int _targetBlock = 0;
  double _progress = 0.0;
  DateTime? _lastSyncTime;
  String? _syncError;
  Map<String, SyncStatus> _accountSyncStatus = {}; // accountId -> SyncStatus

  bool get isSyncing => _isSyncing;
  int get currentBlock => _currentBlock;
  int get targetBlock => _targetBlock;
  double get progress => _progress;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get syncError => _syncError;
  Map<String, SyncStatus> get accountSyncStatus => _accountSyncStatus;

  // Methods:
  // - Future<void> syncAccount(String accountId)
  // - Future<void> syncAllAccounts()
  // - void cancelSync()
  // - SyncStatus getAccountSyncStatus(String accountId)
}

enum SyncStatus { notStarted, syncing, completed, failed }
```

### TransactionProvider

Manages transaction history, creation, and status updates.

```dart
class TransactionProvider extends ChangeNotifier {
  Map<String, List<Transaction>> _transactions = {}; // accountId -> transactions
  bool _isLoading = false;
  String? _error;
  Transaction? _pendingTransaction;

  List<Transaction> getTransactions(String accountId) => _transactions[accountId] ?? [];
  bool get isLoading => _isLoading;
  String? get error => _error;
  Transaction? get pendingTransaction => _pendingTransaction;

  // Methods:
  // - Future<void> loadTransactions(String accountId)
  // - Future<String> sendTransaction(String accountId, String toAddress, BigInt amount, {BigInt? feeRate})
  // - Future<void> updateTransactionStatus(String txid)
  // - Future<void> refreshTransactions(String accountId)
  // - void clearError()
}
```

### SettingsProvider

Manages app settings and preferences.

```dart
class SettingsProvider extends ChangeNotifier {
  bool _biometricEnabled = false;
  int _defaultFeeRate = 10; // sat/vB
  String _currency = 'BTC';
  String _language = 'en';
  bool _testnetMode = false;

  bool get biometricEnabled => _biometricEnabled;
  int get defaultFeeRate => _defaultFeeRate;
  String get currency => _currency;
  String get language => _language;
  bool get testnetMode => _testnetMode;

  // Methods:
  // - Future<void> setBiometricEnabled(bool enabled)
  // - Future<void> setDefaultFeeRate(int feeRate)
  // - Future<void> setCurrency(String currency)
  // - Future<void> setLanguage(String language)
  // - Future<void> setTestnetMode(bool enabled)
  // - Future<void> loadSettings()
  // - Future<void> saveSettings()
}
```

---

## Services

### KeyService

Handles BIP39 mnemonic generation, validation, and BIP32/BIP44 key derivation.

```dart
class KeyService {
  // Methods:
  // - Future<String> generateMnemonic({int wordCount = 24}) // 12 or 24 words
  // - bool validateMnemonic(String mnemonic)
  // - Future<Uint8List> mnemonicToSeed(String mnemonic, {String? passphrase})
  // - Future<String> deriveXprv(Uint8List seed, String derivationPath)
  // - Future<String> deriveXpub(String xprv)
  // - Future<String> derivePrivateKey(String xprv, String derivationPath)
  // - Future<String> derivePublicKey(String xpub, int addressIndex)
  // - Future<String> deriveAddress(String xpub, int addressIndex, BitcoinNetwork network)
  // - Future<Uint8List> signTransaction(Uint8List transaction, String privateKey)
}
```

### StorageService

Manages encrypted storage of sensitive data using flutter_secure_storage.

```dart
class StorageService {
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  // Methods:
  // - Future<void> saveWallet(Wallet wallet)
  // - Future<Wallet?> loadWallet(String walletId)
  // - Future<List<Wallet>> loadAllWallets()
  // - Future<void> deleteWallet(String walletId)
  // - Future<void> saveMnemonic(String walletId, String mnemonic) // Encrypted
  // - Future<String?> loadMnemonic(String walletId) // Decrypted
  // - Future<void> saveXprv(String walletId, String xprv) // Encrypted
  // - Future<String?> loadXprv(String walletId) // Decrypted
  // - Future<void> saveAccount(Account account)
  // - Future<Account?> loadAccount(String accountId)
  // - Future<List<Account>> loadAccountsForWallet(String walletId)
  // - Future<void> saveSettings(Map<String, dynamic> settings)
  // - Future<Map<String, dynamic>> loadSettings()
  // - Future<void> clearAllData() // For logout/reset
}
```

### ApiService

Wraps blockchain API clients (Esplora/Blockstream API or Electrum) for fetching blockchain data.

```dart
class ApiService {
  final String baseUrl;
  final http.Client _client = http.Client();

  ApiService({required this.baseUrl});

  // Methods:
  // - Future<BlockchainInfo> getBlockchainInfo()
  // - Future<List<UTXO>> getUtxos(String address)
  // - Future<List<UTXO>> getAccountUtxos(String xpub) // For HD wallets
  // - Future<Transaction> getTransaction(String txid)
  // - Future<List<Transaction>> getAddressTransactions(String address)
  // - Future<int> getAddressBalance(String address)
  // - Future<int> getBlockHeight()
  // - Future<BlockHeader> getBlockHeader(int height)
  // - Future<String> broadcastTransaction(String hexTx)
  // - Future<FeeEstimate> estimateFee({int blocks = 6})
}
```

### BroadcastService

Handles transaction broadcasting and confirmation tracking.

```dart
class BroadcastService {
  final ApiService _apiService;

  BroadcastService(this._apiService);

  // Methods:
  // - Future<String> broadcastTransaction(Uint8List signedTx)
  // - Future<bool> waitForConfirmation(String txid, {int timeoutSeconds = 300})
  // - Future<TransactionStatus> getTransactionStatus(String txid)
  // - Stream<TransactionStatus> watchTransaction(String txid)
}
```

---

## Security Model

### Storage Architecture

```
┌─────────────────────────────────────────┐
│         App Memory (Runtime)             │
│  - Decrypted mnemonic (temporary)       │
│  - Private keys (temporary)              │
│  - Transaction signing keys              │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│    Flutter Secure Storage (Encrypted)    │
│  - Encrypted mnemonic                    │
│  - Encrypted xprv                        │
│  - Wallet metadata (non-sensitive)       │
│  - Account data                          │
└─────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│    Platform Keychain/Keystore            │
│  - iOS: Keychain Services                │
│  - Android: EncryptedSharedPreferences   │
│    with Android Keystore                 │
└─────────────────────────────────────────┘
```

### Security Principles

1. **Mnemonic Storage**
   - Never stored in plain text
   - Encrypted using platform keychain/keystore
   - Only decrypted in memory when needed (e.g., for backup display)
   - Cleared from memory immediately after use

2. **Private Key Storage**
   - Extended private keys (xprv) encrypted at rest
   - Individual private keys derived on-demand, never stored
   - Keys cleared from memory after transaction signing

3. **Biometric Authentication**
   - Optional biometric gate for sensitive operations
   - Required for: viewing mnemonic, sending transactions, changing security settings
   - Uses `local_auth` package (to be added)
   - Fallback to PIN/password if biometric unavailable

4. **Encryption Details**
   - **iOS**: Uses Keychain Services with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
   - **Android**: Uses EncryptedSharedPreferences with Android Keystore (AES-256)
   - Keys encrypted with device-specific hardware-backed keys when available

5. **Network Security**
   - All API calls over HTTPS
   - Certificate pinning (optional, for production)
   - No sensitive data in API requests (only public keys/addresses)

6. **Memory Security**
   - Sensitive data zeroed from memory when no longer needed
   - No logging of private keys, mnemonics, or raw transaction data
   - Debug mode disabled in production builds

### Access Control Flow

```
User Action (e.g., "Send Transaction")
    ↓
Biometric Check (if enabled)
    ↓
Decrypt xprv from Secure Storage
    ↓
Derive private key for specific UTXO
    ↓
Sign transaction
    ↓
Clear private key from memory
    ↓
Broadcast transaction
    ↓
Re-encrypt and store xprv
```

### Backup Security

- Mnemonic backup shown only once (with confirmation)
- Requires biometric/PIN authentication
- Displayed in secure, non-screenshotable view (if supported)
- User must manually write down (no automatic export)

---

## Data Flow Example: Sending a Transaction

```
1. UI (SendScreen)
   ↓ User enters amount, address
   ↓
2. TransactionProvider.sendTransaction()
   ↓
3. WalletProvider.getCurrentWallet()
   ↓
4. KeyService.derivePrivateKey() [for UTXO]
   ↓
5. TransactionBuilder.buildTransaction() [Service]
   ↓ Uses UTXOs from ApiService
   ↓
6. KeyService.signTransaction()
   ↓
7. BroadcastService.broadcastTransaction()
   ↓
8. ApiService.broadcastTransaction()
   ↓
9. TransactionProvider.updateTransactionStatus()
   ↓
10. UI updates with new transaction
```

---

## Notes

- All providers extend `ChangeNotifier` for reactive state management
- Services are stateless and can be injected/tested independently
- Storage operations are async and handle encryption/decryption transparently
- Network operations include retry logic and error handling
- Models are immutable (use `copyWith` for updates)
- All monetary values stored as `BigInt` (satoshis) to avoid floating-point precision issues

