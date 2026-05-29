import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';

void main() {
  group('ImportScreen', () {
    Widget buildScreen() {
      return testApp(ImportScreen(
        onImportEnpass: (_) async => ImportResult(
          imported: BigInt.zero,
          failures: [],
          skipped: [],
        ),
        onImportBitwarden: (_) async => ImportResult(
          imported: BigInt.zero,
          failures: [],
          skipped: [],
        ),
        onSniffCsv: (_) => CsvPreviewData(headers: [], rows: []),
      ));
    }

    testWidgets('shows duplicate warning banner', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(
        find.textContaining('Entries whose UUID already exists'),
        findsOneWidget,
      );
    });

    testWidgets('skipped dialog shows entry title and reason', (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => showSkippedEntriesDialog(
            context,
            [
              SkippedEntryData(
                title: 'Dupe Entry',
                reason: 'UUID already exists',
              ),
            ],
          ),
          child: const Text('show'),
        ),
      )));
      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Dupe Entry'), findsOneWidget);
      expect(find.textContaining('UUID already exists'), findsOneWidget);
    });

    testWidgets('skipped dialog shows correct entry count in title',
        (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => showSkippedEntriesDialog(
            context,
            [
              SkippedEntryData(title: 'Entry A', reason: 'UUID already exists'),
              SkippedEntryData(title: 'Entry B', reason: 'UUID already exists'),
            ],
          ),
          child: const Text('show'),
        ),
      )));
      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('2 entries skipped'), findsOneWidget);
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