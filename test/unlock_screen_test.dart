import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/unlock_screen.dart';
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
  bool blockPassphraseCopyPaste = true,
  List<YubikeyRecordData>? yubikeyRecords,
  Future<void> Function(List<int>, List<int>, List<int>, String, String, String)?
      onUnlockWithYubikey,
  Future<void> Function(List<int>, List<YubikeyRecordData>, String, String, String)?
      onUnlockWithAnyYubikey,
  String? vaultAlias,
  VaultRegistry? registry,
  bool showVaultList = false,
  void Function(String path, String alias)? onVaultSwitch,
  bool biometricEnabled = false,
  Future<bool> Function(String)? onBiometricIsEnrolled,
  Future<List<int>?> Function(String)? onBiometricAuthenticate,
  void Function()? onBiometricInvalidated,
}) =>
    testApp(UnlockScreen(
      vaultPath: vaultPath,
      onUnlock: onUnlock ?? (a, b) async {},
      onEstimateEntropy: _fakeEntropy,
      blockPassphraseCopyPaste: blockPassphraseCopyPaste,
      yubikeyRecords: yubikeyRecords ?? [],
      onUnlockWithYubikey: onUnlockWithYubikey ?? (a, b, c, d, e, f) async {},
      onUnlockWithAnyYubikey: onUnlockWithAnyYubikey ?? (a, b, c, d, e) async {},
      vaultAlias: vaultAlias,
      registry: registry,
      showVaultList: showVaultList,
      onVaultSwitch: onVaultSwitch,
      biometricEnabled: biometricEnabled,
      onBiometricIsEnrolled: onBiometricIsEnrolled ?? (_) async => false,
      onBiometricAuthenticate: onBiometricAuthenticate ?? (_) async => null,
      onBiometricInvalidated: onBiometricInvalidated,
    ));

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

  // ── Vault dropdown (showVaultList=true) ───────────────────────────────────

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

    testWidgets('shows dropdown when showVaultList=true and registry has 2+ vaults',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        showVaultList: true,
        registry: twoVaultRegistry,
      ));
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('no dropdown when showVaultList=false', (tester) async {
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        showVaultList: false,
        registry: twoVaultRegistry,
      ));
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('no dropdown when registry has only one vault', (tester) async {
      final singleRegistry = VaultRegistry([
        _vaultRecord(path: '/tmp/a.gabbro', alias: 'Alpha'),
      ]);
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        showVaultList: true,
        registry: singleRegistry,
      ));
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('no dropdown when registry is null', (tester) async {
      await tester.pumpWidget(_buildScreen(showVaultList: true, registry: null));
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('dropdown shows all vault aliases', (tester) async {
      await tester.pumpWidget(_buildScreen(
        vaultPath: '/tmp/a.gabbro',
        vaultAlias: 'Alpha',
        showVaultList: true,
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
        showVaultList: true,
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
}
