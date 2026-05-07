import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';

void main() {
  group('ImportScreen', () {
    Widget buildScreen() {
      return MaterialApp(
        home: ImportScreen(
          onImportEnpass: (_) async => ImportResult(
            imported: BigInt.zero,
            failures: [],
          ),
          onImportBitwarden: (_) async => ImportResult(
            imported: BigInt.zero,
            failures: [],
          ),
          onSniffCsv: (_) => CsvPreviewData(headers: [], rows: []),
        ),
      );
    }

    testWidgets('shows duplicate warning banner', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(
        find.textContaining('duplicate entries may be created'),
        findsOneWidget,
      );
    });

    testWidgets('warning banner has warning icon', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows Gabbro vault section', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Gabbro vault'));
      expect(find.text('Gabbro vault'), findsOneWidget);
    });

    testWidgets('shows passphrase field in Gabbro section', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Vault passphrase'));
      expect(find.text('Vault passphrase'), findsOneWidget);
    });

    testWidgets('shows error when Gabbro import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Sync from vault'));
      await tester.tap(find.text('Sync from vault'));
      await tester.pump();
      expect(find.text('Select a file.'), findsOneWidget);
    });
  });
}