import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/change_passphrase_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake entropy ──────────────────────────────────────────────────────────────

EntropyResult _fakeStrongEntropy(String ignored) => EntropyResult(
      bits: 100,
      tier: StrengthTier.veryStrong,
    );

EntropyResult _fakeFairEntropy(String ignored) =>
    EntropyResult(bits: 40, tier: StrengthTier.fair);

EntropyResult _fakeWeakEntropy(String ignored) =>
    EntropyResult(bits: 20, tier: StrengthTier.weak);

EntropyResult _fakeTerribleEntropy(String ignored) =>
    EntropyResult(bits: 5, tier: StrengthTier.terrible);

// ── Fake YubiKey record ───────────────────────────────────────────────────────

YubikeyRecordData _fakeRecord() => YubikeyRecordData(
      credentialId: Uint8List.fromList([1, 2, 3, 4]),
      salt: Uint8List(32),
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

ChangePassphraseScreen _screen({
  Future<void> Function(List<int>, List<int>)? onChangePassphrase,
  bool blockPassphraseCopyPaste = true,
  List<YubikeyRecordData>? yubikeyRecords,
  Future<void> Function(List<int>, List<int>, String, String)? onConfirmYubikey,
  Future<void> Function(List<YubikeyRecordData>, String, String)? onConfirmAnyYubikey,
  bool biometricEnabled = false,
  Future<void> Function()? onDisableBiometric,
  Future<bool> Function(String)? onBiometricIsEnrolled,
  EntropyResult Function(String)? onEstimateEntropy,
}) =>
    ChangePassphraseScreen(
      vaultPath: '/tmp/test.gabbro',
      onChangePassphrase: onChangePassphrase ?? (_, _) async {},
      onEstimateEntropy: onEstimateEntropy ?? _fakeStrongEntropy,
      blockPassphraseCopyPaste: blockPassphraseCopyPaste,
      yubikeyRecords: yubikeyRecords ?? [],
      onConfirmYubikey: onConfirmYubikey ?? (_, _, _, _) async {},
      onConfirmAnyYubikey: onConfirmAnyYubikey ?? (_, _, _) async {},
      biometricEnabled: biometricEnabled,
      onDisableBiometric: onDisableBiometric ?? () async {},
      onBiometricIsEnrolled: onBiometricIsEnrolled ?? (_) async => false,
    );

Widget _buildScreen({
  Future<void> Function(List<int>, List<int>)? onChangePassphrase,
  bool blockPassphraseCopyPaste = true,
  List<YubikeyRecordData>? yubikeyRecords,
  Future<void> Function(List<int>, List<int>, String, String)? onConfirmYubikey,
  Future<void> Function(List<YubikeyRecordData>, String, String)? onConfirmAnyYubikey,
  bool biometricEnabled = false,
  Future<void> Function()? onDisableBiometric,
  Future<bool> Function(String)? onBiometricIsEnrolled,
  EntropyResult Function(String)? onEstimateEntropy,
}) =>
    testApp(_screen(
      onChangePassphrase: onChangePassphrase,
      blockPassphraseCopyPaste: blockPassphraseCopyPaste,
      yubikeyRecords: yubikeyRecords,
      onConfirmYubikey: onConfirmYubikey,
      onConfirmAnyYubikey: onConfirmAnyYubikey,
      biometricEnabled: biometricEnabled,
      onDisableBiometric: onDisableBiometric,
      onBiometricIsEnrolled: onBiometricIsEnrolled,
      onEstimateEntropy: onEstimateEntropy,
    ));

// testApp uses home: (a root route) which the success path's Navigator.pop can't
// pop cleanly — and popping disposes the screen's Scaffold + its SnackBar. Push
// the screen above a host Scaffold so pop returns there and the ScaffoldMessenger
// SnackBar survives. Use for tests that exercise a successful change.
Future<void> _pumpPushed(WidgetTester tester, ChangePassphraseScreen screen) async {
  await tester.pumpWidget(testApp(const Scaffold(body: SizedBox.shrink())));
  Navigator.of(tester.element(find.byType(Scaffold)))
      .push(MaterialPageRoute<void>(builder: (_) => screen));
  await tester.pumpAndSettle();
}

const _newPass = 'correct horse battery staple one two three four';

// Fill the 3 (or 4, with YubiKey) fields and tap Change passphrase.
Future<void> _fillAndSubmit(WidgetTester tester, {String? yubikeyPin}) async {
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Current passphrase'), 'oldpass');
  await tester.pump();
  await tester.enterText(
      find.widgetWithText(TextFormField, 'New passphrase'), _newPass);
  await tester.pump();
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new passphrase'), _newPass);
  await tester.pump();
  if (yubikeyPin != null) {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'YubiKey PIN'), yubikeyPin);
    await tester.pump();
  }
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change passphrase'));
  await tester.tap(find.widgetWithText(FilledButton, 'Change passphrase'));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── ADR-016 reveal-eye: suffix-icon toggles grow with text but are capped ───
  group('reveal-eye toggles scale (capped) at large text', () {
    void setPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('all four suffix eyes scale up and stay capped at 1.4x',
        (tester) async {
      setPhone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
      await tester.pumpAndSettle();

      expect(revealEyeButtons(), findsNWidgets(4));
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

  // ── Enter-submit / focus chain ──────────────────────────────────────────────
  group('Enter-submit chain', () {
    bool focused(WidgetTester tester, String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .focusNode!
        .hasFocus;

    testWidgets('Enter on current advances to the new passphrase',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Current passphrase'), 'oldpass');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(focused(tester, 'New passphrase'), isTrue);
    });

    testWidgets('Enter on new advances to the confirm field', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.enterText(
          find.widgetWithText(TextFormField, 'New passphrase'), _newPass);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(focused(tester, 'Confirm new passphrase'), isTrue);
    });

    testWidgets('Enter on the YubiKey PIN advances to the current passphrase',
        (tester) async {
      await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'YubiKey PIN'), '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(focused(tester, 'Current passphrase'), isTrue);
    });

    testWidgets('meets labelled-tap-target guideline (passphrase + yubikey modes)',
        (tester) async {
      final handle = tester.ensureSemantics();
      for (final records in [<YubikeyRecordData>[], [_fakeRecord()]]) {
        await tester.pumpWidget(_buildScreen(yubikeyRecords: records));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      handle.dispose();
    });
  });

  testWidgets('change passphrase screen renders key elements', (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.text('Change passphrase'), findsWidgets);
    expect(find.byType(TextFormField), findsNWidgets(3));
  });

  // fields[0] = old passphrase, fields[1] = new passphrase, fields[2] = confirm
  // Old passphrase: interactive selection allowed (paste permitted — policy decision).
  // New + confirm: interactive selection blocked.
  // Copy blocking on old passphrase field is enforced via contextMenuBuilder
  // (paste-only menu) — verified manually on device, not via automated test.

  testWidgets('all fields block selection when blockPassphraseCopyPaste is true', (tester) async {
    await tester.pumpWidget(_buildScreen(blockPassphraseCopyPaste: true));

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].enableInteractiveSelection, isFalse); // old: blocked
    expect(fields[1].enableInteractiveSelection, isFalse); // new: blocked
    expect(fields[2].enableInteractiveSelection, isFalse); // confirm: blocked
  });

  testWidgets('all fields allow selection when blockPassphraseCopyPaste is false', (tester) async {
    await tester.pumpWidget(_buildScreen(blockPassphraseCopyPaste: false));

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].enableInteractiveSelection, isNot(isFalse));
    expect(fields[1].enableInteractiveSelection, isNot(isFalse));
    expect(fields[2].enableInteractiveSelection, isNot(isFalse));
  });

  // ── YubiKey mode ─────────────────────────────────────────────────────────────

  testWidgets('yubikey mode shows YubiKey info banner', (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));

    expect(find.byIcon(Icons.security), findsOneWidget);
    expect(find.textContaining('YubiKey'), findsWidgets);
  });

  testWidgets('passphrase-only mode does not show YubiKey banner', (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: []));

    expect(find.byIcon(Icons.security), findsNothing);
  });

  testWidgets('yubikey mode shows YubiKey PIN field', (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));

    expect(find.widgetWithText(TextFormField, 'YubiKey PIN'), findsOneWidget);
    expect(find.textContaining('Touch your YubiKey'), findsOneWidget);
  });

  testWidgets('single-key yubikey mode calls onConfirmYubikey before onChangePassphrase',
      (tester) async {
    bool confirmCalled = false;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord()],
      onConfirmYubikey: (_, _, _, _) async => confirmCalled = true,
      // Throw so the screen does not navigate away — we only need to check
      // that onConfirmYubikey was called first.
      onChangePassphrase: (_, _) async => throw Exception('stop'),
    ));

    const newPass = 'correct horse battery staple one two three four';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current passphrase'),
      'oldpass',
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New passphrase'),
      newPass,
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new passphrase'),
      newPass,
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'YubiKey PIN'),
      '123456',
    );
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change passphrase'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change passphrase'));
    await tester.pumpAndSettle();

    expect(confirmCalled, isTrue);
    expect(find.textContaining('stop'), findsOneWidget);
  });

  testWidgets('multi-key yubikey mode calls onConfirmAnyYubikey before onChangePassphrase',
      (tester) async {
    bool confirmAnyCalled = false;
    await tester.pumpWidget(_buildScreen(
      yubikeyRecords: [_fakeRecord(), _fakeRecord()],
      onConfirmAnyYubikey: (_, _, _) async => confirmAnyCalled = true,
      onChangePassphrase: (_, _) async => throw Exception('stop'),
    ));

    const newPass = 'correct horse battery staple one two three four';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current passphrase'),
      'oldpass',
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New passphrase'),
      newPass,
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new passphrase'),
      newPass,
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'YubiKey PIN'),
      '123456',
    );
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Change passphrase'));
    await tester.tap(find.widgetWithText(FilledButton, 'Change passphrase'));
    await tester.pumpAndSettle();

    expect(confirmAnyCalled, isTrue);
    expect(find.textContaining('stop'), findsOneWidget);
  });

  // ── Approach B: disable biometric on a successful passphrase change ───────────

  testWidgets(
      'N1: passphrase-only success with biometric off shows success, does not disable biometric',
      (tester) async {
    var disableCalled = false;
    await _pumpPushed(tester, _screen(
      onDisableBiometric: () async => disableCalled = true,
    ));
    await _fillAndSubmit(tester);

    expect(disableCalled, isFalse);
    expect(find.text('Passphrase changed successfully'), findsOneWidget);
  });

  testWidgets(
      'N2: YubiKey-mode success with biometric off shows success, does not disable biometric',
      (tester) async {
    var disableCalled = false;
    await _pumpPushed(tester, _screen(
      yubikeyRecords: [_fakeRecord()],
      onDisableBiometric: () async => disableCalled = true,
    ));
    await _fillAndSubmit(tester, yubikeyPin: '123456');

    expect(disableCalled, isFalse);
    expect(find.text('Passphrase changed successfully'), findsOneWidget);
  });

  testWidgets(
      'N3: a FAILED change never disables biometric (even when enabled)',
      (tester) async {
    var disableCalled = false;
    await tester.pumpWidget(_buildScreen(
      biometricEnabled: true,
      onBiometricIsEnrolled: (_) async => true,
      onChangePassphrase: (_, _) async => throw Exception('change failed'),
      onDisableBiometric: () async => disableCalled = true,
    ));
    await _fillAndSubmit(tester);

    expect(disableCalled, isFalse);
    expect(find.text('Passphrase changed successfully'), findsNothing);
  });

  testWidgets(
      'N4: biometric ON globally but NOT enrolled for this vault -> no disable, normal success',
      (tester) async {
    var disableCalled = false;
    await _pumpPushed(tester, _screen(
      biometricEnabled: true, // global flag on...
      onBiometricIsEnrolled: (_) async => false, // ...but this vault isn't enrolled
      onDisableBiometric: () async => disableCalled = true,
    ));
    await _fillAndSubmit(tester);

    expect(disableCalled, isFalse);
    expect(find.text('Passphrase changed successfully'), findsOneWidget);
    expect(
      find.text(
          'Passphrase changed. Biometric unlock was turned off; re-enable it in Settings.'),
      findsNothing,
    );
  });

  testWidgets(
      'R1: passphrase-only success with biometric ON disables biometric and informs the user',
      (tester) async {
    var disableCalled = false;
    await _pumpPushed(tester, _screen(
      biometricEnabled: true,
      onBiometricIsEnrolled: (_) async => true,
      onDisableBiometric: () async => disableCalled = true,
    ));
    await _fillAndSubmit(tester);

    expect(disableCalled, isTrue);
    expect(
      find.text(
          'Passphrase changed. Biometric unlock was turned off; re-enable it in Settings.'),
      findsOneWidget,
    );
  });

  // ── Strength gate: align with onboarding (Fair-and-above) ─────────────────────

  testWidgets('R5: a Fair passphrase is accepted (matches onboarding)',
      (tester) async {
    var changeCalled = false;
    await _pumpPushed(tester, _screen(
      onEstimateEntropy: _fakeFairEntropy,
      onChangePassphrase: (_, _) async => changeCalled = true,
    ));
    await _fillAndSubmit(tester);

    expect(changeCalled, isTrue);
    expect(find.text('Passphrase is too weak'), findsNothing);
  });

  testWidgets('N5: a Weak passphrase is blocked', (tester) async {
    var changeCalled = false;
    await tester.pumpWidget(_buildScreen(
      onEstimateEntropy: _fakeWeakEntropy,
      onChangePassphrase: (_, _) async => changeCalled = true,
    ));
    await _fillAndSubmit(tester);

    expect(changeCalled, isFalse);
  });

  testWidgets('N5b: a Terrible passphrase is blocked', (tester) async {
    var changeCalled = false;
    await tester.pumpWidget(_buildScreen(
      onEstimateEntropy: _fakeTerribleEntropy,
      onChangePassphrase: (_, _) async => changeCalled = true,
    ));
    await _fillAndSubmit(tester);

    expect(changeCalled, isFalse);
  });

  testWidgets('R6: a Weak passphrase shows an explicit too-weak line',
      (tester) async {
    await tester.pumpWidget(_buildScreen(onEstimateEntropy: _fakeWeakEntropy));
    await _fillAndSubmit(tester);

    expect(find.text('Passphrase is too weak'), findsOneWidget);
  });

  // ── Visibility toggles (net-first: pin current flip behaviour) ──────────────
  // Pins the show/hide eye toggles so the later a11y label work cannot regress
  // the flip. Passphrase-only mode has 3 toggles (old/new/confirm); YubiKey mode
  // adds a 4th (PIN).

  testWidgets('passphrase-only mode starts with three obscured fields and flips one',
      (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.byIcon(Icons.visibility_off), findsNWidgets(3));
    expect(find.byIcon(Icons.visibility), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));
  });

  testWidgets('yubikey mode adds a fourth (PIN) toggle that flips independently',
      (tester) async {
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));

    // old + new + confirm + PIN = 4 obscured fields.
    expect(find.byIcon(Icons.visibility_off), findsNWidgets(4));

    // PIN field is the first one rendered (above the passphrase fields).
    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNWidgets(3));
  });

  // A11y: every show/hide eye toggle must carry a semantic label so screen
  // readers announce it, not a bare "button".
  testWidgets('meets labelled-tap-target guideline (yubikey mode, all toggles)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
