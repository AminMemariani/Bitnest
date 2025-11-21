# BitNest Test Suite Plan

## Overview

This document outlines the comprehensive test strategy for BitNest, covering unit tests, widget tests, and integration tests. All tests are designed to run in CI/CD pipelines.

## Test Structure

```
test/
├── unit/                    # Unit tests (business logic, services, utilities)
│   ├── services/            # Service layer tests
│   ├── providers/           # Provider/state management tests
│   └── utils/               # Utility function tests
├── widget/                   # Widget tests (UI components)
│   └── screens/             # Screen-level widget tests
└── integration/             # Integration tests (end-to-end flows)
    ├── wallet_flow_test.dart
    ├── transaction_flow_test.dart
    └── settings_flow_test.dart
```

## Test Categories

### 1. Unit Tests

**Purpose**: Test individual functions, methods, and classes in isolation.

**Coverage Areas**:
- Service layer (KeyService, ApiService, TransactionService, BroadcastService)
- Provider logic (NetworkProvider, WalletProvider, SettingsProvider, SendProvider, TransactionsProvider)
- Utility functions (address derivation, mnemonic validation, etc.)
- Model validation and serialization

**Example Files**:
- `test/unit/services/key_service_test.dart`
- `test/unit/providers/wallet_provider_test.dart`
- `test/unit/utils/address_utils_test.dart`

**Key Principles**:
- Mock external dependencies (API calls, secure storage)
- Test edge cases and error conditions
- Verify state changes and side effects
- Aim for >80% code coverage

### 2. Widget Tests

**Purpose**: Test UI components and user interactions.

**Coverage Areas**:
- Screen rendering and layout
- User interactions (taps, swipes, inputs)
- Provider integration with UI
- Navigation flows
- Adaptive widget behavior

**Example Files**:
- `test/widget/screens/wallet_screen_test.dart`
- `test/widget/screens/send_screen_test.dart`
- `test/widget/screens/settings_screen_test.dart`

**Key Principles**:
- Test widget tree structure
- Verify user interactions trigger correct callbacks
- Test provider state changes reflect in UI
- Use `pumpAndSettle()` for async operations
- Mock providers when needed

### 3. Integration Tests

**Purpose**: Test complete user flows end-to-end.

**Coverage Areas**:
- Wallet creation flow
- Wallet import flow
- Send transaction flow
- Receive transaction flow
- Settings changes
- Network switching

**Example Files**:
- `test/integration/wallet_flow_test.dart`
- `test/integration/transaction_flow_test.dart`
- `test/integration/settings_flow_test.dart`

**Key Principles**:
- Test real user scenarios
- Use test data and mock services
- Verify complete flows from start to finish
- Test error recovery and edge cases

## Test Execution

### Local Execution

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/unit/services/key_service_test.dart

# Run with coverage
flutter test --coverage

# Run integration tests
flutter test test/integration/
```

### CI Execution

Tests run automatically on:
- Push to main/develop branches
- Pull requests
- Scheduled nightly runs

See `.github/workflows/ci.yml` for CI configuration.

## Test Data and Mocks

### Test Data

- Use consistent test mnemonics (documented in test files)
- Use testnet addresses for transaction tests
- Mock API responses for predictable testing

### Mocking Strategy

- **Services**: Use `mockito` for service mocking
- **Providers**: Create test providers with controlled state
- **Secure Storage**: Use in-memory implementations for tests
- **Biometrics**: Mock `local_auth` for consistent test behavior

## Coverage Goals

- **Unit Tests**: >80% code coverage
- **Widget Tests**: All screens and major widgets
- **Integration Tests**: All critical user flows

## Continuous Improvement

- Review test coverage reports regularly
- Add tests for new features before merging
- Refactor tests when code changes
- Update test plan as app evolves

## Example Test Files

See the following example files:
- `test/unit/example_unit_test.dart` - Unit test example
- `test/widget/example_widget_test.dart` - Widget test example
- `test/integration/example_integration_test.dart` - Integration test example



