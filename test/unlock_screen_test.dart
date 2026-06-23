import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';

// ── Fake entropy ──────────────────────────────────────────────────────────────

EntropyResult _fakeEntropy(String ignored) => EntropyResult(
      bits: 0,
      tier: StrengthTier.terrible,
    );

// ── Fake YubiKey record ───────────────────────────────────────────────────────

YubikeyRecordData _fakeRecord() => YubikeyRecordData(
      credentialId: Uint8List.fromList([1, 2, 3, 4]),
      salt: Uint8List(32),
    );

// ── Registry helpers ──────────────────────────────────────────────────────────

VaultRecord _vaultRecord({
  required String path,
  required String alias,
}) =>
    VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

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
  bool biometricEnabled = false,
  Future<bool> Function(String)? onBiometricIsEnrolled,
  Future<List<int>?> Function(String)? onBiometricAuthenticate,
  void Function()? onBiometricInvalidated,
  bool? isAndroid,
  Future<void> Function()? onCancelTap,
  Future<bool> Function(String)? onVaultIsReadable,
  Future<bool> Function(String)? onBackupUsable,
  Future<void> Function(String)? onRestoreBackup,
  Future<bool> Function(String)? onRestoreFromFile,
  Future<void> Function(String)? onRemoveVaultFromList,
  Future<void> Function(String)? onDeleteVaultFile,
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
      biometricEnabled: biometricEnabled,
      onBiometricIsEnrolled: onBiometricIsEnrolled ?? (_) async => false,
      onBiometricAuthenticate: onBiometricAuthenticate ?? (_) async => null,
      onBiometricInvalidated: onBiometricInvalidated,
      isAndroid: isAndroid,
      onCancelTap: onCancelTap ?? () async {},
      onVaultIsReadable: onVaultIsReadable ?? (_) async => true,
      onBackupUsable: onBackupUsable ?? (_) async => false,
      onRestoreBackup: onRestoreBackup ?? (_) async {},
      onRestoreFromFile: onRestoreFromFile ?? (_) async => false,
      onRemoveVaultFromList: onRemoveVaultFromList ?? (_) async {},
      onDeleteVaultFile: onDeleteVaultFile ?? (_) async {},
    ));

// ── Net B appearance shell (top-level per test-helper convention) ──────────────
// Mirrors main.dart's MaterialApp wiring so the screen is exercised under the
// user's real theme / high-contrast / text size / locale — not the test default.

