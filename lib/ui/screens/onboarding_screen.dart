import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/networks.dart';
import 'wallet_screen.dart';

/// Onboarding screen for first-time users to create or import a wallet.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingScreen({super.key, this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentPage = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _ = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (only on first page)
            if (_currentPage == 0)
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => _navigateToWallet(context),
                  child: const Text('Skip'),
                ),
              ),
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _WelcomePage(
                    onNext: () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                  ),
                  _CreateOrImportPage(
                    onComplete: () => _navigateToWallet(context),
                  ),
                ],
              ),
            ),
            // Page indicator
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  2,
                  (index) => _PageIndicator(isActive: index == _currentPage),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToWallet(BuildContext context) {
    // Call onComplete callback if provided
    widget.onComplete?.call();

    // If no callback, navigate manually
    if (widget.onComplete == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
    }
  }
}

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;

  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet,
            size: 120,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 48),
          Text(
            'Welcome to BitNest',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            'A secure Bitcoin wallet for managing your digital assets with ease.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Get Started'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateOrImportPage extends StatelessWidget {
  final VoidCallback onComplete;

  const _CreateOrImportPage({required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Create or Import Wallet',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          // Create Wallet Card
          Card(
            elevation: 2,
            child: InkWell(
              onTap: () => _showCreateWalletDialog(context, walletProvider),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create New Wallet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Generate a new wallet with a recovery phrase',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Import Wallet Card
          Card(
            elevation: 2,
            child: InkWell(
              onTap: () => _showImportWalletDialog(context, walletProvider),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.download_outlined,
                      size: 64,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Import Wallet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Restore from an existing recovery phrase',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateWalletDialog(
    BuildContext context,
    WalletProvider walletProvider,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create New Wallet'),
        content: const Text(
          'A new wallet will be created. Make sure to securely backup your recovery phrase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        await walletProvider.createWallet(
          label: 'My Wallet',
          network: BitcoinNetwork.mainnet,
        );
        if (context.mounted) {
          onComplete();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create wallet: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showImportWalletDialog(
    BuildContext context,
    WalletProvider walletProvider,
  ) async {
    final mnemonicController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import Wallet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your recovery phrase:'),
              const SizedBox(height: 16),
              TextField(
                controller: mnemonicController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'word1 word2 word3 ...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (mnemonicController.text.trim().isNotEmpty) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        await walletProvider.importWallet(
          mnemonic: mnemonicController.text.trim(),
          label: 'Imported Wallet',
          network: BitcoinNetwork.mainnet,
        );
        if (context.mounted) {
          onComplete();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to import wallet: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class _PageIndicator extends StatelessWidget {
  final bool isActive;

  const _PageIndicator({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.outline.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
