import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/passkey_consent_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

// The passkey app shell (buildPasskeyApp): who locks the session on the way
// out. Net: a signed-in get approves and finishes without locking. D1/D2 cover
// the locked-vault flow (unlock-only mode + the relock-after stamp).

VaultRecord _rec(String path, String alias) => VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

VaultRegistry _oneVault() => VaultRegistry([_rec('/tmp/a.gabbro', 'Alpha')]);

void main() {
  const channel = MethodChannel('app.gabbro.gabbro/passkey');

  List<String> mockChannel(WidgetTester tester) {
    final events = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      events.add('channel:${call.method}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    return events;
  }

  testWidgets('net: signed-in get approves and finishes without locking',
      (tester) async {
    final events = mockChannel(tester);
    await tester.pumpWidget(buildPasskeyApp(
      settings: const AppSettings(),
      registry: _oneVault(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: true,
      isCreate: false,
      rpId: 'example.com',
      userName: 'user@example.com',
      channel: channel,
      onUnlock: (a, b) async {},
      onLock: () => events.add('lock'),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(PasskeyConsentScreen));
    final l = AppLocalizations.of(context);
    await tester.tap(find.text(l.confirm));
    await tester.pumpAndSettle();

    expect(events, ['channel:approve', 'channel:finish'],
        reason: 'the main app owns this session; the passkey flow must not '
            'lock a vault it did not open');
  });

  // D1: the AuthenticationAction tap. The activity can only hand fresh picker
  // rows back to the OS — never a signed credential — so Dart shows the unlock
  // screen alone, approves (Kotlin rebuilds the rows) and finishes. The session
  // stays open: the follow-up row tap must not demand a second unlock.
  testWidgets(
      'D1: unlock-only mode shows UnlockScreen only; unlock approves then '
      'finishes without locking', (tester) async {
    final events = mockChannel(tester);
    await tester.pumpWidget(buildPasskeyApp(
      settings: const AppSettings(),
      registry: _oneVault(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: false,
      isUnlockOnly: true,
      isCreate: false,
      rpId: '',
      userName: '',
      channel: channel,
      onUnlock: (a, b) async {},
      onLock: () => events.add('lock'),
    ));
    await tester.pump();

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PasskeyConsentScreen), findsNothing,
        reason: 'no operation to consent to - the row tap gets its own consent');
    expect(events, ['channel:approve', 'channel:finish'],
        reason: 'the rebuilt rows need the session open; the follow-up get '
            'flow relocks');
  });

  // D2: a row stamped EXTRA_RELOCK_AFTER by the D1 unlock. This flow did not
  // open the session, but it is the last one out - Gabbro must end locked.
  testWidgets(
      'D2: get with the relock flag locks after approve even when '
      'alreadyUnlocked', (tester) async {
    final events = mockChannel(tester);
    await tester.pumpWidget(buildPasskeyApp(
      settings: const AppSettings(),
      registry: _oneVault(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: true,
      relockAfter: true,
      isCreate: false,
      rpId: 'example.com',
      userName: 'user@example.com',
      channel: channel,
      onUnlock: (a, b) async {},
      onLock: () => events.add('lock'),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(PasskeyConsentScreen));
    final l = AppLocalizations.of(context);
    await tester.tap(find.text(l.confirm));
    await tester.pumpAndSettle();

    expect(events, ['channel:approve', 'lock', 'channel:finish'],
        reason: 'sign first, lock second - Gabbro ends locked, as the user '
            'left it');
  });

  // D2 companion: cancelling out of a relock-stamped flow must also leave
  // Gabbro locked - the user walked away, not signed in.
  testWidgets('D2: cancel with the relock flag locks too', (tester) async {
    final events = mockChannel(tester);
    await tester.pumpWidget(buildPasskeyApp(
      settings: const AppSettings(),
      registry: _oneVault(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: true,
      relockAfter: true,
      isCreate: false,
      rpId: 'example.com',
      userName: 'user@example.com',
      channel: channel,
      onUnlock: (a, b) async {},
      onLock: () => events.add('lock'),
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(PasskeyConsentScreen));
    final l = AppLocalizations.of(context);
    await tester.tap(find.text(l.cancel));
    await tester.pumpAndSettle();

    expect(events, ['lock', 'channel:cancel']);
  });
}
