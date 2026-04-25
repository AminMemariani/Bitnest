import 'package:flutter/material.dart';

/// Lifecycle of a UTXO scan from the UI's perspective.
enum ScanStatus { idle, scanning, error }

/// Slim banner that sits above the wallet content and communicates the
/// state of the gap-limit scanner:
///
///   * [ScanStatus.idle] — nothing to show; the banner returns a zero-size
///     widget so layouts don't jump.
///   * [ScanStatus.scanning] — linear progress + "Scanning…" message.
///   * [ScanStatus.error] — red surface with the error text and a retry
///     button.
class ScanStatusBanner extends StatelessWidget {
  final ScanStatus status;

  /// Error message to show when [status] is [ScanStatus.error]. Ignored
  /// otherwise.
  final String? errorMessage;

  /// Optional text shown during the scanning state. Defaults to
  /// "Scanning addresses…".
  final String? scanningLabel;

  /// Called when the user taps the retry button in error mode.
  final VoidCallback? onRetry;

  const ScanStatusBanner({
    super.key,
    required this.status,
    this.errorMessage,
    this.scanningLabel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ScanStatus.idle:
        return const SizedBox.shrink();
      case ScanStatus.scanning:
        return Material(
          key: const Key('scan_status_banner_scanning'),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    scanningLabel ?? 'Scanning addresses…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      case ScanStatus.error:
        final scheme = Theme.of(context).colorScheme;
        return Material(
          key: const Key('scan_status_banner_error'),
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorMessage ?? 'Scan failed',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                ),
                if (onRetry != null)
                  TextButton(
                    key: const Key('scan_status_banner_retry'),
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        );
    }
  }
}
