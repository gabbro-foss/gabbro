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

    testWidgets('shows error if export tapped with no path', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            onExport: (path) async {},
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(find.text('Select a destination.'), findsOneWidget);
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

    testWidgets('android mode: no folder icon, path pre-populated',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            isAndroid: true,
            initialPath: '/data/user/0/app.gabbro.gabbro/files/vault.gabbro',
            onExport: (path) async {},
          ),
        ),
      );
      expect(find.byIcon(Icons.folder_open), findsNothing);
      expect(
        find.text('/data/user/0/app.gabbro.gabbro/files/vault.gabbro'),
        findsWidgets,
      );
    });

    testWidgets('android mode: export fires with pre-populated path',
        (tester) async {
      String? exportedPath;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            isAndroid: true,
            initialPath: '/data/user/0/app.gabbro.gabbro/files/vault.gabbro',
            onExport: (path) async => exportedPath = path,
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(
        exportedPath,
        '/data/user/0/app.gabbro.gabbro/files/vault.gabbro',
      );
    });
  });
}