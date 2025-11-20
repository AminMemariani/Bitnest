import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/key_service.dart';
import '../../models/wallet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _NetworkSection(),
          _DisplaySection(),
          _WalletSection(),
          _SecuritySection(),
        ],
      ),
    );
  }
}

class _NetworkSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, networkProvider, _) {
        return _Section(
          title: 'Network',
          children: [
            ListTile(
              title: const Text('Network'),
              subtitle: Text(networkProvider.networkName),
              trailing: Switch.adaptive(
                value: networkProvider.isTestnet,
                onChanged: (value) {
                  networkProvider.toggleNetwork();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                networkProvider.isTestnet
                    ? 'Using Bitcoin Testnet'
                    : 'Using Bitcoin Mainnet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DisplaySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        return _Section(
          title: 'Display',
          children: [
            ListTile(
              title: const Text('Theme'),
              subtitle: Text(_getThemeModeLabel(settingsProvider.themeMode)),
              trailing: PopupMenuButton<ThemeMode>(
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (mode) {
                  settingsProvider.setThemeMode(mode);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  const PopupMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  const PopupMenuItem(
                    value: ThemeMode.dark,
                    child: Text('Dark'),
                  ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Currency'),
              subtitle: Text(settingsProvider.currency),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (currency) {
                  settingsProvider.setCurrency(currency);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'BTC',
                    child: Text('BTC'),
                  ),
                  const PopupMenuItem(
                    value: 'USD',
                    child: Text('USD'),
                  ),
                  const PopupMenuItem(
                    value: 'EUR',
                    child: Text('EUR'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}

class _WalletSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, _) {
        final currentWallet = walletProvider.currentWallet;
        if (currentWallet == null) {
          return const SizedBox.shrink();
        }

        return _Section(
          title: 'Wallet',
          children: [
            ListTile(
              title: const Text('Export Watch-Only Wallet'),
              subtitle: const Text('Export xpub for watch-only access'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showExportWalletDialog(context, currentWallet),
            ),
            ListTile(
              title: const Text('Backup Mnemonic'),
              subtitle: const Text('View your recovery phrase'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showBackupMnemonicDialog(context, currentWallet),
            ),
          ],
        );
      },
    );
  }

  void _showExportWalletDialog(BuildContext context, Wallet wallet) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export Watch-Only Wallet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Extended Public Key (xpub):'),
            const SizedBox(height: 8),
            SelectableText(
              wallet.xpub,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This xpub can be used to create a watch-only wallet. It cannot be used to spend funds.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: wallet.xpub));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('xpub copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showBackupMnemonicDialog(BuildContext context, Wallet wallet) async {
    if (wallet.mnemonic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mnemonic not available for this wallet'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final keyService = KeyService();
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    // Require authentication
    bool authenticated = false;

    // Try biometrics first if enabled
    if (settingsProvider.biometricsEnabled) {
      authenticated = await keyService.authenticateWithBiometrics(
        reason: 'Authenticate to view mnemonic',
      );
    }

    // If biometrics failed or not enabled, try PIN
    if (!authenticated && settingsProvider.hasPin) {
      authenticated = await _showPinDialog(context, settingsProvider);
    }

    // If still not authenticated and no PIN, just show it (for development)
    if (!authenticated && !settingsProvider.hasPin) {
      authenticated = true; // Allow in development
    }

    if (!authenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentication failed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!context.mounted) return;

    final mnemonic = wallet.mnemonic!;
    final words = mnemonic.split(' ');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Backup Mnemonic'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Keep This Secret',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Anyone with access to these words can control your wallet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  words.length,
                  (index) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${index + 1}.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                        ),
                        const SizedBox(width: 4),
                        SelectableText(
                          words[index],
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: mnemonic));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mnemonic copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showPinDialog(BuildContext context, SettingsProvider settingsProvider) async {
    final pinController = TextEditingController();
    bool isValid = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN',
            hintText: 'Enter your PIN',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final pin = pinController.text;
              isValid = await settingsProvider.verifyPin(pin);
              if (isValid) {
                Navigator.of(dialogContext).pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid PIN'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    return isValid;
  }
}

class _SecuritySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        return _Section(
          title: 'Security',
          children: [
            ListTile(
              title: const Text('Enable Biometrics'),
              subtitle: const Text('Use fingerprint or face ID for authentication'),
              trailing: Switch.adaptive(
                value: settingsProvider.biometricsEnabled,
                onChanged: (value) {
                  settingsProvider.setBiometricsEnabled(value);
                },
              ),
            ),
            ListTile(
              title: const Text('Change PIN'),
              subtitle: Text(settingsProvider.hasPin ? 'Update your PIN' : 'Set a PIN'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showChangePinDialog(context, settingsProvider),
            ),
            ListTile(
              title: const Text('Wipe Wallet'),
              subtitle: const Text('Delete all wallet data'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showWipeWalletDialog(context),
            ),
          ],
        );
      },
    );
  }

  void _showChangePinDialog(BuildContext context, SettingsProvider settingsProvider) async {
    final oldPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(settingsProvider.hasPin ? 'Change PIN' : 'Set PIN'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settingsProvider.hasPin)
                TextField(
                  controller: oldPinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Current PIN',
                    hintText: 'Enter current PIN',
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: newPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'New PIN',
                  hintText: 'Enter 4-6 digit PIN',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  hintText: 'Confirm new PIN',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newPin = newPinController.text;
              final confirmPin = confirmPinController.text;

              if (newPin.length < 4 || newPin.length > 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN must be 4-6 digits'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              if (newPin != confirmPin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PINs do not match'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              bool success = false;
              if (settingsProvider.hasPin) {
                final oldPin = oldPinController.text;
                success = await settingsProvider.changePin(oldPin, newPin);
              } else {
                success = await settingsProvider.setPin(newPin);
              }

              if (success) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(settingsProvider.hasPin ? 'PIN changed' : 'PIN set'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to set PIN. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showWipeWalletDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wipe Wallet'),
        content: const Text(
          'This will permanently delete all wallet data. This action cannot be undone. Make sure you have backed up your mnemonic phrase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _confirmWipeWallet(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Wipe Wallet'),
          ),
        ],
      ),
    );
  }

  void _confirmWipeWallet(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final currentWallet = walletProvider.currentWallet;

    if (currentWallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No wallet to wipe'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    walletProvider.removeWallet(currentWallet.id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Wallet wiped'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }
}

