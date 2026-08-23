import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/passkey_daemon.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'test_helpers.dart';

// The daemon-failure hint on the vault list: a failed passkey provider is
// otherwise silent (passkeys just never appear in the browser), so the list
// shows a banner naming the cause and the README fix. X hides it for this
// session; "Don't show again" persists; a screen reader hears the message
// via announce() because the Linux reader never visits an unfocused banner.

Future<void> _pumpList(
  WidgetTester tester, {
  bool? hintDismissed,
  VoidCallback? onDismissForever,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    testApp(
      VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: () => <EntrySummaryData>[],
        passkeyHintDismissed: hintDismissed,
        onPasskeyHintDismissForever: onDismissForever,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => passkeyProviderFailure.value = null);
  tearDown(() => passkeyProviderFailure.value = null);

  testWidgets('daemon failure shows the banner and announces it',
      (tester) async {
    passkeyProviderFailure.value = PasskeyFailureReason.moduleMissing;
    final said = recordAnnouncements(tester);
    await _pumpList(tester);

    expect(find.textContaining('uhid'), findsOneWidget);
    expect(said.join('\n'), contains('uhid'));
  });

  testWidgets('no failure, no banner', (tester) async {
    await _pumpList(tester);
    expect(find.textContaining('uhid'), findsNothing);
    expect(find.textContaining('README'), findsNothing);
  });

  testWidgets('X hides the banner for the session without persisting',
      (tester) async {
    passkeyProviderFailure.value = PasskeyFailureReason.noAccess;
    var persisted = false;
    await _pumpList(tester, onDismissForever: () => persisted = true);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.textContaining('udev'), findsNothing);
    expect(persisted, isFalse);
  });

  testWidgets('"Don\'t show again" hides the banner and persists',
      (tester) async {
    passkeyProviderFailure.value = PasskeyFailureReason.other;
    var persisted = false;
    await _pumpList(tester, onDismissForever: () => persisted = true);

    await tester.tap(find.text("Don't show again"));
    await tester.pumpAndSettle();

    expect(find.textContaining('README'), findsNothing);
    expect(persisted, isTrue);
  });

  testWidgets('a persisted dismissal suppresses the banner and the announce',
      (tester) async {
    passkeyProviderFailure.value = PasskeyFailureReason.moduleMissing;
    final said = recordAnnouncements(tester);
    await _pumpList(tester, hintDismissed: true);

    expect(find.textContaining('uhid'), findsNothing);
    expect(said.join('\n'), isNot(contains('uhid')));
  });
}
