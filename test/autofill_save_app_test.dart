import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/save_confirm_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

// The autofill save app shell: when already unlocked it fetches the save context
// and shows the confirm screen; when locked it shows the unlock flow first.

VaultRecord _rec(String path, String alias) => VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

VaultRegistry _vaults() => VaultRegistry([
      _rec('/tmp/a.gabbro', 'Alpha'),
      _rec('/tmp/b.gabbro', 'Beta'),
    ]);

VaultRegistry _oneVault() => VaultRegistry([_rec('/tmp/a.gabbro', 'Alpha')]);

String _createJson() => jsonEncode({
      'captured': {
        'username': 'alice',
        'email': '',
        'password': 'pw',
        'url': 'https://example.com',
        'appId': '',
      },
      'decision': {'action': 'create'},
      'candidates': const [],
    });

void main() {
  testWidgets('already unlocked: fetches context and shows the confirm screen',
      (tester) async {
    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: true,
      fetchSaveContextJson: () async => _createJson(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SaveConfirmScreen), findsOneWidget);
    expect(find.byType(UnlockScreen), findsNothing);
    expect(find.text('Save as a new login'), findsOneWidget);
  });

  testWidgets('locked: shows the unlock screen first, not the confirm screen',
      (tester) async {
    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: false,
      fetchSaveContextJson: () async => '{}',
    ));
    await tester.pump();

    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.byType(SaveConfirmScreen), findsNothing);
  });

  // N3: the save prompt offers the vault list, and choosing another vault
  // retargets the unlock — the login is saved into the vault you picked.
  testWidgets('locked: choosing another vault switches the unlock target',
      (tester) async {
    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: false,
      fetchSaveContextJson: () async => '{}',
    ));
    await tester.pump();

    expect(find.byType(DropdownButton<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<UnlockScreen>(find.byType(UnlockScreen)).vaultPath,
      '/tmp/b.gabbro',
    );
  });

  // 2: same as the fill prompt — nothing here can open the pick-a-vault-file
  // screen, so the entry is not offered.
  testWidgets('locked: the vault list does not offer the adopt entry',
      (tester) async {
    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: false,
      fetchSaveContextJson: () async => '{}',
    ));
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unlock_adopt_item')), findsNothing);
    expect(find.text('Beta').hitTestable(), findsWidgets);
  });

  // 4: with the entry gone and only one vault, the list can do nothing but
  // reselect the vault already being unlocked, so it is not shown at all.
  testWidgets('locked, one vault: no list at all', (tester) async {
    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _oneVault(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: false,
      fetchSaveContextJson: () async => '{}',
    ));
    await tester.pump();

    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  // RT-5: a vault this flow unlocked is its own, and the activity's isolate dies
  // when it finishes — so it closes the session on the way out, before telling
  // Kotlin to finish.
  //
  // Driven through Cancel, not Save: both routes share `_finish` and differ only
  // in the method name, and Save writes the entry through real FFI first, which
  // a widget test cannot run. The Save route is covered on device.
  testWidgets('save: a vault this flow unlocked is locked again on the way out',
      (tester) async {
    final events = <String>[];
    const channel = MethodChannel('app.gabbro.gabbro/autofill_save');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      events.add('channel:${call.method}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: false,
      fetchSaveContextJson: () async => _createJson(),
      onUnlock: (a, b) async {},
      onLock: () => events.add('lock'),
    ));
    await tester.pump();

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.byType(SaveConfirmScreen), findsOneWidget,
        reason: 'precondition: unlocked, now on the confirm screen');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(events.last, 'channel:cancel');
    expect(events[events.length - 2], 'lock',
        reason: 'lock before the activity is told to finish, not after');
  });

  // The main app already had this vault open, so the session is not ours to
  // close — its own auto-lock owns it.
  testWidgets('save: a session the main app owns is left alone',
      (tester) async {
    var locks = 0;
    const channel = MethodChannel('app.gabbro.gabbro/autofill_save');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(buildAutofillSaveApp(
      settings: AppSettings(),
      registry: _vaults(),
      initialVaultPath: '/tmp/a.gabbro',
      alreadyUnlocked: true,
      fetchSaveContextJson: () async => _createJson(),
      onLock: () => locks++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(locks, 0,
        reason: 'closing it would lock the user out of the app they are using');
  });
}
