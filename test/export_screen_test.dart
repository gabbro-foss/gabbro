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
          ),
        ),
      );
      final exportBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export'),
      );
      expect(exportBtn.onPressed, isNull);
    });

    testWidgets('calls onExport with selected path', (tester) async {
      String? exportedPath;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            initialPath: '/home/user/vault.gabbro',
            onExport: (path) async => exportedPath = path,
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
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(exportedPath, '/storage/emulated/0/Documents/vault.gabbro');
    });
  });
}