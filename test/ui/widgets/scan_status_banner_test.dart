import 'package:bitnest/ui/widgets/scan_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('ScanStatusBanner', () {
    testWidgets('idle state renders nothing visible', (t) async {
      await t.pumpWidget(
        _wrap(const ScanStatusBanner(status: ScanStatus.idle)),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('scan_status_banner_scanning')),
          findsNothing);
      expect(
          find.byKey(const Key('scan_status_banner_error')), findsNothing);
    });

    testWidgets('scanning state shows a progress indicator and label',
        (t) async {
      await t.pumpWidget(_wrap(const ScanStatusBanner(
        status: ScanStatus.scanning,
        scanningLabel: 'Scanning address 7 of ∞',
      )));
      expect(find.byKey(const Key('scan_status_banner_scanning')),
          findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Scanning address 7 of ∞'), findsOneWidget);
    });

    testWidgets(
        'error state shows the error text and a Retry button that fires '
        'the callback', (t) async {
      var retried = false;
      await t.pumpWidget(_wrap(ScanStatusBanner(
        status: ScanStatus.error,
        errorMessage: 'Network timeout while scanning UTXOs',
        onRetry: () => retried = true,
      )));
      expect(
          find.byKey(const Key('scan_status_banner_error')), findsOneWidget);
      expect(find.text('Network timeout while scanning UTXOs'),
          findsOneWidget);

      await t.tap(find.byKey(const Key('scan_status_banner_retry')));
      expect(retried, isTrue);
    });

    testWidgets('error state hides the Retry button when onRetry is null',
        (t) async {
      await t.pumpWidget(_wrap(const ScanStatusBanner(
        status: ScanStatus.error,
        errorMessage: 'Something went wrong',
      )));
      expect(find.byKey(const Key('scan_status_banner_retry')), findsNothing);
    });
  });
}
