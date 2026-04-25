# Security Note: KeyService Storage and Encryption

## Overview

The `KeyService` implements secure storage and encryption for sensitive cryptographic material including BIP39 mnemonics, seeds, and extended private keys (xprv). This document explains the security choices and implementation details.

## Storage Architecture

### Flutter Secure Storage

The service uses `flutter_secure_storage` for persistent storage of sensitive data. This package provides platform-specific secure storage:

- **iOS**: Uses Keychain Services (`kSecClassGenericPassword`)
- **Android**: Uses EncryptedSharedPreferences with Android Keystore (AES-256)
- **Other platforms**: Uses platform-appropriate secure storage mechanisms

### Storage Format

1. **Seeds**: Stored as Base64-encoded strings
   - Original: 64-byte (512-bit) seed
   - Stored: Base64 string (88 characters)
   - Encryption: Handled by platform secure storage

2. **Mnemonics**: Stored as plain text strings (encrypted by platform)
   - Format: Space-separated word list
   - Encryption: Handled by platform secure storage

### Storage Keys

- Seeds: `wallet_seed_{walletId}`
- Mnemonics: `wallet_mnemonic_{walletId}`

The `walletId` ensures data isolation between different wallets.

## Encryption Details

### iOS (Keychain Services)

- **Access Control**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  - Data accessible only when device is unlocked
  - Data not backed up to iCloud
  - Data tied to specific device

- **Encryption**: Hardware-backed when available (Secure Enclave on supported devices)
- **Key Management**: Managed by iOS Keychain

### Android (Android Keystore)

- **Encryption**: AES-256-GCM
- **Key Storage**: Android Keystore (hardware-backed when available)
- **Key Generation**: Automatic, device-specific
- **Access Control**: Requires device unlock

### Security Properties

1. **Hardware-Backed Encryption**: When available, keys are stored in hardware security modules (HSM)
2. **No Cloud Backup**: Sensitive data is not backed up to cloud services
3. **Device Binding**: Keys are tied to specific device
4. **Automatic Key Management**: Platform handles key rotation and secure deletion

## Biometric Authentication

### Implementation

The service uses `local_auth` package for biometric authentication:

- **Supported Methods**: Fingerprint, Face ID, Touch ID, Iris (platform-dependent)
- **Fallback**: None (biometric-only mode)
- **Usage**: Optional gate for sensitive operations

### When Biometric is Required

- Storing seed/mnemonic (optional)
- Retrieving seed/mnemonic (optional)
- Can be enabled per operation via `requireBiometric` parameter

### Security Considerations

1. **Biometric Data**: Never stored by the app; handled entirely by platform
2. **Authentication Result**: Cached temporarily by platform (stickyAuth: true)
3. **Failure Handling**: Throws exception if authentication fails

## Memory Security

### Private Key Handling

- **No Logging**: Private keys are never logged or printed
- **Temporary Storage**: Private keys exist only in memory during derivation
- **Automatic Cleanup**: Dart garbage collector handles memory cleanup
- **No Persistence**: Private keys are never stored; only seeds and mnemonics are stored

### Best Practices

1. **Minimize Exposure**: Private keys derived on-demand, not pre-computed
2. **Clear After Use**: Keys cleared from memory after use (garbage collection)
3. **No Debug Output**: No debug prints or logs containing sensitive data

## Key Derivation Security

### BIP32/BIP44/BIP49/BIP84 Compliance

