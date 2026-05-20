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
}) =>
    MaterialApp(
      home: ChangePassphraseScreen(
        vaultPath: '/tmp/test.gabbro',
        onChangePassphrase: onChangePassphrase ?? (a, b) async {},
        onEstimateEntropy: _fakeStrongEntropy,
        blockPassphraseCopyPaste: blockPassphraseCopyPaste,
        yubikeyRecords: yubikeyRecords ?? [],
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
}
