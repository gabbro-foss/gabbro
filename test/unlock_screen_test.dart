import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

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

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen({
  Future<void> Function(List<int>, String)? onUnlock,
  bool blockPassphraseCopyPaste = true,
  List<YubikeyRecordData>? yubikeyRecords,
  Future<void> Function(List<int>, List<int>, List<int>, String, String, String)?
      onUnlockWithYubikey,
  Future<void> Function(List<int>, List<YubikeyRecordData>, String, String, String)?
      onUnlockWithAnyYubikey,
}) =>
    MaterialApp(
      home: UnlockScreen(
        vaultPath: '/tmp/test.gabbro',
        onUnlock: onUnlock ?? (a, b) async {},
        onEstimateEntropy: _fakeEntropy,
        blockPassphraseCopyPaste: blockPassphraseCopyPaste,
        yubikeyRecords: yubikeyRecords ?? [],
        onUnlockWithYubikey: onUnlockWithYubikey ?? (a, b, c, d, e, f) async {},
        onUnlockWithAnyYubikey: onUnlockWithAnyYubikey ?? (a, b, c, d, e) async {},
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('unlock screen renders key elements', (tester) async {
    await tester.pumpWidget(_buildScreen());

    expect(find.text('Gabbro'), findsOneWidget);
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

  testWidgets('passphrase field blocks selection when blockPassphraseCopyPaste is true', (tester) async {
    await tester.pumpWidget(_buildScreen(blockPassphraseCopyPaste: true));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enableInteractiveSelection, isFalse);
  });

  testWidgets('passphrase field allows selection when blockPassphraseCopyPaste is false', (tester) async {
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

  // ── YubiKey mode ─────────────────────────────────────────────────────────────

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
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets('unlock screen is scrollable in landscape-like viewport (yubikey mode)', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(_buildScreen(yubikeyRecords: [_fakeRecord()]));
    await tester.pumpAndSettle();

    // Screen must wrap content in a SingleChildScrollView so the Unlock
    // button is reachable in landscape / short-height viewports.
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
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not unlock vault'), findsOneWidget);
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
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(anyCalled, isTrue);
    expect(singleCalled, isFalse);
  });
}
