import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/network_provider.dart';
import '../../utils/networks.dart';
import '../../services/key_service.dart';
import 'send_screen.dart';
import 'receive_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BitNest'),
        actions: [
          Consumer<NetworkProvider>(
            builder: (context, networkProvider, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: Row(
                    children: [
                      Text(
                        networkProvider.isMainnet ? 'Mainnet' : 'Testnet',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: networkProvider.isTestnet,
                        onChanged: (_) => networkProvider.toggleNetwork(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<WalletProvider>(
        builder: (context, walletProvider, _) {
          if (walletProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (walletProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: ${walletProvider.error}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => walletProvider.clearError(),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            );
          }

          if (walletProvider.wallets.isEmpty) {
            return _buildEmptyState(context, walletProvider);
          }

          if (walletProvider.currentWallet == null) {
            return _buildWalletList(context, walletProvider);
          }

          return _buildWalletView(context, walletProvider);
        },
      ),
      floatingActionButton: Consumer<WalletProvider>(
        builder: (context, walletProvider, _) {
          if (walletProvider.wallets.isEmpty) {
            return FloatingActionButton.extended(
              onPressed: () => _showCreateWalletDialog(context, walletProvider),
              icon: const Icon(Icons.add),
              label: const Text('Create Wallet'),
            );
          }
          return FloatingActionButton(
            onPressed: () => _showCreateWalletDialog(context, walletProvider),
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WalletProvider walletProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to BitNest',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Create your first Bitcoin wallet to get started',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showCreateWalletDialog(context, walletProvider),
              icon: const Icon(Icons.add),
              label: const Text('Create Wallet'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletList(BuildContext context, WalletProvider walletProvider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: walletProvider.wallets.length,
      itemBuilder: (context, index) {
        final wallet = walletProvider.wallets[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(wallet.label[0].toUpperCase()),
            ),
            title: Text(wallet.label),
            subtitle: Text(
              wallet.network == BitcoinNetwork.mainnet ? 'Mainnet' : 'Testnet',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => walletProvider.selectWallet(wallet.id),
          ),
        );
      },
    );
  }

  Widget _buildWalletView(BuildContext context, WalletProvider walletProvider) {
    final wallet = walletProvider.currentWallet!;
    final accounts = walletProvider.currentAccounts;
    final totalBalance = walletProvider.totalBalance;

    return Column(
      children: [
        // Wallet header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wallet.label,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        wallet.network == BitcoinNetwork.mainnet
                            ? 'Bitcoin Mainnet'
                            : 'Bitcoin Testnet',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => walletProvider.deselectWallet(),
                    tooltip: 'Back to wallets',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Total Balance',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                _formatBalance(totalBalance),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),

        // Accounts list
        Expanded(
          child: accounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'No accounts yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _showCreateAccountDialog(
                          context,
                          walletProvider,
                        ),
                        child: const Text('Create Account'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final balance = walletProvider.getAccountBalance(account.id);
                    final isSyncing = walletProvider.isAccountSyncing(account.id);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          child: Text(account.label[0].toUpperCase()),
                        ),
                        title: Text(account.label),
                        subtitle: Text(_formatBalance(balance)),
                        trailing: isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: () => walletProvider.fetchAccountUtxos(
                                  account.id,
                                ),
                                tooltip: 'Sync',
                              ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoRow('Derivation Path', account.derivationPath),
                                _buildInfoRow('Addresses', '${account.addresses.length}'),
                                if (account.addresses.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Addresses:',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  ...account.addresses.map((address) => Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: SelectableText(
                                          address,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      )),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) => ReceiveScreen(
                                                  account: account,
                                                  onGenerateNextAddress: () =>
                                                      walletProvider.deriveNextReceiveAddress(
                                                    account.id,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.qr_code),
                                          label: const Text('Receive'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) => SendScreen(account: account),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.send),
                                          label: const Text('Send'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
    );
  }

  String _formatBalance(BigInt balance) {
    if (balance == BigInt.zero) {
      return '0.00000000 BTC';
    }
    final btc = balance / BigInt.from(100000000);
    final sats = balance % BigInt.from(100000000);
    return '${btc.toString()}.${sats.toString().padLeft(8, '0')} BTC';
  }

  void _showCreateWalletDialog(
    BuildContext context,
    WalletProvider walletProvider,
  ) {
    final networkProvider = Provider.of<NetworkProvider>(context, listen: false);
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final keyService = KeyService();
    
    // Generate mnemonic first
    final mnemonic = keyService.generateMnemonic(wordCount: 24);
    final words = mnemonic.split(' ');
    bool isRevealed = false;
    bool hasBackedUp = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create New Wallet'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Wallet Name',
                      hintText: 'My Bitcoin Wallet',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a wallet name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Network: ${networkProvider.networkName}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
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
                                'Backup Your Seed Phrase',
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
                          'Write down these 24 words in order. Store them in a safe place. Anyone with access to these words can control your wallet.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!isRevealed)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => isRevealed = true),
                      icon: const Icon(Icons.visibility),
                      label: const Text('Reveal Seed Phrase'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            children: [
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
                                      color: Theme.of(context).colorScheme.surface,
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
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: mnemonic));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Seed phrase copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => isRevealed = false),
                                icon: const Icon(Icons.visibility_off),
                                label: const Text('Hide'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: hasBackedUp,
                          onChanged: (value) => setState(() => hasBackedUp = value ?? false),
                          title: Text(
                            'I have backed up my seed phrase',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (isRevealed && hasBackedUp && formKey.currentState?.validate() == true)
                  ? () async {
                      Navigator.of(context).pop();
                      try {
                        await walletProvider.createWallet(
                          label: nameController.text,
                          network: networkProvider.currentNetwork,
                          mnemonic: mnemonic,
                        );
                        if (mounted) {
                          walletProvider.selectWallet(
                            walletProvider.wallets.last.id,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Wallet created successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Create Wallet'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateAccountDialog(
    BuildContext context,
    WalletProvider walletProvider,
  ) {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Account'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              hintText: 'Savings Account',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter an account name';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop();
                try {
                  await walletProvider.createAccount(
                    label: nameController.text,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

