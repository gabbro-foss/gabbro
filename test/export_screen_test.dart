import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/export_screen.dart';

void main() {
  // ── sanitiseAlias unit tests ──────────────────────────────────────────────

  group('sanitiseAlias', () {
    test('replaces spaces with underscores', () {
      expect(sanitiseAlias('My Work'), 'My_Work');
    });

    test('strips non-alphanum except hyphen and underscore', () {
      expect(sanitiseAlias("Rob's Vault!"), 'Robs_Vault');
    });

    test('preserves hyphens and underscores', () {
      expect(sanitiseAlias('A-B_C'), 'A-B_C');
    });

    test('returns vault fallback for null', () {
      expect(sanitiseAlias(null), 'vault');
    });

    test('returns vault fallback for empty string', () {
      expect(sanitiseAlias(''), 'vault');
    });
  });

  group('ExportScreen', () {
    testWidgets('shows export button', (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('shows path field', (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('export button disabled with no path on linux', (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: false,
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      final exportBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export'),
      );
      expect(exportBtn.onPressed, isNull);
    });

    testWidgets('calls onExport with selected path when format is gabbro',
        (tester) async {
      String? exportedPath;
      await tester.pumpWidget(
        testApp(ExportScreen(
            initialPath: '/home/user/vault.gabbro',
            onExport: (path) async => exportedPath = path,
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, '/home/user/vault.gabbro');
    });

    testWidgets('android mode: shows Choose folder button, Export disabled',
        (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: true,
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      expect(find.text('Choose folder'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsNothing);
      // Export button exists but is disabled (no directory chosen yet)
      final exportBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export'),
      );
      expect(exportBtn.onPressed, isNull);
    });

    testWidgets('android mode: export fires with picked directory path',
        (tester) async {
      String? exportedPath;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: true,
            initialPath: '/storage/emulated/0/Documents',
            onExport: (path) async => exportedPath = path,
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, startsWith('/storage/emulated/0/Documents/vault_'));
      expect(exportedPath, endsWith('.gabbro'));
    });

    testWidgets('android mode: export path uses sanitised alias', (tester) async {
      String? exportedPath;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: true,
            initialPath: '/storage/emulated/0/Documents',
            vaultAlias: 'My Work',
            onExport: (path) async => exportedPath = path,
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, startsWith('/storage/emulated/0/Documents/My_Work_'));
      expect(exportedPath, endsWith('.gabbro'));
    });

    // ── Include date toggle ──────────────────────────────────────────────────

    testWidgets('include date toggle is ON by default', (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: true,
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isTrue);
    });

    testWidgets('android: toggle off omits date from exported path',
        (tester) async {
      String? exportedPath;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: true,
            initialPath: '/storage/emulated/0/Documents',
            vaultAlias: 'My Work',
            onExport: (path) async => exportedPath = path,
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, '/storage/emulated/0/Documents/My_Work.gabbro');
    });

    testWidgets('android: toggle on includes date in exported path',
        (tester) async {
      String? exportedPath;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: true,
            initialPath: '/storage/emulated/0/Documents',
            vaultAlias: 'My Work',
            onExport: (path) async => exportedPath = path,
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, startsWith('/storage/emulated/0/Documents/My_Work_'));
      expect(exportedPath, endsWith('.gabbro'));
    });

    // ── Format selector ──────────────────────────────────────────────────────

    testWidgets('shows format selector with Gabbro and JSON options',
        (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      expect(find.text('.gabbro'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
    });

    testWidgets('default format is gabbro - shows passphrase-only note',
        (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      expect(find.textContaining('passphrase only'), findsOneWidget);
    });

    testWidgets('selecting JSON format shows plaintext warning', (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.text('JSON'));
      await tester.pump();
      expect(find.textContaining('unencrypted'), findsOneWidget);
    });

    testWidgets('selecting JSON format calls onExportJson on android',
        (tester) async {
      String? jsonExportedPath;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: true,
            initialPath: '/storage/emulated/0/Documents',
            onExport: (path) async {},
            onExportJson: (path) async => jsonExportedPath = path,
        )),
      );
      await tester.tap(find.text('JSON'));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(jsonExportedPath, startsWith('/storage/emulated/0/Documents/vault_'));
      expect(jsonExportedPath, endsWith('.json'));
    });

    testWidgets('selecting JSON format calls onExportJson on linux',
        (tester) async {
      String? jsonExportedPath;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: false,
            initialPath: '/home/user/vault.json',
            onExport: (path) async {},
            onExportJson: (path) async => jsonExportedPath = path,
        )),
      );
      await tester.tap(find.text('JSON'));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(jsonExportedPath, '/home/user/vault.json');
    });

    // ── ADR-013: protection-preserving export + opt-in downgrade ─────────────

    const downgradeLabel = 'Export without YubiKey protection (passphrase only)';

    testWidgets('passphrase-only vault: no downgrade toggle, shows passphrase note',
        (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            isKeyProtected: false,
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      expect(find.text(downgradeLabel), findsNothing);
      expect(find.textContaining('passphrase only'), findsOneWidget);
    });

    testWidgets('key-protected vault: shows key-protected note and downgrade toggle (default OFF)',
        (tester) async {
      await tester.pumpWidget(
        testApp(ExportScreen(
            isKeyProtected: true,
            onExport: (path) async {},
            onExportJson: (path) async {},
        )),
      );
      expect(find.textContaining('keeps this protection'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, downgradeLabel),
      );
      expect(toggle.value, isFalse);
      // Warning only appears once the user opts in.
      expect(find.textContaining('no YubiKey needed'), findsNothing);
    });

    testWidgets('key-protected vault: toggle OFF routes to the preserving export',
        (tester) async {
      String? preservedPath;
      var downgraded = false;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: false,
            isKeyProtected: true,
            initialPath: '/home/user/vault.gabbro',
            onExport: (path) async => preservedPath = path,
            onExportPassphraseOnly: (path) async => downgraded = true,
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(preservedPath, '/home/user/vault.gabbro');
      expect(downgraded, isFalse);
    });

    testWidgets('key-protected vault: toggle ON shows warning and routes to passphrase-only export',
        (tester) async {
      String? downgradedPath;
      var preserved = false;
      await tester.pumpWidget(
        testApp(ExportScreen(
            isAndroid: false,
            isKeyProtected: true,
            initialPath: '/home/user/vault.gabbro',
            onExport: (path) async => preserved = true,
            onExportPassphraseOnly: (path) async => downgradedPath = path,
            onExportJson: (path) async {},
        )),
      );
      await tester.tap(find.widgetWithText(SwitchListTile, downgradeLabel));
      await tester.pump();
      // Opting in surfaces the downgrade warning.
      expect(find.textContaining('no YubiKey needed'), findsOneWidget);

      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(downgradedPath, '/home/user/vault.gabbro');
      expect(preserved, isFalse);
    });
  });
}
