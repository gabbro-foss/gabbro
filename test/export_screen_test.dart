import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/export_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// A fake SAF write capture, shared by the Android .gabbro export tests.
class _SafCapture {
  String? treeUri;
  String? filename;
  Uint8List? data;
  String? sha256Filename;
  String? sha256Content;
}

/// Builds an ExportScreen wired for Android `.gabbro` SAF export with a
/// pre-remembered folder, capturing what the SAF write seam receives.
Widget _androidGabbroScreen(
  _SafCapture cap, {
  String? vaultAlias,
  bool isKeyProtected = false,
  ExportArtifact? preservingArtifact,
  ExportArtifact? downgradeArtifact,
}) {
  final preserving = preservingArtifact ??
      ExportArtifact(vaultBytes: Uint8List.fromList([1, 2, 3]), sha256Line: 'AA  x\n');
  final downgrade = downgradeArtifact ??
      ExportArtifact(vaultBytes: Uint8List.fromList([9, 9]), sha256Line: 'BB  x\n');
  return testApp(ExportScreen(
    isAndroid: true,
    vaultAlias: vaultAlias,
    isKeyProtected: isKeyProtected,
    initialExportFolderUri: 'content://docs/tree/primary%3ADownload%2FGabbroSync',
    onHasGrant: (_) async => true,
    onExport: (path) async {},
    onExportJson: (path) async {},
    onBuildExportBytes: (filename) async => preserving,
    onBuildExportPassphraseOnlyBytes: (filename) async => downgrade,
    onWriteExport: (treeUri, filename, data, shaName, shaContent) async {
      cap.treeUri = treeUri;
      cap.filename = filename;
      cap.data = data;
      cap.sha256Filename = shaName;
      cap.sha256Content = shaContent;
    },
  ));
}

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

    testWidgets('android .gabbro: SAF write receives bytes + sha companion',
        (tester) async {
      final cap = _SafCapture();
      await tester.pumpWidget(_androidGabbroScreen(cap, vaultAlias: 'My Work'));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      // Date toggle is ON by default, so a dated filename is expected here.
      expect(cap.treeUri, 'content://docs/tree/primary%3ADownload%2FGabbroSync');
      expect(cap.filename, startsWith('My_Work_'));
      expect(cap.filename, endsWith('.gabbro'));
      expect(cap.sha256Filename, '${cap.filename}.sha256');
      expect(cap.data, equals(Uint8List.fromList([1, 2, 3])));
      expect(cap.sha256Content, 'AA  x\n');
    });

    testWidgets('android .gabbro: filename uses sanitised alias', (tester) async {
      final cap = _SafCapture();
      await tester.pumpWidget(_androidGabbroScreen(cap, vaultAlias: "Rob's Vault!"));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(cap.filename, startsWith('Robs_Vault_'));
      expect(cap.filename, endsWith('.gabbro'));
    });

    testWidgets('android .gabbro: no remembered folder -> Export disabled, no write',
        (tester) async {
      final cap = _SafCapture();
      await tester.pumpWidget(testApp(ExportScreen(
        isAndroid: true,
        onExport: (path) async {},
        onExportJson: (path) async {},
        onWriteExport: (a, b, c, d, e) async => cap.filename = b,
      )));
      await tester.pumpAndSettle();
      final exportBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export'),
      );
      expect(exportBtn.onPressed, isNull);
      expect(cap.filename, isNull);
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

    testWidgets('android .gabbro: date toggle off -> static filename (rsync target)',
        (tester) async {
      final cap = _SafCapture();
      await tester.pumpWidget(_androidGabbroScreen(cap, vaultAlias: 'My Work'));
      // Turn the include-date toggle off — there is exactly one SwitchListTile
      // for a passphrase-only vault (no downgrade toggle).
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(cap.filename, 'My_Work.gabbro');
      expect(cap.sha256Filename, 'My_Work.gabbro.sha256');
    });

    testWidgets('android .gabbro: date toggle on -> dated filename',
        (tester) async {
      final cap = _SafCapture();
      await tester.pumpWidget(_androidGabbroScreen(cap, vaultAlias: 'My Work'));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(cap.filename, startsWith('My_Work_'));
      expect(cap.filename, endsWith('.gabbro'));
    });

    testWidgets('android .gabbro: downgrade toggle routes to passphrase-only build',
        (tester) async {
      final cap = _SafCapture();
      await tester.pumpWidget(_androidGabbroScreen(
        cap,
        vaultAlias: 'My Work',
        isKeyProtected: true,
        downgradeArtifact: ExportArtifact(
          vaultBytes: Uint8List.fromList([7, 7, 7]),
          sha256Line: 'DD  x\n',
        ),
      ));
      // Opt in to the downgrade, then export.
      await tester.tap(find.widgetWithText(
          SwitchListTile, 'Export without YubiKey protection (passphrase only)'));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(cap.data, equals(Uint8List.fromList([7, 7, 7])));
      expect(cap.sha256Content, 'DD  x\n');
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
