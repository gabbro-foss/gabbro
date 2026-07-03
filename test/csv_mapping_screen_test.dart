import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/csv_mapping_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'test_helpers.dart';

// ── Factories ─────────────────────────────────────────────────────────────────

CsvPreviewData _preview(List<String> headers) =>
    CsvPreviewData(headers: headers, rows: const []);

ImportResult _ok(int count) =>
    ImportResult(imported: BigInt.from(count), failures: [], skipped: []);

// ── Screen builder ────────────────────────────────────────────────────────────

Widget _buildScreen({
  required CsvPreviewData preview,
  String csvContent = 'csv',
  Future<ImportResult> Function(String, CsvImportConfigData)? onImport,
}) =>
    testApp(CsvMappingScreen(
      csvContent: csvContent,
      preview: preview,
      onImport: onImport ?? (_, _) async => _ok(0),
    ));

// Wraps the screen in a push so Navigator.pop(value) can be captured.
Widget _buildViaRoute({
  required CsvPreviewData preview,
  required Future<ImportResult> Function(String, CsvImportConfigData) onImport,
  required void Function(int?) onPopped,
  String csvContent = 'csv',
}) =>
    testApp(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<int>(
            MaterialPageRoute(
              builder: (_) => CsvMappingScreen(
                csvContent: csvContent,
                preview: preview,
                onImport: onImport,
              ),
            ),
          );
          onPopped(result);
        },
        child: const Text('Open'),
      ),
    ));

// Renders the screen at a chosen text scale (ADR-016 large-text checks).
Widget _buildScreenScaled({
  required CsvPreviewData preview,
  required double scale,
}) =>
    testApp(MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: CsvMappingScreen(
        csvContent: 'csv',
        preview: preview,
        onImport: (_, _) async => _ok(0),
      ),
    ));

DataTable _previewTable(WidgetTester tester) =>
    tester.widget<DataTable>(find.byType(DataTable));

Future<void> _tapImport(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(FilledButton));
  await tester.tap(find.byType(FilledButton));
}

