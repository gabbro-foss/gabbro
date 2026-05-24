import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/export_screen.dart';

void main() {
  group('ExportScreen', () {
    testWidgets('shows export button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
          ),
        ),
      );
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('shows path field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
          ),
        ),
      );
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('export button disabled with no path on linux', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            isAndroid: false,
            onExport: (path) async {},
            onExportJson: (path) async {},
          ),
        ),
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
        MaterialApp(
          home: ExportScreen(
            initialPath: '/home/user/vault.gabbro',
            onExport: (path) async => exportedPath = path,
            onExportJson: (path) async {},
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, '/home/user/vault.gabbro');
    });

    testWidgets('android mode: shows Choose folder button, Export disabled',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            isAndroid: true,
            onExport: (path) async {},
            onExportJson: (path) async {},
          ),
        ),
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
        MaterialApp(
          home: ExportScreen(
            isAndroid: true,
            initialPath: '/storage/emulated/0/Documents',
            onExport: (path) async => exportedPath = path,
            onExportJson: (path) async {},
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, '/storage/emulated/0/Documents/vault.gabbro');
    });

    // ── Format selector ──────────────────────────────────────────────────────

    testWidgets('shows format selector with Gabbro and JSON options',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
          ),
        ),
      );
      expect(find.text('.gabbro'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
    });

    testWidgets('default format is gabbro — shows passphrase-only note',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
          ),
        ),
      );
      expect(find.textContaining('passphrase only'), findsOneWidget);
    });

    testWidgets('selecting JSON format shows plaintext warning', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            onExport: (path) async {},
            onExportJson: (path) async {},
          ),
        ),
      );
      await tester.tap(find.text('JSON'));
      await tester.pump();
      expect(find.textContaining('unencrypted'), findsOneWidget);
    });

    testWidgets('selecting JSON format calls onExportJson on android',
        (tester) async {
      String? jsonExportedPath;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            isAndroid: true,
            initialPath: '/storage/emulated/0/Documents',
            onExport: (path) async {},
            onExportJson: (path) async => jsonExportedPath = path,
          ),
        ),
      );
      await tester.tap(find.text('JSON'));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(jsonExportedPath, '/storage/emulated/0/Documents/vault.json');
    });

    testWidgets('selecting JSON format calls onExportJson on linux',
        (tester) async {
      String? jsonExportedPath;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            isAndroid: false,
            initialPath: '/home/user/vault.json',
            onExport: (path) async {},
            onExportJson: (path) async => jsonExportedPath = path,
          ),
        ),
      );
      await tester.tap(find.text('JSON'));
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(jsonExportedPath, '/home/user/vault.json');
    });
  });
}
