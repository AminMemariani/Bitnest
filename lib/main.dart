import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/network_provider.dart';
import 'services/key_service.dart';
import 'services/api_service.dart';
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
          'informationCollector': details.informationCollector?.call().toString(),
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

class BitNestApp extends StatelessWidget {
  const BitNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize services
    final keyService = KeyService();
    final apiService = ApiService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NetworkProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => WalletProvider(
            keyService: keyService,
            apiService: apiService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'BitNest',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF977439),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFFBC985E),
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF977439),
            brightness: Brightness.dark,
          ).copyWith(
            primary: const Color(0xFFBC985E),
          ),
          useMaterial3: true,
        ),
        home: const WalletScreen(),
      ),
    );
  }
}
