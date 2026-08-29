import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/nfc_capability.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';

EntropyResult _fakeEntropy(String ignored) => EntropyResult(
      bits: 0,
      tier: StrengthTier.terrible,
    );

YubikeyRecordData _fakeRecord() => YubikeyRecordData(
      credentialId: Uint8List.fromList([1, 2, 3, 4]),
      salt: Uint8List(32),
    );

VaultRecord _vaultRecord({
  required String path,
  required String alias,
}) =>
    VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

Widget _buildScreen({
  String vaultPath = '/tmp/test.gabbro',
  Future<void> Function(List<int>, String)? onUnlock,
  Future<void> Function()? onUnlocked,
  bool blockPassphraseCopyPaste = true,
  List<YubikeyRecordData>? yubikeyRecords,
  Future<void> Function(List<int>, List<int>, List<int>, String, String, String)?
      onUnlockWithYubikey,
  Future<void> Function(List<int>, List<YubikeyRecordData>, String, String, String)?
      onUnlockWithAnyYubikey,
  String? vaultAlias,
  VaultRegistry? registry,
  void Function(String path, String alias)? onVaultSwitch,
  Future<bool> Function(String)? onBiometricIsEnrolled,
  Future<List<int>?> Function(String)? onBiometricAuthenticate,
  bool? isAndroid,
  Future<void> Function()? onCancelTap,
  Future<bool> Function(String)? onVaultIsReadable,
  Future<bool> Function(String)? onVaultFormatTooOld,
  Future<bool> Function(String)? onVaultFormatTooNew,
  Future<bool> Function(String)? onBackupUsable,
  Future<void> Function(String)? onRestoreBackup,
  Future<String?> Function()? onPickRestoreFile,
  Future<void> Function(String, String)? onRestoreFromPickedFile,
  Future<void> Function(String)? onDisableBiometric,
  Future<void> Function(String)? onRemoveVaultFromList,
  Future<void> Function(String)? onDeleteVaultFile,
  VoidCallback? onQuit,
  VoidCallback? onAdoptRequested,
}) =>
    testApp(UnlockScreen(
      vaultPath: vaultPath,
      onUnlock: onUnlock ?? (a, b) async {},
      onUnlocked: onUnlocked,
      onEstimateEntropy: _fakeEntropy,
      blockPassphraseCopyPaste: blockPassphraseCopyPaste,
      yubikeyRecords: yubikeyRecords ?? [],
      onUnlockWithYubikey: onUnlockWithYubikey ?? (a, b, c, d, e, f) async {},
      onUnlockWithAnyYubikey: onUnlockWithAnyYubikey ?? (a, b, c, d, e) async {},
      vaultAlias: vaultAlias,
      registry: registry,
      onVaultSwitch: onVaultSwitch,
      onBiometricIsEnrolled: onBiometricIsEnrolled ?? (_) async => false,
      onBiometricAuthenticate: onBiometricAuthenticate ?? (_) async => null,
      isAndroid: isAndroid,
      onCancelTap: onCancelTap ?? () async {},
      onVaultIsReadable: onVaultIsReadable ?? (_) async => true,
      onVaultFormatTooOld: onVaultFormatTooOld ?? (_) async => false,
      onVaultFormatTooNew: onVaultFormatTooNew ?? (_) async => false,
      onBackupUsable: onBackupUsable ?? (_) async => false,
      onRestoreBackup: onRestoreBackup ?? (_) async {},
      onPickRestoreFile: onPickRestoreFile ?? () async => null,
      onRestoreFromPickedFile: onRestoreFromPickedFile ?? (_, _) async {},
      onDisableBiometric: onDisableBiometric ?? (_) async {},
      onRemoveVaultFromList: onRemoveVaultFromList ?? (_) async {},
      onDeleteVaultFile: onDeleteVaultFile ?? (_) async {},
      onQuit: onQuit,
      onAdoptRequested: onAdoptRequested,
    ));

/// The same screen under the real app shell, as the main app builds it
/// (`main.dart:_buildUnlockScreen`): no adopt callback, the shell above it.
/// `testApp` alone renders it bare, which no user ever meets - and the offer to
/// open another vault file depends on that shell being there.
Widget _buildScreenInApp({
  String vaultPath = '/tmp/a.gabbro',
  String? vaultAlias,
  VaultRegistry? registry,
}) =>
    GabbroApp(
      registry: registry ?? VaultRegistry([]),
      vaultPath: vaultPath,
      settings: const AppSettings(),
      initialScreen: UnlockScreen(
        vaultPath: vaultPath,
        vaultAlias: vaultAlias,
        registry: registry,
        onUnlock: (a, b) async {},
        onEstimateEntropy: _fakeEntropy,
        onBiometricIsEnrolled: (_) async => false,
        onBiometricAuthenticate: (_) async => null,
        onCancelTap: () async {},
        onVaultIsReadable: (_) async => true,
        onVaultFormatTooOld: (_) async => false,
        onVaultFormatTooNew: (_) async => false,
        onBackupUsable: (_) async => false,
      ),
    );

// Mirrors main.dart's MaterialApp wiring so the screen is exercised under the
// user's real theme / high-contrast / text size / locale - not the test default.

Widget _appShell(
  Widget home, {
  ThemeMode mode = ThemeMode.light,
  bool highContrast = false,
  Locale? locale,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      // Production's delegates, not AppLocalizations' bare list: they ship the
      // nn and yo fallbacks, so no sweep below has to tolerate a warning no user
      // ever meets - and a tolerance cannot swallow a real overflow raised in
      // the same frame.
      localizationsDelegates: gabbroLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      themeMode: mode,
      theme: gabbroLightTheme(highContrast: highContrast),
      darkTheme: gabbroDarkTheme(highContrast: highContrast),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: home,
    );

// A bare UnlockScreen with only the mount-safe seams overridden (no real FFI on
// mount); appearance tests render it, they never tap unlock.
UnlockScreen _bareUnlock({
  List<YubikeyRecordData> yubikeyRecords = const [],
  VoidCallback? onQuit,
}) =>
    UnlockScreen(
      vaultPath: '/tmp/test.gabbro',
      onEstimateEntropy: _fakeEntropy,
      yubikeyRecords: yubikeyRecords,
      onVaultIsReadable: (_) async => true,
      onBackupUsable: (_) async => false,
      onBiometricIsEnrolled: (_) async => false,
      onQuit: onQuit,
    );

// RT-3: a bare UnlockScreen showing the pre-v11 format banner. The Net A/B/C
// sweeps below use this so the banner is exercised for overflow, contrast, tap
// targets and long-string locales - _bareUnlock has a readable vault, so it
// never renders the banner at all.
Widget _bareFormatTooOld() => UnlockScreen(
      vaultPath: '/tmp/test.gabbro',
      onEstimateEntropy: _fakeEntropy,
      yubikeyRecords: const [],
      onVaultIsReadable: (_) async => false,
      onVaultFormatTooOld: (_) async => true,
      onBackupUsable: (_) async => false,
      onBiometricIsEnrolled: (_) async => false,
    );

// Biometric-enrolled UnlockScreen at a chosen text scale on a phone-sized
// surface (ADR-016): past 1.5x the button drops its label for an icon.
Widget _biometricAtScale(
  double scale, {
  Future<List<int>?> Function(String)? onAuth,
}) =>
    testApp(MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        size: const Size(360, 800),
      ),
      child: UnlockScreen(
        vaultPath: '/tmp/test.gabbro',
        onEstimateEntropy: _fakeEntropy,
        yubikeyRecords: const [],
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: onAuth ?? (_) async => null,
        onVaultIsReadable: (_) async => true,
        onBackupUsable: (_) async => false,
      ),
    ));

// The unlock screen as the vault-switch route builds it: a second route on the
// stack, so Navigator.canPop is true and the vault below is still unlocked.
// Only that route can be cancelled - every other way in clears the stack on
// purpose, which _bareUnlock (a lone route) stands for.
Widget _nestedUnlock({
  VoidCallback? onQuit,
  Locale? locale,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      // Production's delegates, not AppLocalizations' - they ship the nn and yo
      // fallbacks, so the locale sweep below can demand a clean render instead
      // of tolerating a warning that no user ever meets.
      localizationsDelegates: gabbroLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: gabbroLightTheme(highContrast: false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Navigator(
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('the open vault')),
          ),
          MaterialPageRoute<void>(
            builder: (_) => _bareUnlock(onQuit: onQuit),
          ),
        ],
      ),
    );