- **Standards Compliance**: Follows BIP standards for deterministic key derivation
- **Path Hardening**: Uses hardened derivation (') for account-level keys
- **Network Isolation**: Different keys for mainnet vs testnet

### Derivation Paths

- **Legacy (BIP44)**: `m/44'/coin'/account'`
- **P2SH-Segwit (BIP49)**: `m/49'/coin'/account'`
- **Native Segwit (BIP84)**: `m/84'/coin'/account'`

Where:
- `coin'` = 0 for mainnet, 1 for testnet
- `account'` = Account index (typically 0)

## Threat Model

### Protected Against

1. **Device Theft**: Requires device unlock + biometric (if enabled)
2. **Malicious Apps**: Platform isolation prevents other apps from accessing secure storage
3. **Cloud Backup**: Sensitive data not included in backups
4. **Memory Dumps**: Private keys not persisted, only in memory temporarily

### Not Protected Against

1. **Compromised Device**: If device is rooted/jailbroken, security is reduced
2. **Physical Access + Unlock**: If device is unlocked, data is accessible
3. **Malware with Root**: Root-level malware could potentially access secure storage
4. **Social Engineering**: User revealing mnemonic/phrase

## Recommendations

### For Production

1. **Enable Biometric**: Require biometric for all sensitive operations
2. **Regular Updates**: Keep dependencies updated for security patches
3. **Device Security**: Encourage users to enable device lock screen
4. **Backup Strategy**: Users should write down mnemonic (not stored digitally)
5. **Testing**: Test on both iOS and Android to verify platform security

### Additional Security Measures

1. **Certificate Pinning**: For API calls (not in KeyService scope)
2. **App Integrity**: Use code signing and app attestation
3. **Anti-Tampering**: Detect if device is rooted/jailbroken
4. **Rate Limiting**: Limit failed authentication attempts

## Compliance

- **BIP39**: Mnemonic generation and validation
- **BIP32**: HD key derivation
- **BIP44**: Legacy address derivation
- **BIP49**: P2SH-wrapped Segwit derivation
- **BIP84**: Native Segwit derivation
- **BIP143**: Witness transaction signature digest (used by `TransactionSigner`)
- **BIP173 / BIP350**: Bech32 / Bech32m address encoding (used by `lib/utils/bech32.dart`)

## Scope and Limitations

### Taproot (BIP86) is not fully supported

The wallet **can pay** Taproot recipients — `bc1p…` / `tb1p…` addresses are
decoded via the project's BIP350 (bech32m) codec and the correct
`OP_1 <32-byte program>` `scriptPubKey` is emitted in the transaction
output.

The wallet **cannot spend** Taproot UTXOs. `HdWalletService` derives only
BIP84 keypairs (`m/84'/coin'/account'/change/index`); no
`m/86'/...` derivation, no Schnorr (BIP340) signing path, and no
BIP341 sighash. A Taproot UTXO would have no matching derivation
metadata and would fail at `TransactionSigner.sign()` time.

Recommendation: do not import a seed into this wallet that has accumulated
Taproot UTXOs elsewhere. Until BIP86 support lands, those funds are not
recoverable through this codebase. Migration plan, when prioritised:

1. Add `DerivationScheme.taproot` and corresponding paths to
   `HdWalletService`.
2. Replace ECDSA-over-secp256k1 with Schnorr (`pointycastle` does not
   ship Schnorr; use BDK / a vetted Dart binding).
3. Implement BIP341 sighash and witness construction for key-path
   spends; defer script-path spends.

### Development-mode plaintext fallback removed

A previous iteration of `KeyService` had a `_fallbackStorage` map that, in
debug builds, kept seeds and mnemonics in process memory if
`flutter_secure_storage` failed. **That fallback has been removed.** Storage
failures now propagate as exceptions. If you need a dev-time stub, use a
mock `FlutterSecureStorage` in the constructor — never reintroduce a
debug-only plaintext path.

### PSBT (BIP174) is not supported

The signer consumes the in-house `UnsignedTransaction` data class and
emits a witness-serialised transaction hex. There is no PSBT import or
export; hardware-wallet integrations would need that layered on top.
The data carried by `UnsignedTransaction` is sufficient to round-trip
into PSBT v0 if added later.

### Cross-validation against an external Bitcoin node has not been performed

The signer's tests verify internal consistency: the produced signature
verifies against its own pubkey, the witness stack has the expected
shape, and the bech32 round-trip is correct. Before enabling mainnet use,
a separate validation pass should sign a tx with a known seed and confirm
that `bitcoin-cli decoderawtransaction` (or the equivalent `bitcoinjs-lib`
or `bdk` API) accepts the hex.

## References

- [BIP39: Mnemonic code](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [BIP32: HD Wallets](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
- [BIP44: Multi-Account Hierarchy](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki)
- [BIP84: Native SegWit](https://github.com/bitcoin/bips/blob/master/bip-0084.mediawiki)
- [BIP86: Taproot key derivation (not yet supported here)](https://github.com/bitcoin/bips/blob/master/bip-0086.mediawiki)
- [BIP143: Transaction Signature Verification for Version 0 Witness Program](https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki)
- [BIP173: Bech32](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki)
- [BIP350: Bech32m](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki)
- [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage)
- [Local Auth](https://pub.dev/packages/local_auth)

