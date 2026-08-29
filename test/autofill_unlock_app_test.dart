import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

// Net D: the autofill unlock entrypoint reuses the main UnlockScreen and mirrors
// main.dart's shell wiring (delegates / locale / theme / text scale), adds the
// vault picker, and signals the native side via onUnlocked.

VaultRecord _rec(String path, String alias) => VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

VaultRegistry _twoVaults() => VaultRegistry([
      _rec('/tmp/a.gabbro', 'Alpha'),
      _rec('/tmp/b.gabbro', 'Beta'),
    ]);

VaultRegistry _oneVault() => VaultRegistry([_rec('/tmp/a.gabbro', 'Alpha')]);

void main() {
  const channel = MethodChannel('app.gabbro.gabbro/autofill');

  testWidgets('mirrors main wiring: delegates, supported locales, themes',
      (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.localizationsDelegates, isNotNull);
    expect(app.supportedLocales, AppLocalizations.supportedLocales);
    expect(app.theme, isNotNull);
    expect(app.darkTheme, isNotNull);
  });

  testWidgets('applies the settings text scale (1.5)', (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: const AppSettings(textScale: 1.5),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    final mq = MediaQuery.of(tester.element(find.byType(UnlockScreen)));
    expect(mq.textScaler.scale(10), 15.0);
  });

  testWidgets('reuses UnlockScreen with registry picker and onUnlocked',
      (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: const AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    final screen = tester.widget<UnlockScreen>(find.byType(UnlockScreen));
    expect(screen.registry, isNotNull);
    expect(screen.onUnlocked, isNotNull);
    expect(screen.vaultPath, '/tmp/a.gabbro');
    expect(find.byType(DropdownButton<String>), findsOneWidget);
  });

  testWidgets('selecting another vault in the picker switches the unlock target',
      (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<UnlockScreen>(find.byType(UnlockScreen)).vaultPath,
      '/tmp/b.gabbro',
    );
  });

  // N4: the closed list names the vault you are about to unlock. The screen
  // builds two parallel lists (the entries and their collapsed labels); if they
  // ever fall out of step the prompt names the wrong vault.
  testWidgets('the closed list names the current vault', (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: const AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsNothing);
  });

  // 1: nothing here can open the pick-a-vault-file screen, so the entry must
  // not be offered - tapping it did nothing at all.
  testWidgets('the vault list does not offer the adopt entry', (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: const AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unlock_adopt_item')), findsNothing);
    expect(find.text('Alpha').hitTestable(), findsWidgets);
    expect(find.text('Beta').hitTestable(), findsWidgets);
  });

  // 3: with the entry gone and only one vault, the list can do nothing but
  // reselect the vault already being unlocked, so it is not shown at all.
  testWidgets('one vault: no list at all', (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: const AppSettings(),
      registry: _oneVault(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('no-match dialog shows localized text and cancels on dismiss',
      (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showAutofillNoMatchDialog(context, channel),
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('No credentials found'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(calls, contains('cancel'));
  });

  // D1: the *real* path - unlocking with no match must show the localized
  // no-match dialog (not silently fail / not a false auth error). Regression
  // for the dialog being shown from a context above the MaterialApp's Navigator.
  testWidgets(
      'real path: unlock with no match shows the no-match dialog, not an auth error',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'unlock') return false; // unlocked, but nothing matched
      return null; // 'cancel' etc.
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
      onUnlock: (a, b) async {}, // unlock succeeds (test seam)
    ));
    await tester.pump();

    // Tap Unlock directly (Unlock is enabled even with an empty passphrase; the
    // injected onUnlock succeeds). Avoids the passphrase field's onChanged ->
    // estimateEntropy FFI, which isn't initialized in a widget test.
    // Use explicit pumps, not pumpAndSettle: _doUnlock awaits the open dialog, so
    // the Unlock spinner keeps animating and pumpAndSettle would never settle.
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('No credentials found'), findsOneWidget);
    expect(
      find.text('Could not unlock vault. Check your passphrase.'),
      findsNothing,
    );

    // Dismiss to let the unlock flow finish (channel 'cancel') and the spinner stop.
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
  });

  // RT-5: this activity exists only because the vault was locked, so the
  // session it opens is its own. It finishes right after the fill and its Dart
  // isolate dies with it, leaving nothing running to close that session - so it
  // must lock on the way out. The ORDER matters: locking after `finish` would
  // race the engine teardown, which is why `unlock` no longer finishes.
  testWidgets('a successful fill locks the vault, then finishes', (tester) async {
    final events = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      events.add('channel:${call.method}');
      if (call.method == 'unlock') return true; // a credential matched
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
      onUnlock: (a, b) async {},
      onLock: () => events.add('lock'),
    ));
    await tester.pump();

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    expect(events, ['channel:unlock', 'lock', 'channel:finish'],
        reason: 'the fill response is built, then we lock, then the activity ends');
  });

  testWidgets('cancelling after no match locks the vault too', (tester) async {
    final events = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      events.add('channel:${call.method}');
      if (call.method == 'unlock') return false; // unlocked, nothing matched
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: AppSettings(),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
      onUnlock: (a, b) async {},
      onLock: () => events.add('lock'),
    ));
    await tester.pump();

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(events, ['channel:unlock', 'lock', 'channel:cancel'],
        reason: 'a vault opened for a fill that matched nothing still closes');
  });
}
