import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/network_provider.dart';
import 'services/key_service.dart';
import 'services/api_service.dart';
import 'ui/screens/wallet_screen.dart';

void main() {
  runApp(const BitNestApp());
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
            seedColor: Colors.orange,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const WalletScreen(),
      ),
    );
  }
}
