# BitNest QA Checklist

This document provides a comprehensive manual testing checklist for BitNest. Use this checklist before each release to ensure all critical functionality works correctly.

## Test Environment Setup

- [ ] Clean install of the app (uninstall previous version if exists)
- [ ] Test on both Android and iOS devices (if applicable)
- [ ] Test on different screen sizes (phone, tablet)
- [ ] Test on different OS versions (minimum supported and latest)
- [ ] Ensure testnet Bitcoin faucet is available for testing

---

## 1. Wallet Creation & Import

### 1.1 Mnemonic Generation

- [ ] **TC-WC-001**: Create new wallet generates valid 12-word mnemonic
  - Steps: Launch app → Skip onboarding or create wallet → Verify mnemonic is displayed
  - Expected: 12-word mnemonic phrase is shown, words are valid BIP39 words
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WC-002**: Mnemonic can be copied to clipboard
  - Steps: View mnemonic → Tap copy button → Paste in text editor
  - Expected: Mnemonic is correctly copied, all 12 words are present
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WC-003**: Mnemonic is hidden after viewing (security)
  - Steps: View mnemonic → Navigate away → Return to mnemonic view
  - Expected: Mnemonic requires re-authentication to view
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WC-004**: Mnemonic backup warning is shown
  - Steps: Create wallet → View mnemonic
  - Expected: Warning message about backing up mnemonic is displayed
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

### 1.2 Wallet Import

- [ ] **TC-WI-001**: Import wallet with valid 12-word mnemonic
  - Steps: Import wallet → Enter valid mnemonic → Confirm
  - Expected: Wallet is imported successfully, accounts are visible
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WI-002**: Import wallet with valid 24-word mnemonic (if supported)
  - Steps: Import wallet → Enter valid 24-word mnemonic → Confirm
  - Expected: Wallet is imported successfully
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WI-003**: Reject invalid mnemonic (wrong word count)
  - Steps: Import wallet → Enter 11 words → Confirm
  - Expected: Error message shown, wallet not imported
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WI-004**: Reject invalid mnemonic (invalid words)
  - Steps: Import wallet → Enter mnemonic with invalid word → Confirm
  - Expected: Error message shown, wallet not imported
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WI-005**: Reject invalid mnemonic (wrong checksum)
  - Steps: Import wallet → Enter mnemonic with wrong checksum → Confirm
  - Expected: Error message shown, wallet not imported
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WI-006**: Imported wallet shows correct addresses
  - Steps: Import known test wallet → Verify receive addresses match expected
  - Expected: Addresses match expected derivation (BIP84, account 0, etc.)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 2. Address Derivation

### 2.1 Receive Address Generation

