import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/passkey_daemon.dart';
import 'package:gabbro/widgets/passkey_consent_dialog.dart';

// Consent dialog net (G3a): the in-app pop-up the Linux daemon shows for each
// request. Approve returns the account index, Cancel returns null, and when
// several accounts match the user taps one. Matches the ctap2 seam: index for
// perform, null for denied.

Widget _host(void Function(BuildContext) onReady) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => onReady(context),
          child: const Text('go'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('approving a create returns account index 0', (tester) async {
    int? result = -1;
    await tester.pumpWidget(
      _host((context) async {
        result = await showPasskeyConsent(
          context,
          PasskeyRequest(isCreate: true, rpId: 'example.com', accounts: const [
            'user@example.com',
          ]),
        );
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Create a passkey for example.com?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result, 0);
  });

  testWidgets('cancelling returns null', (tester) async {
    int? result = -1;
    await tester.pumpWidget(
      _host((context) async {
        result = await showPasskeyConsent(
          context,
          PasskeyRequest(isCreate: false, rpId: 'example.com', accounts: const [
            'user@example.com',
          ]),
        );
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('with several accounts, tapping one returns its index', (
    tester,
  ) async {
    int? result = -1;
    await tester.pumpWidget(
      _host((context) async {
        result = await showPasskeyConsent(
          context,
          PasskeyRequest(
            isCreate: false,
            rpId: 'example.com',
            accounts: const ['a@example.com', 'b@example.com'],
          ),
        );
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Both accounts are offered; tapping the second returns index 1.
    expect(find.text('a@example.com'), findsOneWidget);
    await tester.tap(find.text('b@example.com'));
    await tester.pumpAndSettle();
    expect(result, 1);
  });
}
