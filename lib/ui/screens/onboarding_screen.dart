import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/networks.dart';
import '../../utils/responsive.dart';
import 'wallet_screen.dart';

/// Onboarding screen for first-time users to create or import a wallet.
///
/// Features:
/// - Welcome page with app introduction
/// - Create/Import wallet selection
/// - Responsive layout for all screen sizes
/// - Full accessibility support with semantic labels
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (only on first page)
            if (_currentPage == 0)
              Align(
                alignment: Alignment.topRight,
                child: Semantics(
                  label: 'Skip onboarding and go to wallet',
                  button: true,
                  child: TextButton(
                    onPressed: () => _navigateToWallet(context),
                    child: const Text('Skip'),
                  ),
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
            Semantics(
              label: 'Page ${_currentPage + 1} of 2',
              child: Padding(
                padding: Breakpoints.responsivePadding(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    2,
                    (index) => _PageIndicator(isActive: index == _currentPage),
                  ),
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
    final isLarge = Breakpoints.isLarge(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Breakpoints.maxContentWidth(context),
        ),
        child: Padding(
          padding: Breakpoints.responsivePadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: 'BitNest wallet icon',
                child: Icon(
                  Icons.account_balance_wallet,
                  size: isLarge ? 140 : 120,
                  color: theme.colorScheme.primary,
                ),
              ),
              SizedBox(height: isLarge ? 56 : 48),
              Semantics(
                header: true,
                child: Text(
                  'Welcome to BitNest',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Your Bitcoin, your control.\n'
                'A secure, self-custody wallet that puts you in charge.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'BitNest keeps your Bitcoin safe with industry-standard security. '
                'Your keys, your coins—always.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isLarge ? 56 : 48),
              Semantics(
                label: 'Get started with BitNest',
                button: true,
                child: ElevatedButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Get Started'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLarge ? 40 : 32,
                      vertical: isLarge ? 20 : 16,
                    ),
                    minimumSize: Size(isLarge ? 200 : 160, isLarge ? 56 : 48),
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final isLarge = Breakpoints.isLarge(context);
    final isMedium = Breakpoints.isMedium(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Breakpoints.maxContentWidth(context),
        ),
        child: Padding(
          padding: Breakpoints.responsivePadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Create or Import Wallet',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: isLarge ? 56 : 48),
              // Cards layout: side-by-side on large screens, stacked on small
              if (isMedium || isLarge)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _WalletOptionCard(
                        title: 'Create New Wallet',
                        description:
                            'Generate a new wallet with a secure recovery phrase. '
                            'You\'ll be the only one with access to your funds.',
                        icon: Icons.add_circle_outline,
                        iconColor: theme.colorScheme.primary,
                        onTap: () =>
                            _showCreateWalletDialog(context, walletProvider),
                      ),
                    ),
                    SizedBox(width: isLarge ? 24 : 16),
                    Expanded(
                      child: _WalletOptionCard(
                        title: 'Import Existing Wallet',
                        description:
                            'Restore your wallet using your recovery phrase. '
                            'Make sure you\'re in a private location before entering it.',
                        icon: Icons.download_outlined,
                        iconColor: theme.colorScheme.secondary,
                        onTap: () =>
                            _showImportWalletDialog(context, walletProvider),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _WalletOptionCard(
                      title: 'Create New Wallet',
                      description:
                          'Generate a new wallet with a secure recovery phrase. '
                          'You\'ll be the only one with access to your funds.',
                      icon: Icons.add_circle_outline,
                      iconColor: theme.colorScheme.primary,
                      onTap: () =>
                          _showCreateWalletDialog(context, walletProvider),
                    ),
                    const SizedBox(height: 24),
                    _WalletOptionCard(
                      title: 'Import Existing Wallet',
                      description:
                          'Restore your wallet using your recovery phrase. '
                          'Make sure you\'re in a private location before entering it.',
                      icon: Icons.download_outlined,
                      iconColor: theme.colorScheme.secondary,
                      onTap: () =>
                          _showImportWalletDialog(context, walletProvider),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateWalletDialog(
    BuildContext context,
    WalletProvider walletProvider,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Semantics(
        label: 'Create new wallet dialog',
        child: AlertDialog(
          title: Semantics(
            header: true,
            child: const Text('Create New Wallet'),
          ),
          content: const Text(
            'A new wallet will be created. You\'ll be shown a recovery phrase that you must backup securely. '
            'If you lose this phrase, you\'ll lose access to your Bitcoin forever.',
          ),
          actions: [
            Semantics(
              label: 'Cancel wallet creation',
              button: true,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
            ),
            Semantics(
              label: 'Create new wallet',
              button: true,
              child: ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Create'),
              ),
            ),
          ],
        ),
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
      builder: (dialogContext) => Semantics(
        label: 'Import wallet dialog',
        child: AlertDialog(
          title: Semantics(
            header: true,
            child: const Text('Import Existing Wallet'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter your recovery phrase to restore your wallet. '
                  'Make sure you\'re in a private location.',
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Recovery phrase input field',
                  hint: 'Enter your 12 or 24 word recovery phrase',
                  textField: true,
                  child: TextField(
                    controller: mnemonicController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Recovery Phrase',
                      hintText: 'word1 word2 word3 ...',
                      border: OutlineInputBorder(),
                      helperText:
                          'Enter all words in order, separated by spaces',
                    ),
                    autofocus: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Semantics(
              label: 'Cancel wallet import',
              button: true,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
            ),
            Semantics(
              label: 'Import wallet with recovery phrase',
              button: true,
              child: ElevatedButton(
                onPressed: () {
                  if (mnemonicController.text.trim().isNotEmpty) {
                    Navigator.of(dialogContext).pop(true);
                  }
                },
                child: const Text('Import'),
              ),
            ),
          ],
        ),
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

class _WalletOptionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _WalletOptionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLarge = Breakpoints.isLarge(context);

    return Semantics(
      label: '$title. $description',
      button: true,
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(isLarge ? 28.0 : 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: isLarge ? 72 : 64, color: iconColor),
                SizedBox(height: isLarge ? 20 : 16),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isLarge ? 12 : 8),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final bool isActive;

  const _PageIndicator({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: isActive ? 'Current page' : 'Page indicator',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: isActive ? 24 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withOpacity(0.3),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
