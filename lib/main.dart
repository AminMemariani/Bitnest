import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/wallet_provider.dart';
import 'providers/network_provider.dart';
import 'providers/send_provider.dart';
import 'providers/transactions_provider.dart';
import 'providers/settings_provider.dart';
import 'services/key_service.dart';
import 'services/api_service.dart';
import 'services/transaction_service.dart';
import 'services/broadcast_service.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/wallet_screen.dart';
import 'utils/debug_logger.dart';

void main() {
  // Set up global error handlers for debugging
  if (kDebugMode) {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      DebugLogger.logException(
        details.exception,
        details.stack,
        context: 'Flutter Framework Error',
        additionalInfo: {
          'library': details.library,
          'informationCollector':
              details.informationCollector?.call().toString(),
        },
      );
      FlutterError.presentError(details);
    };

    // Handle async errors outside of Flutter framework
    PlatformDispatcher.instance.onError = (error, stack) {
      DebugLogger.logException(
        error,
        stack,
        context: 'Platform Dispatcher Error',
      );
      return true; // Return true to prevent default error handling
    };

    // Handle uncaught errors in zones
    runZonedGuarded(
      () {
        runApp(const BitNestApp());
      },
      (error, stack) {
        DebugLogger.logException(
          error,
          stack,
          context: 'Uncaught Error in Zone',
        );
      },
    );
  } else {
    // Production mode - use default error handling
    runApp(const BitNestApp());
  }
}

/// Main app widget with provider setup and adaptive navigation.
///
/// This widget:
/// - Initializes all services (KeyService, ApiService, TransactionService, BroadcastService)
/// - Sets up all providers (NetworkProvider, SettingsProvider, WalletProvider, SendProvider, TransactionsProvider)
/// - Handles responsive layout and text scaling
/// - Manages theme based on user preferences
/// - Routes to appropriate screen based on app state (splash → onboarding → wallet)
class BitNestApp extends StatelessWidget {
  const BitNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize services as singletons
    // These are created once and shared across the app
    final keyService = KeyService();
    final apiService = ApiService();
    final transactionService = TransactionService(
      keyService: keyService,
      apiService: apiService,
    );
    final broadcastService = BroadcastService(
      apiService: apiService,
    );

    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Show splash screen while initializing SharedPreferences
          return MaterialApp(
            title: 'BitNest',
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            home: const SplashScreen(),
            debugShowCheckedModeBanner: false,
          );
        }

        final prefs = snapshot.data!;

        // Wrap app with all providers
        // Provider order matters: dependencies must be created before dependents
        return MultiProvider(
          providers: [
            // 1. NetworkProvider - manages mainnet/testnet selection
            //    No dependencies, can be created first
            ChangeNotifierProvider(
              create: (_) => NetworkProvider(),
            ),

            // 2. SettingsProvider - manages app settings (theme, currency, security)
            //    Depends on SharedPreferences
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(prefs: prefs),
            ),

            // 3. WalletProvider - manages wallets, accounts, and balances
            //    Depends on KeyService and ApiService
            ChangeNotifierProvider(
              create: (_) => WalletProvider(
                keyService: keyService,
                apiService: apiService,
              ),
            ),

            // 4. SendProvider - manages transaction sending state
            //    Depends on WalletProvider, TransactionService, BroadcastService, KeyService
            //    Uses ChangeNotifierProxyProvider to react to WalletProvider changes
            ChangeNotifierProxyProvider<WalletProvider, SendProvider>(
              create: (context) => SendProvider(
                transactionService: transactionService,
                broadcastService: broadcastService,
                keyService: keyService,
                walletProvider: context.read<WalletProvider>(),
              ),
              update: (_, walletProvider, sendProvider) {
                final provider = sendProvider ??
                    SendProvider(
                      transactionService: transactionService,
                      broadcastService: broadcastService,
                      keyService: keyService,
                      walletProvider: walletProvider,
                    );
                provider.updateWalletProvider(walletProvider);
                return provider;
              },
            ),

            // 5. TransactionsProvider - manages transaction history
            //    Depends on ApiService
            ChangeNotifierProvider(
              create: (_) => TransactionsProvider(
                apiService: apiService,
              ),
            ),
          ],
          child: Consumer2<SettingsProvider, WalletProvider>(
            builder: (context, settingsProvider, walletProvider, _) {
              return MaterialApp(
                title: 'BitNest',
                theme: _buildLightTheme(),
                darkTheme: _buildDarkTheme(),
                themeMode: settingsProvider.themeMode,
                debugShowCheckedModeBanner: false,

                // Responsive builder: ensures text scaling and layout adapt to screen size
                builder: (context, child) {
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      // Clamp text scaling for accessibility while preventing extreme sizes
                      // Increased max to 2.0x for better accessibility support (WCAG 2.1)
                      textScaler: MediaQuery.of(context).textScaler.clamp(
                            minScaleFactor: 0.8,
                            maxScaleFactor: 2.0,
                          ),
                    ),
                    child: child!,
                  );
                },

                // Adaptive navigation: routes based on app state
                home: _AppNavigator(
                  walletProvider: walletProvider,
                  prefs: prefs,
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Builds the light theme with adaptive page transitions.
  ///
  /// Uses platform-specific transitions:
  /// - Android: FadeUpwards (Material Design)
  /// - iOS/macOS: Cupertino (native iOS style)
  ThemeData _buildLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF977439),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFFBC985E),
      ),
      useMaterial3: true,
      // Adaptive page transitions based on platform
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Builds the dark theme with adaptive page transitions.
  ///
  /// Uses platform-specific transitions:
  /// - Android: FadeUpwards (Material Design)
  /// - iOS/macOS: Cupertino (native iOS style)
  ThemeData _buildDarkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF977439),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFFBC985E),
      ),
      useMaterial3: true,
      // Adaptive page transitions based on platform
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Navigator widget that handles initial routing based on app state.
///
/// Navigation flow:
/// 1. SplashScreen (during initialization)
/// 2. OnboardingScreen (if first run and no wallets)
/// 3. WalletScreen (main app)
///
/// The navigator checks:
/// - If onboarding has been completed (stored in SharedPreferences)
/// - If user has any wallets
/// - Shows onboarding only if both conditions are false
class _AppNavigator extends StatefulWidget {
  final WalletProvider walletProvider;
  final SharedPreferences prefs;