void main() {
  // ── Large-text preview table (ADR-016) ────────────────────────────────────
  // On hardware the preview heading row ([name, url, username]) clipped
  // mid-height at tablet 5x (default 56px row); it must grow with the scale.

  testWidgets('preview heading row grows with the text scale', (tester) async {
    await tester.pumpWidget(_buildScreenScaled(
      preview: _preview(['Name', 'URL', 'Username']),
      scale: 3.0,
    ));
    final h = _previewTable(tester).headingRowHeight;
    expect(h, isNotNull);
    expect(h! > 56, isTrue);
  });

  testWidgets('preview heading row keeps the default at normal text scale',
      (tester) async {
    await tester.pumpWidget(_buildScreenScaled(
      preview: _preview(['Name', 'URL', 'Username']),
      scale: 1.0,
    ));
    expect(_previewTable(tester).headingRowHeight, isNull);
  });

  // ── Column auto-detection ─────────────────────────────────────────────────

  testWidgets('standard column names are all pre-selected on open',
      (tester) async {
    CsvImportConfigData? capturedConfig;
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['Title', 'URL', 'Username', 'Password', 'Notes']),
      onImport: (_, config) async {
        capturedConfig = config;
        return _ok(0);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(capturedConfig?.titleCol, 'Title');
    expect(capturedConfig?.urlCol, 'URL');
    expect(capturedConfig?.usernameCol, 'Username');
    expect(capturedConfig?.passwordCol, 'Password');
    expect(capturedConfig?.notesCol, 'Notes');
  });

  testWidgets('common alias names are matched by auto-detection', (tester) async {
    CsvImportConfigData? capturedConfig;
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['Name', 'Website', 'Login', 'Pass', 'Comments']),
      onImport: (_, config) async {
        capturedConfig = config;
        return _ok(0);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(capturedConfig?.titleCol, 'Name');
    expect(capturedConfig?.urlCol, 'Website');
    expect(capturedConfig?.usernameCol, 'Login');
    expect(capturedConfig?.passwordCol, 'Pass');
    expect(capturedConfig?.notesCol, 'Comments');
  });

  testWidgets('auto-detection is case-insensitive', (tester) async {
    CsvImportConfigData? capturedConfig;
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['TITLE', 'URL', 'USERNAME', 'PASSWORD', 'NOTES']),
      onImport: (_, config) async {
        capturedConfig = config;
        return _ok(0);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(capturedConfig?.titleCol, 'TITLE');
    expect(capturedConfig?.urlCol, 'URL');
    expect(capturedConfig?.usernameCol, 'USERNAME');
    expect(capturedConfig?.passwordCol, 'PASSWORD');
    expect(capturedConfig?.notesCol, 'NOTES');
  });

  testWidgets('auto-detection uses substring matching', (tester) async {
    CsvImportConfigData? capturedConfig;
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['entry_title', 'web_url', 'email_username']),
      onImport: (_, config) async {
        capturedConfig = config;
        return _ok(0);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(capturedConfig?.titleCol, 'entry_title');
    expect(capturedConfig?.urlCol, 'web_url');
    expect(capturedConfig?.usernameCol, 'email_username');
  });

  // ── Validation ────────────────────────────────────────────────────────────

  testWidgets('tapping Import with no recognisable columns shows error',
      (tester) async {
    bool importCalled = false;
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['ColA', 'ColB', 'ColC']),
      onImport: (_, _) async {
        importCalled = true;
        return _ok(0);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Map at least Title or URL'), findsOneWidget);
    expect(importCalled, isFalse);
  });

  testWidgets('import proceeds when only title column is mapped', (tester) async {
    bool importCalled = false;
    // Only 'Title' is recognisable; remaining columns produce no match.
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['Title', 'ColB']),
      onImport: (_, _) async {
        importCalled = true;
        return _ok(1);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Map at least Title or URL'), findsNothing);
    expect(importCalled, isTrue);
  });

  testWidgets('import proceeds when only url column is mapped', (tester) async {
    bool importCalled = false;
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['ColA', 'URL']),
      onImport: (_, _) async {
        importCalled = true;
        return _ok(1);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(importCalled, isTrue);
  });

  // ── Import flow ───────────────────────────────────────────────────────────

  testWidgets('successful import pops with the imported entry count',
      (tester) async {
    int? poppedWith;
    await tester.pumpWidget(_buildViaRoute(
      preview: _preview(['Title', 'URL']),
      onImport: (_, _) async => _ok(7),
      onPopped: (v) => poppedWith = v,
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(poppedWith, 7);
  });

  testWidgets('import error is displayed and screen stays open', (tester) async {
    bool popped = false;
    await tester.pumpWidget(_buildViaRoute(
      preview: _preview(['Title']),
      onImport: (_, _) async => throw Exception('vault is locked'),
      onPopped: (_) => popped = true,
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('vault is locked'), findsOneWidget);
    expect(popped, isFalse);
  });

  testWidgets('Import button is disabled while import is in progress',
      (tester) async {
    final completer = Completer<ImportResult>();
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['Title']),
      onImport: (_, _) => completer.future,
    ));

    await _tapImport(tester);
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull,
        reason: 'button must be disabled while import is running');

    // Complete the future so no pending async work leaks out of this test.
    completer.complete(_ok(0));
    await tester.pumpAndSettle();
  });

  testWidgets('Import button re-enables after an import error', (tester) async {
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['Title']),
      onImport: (_, _) async => throw Exception('disk full'),
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    // Screen stays open on error; button must be clickable again.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  // ── Config assembly ───────────────────────────────────────────────────────

  testWidgets('csvContent string is forwarded to onImport unchanged',
      (tester) async {
    String? capturedContent;
    await tester.pumpWidget(_buildScreen(
      preview: _preview(['Title']),
      csvContent: 'Title\nfoo',
      onImport: (content, _) async {
        capturedContent = content;
        return _ok(1);
      },
    ));

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(capturedContent, 'Title\nfoo');
  });
}
