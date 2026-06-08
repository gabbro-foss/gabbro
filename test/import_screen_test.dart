import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';

/// Scrolls to [sectionTitle], then taps the FilledButton in that section.
Future<void> _tapImportForSection(
    WidgetTester tester, String sectionTitle) async {
  await tester.scrollUntilVisible(
    find.text(sectionTitle),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  final col = find
      .ancestor(of: find.text(sectionTitle), matching: find.byType(Column))
      .first;
  final btn = find.descendant(of: col, matching: find.byType(FilledButton));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pump();
}

void main() {
  group('ImportScreen', () {
    Widget buildScreen({
      Future<ImportResult> Function(List<int>)? onImportEnpass,
      Future<ImportResult> Function(List<int>)? onImportBitwarden,
      Future<ImportResult> Function(List<int>)? onImportGooglePm,
      Future<ImportResult> Function(List<int>)? onImportDashlane,
      CsvPreviewData Function(String)? onSniffCsv,
    }) {
      return testApp(ImportScreen(
        onImportEnpass: onImportEnpass ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onImportBitwarden: onImportBitwarden ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onImportGooglePm: onImportGooglePm ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onImportDashlane: onImportDashlane ??
            (_) async => ImportResult(
                  imported: BigInt.zero,
                  failures: [],
                  skipped: [],
                ),
        onSniffCsv: onSniffCsv ?? (_) => CsvPreviewData(headers: [], rows: []),
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

    // ── No-file validation for each importer ─────────────────────────────────

    testWidgets('shows error when Enpass import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Enpass');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when Bitwarden import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Bitwarden');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when Google PM import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Google Password Manager');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when Dashlane import attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await _tapImportForSection(tester, 'Dashlane');
      expect(find.text('Select a file.'), findsWidgets);
    });

    testWidgets('shows error when CSV continue attempted with no file',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Generic CSV'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final col = find
          .ancestor(
              of: find.text('Generic CSV'), matching: find.byType(Column))
          .first;
      final btn = find.descendant(of: col, matching: find.byType(FilledButton));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      expect(find.text('Select a file.'), findsWidgets);
    });

    // ── Section visibility ────────────────────────────────────────────────────

    testWidgets('Enpass section is visible when scrolled to', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Enpass'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Enpass'), findsOneWidget);
    });

    testWidgets('Bitwarden section is visible when scrolled to',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Bitwarden'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Bitwarden'), findsOneWidget);
    });

    testWidgets('Google PM section is visible when scrolled to',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Google Password Manager'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Google Password Manager'), findsOneWidget);
    });

    testWidgets('Dashlane section is visible when scrolled to', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.scrollUntilVisible(
        find.text('Dashlane'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dashlane'), findsOneWidget);
    });

    // ── Passphrase field ─────────────────────────────────────────────────────

    testWidgets('passphrase field toggles visibility', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.ensureVisible(find.text('Vault passphrase'));

      // Initially obscured → visibility icon shown.
      final toggleBtn = find.byIcon(Icons.visibility);
      await tester.ensureVisible(toggleBtn);
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      // After toggle, passphrase visible → visibility_off icon shown.
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });
  });
}