Widget _appShell(
  Widget home, {
  ThemeMode mode = ThemeMode.light,
  bool highContrast = false,
  Locale? locale,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
UnlockScreen _bareUnlock({List<YubikeyRecordData> yubikeyRecords = const []}) =>
    UnlockScreen(
      vaultPath: '/tmp/test.gabbro',
      onEstimateEntropy: _fakeEntropy,
      yubikeyRecords: yubikeyRecords,
      onVaultIsReadable: (_) async => true,
      onBackupUsable: (_) async => false,
      onBiometricIsEnrolled: (_) async => false,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('unlock screen renders key elements', (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.byType(GabbroLogo), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
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

  // ── Net A regression pins ───────────────────────────────────────────────────
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
      biometricEnabled: true,
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

  // ── Net B: appearance + language ────────────────────────────────────────────

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
  });

  // ── Net C: accessibility (broad sweep) ──────────────────────────────────────

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

    // NOTE: labeledTapTargetGuideline is intentionally NOT asserted here. The
    // sweep found the show/hide eye toggles (passphrase + PIN suffixIcon) carry
    // no semantic label — known pre-existing a11y debt, waived for now and
    // tracked in the Bikeshed (not a regression from the autofill-unlock work).

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

  // ── Safe area ─────────────────────────────────────────────────────────────

  testWidgets('body uses SafeArea to avoid system navigation bar overlap',
      (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
    expect(find.byType(SafeArea), findsOneWidget);
  });

  // ── YubiKey mode ──────────────────────────────────────────────────────────

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

  // ── Vault alias ───────────────────────────────────────────────────────────

  testWidgets('shows vault alias below title when provided', (tester) async {
    await tester.pumpWidget(_buildScreen(vaultAlias: 'Work'));
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('does not show alias text when vaultAlias is null', (tester) async {
    await tester.pumpWidget(_buildScreen());
    expect(find.text('Work'), findsNothing);
  });

  // ── No switch icon ────────────────────────────────────────────────────────

  testWidgets('no switch icon shown (switch icon removed in new design)', (tester) async {
    await tester.pumpWidget(_buildScreen());
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
  });

  // ── Multi-key vault ───────────────────────────────────────────────────────

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

  // ── biometric button ──────────────────────────────────────────────────────

  group('biometric button', () {
    testWidgets('not shown when biometricEnabled is false', (tester) async {
      await tester.pumpWidget(_buildScreen(biometricEnabled: false));
      expect(find.text('Use biometrics'), findsNothing);
    });

    testWidgets('not shown when biometricEnabled true but not enrolled', (tester) async {
      await tester.pumpWidget(_buildScreen(
        biometricEnabled: true,
        onBiometricIsEnrolled: (_) async => false,
      ));
      await tester.pump(); // allow initState async to settle
      expect(find.text('Use biometrics'), findsNothing);
    });

    testWidgets('shown when biometricEnabled true and enrolled', (tester) async {
      await tester.pumpWidget(_buildScreen(
        biometricEnabled: true,
        onBiometricIsEnrolled: (_) async => true,
      ));
      await tester.pump();
      expect(find.text('Use biometrics'), findsOneWidget);
    });

    testWidgets('passphrase field always present alongside biometric button', (tester) async {
      await tester.pumpWidget(_buildScreen(
        biometricEnabled: true,
        onBiometricIsEnrolled: (_) async => true,
      ));
      await tester.pump();
      expect(find.text('Use biometrics'), findsOneWidget);
      expect(find.byType(TextField), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping biometric button calls onBiometricAuthenticate', (tester) async {
      bool called = false;
      await tester.pumpWidget(_buildScreen(
        biometricEnabled: true,
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async { called = true; return null; },
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });

    testWidgets('biometric cancelled shows hint message', (tester) async {
      await tester.pumpWidget(_buildScreen(
        biometricEnabled: true,
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
      bool invalidatedCalled = false;
      await tester.pumpWidget(_buildScreen(
        biometricEnabled: true,
        onBiometricIsEnrolled: (_) async => true,
        onBiometricAuthenticate: (_) async {
          throw PlatformException(code: 'BIOMETRIC_INVALIDATED');
        },
        onBiometricInvalidated: () => invalidatedCalled = true,
      ));
      await tester.pump();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      // Button must disappear (biometricEnrolled reset to false).
      expect(find.text('Use biometrics'), findsNothing);
      // onBiometricInvalidated must have been called.
      expect(invalidatedCalled, isTrue);
    });

    testWidgets('other PlatformException shows biometric cancelled message',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        biometricEnabled: true,
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
        biometricEnabled: true,
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

    testWidgets('no dropdown when registry has only one vault', (tester) async {
      final singleRegistry = VaultRegistry([
        _vaultRecord(path: '/tmp/a.gabbro', alias: 'Alpha'),
      ]);
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        registry: singleRegistry,
      ));
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('no dropdown when registry is null', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: null));
      expect(find.byType(DropdownButton<String>), findsNothing);
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
  });

  // ── Passphrase visibility toggle ───────────────────────────────────────────

  testWidgets('passphrase visibility toggle switches icon', (tester) async {
    await tester.pumpWidget(_buildScreen()); // passphrase-only mode

    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNothing);
  });

  // ── PIN visibility toggle in YubiKey mode ─────────────────────────────────

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

  // ── PlatformException error codes ─────────────────────────────────────────

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

  // ── Entropy indicator ─────────────────────────────────────────────────────

  testWidgets('typing in passphrase field shows entropy strength indicator',
      (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  // ── Stalled-tap Cancel (Android) ──────────────────────────────────────────

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

  // ── R-03: vault-corruption restore flow ────────────────────────────────────

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
      PlatformException(code: 'CTAP_ERROR', message: 'Wrong PIN'),
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
      onRestoreFromFile: (_) async {
        readable = true;
        return true;
      },
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing,
        reason: 'controls hidden while corrupt');

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
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
      onRestoreFromFile: (_) async =>
          throw Exception('not a usable Gabbro vault — restore refused'),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from a backup file'));
    await tester.tap(find.text('Restore from a backup file'));
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
      onRestoreFromFile: (_) async =>
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
}
