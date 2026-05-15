import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/change_passphrase_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';

// ── Fake entropy ──────────────────────────────────────────────────────────────

EntropyResult _fakeStrongEntropy(String ignored) => EntropyResult(
      bits: 100,
      tier: StrengthTier.veryStrong,
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen({
  Future<void> Function(List<int>, List<int>)? onChangePassphrase,
  bool blockPassphraseCopyPaste = true,
}) =>
    MaterialApp(
      home: ChangePassphraseScreen(
        onChangePassphrase: onChangePassphrase ?? (a, b) async {},
        onEstimateEntropy: _fakeStrongEntropy,
        blockPassphraseCopyPaste: blockPassphraseCopyPaste,
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
}