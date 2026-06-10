import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

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

    // ── ADR-013: key-protected source sync ───────────────────────────────────

    YubikeyRecordData fakeRecord() => YubikeyRecordData(
          credentialId: Uint8List.fromList([1, 2]),
          salt: Uint8List.fromList([3, 4]),
        );

    File tempGabbroFile() {
      final f = File(
          '${Directory.systemTemp.path}/gabbro_kp_${DateTime.now().microsecondsSinceEpoch}.gabbro')
        ..writeAsStringSync('x');
      addTearDown(() {
        if (f.existsSync()) f.deleteSync();
      });
      return f;
    }

    testWidgets('key-protected source shows YubiKey PIN field and info note',
        (tester) async {
      final tmp = tempGabbroFile();
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
      )));
      await tester.ensureVisible(find.text('YubiKey PIN'));
      expect(find.text('YubiKey PIN'), findsOneWidget);
      expect(find.textContaining('protected by a YubiKey'), findsOneWidget);
    });

    testWidgets('passphrase-only source shows no YubiKey fields', (tester) async {
      final tmp = tempGabbroFile();
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [],
      )));
      await tester.ensureVisible(find.text('Sync from vault'));
      expect(find.text('YubiKey PIN'), findsNothing);
      expect(find.textContaining('protected by a YubiKey'), findsNothing);
    });

    testWidgets('key-protected source routes Sync to import-with-key',
        (tester) async {
      final tmp = tempGabbroFile();
      String? keyPath;
      List<int>? keyHmac;
      List<int>? keyCred;
      String? tapPin;
      var plainCalled = false;

      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        initialGabbroPath: tmp.path,
        onDetectSourceRecords: (_) => [fakeRecord()],
        onGetYubikeyHmac: (records, pin, transport) async {
          tapPin = pin;
          return (hmac: <int>[9, 9, 9], credentialId: <int>[1, 2]);
        },
        onImportGabbroWithKey: (path, pass, hmac, cred) async {
          keyPath = path;
          keyHmac = hmac;
          keyCred = cred;
          return GabbroImportResult(imported: BigInt.one, skipped: []);
        },
        onImportGabbro: (_, _) async {
          plainCalled = true;
          return GabbroImportResult(imported: BigInt.zero, skipped: []);
        },
      )));

      await tester.enterText(
          find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
      await tester.enterText(
          find.widgetWithText(TextField, 'YubiKey PIN'), '1234');
      await tester.ensureVisible(find.text('Sync from vault'));
      await tester.tap(find.text('Sync from vault'));
      await tester.pump();
      await tester.pump();

      expect(keyPath, tmp.path);
      expect(keyHmac, [9, 9, 9]);
      expect(keyCred, [1, 2]);
      expect(tapPin, '1234');
      expect(plainCalled, isFalse);
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