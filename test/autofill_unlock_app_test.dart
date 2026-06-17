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

  testWidgets('applies the settings text scale (xxLarge => 1.5)', (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: AppSettings(textSize: TextSizeChoice.xxLarge),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    final mq = MediaQuery.of(tester.element(find.byType(UnlockScreen)));
    expect(mq.textScaler.scale(10), 15.0);
  });

  testWidgets('reuses UnlockScreen with registry picker, onUnlocked, biometric',
      (tester) async {
    await tester.pumpWidget(buildAutofillUnlockApp(
      settings: AppSettings(biometricUnlock: true),
      registry: _twoVaults(),
      initialVaultPath: '/tmp/a.gabbro',
      channel: channel,
    ));
    await tester.pump();

    final screen = tester.widget<UnlockScreen>(find.byType(UnlockScreen));
    expect(screen.registry, isNotNull);
    expect(screen.onUnlocked, isNotNull);
    expect(screen.biometricEnabled, isTrue);
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
}
