import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/passkey_consent_screen.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('create mode names the site and the account', (tester) async {
    await tester.pumpWidget(
      testApp(
        PasskeyConsentScreen(
          isCreate: true,
          rpId: 'example.com',
          userName: 'user@example.com',
          onApprove: () {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('example.com'), findsWidgets);
    expect(find.textContaining('user@example.com'), findsOneWidget);
  });

  testWidgets('sign-in mode differs from create mode', (tester) async {
    Widget screen(bool isCreate) => testApp(
      PasskeyConsentScreen(
        isCreate: isCreate,
        rpId: 'example.com',
        userName: '',
        onApprove: () {},
        onCancel: () {},
      ),
    );
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    final createTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    final getTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(createTexts, isNot(equals(getTexts)),
        reason: 'the user must see WHICH action they are approving');
  });

  testWidgets('approve and cancel fire their callbacks', (tester) async {
    var approved = false;
    var cancelled = false;
    await tester.pumpWidget(
      testApp(
        PasskeyConsentScreen(
          isCreate: false,
          rpId: 'example.com',
          userName: 'user@example.com',
          onApprove: () => approved = true,
          onCancel: () => cancelled = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PasskeyConsentScreen));
    final l = AppLocalizations.of(context);
    await tester.tap(find.text(l.confirm));
    expect(approved, isTrue);
    await tester.tap(find.text(l.cancel));
    expect(cancelled, isTrue);
  });
}
