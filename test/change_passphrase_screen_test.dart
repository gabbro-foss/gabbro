import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/change_passphrase_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake entropy ──────────────────────────────────────────────────────────────

EntropyResult _fakeStrongEntropy(String ignored) => EntropyResult(
      bits: 100,
      tier: StrengthTier.veryStrong,
    );

// ── Fake YubiKey record ───────────────────────────────────────────────────────

YubikeyRecordData _fakeRecord() => YubikeyRecordData(
      credentialId: Uint8List.fromList([1, 2, 3, 4]),
      salt: Uint8List(32),
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen({
  Future<void> Function(List<int>, List<int>)? onChangePassphrase,
  bool blockPassphraseCopyPaste = true,
  List<YubikeyRecordData>? yubikeyRecords,
  Future<void> Function(List<int>, List<int>, String, String)? onConfirmYubikey,
  Future<void> Function(List<YubikeyRecordData>, String, String)? onConfirmAnyYubikey,
}) =>
    MaterialApp(
      home: ChangePassphraseScreen(
        vaultPath: '/tmp/test.gabbro',
        onChangePassphrase: onChangePassphrase ?? (_, _) async {},
        onEstimateEntropy: _fakeStrongEntropy,
        blockPassphraseCopyPaste: blockPassphraseCopyPaste,
        yubikeyRecords: yubikeyRecords ?? [],
        onConfirmYubikey: onConfirmYubikey ?? (_, _, _, _) async {},
        onConfirmAnyYubikey: onConfirmAnyYubikey ?? (_, _, _) async {},
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
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
}
