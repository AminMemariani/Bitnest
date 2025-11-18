# Transaction Service Implementation Notes

## Current Status

The transaction service has been implemented with the following components:

### ✅ Completed

1. **TransactionService** (`lib/services/transaction_service.dart`)
   - Fee preset selection (slow/normal/fast)
   - Fee calculation and estimation
   - UTXO selection and input creation
   - Change address derivation
   - Transaction structure building
   - Basic transaction signing framework

2. **BroadcastService** (`lib/services/broadcast_service.dart`)
   - Wraps ApiService broadcast functionality
   - Error handling and logging
   - Network switching support

3. **SendProvider** (`lib/providers/send_provider.dart`)
   - Transaction state management
   - UTXO selection
   - Fee selection (preset or manual)
   - Transaction validation
   - Change calculation
   - Integration with TransactionService and BroadcastService

4. **SendScreen** (`lib/ui/screens/send_screen.dart`)
   - Complete UI for sending transactions
   - Address input
   - Amount input (BTC)
   - Fee selection (preset or manual)
   - UTXO selection interface
   - Transaction summary
   - Biometric authentication before sending
   - Success/error handling

5. **Tests**
   - `test/services/transaction_service_test.dart` - TransactionService unit tests
   - `test/providers/send_provider_test.dart` - SendProvider unit tests

### ⚠️ Implementation Notes

**Transaction Serialization and Signing:**

The current implementation includes a framework for transaction building and signing, but the actual Bitcoin transaction serialization is simplified. For production use, you should:

1. **Use a proper Bitcoin library** such as:
   - `bitcoin` package (if available for Dart)
   - Or implement full BIP143 Segwit transaction format
   - Proper script serialization (P2PKH, P2WPKH, P2SH-wrapped Segwit)

2. **Key areas that need full implementation:**
   - `_buildRawTransaction()` - Full transaction serialization
   - `_signInput()` - Proper ECDSA signing with SIGHASH flags
   - `_createSignatureHash()` - BIP143 signature hash for Segwit
   - `_addressToScriptPubKey()` - Proper address decoding and script building
   - `_buildScriptSig()` - Proper script signature construction
   - `_insertScriptSig()` - Proper script insertion into transaction

3. **Current limitations:**
   - Transaction hex generation is incomplete
   - Script serialization is placeholder
   - Signature format may not be fully compatible
   - Change address detection needs improvement

### Security Features

✅ **Biometric Authentication:**
- Required before sending transactions
- Uses `local_auth` package
- Falls back gracefully if biometrics unavailable

✅ **Private Key Handling:**
- Keys derived on-demand from seed
- Never stored in plain text
- Cleared from memory after use

### Testing

All unit tests pass:
- ✅ SendProvider tests (16 tests)
- ✅ TransactionService structure tests
- ⚠️ Full transaction building tests need mocked Bitcoin library

### Next Steps for Production

1. Integrate a proper Bitcoin transaction library
2. Implement full BIP143 Segwit support
3. Add comprehensive transaction validation
4. Implement proper change address tracking
5. Add transaction history tracking
6. Implement replace-by-fee (RBF) support
7. Add transaction fee bumping