- [ ] **TC-AD-001**: First receive address is correctly derived
  - Steps: Create/import wallet → View receive screen → Check first address
  - Expected: Address matches expected derivation path (m/84'/0'/0'/0/0 for mainnet)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-AD-002**: Generate new receive address increments derivation
  - Steps: Receive screen → Generate new address → Verify address changed
  - Expected: New address is different, derivation path increments (0/0 → 0/1)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-AD-003**: Address format is correct for mainnet (Bech32)
  - Steps: Switch to mainnet → View receive address
  - Expected: Address starts with "bc1" (Bech32 format)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-AD-004**: Address format is correct for testnet (Bech32)
  - Steps: Switch to testnet → View receive address
  - Expected: Address starts with "tb1" (Bech32 format)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-AD-005**: Address derivation path is displayed correctly
  - Steps: Receive screen → View address details
  - Expected: Derivation path is shown (e.g., m/84'/0'/0'/0/0)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-AD-006**: Address can be copied to clipboard
  - Steps: Receive screen → Tap copy button → Paste in text editor
  - Expected: Address is correctly copied
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-AD-007**: QR code displays correct address
  - Steps: Receive screen → Verify QR code
  - Expected: QR code contains the displayed address
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 3. Network Switching

### 3.1 Mainnet/Testnet Toggle

- [ ] **TC-NS-001**: Switch from mainnet to testnet
  - Steps: Settings → Network toggle → Switch to testnet
  - Expected: Network changes to testnet, addresses update, balances refresh
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-NS-002**: Switch from testnet to mainnet
  - Steps: Settings → Network toggle → Switch to mainnet
  - Expected: Network changes to mainnet, addresses update, balances refresh
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-NS-003**: Network change persists after app restart
  - Steps: Change network → Close app → Reopen app
  - Expected: Network setting is preserved
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-NS-004**: Addresses update when network changes
  - Steps: View receive address on mainnet → Switch to testnet → View receive address
  - Expected: Address changes to testnet format (tb1...)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-NS-005**: Transaction history updates when network changes
  - Steps: View transactions on mainnet → Switch to testnet
  - Expected: Transaction list updates to show testnet transactions
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-NS-006**: Warning shown when switching networks (if applicable)
  - Steps: Settings → Network toggle → Switch network
  - Expected: Warning dialog shown (if implemented)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 4. Send Transaction (Testnet)

### 4.1 Transaction Creation

- [ ] **TC-ST-001**: Send transaction with valid testnet address
  - Steps: Send screen → Enter testnet address → Enter amount → Send
  - Expected: Transaction is created and broadcast successfully
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-002**: Send transaction with amount validation
  - Steps: Send screen → Enter amount greater than balance
  - Expected: Error message shown, transaction not created
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-003**: Send transaction with fee selection (slow/normal/fast)
  - Steps: Send screen → Select fee preset → Verify fee amount
  - Expected: Fee is calculated correctly for selected preset
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-004**: Send transaction with manual fee
  - Steps: Send screen → Select manual fee → Enter custom fee → Send
  - Expected: Transaction uses custom fee amount
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-005**: Send transaction shows change address
  - Steps: Send screen → Enter amount less than balance → Review transaction
  - Expected: Change output is shown in transaction summary
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-006**: Send transaction with UTXO selection
  - Steps: Send screen → Select specific UTXOs → Send
  - Expected: Transaction uses only selected UTXOs
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

### 4.2 Transaction Signing & Broadcasting

- [ ] **TC-ST-007**: Transaction requires authentication before sending
  - Steps: Send screen → Fill transaction → Tap send
  - Expected: Biometric/PIN prompt appears before signing
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-008**: Transaction is signed correctly
  - Steps: Send transaction → Authenticate → Verify transaction
  - Expected: Transaction signature is valid (can be verified on explorer)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-009**: Transaction is broadcast to network
  - Steps: Send transaction → Authenticate → Wait for confirmation
  - Expected: Transaction appears on blockchain explorer
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ST-010**: Transaction appears in transaction history
  - Steps: Send transaction → Navigate to transactions screen
  - Expected: Sent transaction appears in list with correct status
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 5. Receive Transaction (Testnet)

### 5.1 Receiving Funds

- [ ] **TC-RT-001**: Receive testnet funds to address
  - Steps: Receive screen → Copy address → Send from testnet faucet
  - Expected: Funds appear in wallet after confirmation
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-RT-002**: Balance updates after receiving funds
  - Steps: Receive funds → Check wallet balance
  - Expected: Balance increases by received amount
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-RT-003**: Transaction appears in history after receiving
  - Steps: Receive funds → Navigate to transactions screen
  - Expected: Received transaction appears in list
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-RT-004**: Transaction shows correct confirmations
  - Steps: Receive funds → View transaction details
  - Expected: Confirmation count is displayed and updates
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 6. Biometric & PIN Security

### 6.1 Biometric Authentication

- [ ] **TC-BIO-001**: Enable biometric authentication
  - Steps: Settings → Security → Enable biometrics toggle
  - Expected: Biometric authentication is enabled, setting persists
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-BIO-002**: Disable biometric authentication
  - Steps: Settings → Security → Disable biometrics toggle
  - Expected: Biometric authentication is disabled
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-BIO-003**: Biometric prompt appears when viewing mnemonic
  - Steps: Settings → Wallet → Backup mnemonic → Authenticate
  - Expected: Biometric prompt appears (if enabled)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-BIO-004**: Biometric prompt appears before sending transaction
  - Steps: Send screen → Fill transaction → Tap send
  - Expected: Biometric prompt appears (if enabled)
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-BIO-005**: Biometric authentication fails gracefully
  - Steps: Trigger biometric prompt → Cancel or fail authentication
  - Expected: Action is cancelled, no sensitive data is shown
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-BIO-006**: Fallback to PIN when biometric fails
  - Steps: Enable both biometric and PIN → Fail biometric → Enter PIN
  - Expected: PIN authentication works as fallback
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

### 6.2 PIN Authentication

- [ ] **TC-PIN-001**: Set PIN for first time
  - Steps: Settings → Security → Change PIN → Enter new PIN
  - Expected: PIN is set successfully, setting persists
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-PIN-002**: Change existing PIN
  - Steps: Settings → Security → Change PIN → Enter old PIN → Enter new PIN
  - Expected: PIN is changed successfully
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-PIN-003**: Reject PIN change with wrong old PIN
  - Steps: Settings → Security → Change PIN → Enter wrong old PIN
  - Expected: Error message shown, PIN not changed
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-PIN-004**: PIN prompt appears when biometric disabled
  - Steps: Disable biometrics → View mnemonic
  - Expected: PIN prompt appears
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-PIN-005**: PIN validation (minimum length)
  - Steps: Settings → Security → Change PIN → Enter 3-digit PIN
  - Expected: Error message shown, PIN not accepted
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-PIN-006**: PIN validation (maximum length)
  - Steps: Settings → Security → Change PIN → Enter 9-digit PIN
  - Expected: Error message shown, PIN not accepted
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 7. App Wipe / Reset

### 7.1 Wallet Wipe

- [ ] **TC-WIPE-001**: Wipe wallet shows confirmation dialog
  - Steps: Settings → Security → Wipe wallet
  - Expected: Confirmation dialog appears with warning
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WIPE-002**: Wipe wallet requires authentication
  - Steps: Settings → Security → Wipe wallet → Confirm
  - Expected: Authentication prompt appears before wipe
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WIPE-003**: Wipe wallet removes all data
  - Steps: Wipe wallet → Authenticate → Confirm
  - Expected: All wallets, settings, and data are removed
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WIPE-004**: App returns to onboarding after wipe
  - Steps: Wipe wallet → Confirm → App restarts
  - Expected: Onboarding screen is shown
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-WIPE-005**: Wipe wallet can be cancelled
  - Steps: Settings → Security → Wipe wallet → Cancel
  - Expected: Dialog closes, wallet data remains
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 8. Settings & Preferences

### 8.1 Theme Settings

- [ ] **TC-THEME-001**: Switch to light theme
  - Steps: Settings → Display → Theme → Select Light
  - Expected: App theme changes to light mode
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-THEME-002**: Switch to dark theme
  - Steps: Settings → Display → Theme → Select Dark
  - Expected: App theme changes to dark mode
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-THEME-003**: Switch to system theme
  - Steps: Settings → Display → Theme → Select System
  - Expected: App theme follows system setting
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-THEME-004**: Theme setting persists after app restart
  - Steps: Change theme → Close app → Reopen app
  - Expected: Theme setting is preserved
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

### 8.2 Currency Settings

- [ ] **TC-CURR-001**: Switch currency display (BTC ↔ fiat)
  - Steps: Settings → Display → Currency → Select currency
  - Expected: Currency display changes throughout app
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-CURR-002**: Currency conversion is accurate
  - Steps: Switch to USD → Check balance display
  - Expected: BTC amount is converted to USD correctly
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-CURR-003**: Currency setting persists after app restart
  - Steps: Change currency → Close app → Reopen app
  - Expected: Currency setting is preserved
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

### 8.3 Wallet Export

- [ ] **TC-EXP-001**: Export xpub (watch-only)
  - Steps: Settings → Wallet → Export wallet → Copy xpub
  - Expected: xpub is displayed and can be copied
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-EXP-002**: Exported xpub is valid
  - Steps: Export xpub → Verify format
  - Expected: xpub starts with "xpub" and is valid BIP32 format
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 9. Error Handling & Edge Cases

- [ ] **TC-ERR-001**: Handle network errors gracefully
  - Steps: Disable network → Try to refresh balance
  - Expected: Error message shown, app doesn't crash
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ERR-002**: Handle invalid address input
  - Steps: Send screen → Enter invalid address → Try to send
  - Expected: Validation error shown, transaction not created
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ERR-003**: Handle insufficient funds error
  - Steps: Send screen → Enter amount > balance → Try to send
  - Expected: Error message shown, transaction not created
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-ERR-004**: Handle app backgrounding during transaction
  - Steps: Start transaction → Background app → Return to app
  - Expected: Transaction state is preserved or cancelled gracefully
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## 10. Performance & Usability

- [ ] **TC-PERF-001**: App launches within 3 seconds
  - Steps: Cold start app → Measure time to first screen
  - Expected: App is usable within 3 seconds
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-PERF-002**: Balance refresh is responsive
  - Steps: Pull to refresh balance → Measure time
  - Expected: Balance updates within 5 seconds
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-PERF-003**: Navigation is smooth
  - Steps: Navigate between screens multiple times
  - Expected: No lag or stuttering
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-USAB-001**: All text is readable
  - Steps: Check all screens for text readability
  - Expected: Text is clear and readable in both light and dark themes
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

- [ ] **TC-USAB-002**: Buttons are tappable
  - Steps: Test all interactive elements
  - Expected: All buttons respond to taps
  - Status: ⬜ Pass / ⬜ Fail / ⬜ N/A

---

## Test Summary

**Total Test Cases**: ___

**Passed**: ___

**Failed**: ___

**Not Applicable**: ___

**Pass Rate**: ___%

**Tester**: ________________

**Date**: ________________

**Notes**:

________________________________________________________

________________________________________________________

________________________________________________________



