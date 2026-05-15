import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';

// ── Fake entropy ──────────────────────────────────────────────────────────────

EntropyResult _fakeEntropy(String ignored) => EntropyResult(
      bits: 0,
      tier: StrengthTier.terrible,
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen({
  Future<void> Function(List<int>, String)? onUnlock,
  bool blockPassphraseCopyPaste = true,
}) =>
    MaterialApp(
      home: UnlockScreen(
        vaultPath: '/tmp/test.gabbro',
        onUnlock: onUnlock ?? (a, b) async {},
        onEstimateEntropy: _fakeEntropy,
        blockPassphraseCopyPaste: blockPassphraseCopyPaste,
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
}