void main() {
  testWidgets('unlock screen renders key elements', (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.byType(GabbroLogo), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  // Quit: a tiling-WM user with no title-bar close
  // needs a way out of the locked screen. First scenario: the button exists.
  testWidgets('shows a Quit button (power icon) on the locked screen',
      (tester) async {
    await tester.pumpWidget(_buildScreen(onQuit: () {}));

    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
  });

  // Linux-only: production wires onQuit only on Linux, so elsewhere the button
  // is absent (not a greyed-out dead control).
  testWidgets('no Quit button when onQuit is not wired (non-Linux)',
      (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.byIcon(Icons.power_settings_new), findsNothing);
  });

  // Quit (canon-TDD #2): the button needs a localized name so a screen-reader
  // user and a hover both get "Quit", and it satisfies the labelled-tap-target
  // guideline. English base string checked here; all 37 locales via l10n_test.
  testWidgets('the Quit button carries a localized tooltip/label',
      (tester) async {
    await tester.pumpWidget(_buildScreen(onQuit: () {}));

    expect(find.byTooltip('Quit'), findsOneWidget);
  });

  // Quit (canon-TDD #3): the locked screen holds no secrets, so Quit exits at
  // once - it fires onQuit and never raises a confirm dialog (that beat is only
  // for the unlocked vault, where an accidental quit costs a re-unlock).
  testWidgets('tapping Quit on the locked screen fires onQuit, no confirm',
      (tester) async {
    var quitCalls = 0;
    await tester.pumpWidget(_buildScreen(onQuit: () => quitCalls++));

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();

    expect(quitCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  // Reached from Manage vaults -> switch, the vault you came from is still open
  // behind this screen, but nothing on screen says how to get back to it. Esc
  // does it in two presses and says so nowhere.

  // R1: Cancel replaces Quit on that route. Quitting the app from a screen you
  // arrived at mid-task is not what you meant, and Ctrl+Q is already inert here
  // (vault_list_screen.dart:602 gates on the current route).
  testWidgets('shows Cancel and hides Quit when the screen can pop',
      (tester) async {
    await tester.pumpWidget(_nestedUnlock(onQuit: () {}));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsNothing,
        reason: 'Quit keeps its other three surfaces, not this one');
  });

  // R2 (route-level) lives in vault_switch_routing_test.dart, where the real
  // production route is what puts the unlock screen over the open vault.

  // R3: every other way to the unlock screen cleared the stack, so there is
  // nothing to cancel back to and Quit stays.
  testWidgets('shows Quit and no Cancel when the screen cannot pop',
      (tester) async {
    await tester.pumpWidget(_buildScreen(onQuit: () {}));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsNothing);
  });

  // R4: a tooltip is not an accessible name - on Linux a screen reader reads
  // only the name, so the icon carries a semanticLabel too.
  testWidgets('Cancel carries a localized accessible name', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_nestedUnlock(onQuit: () {}));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  // R5: the label is longer in most languages than in English, and the worst
  // case is the longest translation at the largest scale on the narrowest
  // screen - all three together (ADR-016).
  testWidgets('Cancel survives every locale at 2x text on a 360dp phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(_nestedUnlock(
        onQuit: () {},
        locale: locale,
        textScaler: const TextScaler.linear(kPhoneMaxScale),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsWidgets,
          reason: 'precondition: the Cancel control is rendered in $locale');
      expect(tester.takeException(), isNull,
          reason: 'Cancel must not overflow at 2x text in $locale');
    }
  });

  testWidgets('error message shown when unlock throws', (tester) async {
    await tester.pumpWidget(
      _buildScreen(
        onUnlock: (a, b) async => throw Exception('wrong passphrase'),
      ),
    );

    await tester.enterText(find.byType(TextField), 'wrongpassphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not unlock vault. Check your passphrase.'),
      findsOneWidget,
    );
  });

  testWidgets('passphrase field blocks selection when blockPassphraseCopyPaste is true',
      (tester) async {
    await tester.pumpWidget(_buildScreen(blockPassphraseCopyPaste: true));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enableInteractiveSelection, isFalse);
  });

  testWidgets('passphrase field allows selection when blockPassphraseCopyPaste is false',
      (tester) async {
    await tester.pumpWidget(_buildScreen(blockPassphraseCopyPaste: false));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enableInteractiveSelection, isNot(isFalse));
  });

  testWidgets('unlock button is present and tappable', (tester) async {
    bool called = false;
    await tester.pumpWidget(
      _buildScreen(onUnlock: (a, b) async => called = true),
    );

    await tester.enterText(find.byType(TextField), 'anypassphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  // Lock the *current* unlock-flow behaviour before the autofill `onUnlocked`
  // hook is introduced, so any regression from the reuse/extraction is caught.

  testWidgets(
      'Net A: successful passphrase unlock navigates to VaultListScreen',
      (tester) async {
    await tester.pumpWidget(_buildScreen(onUnlock: (a, b) async {}));

    await tester.enterText(find.byType(TextField), 'anypassphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.byType(VaultListScreen), findsOneWidget);
    expect(find.byType(UnlockScreen), findsNothing);
  });

  testWidgets(
      'onUnlocked hook fires on success and suppresses VaultListScreen navigation',
      (tester) async {
    bool hookCalled = false;
    await tester.pumpWidget(_buildScreen(
      onUnlock: (a, b) async {},
      onUnlocked: () async => hookCalled = true,
    ));

    await tester.enterText(find.byType(TextField), 'anypassphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(hookCalled, isTrue);
    expect(find.byType(VaultListScreen), findsNothing);
    expect(find.byType(UnlockScreen), findsOneWidget);
  });

  // D2: once the vault is unlocked, a failure in the post-unlock work (the
  // autofill onUnlocked signaling) must NOT be reported as an auth failure.
  testWidgets(
      'D2: a successful unlock never shows an auth error, even if onUnlocked throws',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onUnlock: (a, b) async {}, // unlock succeeds
      onUnlocked: () async => throw Exception('post-unlock boom'),
    ));

    await tester.enterText(find.byType(TextField), 'correct-passphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not unlock vault. Check your passphrase.'),
      findsNothing,
    );
  });

  testWidgets('Net A: successful YubiKey unlock navigates to VaultListScreen',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async {},
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.byType(VaultListScreen), findsOneWidget);
    expect(find.byType(UnlockScreen), findsNothing);
  });

  testWidgets('Net A: YubiKey unlock passes the default usb transport',
      (tester) async {
    String? transport;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, path, t) async => transport = t,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(transport, 'usb');
  });

  testWidgets('Net A: selecting NFC passes the nfc transport (Android)',
      (tester) async {
    nfcAvailable = true; // device has NFC -> the USB/NFC selector is offered
    addTearDown(() => nfcAvailable = false);
    String? transport;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      isAndroid: true,
      onUnlockWithYubikey: (a, b, c, d, path, t) async => transport = t,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('NFC'));
    await tester.tap(find.text('NFC'));
    await tester.pump();
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(transport, 'nfc');
  });

  testWidgets('NFC transport is not offered on an Android device without NFC',
      (tester) async {
    nfcAvailable = false; // non-NFC tablet
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      isAndroid: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('NFC'), findsNothing);
    expect(find.text('USB'), findsNothing);
  });

  testWidgets('Net A: PIN field blocks selection when blockPassphraseCopyPaste is true',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      blockPassphraseCopyPaste: true,
    ));

    // Two fields in yubikey mode: passphrase then PIN. The PIN (last) must
    // honour the same copy/paste block as the passphrase field.
    final pin = tester.widgetList<TextField>(find.byType(TextField)).last;
    expect(pin.enableInteractiveSelection, isFalse);
  });

  testWidgets('Net A: keyboard submit (done action) triggers unlock',
      (tester) async {
    bool called = false;
    await tester.pumpWidget(_buildScreen(onUnlock: (a, b) async => called = true));

    await tester.enterText(find.byType(TextField), 'anypassphrase');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets(
      'Net A: in YubiKey mode, Enter on the passphrase advances to the PIN (no submit)',
      (tester) async {
    var submitted = false;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlock: (a, b) async => submitted = true,
      onUnlockWithYubikey: (a, b, c, d, e, f) async => submitted = true,
      onUnlockWithAnyYubikey: (a, b, c, d, e) async => submitted = true,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, isFalse,
        reason: 'Enter on the passphrase must not submit while a PIN is still needed');
    final pin = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(pin.focusNode?.hasFocus, isTrue,
        reason: 'Enter should move focus to the YubiKey PIN field');
  });

  testWidgets('Net A: in YubiKey mode, Enter on the PIN field submits',
      (tester) async {
    var ykCalled = false;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async => ykCalled = true,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(ykCalled, isTrue);
  });

  testWidgets('Net A: Enter on the PIN field does not double-submit while unlocking',
      (tester) async {
    var count = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async {
        count++;
        await gate.future;
      },
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done); // first submit; hangs
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done); // must be ignored
    await tester.pump();

    expect(count, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Net A: unlock button is disabled with a spinner while unlocking',
      (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(_buildScreen(onUnlock: (a, b) => gate.future));

    await tester.enterText(find.byType(TextField), 'anypassphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pump(); // enter the unlocking state

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Net A: biometric+YubiKey hint shown in yubikey mode when enrolled',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onBiometricIsEnrolled: (_) async => true,
    ));
    await tester.pump(); // enrollment probe settles

    expect(
      find.text('Enter your YubiKey PIN below, then tap Use biometrics, '
          'then tap your YubiKey.'),
      findsOneWidget,
    );
  });

  testWidgets('Net A: no overflow in a short viewport with an error showing '
      '(passphrase-only and yubikey modes)', (tester) async {
    tester.view.physicalSize = const Size(400, 340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    for (final records in [<YubikeyRecordData>[], [_fakeRecord()]]) {
      await tester.pumpWidget(_buildScreen(
        yubikeyRecords: records,
        onUnlock: (a, b) async => throw Exception('wrong'),
        onUnlockWithYubikey: (a, b, c, d, e, f) async => throw Exception('wrong'),
      ));
      await tester.enterText(find.byType(TextField).first, 'wrongpassphrase');
      await tester.ensureVisible(find.text('Unlock'));
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'short viewport must scroll, never overflow');
    }
  });

  group('Net B appearance + language', () {
    testWidgets('renders under light/dark themes, plain and high-contrast',
        (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final hc in [false, true]) {
          await tester.pumpWidget(
            _appShell(_bareUnlock(), mode: mode, highContrast: hc),
          );
          await tester.pump();
          expect(find.byType(GabbroLogo), findsOneWidget);
          expect(find.text('Unlock'), findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: 'mode=$mode highContrast=$hc must render cleanly');
        }
      }
    });

    testWidgets('renders at 2x text scale without overflow (both modes)',
        (tester) async {
      for (final records in [<YubikeyRecordData>[], [_fakeRecord()]]) {
        await tester.pumpWidget(_appShell(
          _bareUnlock(yubikeyRecords: records),
          textScaler: const TextScaler.linear(2.0),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Unlock'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: 'large text must scroll, never overflow');
      }
    });

    testWidgets('renders under a long-string locale (de) without overflow',
        (tester) async {
      await tester.pumpWidget(_appShell(_bareUnlock(), locale: const Locale('de')));
      await tester.pumpAndSettle();
      expect(find.byType(GabbroLogo), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // RT-3 banner: two sentences plus a link button, so it is the longest text
    // block on the screen and the likeliest to bleed.
    testWidgets('format-too-old banner survives a narrow phone at 2x text',
        (tester) async {
      // 360x800 phone, the app's text-scale ceiling (ADR-016).
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(_appShell(
        _bareFormatTooOld(),
        textScaler: const TextScaler.linear(kPhoneMaxScale),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the banner must scroll at 2x text, never overflow');
    });

    // A user who needs large text must not get a broken screen in their own
    // language: the worst case is the LONGEST translation at the LARGEST scale
    // on the NARROWEST screen, and testing scale and locale separately never
    // meets it. Sweep every supported locale at the 2x phone ceiling rather
    // than guessing which translation is longest.
    testWidgets('format-too-old banner survives every locale at 2x text',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(_appShell(
          _bareFormatTooOld(),
          locale: locale,
          textScaler: const TextScaler.linear(kPhoneMaxScale),
        ));
        await tester.pumpAndSettle();

        // No tolerance: _appShell now uses production's delegates, so nn and yo
        // render as cleanly as every other locale. A tolerance here could not
        // tell a delegate warning from an overflow raised in the same frame -
        // Flutter folds both into one opaque "Multiple exceptions" wrapper, and
        // a `contains` check on it passes either way.
        expect(tester.takeException(), isNull,
            reason: '$locale at 2x must scroll, never overflow');
      }
    });

    testWidgets('format-too-old banner scrolls in a short viewport',
        (tester) async {
      tester.view.physicalSize = const Size(400, 340);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(_appShell(_bareFormatTooOld()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'short viewport must scroll, never overflow');
    });

    testWidgets('format-too-old banner renders in every theme and in de',
        (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final hc in [false, true]) {
          await tester.pumpWidget(
            _appShell(_bareFormatTooOld(), mode: mode, highContrast: hc),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'mode=$mode highContrast=$hc must render cleanly');
        }
      }
      await tester.pumpWidget(
        _appShell(_bareFormatTooOld(), locale: const Locale('de')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the long-string locale must not overflow the banner');
    });
  });

  group('Net C accessibility (broad sweep)', () {
    testWidgets('meets Android tap-target guideline (passphrase + yubikey modes)',
        (tester) async {
      final handle = tester.ensureSemantics();
      for (final records in [<YubikeyRecordData>[], [_fakeRecord()]]) {
        await tester.pumpWidget(_appShell(_bareUnlock(yubikeyRecords: records)));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      handle.dispose();
    });

    // The show/hide eye toggles (passphrase + PIN suffixIcon) must carry a
    // semantic label so screen readers announce them, not a bare "button".
    testWidgets('meets Android labelled-tap-target guideline (passphrase + yubikey modes)',
        (tester) async {
      final handle = tester.ensureSemantics();
      for (final records in [<YubikeyRecordData>[], [_fakeRecord()]]) {
        await tester.pumpWidget(_appShell(_bareUnlock(yubikeyRecords: records)));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      handle.dispose();
    });

    // Quit (canon-TDD #4): the Quit button is enabled only when onQuit is wired,
    // so the sweeps above (button disabled) skip it. Pin its 48dp target and its
    // localized label directly, with Quit active.
    testWidgets('enabled Quit button meets tap-target and label guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_appShell(_bareUnlock(onQuit: () {})));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('meets text-contrast guideline in light and dark themes',
        (tester) async {
      final handle = tester.ensureSemantics();
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(_appShell(_bareUnlock(), mode: mode));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });

    // RT-3 banner: it is what the user sees INSTEAD of the unlock controls, so
    // it must clear the same bars - the upgrade link must be reachable and
    // announced, not a bare unlabelled button.
    testWidgets('format-too-old banner meets tap-target, label and contrast '
        'guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(_appShell(_bareFormatTooOld(), mode: mode));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });

    testWidgets('focus starts on passphrase and Tab advances toward unlock',
        (tester) async {
      await tester.pumpWidget(_appShell(_bareUnlock(yubikeyRecords: [_fakeRecord()])));
      await tester.pumpAndSettle();

      final passphrase = tester.widget<TextField>(find.byType(TextField).first);
      expect(passphrase.autofocus, isTrue,
          reason: 'keyboard/screen-reader users land on the passphrase field');

      final before = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNot(before),
          reason: 'forward traversal must move focus (reading order)');
    });
  });

  testWidgets('body uses SafeArea to avoid system navigation bar overlap',
      (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
    expect(find.byType(SafeArea), findsOneWidget);
  });

  testWidgets('passphrase-only mode when yubikey records are empty', (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: []));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Enter your passphrase to unlock'), findsOneWidget);
  });

  testWidgets('yubikey mode when yubikey records are present', (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Insert your YubiKey and tap when it flashes'), findsOneWidget);
  });

  testWidgets('yubikey unlock calls onUnlockWithYubikey', (tester) async {
    bool called = false;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async => called = true,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets('unlock screen is scrollable in landscape-like viewport (yubikey mode)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('yubikey error shown when onUnlockWithYubikey throws', (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async =>
          throw Exception('bad yubikey'),
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not unlock vault'), findsOneWidget);
  });

  testWidgets('shows vault alias below title when provided', (tester) async {
    await tester.pumpWidget(_buildScreen(vaultAlias: 'Work'));
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('does not show alias text when vaultAlias is null', (tester) async {
    await tester.pumpWidget(_buildScreen());
    expect(find.text('Work'), findsNothing);
  });

  testWidgets('no switch icon shown (switch icon removed in new design)', (tester) async {
    await tester.pumpWidget(_buildScreen());
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
  });

  testWidgets('multi-key vault calls onUnlockWithAnyYubikey not onUnlockWithYubikey',
      (tester) async {
    bool anyCalled = false;
    bool singleCalled = false;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord(), _fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async => singleCalled = true,
      onUnlockWithAnyYubikey: (passphrase, records, pin, path, transport) async =>
          anyCalled = true,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(anyCalled, isTrue);
    expect(singleCalled, isFalse);
  });

  group('biometric button', () {
    testWidgets('not shown when this vault is not enrolled', (tester) async {
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => false,
      ));
      await tester.pump(); // allow initState async to settle
      expect(find.text('Use biometrics'), findsNothing);
    });

    testWidgets('shown when this vault is enrolled (no global flag)', (tester) async {
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
      ));
      await tester.pump();
      expect(find.text('Use biometrics'), findsOneWidget);
    });

    testWidgets('passphrase field always present alongside biometric button', (tester) async {
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
      ));
      await tester.pump();
      expect(find.text('Use biometrics'), findsOneWidget);
      expect(find.byType(TextField), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping biometric button calls onBiometricAuthenticate', (tester) async {
      bool called = false;
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async { called = true; return null; },
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });

    testWidgets('keeps the labelled button at normal text scale', (tester) async {
      await tester.pumpWidget(_biometricAtScale(1.0));
      await tester.pump();
      expect(find.text('Use biometrics'), findsOneWidget);
    });

    testWidgets('drops the label for an icon at large text scale', (tester) async {
      await tester.pumpWidget(_biometricAtScale(3.0));
      await tester.pump();
      // Label text gone (it wrapped over several lines on hardware)...
      expect(find.text('Use biometrics'), findsNothing);
      // ...replaced by a fingerprint icon that keeps the screen-reader name
      // (the tooltip is the button's accessible label).
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      expect(find.byTooltip('Use biometrics'), findsOneWidget);
    });

    testWidgets('icon-only button still authenticates when tapped', (tester) async {
      bool called = false;
      await tester.pumpWidget(_biometricAtScale(
        3.0,
        onAuth: (_) async {
          called = true;
          return null;
        },
      ));
      await tester.pump();
      await tester.ensureVisible(find.byIcon(Icons.fingerprint));
      await tester.tap(find.byIcon(Icons.fingerprint));
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });

    testWidgets('biometric cancelled shows hint message', (tester) async {
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async => null,
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();
      expect(
        find.text('Biometric authentication was not completed.'
            ' Enter your passphrase to unlock.'),
        findsOneWidget,
      );
    });

    testWidgets('BIOMETRIC_INVALIDATED exception hides button and shows error',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async {
          throw PlatformException(code: 'BIOMETRIC_INVALIDATED');
        },
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      // Button must disappear: the native side auto-unenrolled this vault, so
      // the local enrolled state resets to false. No global setting to clear.
      expect(find.text('Use biometrics'), findsNothing);
    });

    testWidgets('other PlatformException shows biometric cancelled message',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async {
          throw PlatformException(code: 'SOME_OTHER_ERROR');
        },
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('not completed'),
        findsOneWidget,
        reason: 'non-invalidated PlatformException shows cancellation message',
      );
      // Button must still be visible (biometricEnrolled not reset).
      expect(find.text('Use biometrics'), findsOneWidget);
    });

    testWidgets('biometric success calls unlock and navigates', (tester) async {
      bool unlockCalled = false;
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async => [1, 2, 3],
        onUnlock: (_, _) async => unlockCalled = true,
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      expect(unlockCalled, isTrue);
    });
  });

  // H1 error contract: tap-stage failures are PlatformExceptions before the
  // passphrase is tried; a wrong passphrase is a plain exception from the
  // decrypt call. Only the decrypt stage may conclude the stored passphrase
  // is stale.
  group('H1: external vault swap vs biometric', () {
    testWidgets('N1: a typed wrong passphrase never touches biometric enrolment',
        (tester) async {
      var unenrolled = false;
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onDisableBiometric: (_) async => unenrolled = true,
        onUnlock: (_, _) async => throw Exception('wrong passphrase'),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'typed-wrong');
      await tester.ensureVisible(find.text('Unlock'));
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Could not unlock vault. Check your passphrase.'),
          findsOneWidget);
      expect(unenrolled, isFalse,
          reason: 'a typed mistake proves nothing about the stored passphrase');
      expect(find.text('Use biometrics'), findsOneWidget);
    });

    testWidgets(
        'N2: a tap-stage failure (wrong PIN) never touches biometric enrolment',
        (tester) async {
      for (final code in ['HMAC_FAILED', 'HMAC_MULTI_FAILED']) {
        var unenrolled = false;
        await tester.pumpWidget(_buildScreen(
          yubikeyRecords: [_fakeRecord()],
          onBiometricIsEnrolled: (_) async => true,
          onDisableBiometric: (_) async => unenrolled = true,
          onUnlockWithYubikey: (a, b, c, d, e, f) async =>
              throw PlatformException(code: code),
        ));
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, 'anypassphrase');
        await tester.ensureVisible(find.text('Unlock'));
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();

        expect(
            find.text(
                'Could not unlock vault. Check your passphrase and YubiKey PIN.'),
            findsOneWidget,
            reason: '$code is a tap-stage failure: generic message');
        expect(unenrolled, isFalse,
            reason: '$code says nothing about the stored passphrase');
      }
    });

    const staleMessage = 'Biometric unlock was turned off: the vault file '
        'changed and the saved passphrase no longer opens it. '
        'Re-enable it in Security.';

    testWidgets(
        'H1a: biometric-fed decrypt rejection unenrols and says the file changed',
        (tester) async {
      var unenrolCalls = 0;
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async => [1, 2, 3],
        onDisableBiometric: (_) async => unenrolCalls++,
        onUnlock: (_, _) async => throw Exception('decryption failed'),
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      expect(unenrolCalls, 1,
          reason: 'the stored passphrase is provably stale: unenrol once');
      expect(find.text('Use biometrics'), findsNothing,
          reason: 'the button must go with the enrolment');
      expect(find.text(staleMessage), findsOneWidget,
          reason: 'the message must name the cause, not blame the passphrase');
    });

    testWidgets('H1b: same on a keyed vault (decrypt stage rejects)',
        (tester) async {
      var unenrolCalls = 0;
      await tester.pumpWidget(_buildScreen(
        yubikeyRecords: [_fakeRecord()],
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async => [1, 2, 3],
        onDisableBiometric: (_) async => unenrolCalls++,
        onUnlockWithYubikey: (a, b, c, d, e, f) async =>
            throw Exception('decryption failed'),
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      expect(unenrolCalls, 1);
      expect(find.text('Use biometrics'), findsNothing);
      expect(find.text(staleMessage), findsOneWidget);
    });

    testWidgets(
        'H1c: keyed, biometric-fed, tap-stage wrong PIN leaves enrolment alone',
        (tester) async {
      var unenrolled = false;
      await tester.pumpWidget(_buildScreen(
        yubikeyRecords: [_fakeRecord()],
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async => [1, 2, 3],
        onDisableBiometric: (_) async => unenrolled = true,
        onUnlockWithYubikey: (a, b, c, d, e, f) async =>
            throw PlatformException(code: 'HMAC_FAILED'),
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      expect(unenrolled, isFalse,
          reason: 'a wrong PIN must never switch the fingerprint off');
      expect(
          find.text(
              'Could not unlock vault. Check your passphrase and YubiKey PIN.'),
          findsOneWidget);
      expect(find.text('Use biometrics'), findsOneWidget);
    });

    testWidgets(
        'H1d: biometric-fed failure on an unreadable file shows the corruption '
        'banner and leaves enrolment alone', (tester) async {
      var unenrolled = false;
      var readable = true;
      await tester.pumpWidget(_buildScreen(
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async => [1, 2, 3],
        onDisableBiometric: (_) async => unenrolled = true,
        onVaultIsReadable: (_) async => readable,
        onBackupUsable: (_) async => true,
        onUnlock: (_, _) async {
          readable = false; // corrupted while this screen was mounted
          throw Exception('parse failed');
        },
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      expect(find.text('Restore from safety copy'), findsOneWidget,
          reason: 'an unreadable file is corruption, not a swap verdict');
      expect(unenrolled, isFalse);
    });

    testWidgets(
        'H1e: the stale-biometric message survives every locale at 2x on a '
        '360dp phone', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: gabbroLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(kPhoneMaxScale)),
            child: child!,
          ),
          home: UnlockScreen(
            vaultPath: '/tmp/test.gabbro',
            onEstimateEntropy: _fakeEntropy,
            yubikeyRecords: const [],
            isAndroid: true,
            onBiometricIsEnrolled: (_) async => true,
            onBiometricAuthenticate: (_) async => [1, 2, 3],
            onDisableBiometric: (_) async {},
            onUnlock: (_, _) async => throw Exception('decryption failed'),
            onVaultIsReadable: (_) async => true,
            onVaultFormatTooOld: (_) async => false,
            onVaultFormatTooNew: (_) async => false,
            onBackupUsable: (_) async => false,
          ),
        ));
        await tester.pumpAndSettle();

        // Past 1.5x the biometric button is icon-only.
        final biometric = find.byIcon(Icons.fingerprint);
        await tester.ensureVisible(biometric);
        await tester.pumpAndSettle();
        await tester.tap(biometric, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'the message must scroll at 2x in $locale, never overflow');
        final l = lookupAppLocalizations(locale);
        expect(find.text(l.biometricStaleDisabled), findsOneWidget,
            reason: 'the message must be on screen for $locale to mean anything');
      }
    });
  });

  group('vault dropdown', () {
    final twoVaultRegistry = VaultRegistry([
      _vaultRecord(path: '/tmp/a.gabbro', alias: 'Alpha'),
      _vaultRecord(path: '/tmp/b.gabbro', alias: 'Beta'),
    ]);

    testWidgets('shows dropdown when registry has 2+ vaults', (tester) async {
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        registry: twoVaultRegistry,
      ));
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    // E2 (adopt): a single registered vault still gets the dropdown - it now
    // carries the "Open a vault file..." entry, the unlock screen's route to
    // adopting a second device's export. Flips the pre-adopt one-vault pin.
    testWidgets('shows dropdown with one vault (it carries the adopt entry)',
        (tester) async {
      final singleRegistry = VaultRegistry([
        _vaultRecord(path: '/tmp/a.gabbro', alias: 'Alpha'),
      ]);
      await tester.pumpWidget(_buildScreenInApp(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        registry: singleRegistry,
      ));
      expect(find.byType(DropdownButton<String>), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlock_adopt_item')), findsWidgets);
    });

    testWidgets('no dropdown when registry is null', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: null));
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('no dropdown when the registry is empty', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: VaultRegistry([])));
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('the adopt entry fires onAdoptRequested and switches nothing',
        (tester) async {
      var requested = 0;
      String? switchedPath;
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        registry: twoVaultRegistry,
        onVaultSwitch: (p, _) => switchedPath = p,
        onAdoptRequested: () => requested++,
      ));
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unlock_adopt_item')).last);
      await tester.pumpAndSettle();

      expect(requested, 1);
      expect(switchedPath, isNull,
          reason: 'adopt is not a vault switch and must not navigate to one');
    });

    testWidgets('dropdown shows all vault aliases', (tester) async {
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        registry: twoVaultRegistry,
      ));
      // Current vault alias shown in collapsed dropdown
      expect(find.text('Alpha'), findsWidgets);
    });

    testWidgets('selecting a different vault calls onVaultSwitch', (tester) async {
      String? switchedPath;
      String? switchedAlias;
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        registry: twoVaultRegistry,
        onVaultSwitch: (p, a) {
          switchedPath = p;
          switchedAlias = a;
        },
      ));
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta').last);
      await tester.pumpAndSettle();
      expect(switchedPath, '/tmp/b.gabbro');
      expect(switchedAlias, 'Beta');
    });

    // E3: the adopt entry rides along without regressing vault switching.
    testWidgets('two vaults: both aliases and the adopt entry are offered',
        (tester) async {
      await tester.pumpWidget(_buildScreenInApp(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        registry: twoVaultRegistry,
      ));
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Beta'), findsWidgets);
      expect(find.byKey(const Key('unlock_adopt_item')), findsWidgets);
    });
  });

  group('reveal-eye toggles scale (capped) at large text', () {
    void setPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('passphrase and PIN eyes scale up and stay capped at 1.4x',
        (tester) async {
      setPhone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
      await tester.pumpAndSettle();

      expect(revealEyeButtons(), findsNWidgets(2));
      for (final eye in tester.widgetList<IconButton>(revealEyeButtons())) {
        expect(eye.iconSize, isNotNull);
        expect(eye.iconSize, greaterThan(24));
        expect(eye.iconSize, lessThanOrEqualTo(24 * 1.4));
      }
    });

    testWidgets('the fields do not overflow at large text', (tester) async {
      setPhone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('passphrase visibility toggle switches icon', (tester) async {
    await tester.pumpWidget(_buildScreen()); // passphrase-only mode

    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNothing);
  });

  testWidgets('PIN visibility toggle in yubikey mode switches icon',
      (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));

    // Both passphrase and PIN fields start with visibility_off.
    expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));

    // Tap the PIN field's eye icon (last visibility_off).
    await tester.tap(find.byIcon(Icons.visibility_off).last);
    await tester.pump();

    // PIN icon flips to visibility; passphrase icon stays as visibility_off.
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('TRANSPORT_ERROR exception shows transport error message',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async => throw PlatformException(
        code: 'TRANSPORT_ERROR',
        message: 'NFC read timed out',
      ),
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('NFC read timed out'), findsOneWidget);
  });

  testWidgets('NO_FIDO2_DEVICE exception shows device-not-found message',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onUnlockWithYubikey: (a, b, c, d, e, f) async => throw PlatformException(
        code: 'NO_FIDO2_DEVICE',
        message: 'No FIDO2 device found',
      ),
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('No FIDO2 device found'), findsOneWidget);
  });

  testWidgets('typing in passphrase field shows entropy strength indicator',
      (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('yubikey unlock shows a Cancel button on Android while tapping',
      (tester) async {
    bool cancelled = false;
    final gate = Completer<void>();
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      isAndroid: true,
      onUnlockWithYubikey: (a, b, c, d, e, f) => gate.future,
      onCancelTap: () async => cancelled = true,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pump(); // start the tap; spinner + Cancel appear

    expect(find.text('Cancel'), findsOneWidget);

    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelled, isTrue);

    gate.completeError(PlatformException(code: 'TAP_CANCELLED'));
    await tester.pumpAndSettle();
  });

  testWidgets('no Cancel button shown on non-Android while tapping',
      (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      isAndroid: false,
      onUnlockWithYubikey: (a, b, c, d, e, f) => gate.future,
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(find.text('Cancel'), findsNothing);

    gate.completeError(PlatformException(code: 'TAP_CANCELLED'));
    await tester.pumpAndSettle();
  });

  testWidgets('TAP_CANCELLED clears the spinner without showing an error',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      isAndroid: true,
      onUnlockWithYubikey: (a, b, c, d, e, f) async =>
          throw PlatformException(code: 'TAP_CANCELLED'),
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.textContaining('Could not unlock'), findsNothing);
  });

  testWidgets('TAP_TIMEOUT shows a no-key message, not a wrong-passphrase error',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      isAndroid: true,
      onUnlockWithYubikey: (a, b, c, d, e, f) async => throw PlatformException(
        code: 'TAP_TIMEOUT',
        message: 'No YubiKey detected. Tap timed out.',
      ),
    ));

    await tester.enterText(find.byType(TextField).first, 'anypassphrase');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('No YubiKey detected. Tap timed out.'), findsOneWidget);
    expect(find.textContaining('Check your passphrase'), findsNothing);
  });

  testWidgets('corrupt vault with a backup offers the restore option',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Restore from safety copy'), findsOneWidget);
  });

  testWidgets(
      'corrupt vault without a usable backup shows the unrecoverable state '
      'with remove/delete actions, no restore', (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
    ));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This vault file cannot be read, and its safety copy is unreadable '
        'too. Its contents cannot be recovered on this device.',
      ),
      findsOneWidget,
    );
    expect(find.text('Restore from safety copy'), findsNothing);
    expect(find.text('Remove from list'), findsOneWidget);
    expect(find.text('Delete file'), findsOneWidget);
  });

  // A pre-floor vault does not parse; without these the user is told it is
  // corrupt and invited to delete a file that only needs migrating.

  const oldFormatMessage =
      'This vault uses an older format that this version of Gabbro cannot '
      'open. Your vault file has not been changed.';
  const upgradeUrl =
      'https://github.com/gabbro-foss/gabbro/blob/master/docs/VAULT_UPGRADE_PATH.md';

  testWidgets('a pre-v11 vault explains the format, never the corruption banner',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false, // does not parse at floor v11
      onVaultFormatTooOld: (_) async => true, // ...because it is an old format
      onBackupUsable: (_) async => true, // a .bak exists, and is equally old
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining(oldFormatMessage), findsOneWidget);
    // None of the corruption vocabulary or destructive offers may appear: the
    // .bak is the same old format, so restoring it would fix nothing, and
    // deleting is the one thing that would actually lose the vault.
    expect(find.text('Restore from safety copy'), findsNothing);
    expect(find.text('Delete file'), findsNothing);
    expect(find.text('Remove from list'), findsNothing);
  });

  testWidgets('a pre-v11 vault offers a tappable link to the upgrade steps',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onVaultFormatTooOld: (_) async => true,
    ));
    await tester.pumpAndSettle();

    // Same convention as the About screen: tapping shows the URL first, so the
    // user sees where they are going before any browser opens.
    await tester.tap(find.textContaining('upgrade'));
    await tester.pumpAndSettle();

    expect(find.text(upgradeUrl), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
  });

  testWidgets('an unreadable vault that is NOT old still reports corruption',
      (tester) async {
    // Guards the regression the two tests above could cause: a genuinely
    // corrupt file must keep its restore path.
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onVaultFormatTooOld: (_) async => false,
      onBackupUsable: (_) async => true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Restore from safety copy'), findsOneWidget);
    expect(find.textContaining(oldFormatMessage), findsNothing);
  });

  // A vault written by a NEWER build also fails to parse, but it is intact: the
  // fix is to update Gabbro, so it must never surface the corruption banner.
  const newFormatMessage =
      'This vault was created by a newer version of Gabbro. Update Gabbro to '
      'open it. Your vault file has not been changed.';

  testWidgets('a too-new vault explains "update Gabbro", never corruption',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false, // does not parse
      onVaultFormatTooOld: (_) async => false, // ...and it is not too old
      onVaultFormatTooNew: (_) async => true, // ...it is too new
      onBackupUsable: (_) async => true,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining(newFormatMessage), findsOneWidget);
    expect(find.text('Restore from safety copy'), findsNothing);
    expect(find.text('Delete file'), findsNothing);
    expect(find.text('Remove from list'), findsNothing);
  });

  testWidgets('a too-new vault offers a tappable link to update Gabbro',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onVaultFormatTooNew: (_) async => true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('update Gabbro'));
    await tester.pumpAndSettle();

    expect(find.text(upgradeUrl), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
  });

  testWidgets('wrong passphrase on a healthy vault never offers restore',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onBackupUsable: (_) async => true, // even with a backup present
      onUnlock: (a, b) async => throw Exception('wrong passphrase'),
    ));

    await tester.enterText(find.byType(TextField), 'wrongpassphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Could not unlock vault. Check your passphrase.'),
        findsOneWidget);
    expect(find.text('Restore from safety copy'), findsNothing);
  });

  testWidgets(
      'R-03 P2: unlock failure after the file became unreadable shows the '
      'corruption banner, not the passphrase error',
      (tester) async {
    var readable = true; // healthy at mount, so no banner appears initially
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => readable,
      onBackupUsable: (_) async => true,
      onUnlock: (a, b) async {
        // The vault file was corrupted while this screen was mounted.
        readable = false;
        throw Exception('decrypt failed');
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('Restore from safety copy'), findsNothing,
        reason: 'healthy at mount: the banner must not appear yet');

    await tester.enterText(find.byType(TextField), 'whatever');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Restore from safety copy'), findsOneWidget,
        reason: 're-probe on failure must surface the corruption banner');
    expect(find.text('Could not unlock vault. Check your passphrase.'),
        findsNothing,
        reason: 'a corrupt file must not show the misleading passphrase error');
  });

  testWidgets(
      'R-03: re-probes on app resume so a vault corrupted while backgrounded '
      'shows the banner on return', (tester) async {
    var readable = true; // healthy when the screen first mounts
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => readable,
      onBackupUsable: (_) async => true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Restore from safety copy'), findsNothing,
        reason: 'healthy at mount: no banner');

    // Corrupted while the app was backgrounded, then brought back to the
    // foreground (valid lifecycle path back to resumed is via inactive).
    readable = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Restore from safety copy'), findsOneWidget,
        reason: 'resume must re-probe and surface the corruption banner');
  });

  testWidgets(
      'yubikey auth failures (wrong PIN, wrong key, timeout, cancel) never offer restore',
      (tester) async {
    final failures = <Object>[
      // The real wrong-PIN code (GabbroUnlockHostActivity registers HMAC_FAILED
      // for the single-key tap); an invented CTAP_ERROR passed here for the
      // same reason any unknown code does - keep the pin on the real contract.
      PlatformException(code: 'HMAC_FAILED', message: 'Wrong PIN'),
      Exception('decryption failed'),
      PlatformException(code: 'TAP_TIMEOUT'),
      PlatformException(code: 'TAP_CANCELLED'),
    ];

    for (final failure in failures) {
      await tester.pumpWidget(_buildScreen(
        yubikeyRecords: [_fakeRecord()],
        onBackupUsable: (_) async => true,
        onUnlockWithYubikey: (a, b, c, d, e, f) async => throw failure,
      ));

      await tester.enterText(find.byType(TextField).first, 'anypassphrase');
      await tester.ensureVisible(find.text('Unlock'));
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Restore from safety copy'), findsNothing,
          reason: 'no restore offer after: $failure');
    }
  });

  testWidgets('confirmed restore calls onRestoreBackup and clears the banner',
      (tester) async {
    final restoreCalls = <String>[];
    var readable = false;
    await tester.pumpWidget(_buildScreen(
      vaultPath: '/tmp/corrupt.gabbro',
      onVaultIsReadable: (_) async => readable,
      onBackupUsable: (_) async => true,
      onRestoreBackup: (p) async {
        restoreCalls.add(p);
        readable = true;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore from safety copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(restoreCalls, ['/tmp/corrupt.gabbro']);
    expect(find.text('Restore from safety copy'), findsNothing);
    expect(find.text('Safety copy restored. Unlock with your credentials.'),
        findsOneWidget);
  });

  testWidgets('declined restore touches nothing', (tester) async {
    final restoreCalls = <String>[];
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => true,
      onRestoreBackup: (p) async => restoreCalls.add(p),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore from safety copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(restoreCalls, isEmpty);
    expect(find.text('Restore from safety copy'), findsOneWidget);
  });

  testWidgets(
      'failed restore (backup rotted after probe) drops to the unrecoverable '
      'state and Delete file calls onDeleteVaultFile', (tester) async {
    final deleteCalls = <String>[];
    await tester.pumpWidget(_buildScreen(
      vaultPath: '/tmp/corrupt.gabbro',
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => true, // usable at probe...
      onRestoreBackup: (_) async => // ...but rotted by restore time
          throw Exception('The vault backup is not usable — restore refused'),
      onDeleteVaultFile: (p) async => deleteCalls.add(p),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore from safety copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    // Restore failed: the screen must drop to the unrecoverable state, no
    // longer offering a restore the backup can't honour.
    expect(find.text('Restore from safety copy'), findsNothing);
    expect(find.text('Remove from list'), findsOneWidget);

    await tester.ensureVisible(find.text('Delete file'));
    await tester.tap(find.text('Delete file')); // the card button
    await tester.pumpAndSettle();
    expect(find.text('Delete corrupted vault file permanently?'), findsOneWidget);
    // Confirm via the dialog's action button (scoped to the AlertDialog, since
    // the card button carries the same label).
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Delete file'),
    ));
    await tester.pumpAndSettle();

    expect(deleteCalls, ['/tmp/corrupt.gabbro']);
  });

  testWidgets('R-03 P5: Remove from list calls onRemoveVaultFromList',
      (tester) async {
    final removeCalls = <String>[];
    await tester.pumpWidget(_buildScreen(
      vaultPath: '/tmp/dead.gabbro',
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
      onRemoveVaultFromList: (p) async => removeCalls.add(p),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Remove from list'));
    await tester.tap(find.text('Remove from list')); // the card button
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Remove from list'),
    ));
    await tester.pumpAndSettle();

    expect(removeCalls, ['/tmp/dead.gabbro']);
  });

  testWidgets(
      'R-03: corrupt vault (no usable backup) offers Restore from a backup file',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Restore from a backup file'), findsOneWidget);
  });

  testWidgets(
      'R-03: corrupt vault WITH a usable backup offers both safety-copy and '
      'backup-file restore', (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Restore from safety copy'), findsOneWidget);
    expect(find.text('Restore from a backup file'), findsOneWidget);
  });

  testWidgets(
      'R-03: restore from file success clears the banner, restores the unlock '
      'controls, and confirms', (tester) async {
    var readable = false;
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => readable,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
      onRestoreFromPickedFile: (_, _) async => readable = true,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing,
        reason: 'controls hidden while corrupt');

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Vault restored. Unlock with your credentials.'),
        findsOneWidget);
    expect(find.byType(TextField), findsOneWidget,
        reason: 'unlock controls return after a successful restore');
    expect(find.text('Restore from a backup file'), findsNothing,
        reason: 'the corruption card is gone');
  });

  testWidgets(
      'R-03: restoring from an invalid file shows an error and stays corrupt',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
      onRestoreFromPickedFile: (_, _) async =>
          throw Exception('not a usable Gabbro vault — restore refused'),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('That file is not a usable Gabbro vault.'), findsOneWidget);
    expect(find.text('Restore from a backup file'), findsOneWidget,
        reason: 'an invalid restore leaves the vault in the corrupt state');
  });

  // When the file dialog can't open (sandbox/no portal), the restore-from-file
  // button must surface the portal message, NOT the misleading "invalid vault"
  // error, and the vault stays corrupt.
  testWidgets(
      'R-03: restore-from-file with an unavailable picker shows the portal '
      'message, not the invalid-vault error', (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: () async =>
          throw const FilePickerUnavailable(SocketException('no bus')),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();

    expect(
        find.text(
            "File dialog unavailable here. The system file portal isn't reachable."),
        findsOneWidget);
    expect(find.text('That file is not a usable Gabbro vault.'), findsNothing,
        reason: 'a portal failure is not an invalid-vault error');
    expect(find.text('Restore from a backup file'), findsOneWidget,
        reason: 'the vault stays corrupt');
  });

  testWidgets(
      'R-03: a corrupt vault hides the passphrase field and Unlock button '
      '(they are useless until restored)', (tester) async {
    await tester.pumpWidget(_buildScreen(
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Delete file'), findsOneWidget,
        reason: 'the corruption card must still show');
    expect(find.byType(TextField), findsNothing,
        reason: 'no passphrase field while the vault cannot be opened');
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsNothing,
        reason: 'no Unlock button while the vault cannot be opened');
  });

  testWidgets(
      'R-03 P5: State B on Android offers only Delete file (Remove-from-list '
      'would orphan an unreachable app-private file)', (tester) async {
    await tester.pumpWidget(_buildScreen(
      isAndroid: true,
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Delete file'), findsOneWidget);
    expect(find.text('Remove from list'), findsNothing);
  });

  testWidgets('R-03 P5: State B on desktop offers both actions',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      isAndroid: false,
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Remove from list'), findsOneWidget);
    expect(find.text('Delete file'), findsOneWidget);
  });

  testWidgets('R-03 P5: the unrecoverable note is platform-specific',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      isAndroid: true,
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining("app's private storage"), findsOneWidget);
    expect(find.textContaining('stays on disk'), findsNothing);

    await tester.pumpWidget(_buildScreen(
      isAndroid: false,
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('stays on disk'), findsOneWidget);
    expect(find.textContaining("app's private storage"), findsNothing);
  });

  //
  // Picking a `.gabbro` here is a repair for a vault that cannot be read, not a
  // way to add one: it replaces the bytes at the path already in the list.

  testWidgets('a healthy vault offers no restore-from-file', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Restore from a backup file'), findsNothing);
  });

  testWidgets('restore-from-file replaces the registered vault and adds no new one',
      (tester) async {
    final registry = VaultRegistry([
      _vaultRecord(path: '/tmp/only.gabbro', alias: 'Only'),
    ]);
    String? restoredOver;

    await tester.pumpWidget(_buildScreen(
      vaultPath: '/tmp/only.gabbro',
      registry: registry,
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
      onRestoreFromPickedFile: (path, _) async => restoredOver = path,
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(restoredOver, '/tmp/only.gabbro',
        reason: 'the picked file overwrites the vault already registered here');
    expect(registry.records.length, 1,
        reason: 'the picked file is never registered as a second vault');
  });

  //
  // One mis-pick here overwrites the vault AND refreshes its .bak, so this
  // dialog is the user's last chance to stop it. The Rust side keeps the old
  // vault as a .pre-restore safety copy; the dialog names both.

  /// Renders a corrupt vault and taps the restore-from-file button.
  Future<void> openRestoreFlow(
    WidgetTester tester, {
    required Future<String?> Function() onPickRestoreFile,
    required Future<void> Function(String, String) onRestoreFromPickedFile,
  }) async {
    await tester.pumpWidget(_buildScreen(
      vaultAlias: 'My vault',
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: onPickRestoreFile,
      onRestoreFromPickedFile: onRestoreFromPickedFile,
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();
  }

  testWidgets('F8: picking a file raises the confirm dialog before any write',
      (tester) async {
    var wrote = false;
    await openRestoreFlow(
      tester,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
      onRestoreFromPickedFile: (_, _) async => wrote = true,
    );

    expect(find.text('Replace this vault?'), findsOneWidget);
    expect(
      find.text("The picked file will replace 'My vault'. "
          'The old file is kept as a safety copy.'),
      findsOneWidget,
      reason: 'the dialog must name the vault being replaced and the safety copy',
    );
    expect(wrote, isFalse, reason: 'nothing may be written before Continue');
  });

  testWidgets('F9: Cancel writes nothing and leaves the corrupt state',
      (tester) async {
    var wrote = false;
    await openRestoreFlow(
      tester,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
      onRestoreFromPickedFile: (_, _) async => wrote = true,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(wrote, isFalse, reason: 'Cancel must reach no bridge call');
    expect(find.text('Restore from a backup file'), findsOneWidget,
        reason: 'the vault stays corrupt, the offer stays available');
    expect(find.textContaining('Vault restored'), findsNothing);
  });

  testWidgets('F10: Continue restores exactly as before the dialog existed',
      (tester) async {
    var wrote = false;
    await openRestoreFlow(
      tester,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
      onRestoreFromPickedFile: (_, _) async => wrote = true,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(wrote, isTrue);
    expect(find.text('Vault restored. Unlock with your credentials.'),
        findsOneWidget);
    expect(find.text('Restore from a backup file'), findsNothing,
        reason: 'the corruption card is gone after the restore');
  });

  testWidgets('F11: a cancelled picker shows no dialog and writes nothing',
      (tester) async {
    var wrote = false;
    await openRestoreFlow(
      tester,
      onPickRestoreFile: () async => null,
      onRestoreFromPickedFile: (_, _) async => wrote = true,
    );

    expect(find.text('Replace this vault?'), findsNothing,
        reason: 'no file was picked, so there is nothing to confirm');
    expect(wrote, isFalse);
    expect(find.text('Restore from a backup file'), findsOneWidget,
        reason: 'the vault stays corrupt');
  });

  // Biometric keeps the passphrase of whatever vault sat at this path;
  // restoring a different file would hand it a stale one with nothing to
  // explain the failure. A passphrase change unenrols for the same reason.

  /// Drives a corrupt vault through restore-from-file and reports whether the
  /// biometric enrolment was dropped.
  Future<bool> restoreAndReportUnenrol(
    WidgetTester tester, {
    required bool isAndroid,
    Future<String?> Function()? onPickRestoreFile,
    Future<void> Function(String, String)? onRestoreFromPickedFile,
  }) async {
    var disabled = false;
    await tester.pumpWidget(_buildScreen(
      isAndroid: isAndroid,
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: onPickRestoreFile ?? () async => '/tmp/backup.gabbro',
      onRestoreFromPickedFile: onRestoreFromPickedFile ?? (_, _) async {},
      onDisableBiometric: (_) async => disabled = true,
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();
    // A cancelled picker raises no dialog; everything else confirms through it.
    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    if (continueButton.evaluate().isNotEmpty) {
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
    }
    return disabled;
  }

  testWidgets('Android: a successful restore turns biometric unlock off',
      (tester) async {
    expect(
      await restoreAndReportUnenrol(tester, isAndroid: true),
      isTrue,
      reason: 'the stored passphrase belongs to the vault that was replaced',
    );
  });

  testWidgets('Linux: a successful restore touches no biometric enrolment',
      (tester) async {
    expect(
      await restoreAndReportUnenrol(tester, isAndroid: false),
      isFalse,
      reason: 'there is no biometric unlock off Android',
    );
  });

  testWidgets('a cancelled picker leaves biometric unlock alone',
      (tester) async {
    expect(
      await restoreAndReportUnenrol(tester,
          isAndroid: true, onPickRestoreFile: () async => null),
      isFalse,
      reason: 'nothing was replaced, so the stored passphrase still fits',
    );
  });

  testWidgets('a refused restore leaves biometric unlock alone', (tester) async {
    expect(
      await restoreAndReportUnenrol(tester,
          isAndroid: true,
          onRestoreFromPickedFile: (_, _) async =>
              throw Exception('not a vault')),
      isFalse,
      reason: 'a refused restore replaced nothing',
    );
  });

  /// Drives a corrupt vault through a successful restore-from-file, with
  /// biometric [enrolled] beforehand.
  Future<void> restoreWithBiometric(
    WidgetTester tester, {
    required bool enrolled,
  }) async {
    await tester.pumpWidget(_buildScreen(
      isAndroid: true,
      onBiometricIsEnrolled: (_) async => enrolled,
      onVaultIsReadable: (_) async => false,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
  }

  // On Android the file picker backgrounds the app, so the screen re-probes the
  // vault on the way back (didChangeAppLifecycleState). The restore's own
  // setState and that probe race, and the emulator run showed neither message
  // afterwards.
  testWidgets('the messages survive the resume the file picker causes',
      (tester) async {
    var readable = false;
    await tester.pumpWidget(_buildScreen(
      isAndroid: true,
      onBiometricIsEnrolled: (_) async => true,
      onVaultIsReadable: (_) async => readable,
      onBackupUsable: (_) async => false,
      onPickRestoreFile: () async => '/tmp/backup.gabbro',
      // the file on disk is a good vault again
      onRestoreFromPickedFile: (_, _) async => readable = true,
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    // The picker returning wakes the app before the restore's setState lands.
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.textContaining('Vault restored'), findsOneWidget);
    expect(
        find.textContaining('Biometric unlock was turned off'), findsOneWidget);
  });

  testWidgets('the user is told biometric unlock was turned off',
      (tester) async {
    await restoreWithBiometric(tester, enrolled: true);

    expect(
      find.textContaining('Biometric unlock was turned off'),
      findsOneWidget,
      reason: 'silently losing the fingerprint is what left the user stuck',
    );
  });

  testWidgets('no biometric notice for a user who never enabled it',
      (tester) async {
    await restoreWithBiometric(tester, enrolled: false);

    expect(find.textContaining('Biometric unlock was turned off'), findsNothing);
    expect(find.textContaining('Vault restored'), findsOneWidget);
  });

  // A new string is not done until the longest translation survives the largest
  // text on the narrowest phone. Testing scale and locale apart never meets that
  // case - the sync chooser overflowed in 32 of 37 languages while its English
  // check passed.
  testWidgets('the biometric notice survives every locale at 2x on a 360dp phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    for (final locale in AppLocalizations.supportedLocales) {
      // Tear the previous tree down first. Without this the UnlockScreen State
      // is reused across iterations, so the second locale opens on a screen
      // already restored - no corrupt block, no button, and nothing swept.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        // Production's delegate list, which ships fallbacks for nn and yo. The
        // shared _appShell uses the bare AppLocalizations list, whose missing
        // Material/Cupertino delegates warn for those two - a test-helper
        // artefact users never meet.
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(kPhoneMaxScale)),
          child: child!,
        ),
        home: UnlockScreen(
          vaultPath: '/tmp/test.gabbro',
          onEstimateEntropy: _fakeEntropy,
          yubikeyRecords: const [],
          isAndroid: true,
          onBiometricIsEnrolled: (_) async => true,
          onVaultIsReadable: (_) async => false,
          // Stubbed like _buildScreen does: left at their defaults these call
          // the real bridge, the probe never settles and the corrupt block -
          // which holds the restore button - never renders.
          onVaultFormatTooOld: (_) async => false,
          onVaultFormatTooNew: (_) async => false,
          onBackupUsable: (_) async => false,
          onPickRestoreFile: () async => '/tmp/backup.gabbro',
          onRestoreFromPickedFile: (_, _) async {},
          onDisableBiometric: (_) async {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: '$locale must render the corrupt screen cleanly at 2x');

      // Drive the restore, or the notice never renders and this sweep passes
      // without ever laying the new string out.
      final l = lookupAppLocalizations(locale);
      final restoreButton = find.text(l.restoreFromFileButton).first;
      await tester.ensureVisible(restoreButton);
      await tester.pumpAndSettle();
      // At large text the wrapped label can extend below the screen, putting
      // its centre (what tap aims at) off the bottom while the control is
      // reachable. Hit a point inside its visible part, as a finger would.
      final rect = tester.getRect(restoreButton);
      final y = (rect.top < 0 ? 0.0 : rect.top) + 20;
      await tester.tapAt(Offset(rect.center.dx, y));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the confirm dialog must render at 2x in $locale, '
              'never overflow');

      // F12: drive through the confirm dialog, same visible-part tap.
      final continueButton =
          find.widgetWithText(FilledButton, l.continueAction).first;
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      final cRect = tester.getRect(continueButton);
      final cy = (cRect.top < 0 ? 0.0 : cRect.top) + 10;
      await tester.tapAt(Offset(cRect.center.dx, cy));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the notice must scroll at 2x in $locale, never overflow');

      expect(
        find.text(l.vaultRestoredBiometricDisabled),
        findsOneWidget,
        reason: 'the notice must be on screen for $locale to mean anything',
      );
    }
  });
}