  const _AppNavigator({
    required this.walletProvider,
    required this.prefs,
  });

  @override
  State<_AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<_AppNavigator> {
  static const String _firstRunKey = 'has_completed_onboarding';
  bool _isInitializing = true;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _checkFirstRun();
  }

  /// Checks if this is the first run and determines which screen to show.
  ///
  /// Shows splash for minimum duration, then checks:
  /// - Has user completed onboarding?
  /// - Does user have any wallets?
  ///
  /// If no onboarding and no wallets → show onboarding
  /// Otherwise → show wallet screen
  Future<void> _checkFirstRun() async {
    // Show splash screen for a minimum duration (smooth UX)
    await Future.delayed(const Duration(milliseconds: 1500));

    // Check if user has completed onboarding
    final hasCompletedOnboarding = widget.prefs.getBool(_firstRunKey) ?? false;

    // Check if user has any wallets
    final hasWallets = widget.walletProvider.wallets.isNotEmpty;

    if (mounted) {
      setState(() {
        _showOnboarding = !hasCompletedOnboarding && !hasWallets;
        _isInitializing = false;
      });
    }

    // Mark onboarding as completed if user has wallets (imported wallet)
    if (hasWallets && !hasCompletedOnboarding) {
      await widget.prefs.setBool(_firstRunKey, true);
    }
  }

  /// Called when onboarding is completed.
  ///
  /// Marks onboarding as complete and navigates to wallet screen.
  void _onOnboardingComplete() async {
    await widget.prefs.setBool(_firstRunKey, true);
    if (mounted) {
      setState(() {
        _showOnboarding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show splash during initialization
    if (_isInitializing) {
      return const SplashScreen();
    }

    // Show onboarding if first run and no wallets
    if (_showOnboarding) {
      return OnboardingScreen(
        onComplete: _onOnboardingComplete,
      );
    }

    // Show main wallet screen
    return const WalletScreen();
  }
}
