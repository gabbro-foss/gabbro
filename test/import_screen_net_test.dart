// Net for the import screen remold (Bikeshed step 2: one picker, not six).
// Pins the five non-Gabbro flows the existing suite covers only for "no file":
// gone file, size cap, success pops the count, failures dialog adds the edited
// count, generic failure text, spinner clears. The Gabbro flow is pinned in
// import_screen_test.dart. Only the two helpers below know the section layout.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/csv_mapping_screen.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';

import 'test_helpers.dart';

/// Picks [title] in the type dropdown.
Future<void> _selectType(WidgetTester tester, String title) async {
  final dd = find.byType(DropdownButton<ImportType>);
  await tester.ensureVisible(dd);
  await tester.tap(dd);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title).last);
  await tester.pumpAndSettle();
}

/// Selects the type, then types [path] into the one path field (the
/// PathField's onChanged is the same callback the native picker feeds).
Future<void> _setPath(WidgetTester tester, String title, String path) async {
  await _selectType(tester, title);
  final field = find.byType(TextFormField);
  await tester.ensureVisible(field);
  await tester.enterText(field, path);
  await tester.pump();
}

/// Taps the action button and lets the flow run. The importers read
/// the file with real I/O, which the test's fake clock never completes, so
/// real time runs briefly before settling.
Future<void> _tapAction(WidgetTester tester, String title,
    {bool settle = true}) async {
  final btn = find.byType(FilledButton);
  await tester.ensureVisible(btn);
  final onPressed = tester.widget<FilledButton>(btn).onPressed;
  expect(onPressed, isNotNull, reason: 'action button disabled');
  await tester.runAsync(() async {
    onPressed!();
    // Real-time beats WITH pumps inside one runAsync window: the IO completion
    // lands on the fake zone's microtask queue, which only a pump flushes.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  // A failures dialog keeps the spinner alive behind it, so no settle there.
  if (settle) await tester.pumpAndSettle();
}

File _tempFile(String ext, {int sparseLength = 0}) {
  final f = File(
      '${Directory.systemTemp.path}/gabbro_net_${DateTime.now().microsecondsSinceEpoch}.$ext');
  if (sparseLength > 0) {
    // A sparse file reports the length without writing the bytes.
    final raf = f.openSync(mode: FileMode.write);
    raf.setPositionSync(sparseLength - 1);
    raf.writeByteSync(0);
    raf.closeSync();
  } else {
    f.writeAsStringSync('{}');
  }
  addTearDown(() {
    if (f.existsSync()) f.deleteSync();
  });
  return f;
}

ImportResult _result(int imported, {List<ImportFailureData> failures = const []}) =>
    ImportResult(imported: BigInt.from(imported), failures: failures);

ImportFailureData _failure() => ImportFailureData(
      title: 'broken',
      category: 'login',
      reason: 'bad row',
      rawFields: const [],
    );

typedef _Importer = Future<ImportResult> Function(List<int>);

/// One row per JSON/CSV importer: section title, file extension, size cap,
/// and how to hand the screen a fake importer for that type.
class _Type {
  final String title;
  final String ext;
  final int cap;
  final ImportScreen Function(_Importer importer) build;
  const _Type(this.title, this.ext, this.cap, this.build);
}

final _types = [
  _Type('Enpass', 'json', kEnpassImportMaxBytes,
      (i) => ImportScreen(isAndroid: false, onImportEnpass: i)),
  _Type('Bitwarden', 'json', kTextImportMaxBytes,
      (i) => ImportScreen(isAndroid: false, onImportBitwarden: i)),
  _Type('Google Password Manager', 'csv', kTextImportMaxBytes,
      (i) => ImportScreen(isAndroid: false, onImportGooglePm: i)),
  _Type('Dashlane', 'csv', kTextImportMaxBytes,
      (i) => ImportScreen(isAndroid: false, onImportDashlane: i)),
];

/// Pushes [screen] from a button so the popped count can be read back.
Future<Future<int?> Function()> _pushScreen(
    WidgetTester tester, Widget screen) async {
  int? popped;
  var done = false;
  await tester.pumpWidget(testApp(Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        popped = await Navigator.of(context)
            .push<int>(MaterialPageRoute(builder: (_) => screen));
        done = true;
      },
      child: const Text('Open'),
    ),
  )));
  return () async {
    expect(done, isTrue, reason: 'screen did not pop');
    return popped;
  };
}

void main() {
  for (final t in _types) {
    group('${t.title} (net)', () {
      testWidgets('a file that is gone from disk is refused', (tester) async {
        var called = false;
        await tester.pumpWidget(testApp(t.build((_) async {
          called = true;
          return _result(0);
        })));
        await _setPath(tester, t.title, '/nonexistent/${t.title}.${t.ext}');
        await _tapAction(tester, t.title);
        expect(find.text('File not found.'), findsOneWidget);
        expect(called, isFalse);
      });

      testWidgets('a file over the size cap is refused', (tester) async {
        var called = false;
        final big = _tempFile(t.ext, sparseLength: t.cap + 1);
        await tester.pumpWidget(testApp(t.build((_) async {
          called = true;
          return _result(0);
        })));
        await _setPath(tester, t.title, big.path);
        await _tapAction(tester, t.title);
        expect(find.textContaining('exceeds the'), findsOneWidget);
        expect(find.textContaining(importLimitLabel(t.cap)), findsWidgets);
        expect(called, isFalse);
      });

      testWidgets('a successful import pops with the count', (tester) async {
        final f = _tempFile(t.ext);
        List<int>? seen;
        final read = await _pushScreen(
            tester,
            t.build((bytes) async {
              seen = bytes;
              return _result(4);
            }));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await _setPath(tester, t.title, f.path);
        await _tapAction(tester, t.title);
        expect(await read(), 4);
        expect(seen, f.readAsBytesSync());
      });

      testWidgets('failures raise the dialog; skipped ones add nothing',
          (tester) async {
        final f = _tempFile(t.ext);
        final read = await _pushScreen(
            tester,
            t.build((_) async =>
                _result(2, failures: [_failure(), _failure()])));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await _setPath(tester, t.title, f.path);
        await _tapAction(tester, t.title, settle: false);
        // One dialog per failure, each skipped. The spinner behind the dialog
        // never settles, so pump fixed frames and press via onPressed.
        // The import chain runs in the real-async zone (started under
        // runAsync), so each dialog's pop continuation needs a runAsync window
        // with real-time beats and pumps; the counter proves which dialog is up.
        for (var i = 1; i <= 2; i++) {
          expect(find.textContaining('$i of 2'), findsOneWidget);
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Skip'))
              .onPressed!();
          await tester.runAsync(() async {
            for (var f = 0; f < 5; f++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await tester.pump(const Duration(milliseconds: 100));
            }
          });
        }
        await tester.pumpAndSettle();
        expect(await read(), 2);
      });

      testWidgets('a failed import shows the error and re-arms the button',
          (tester) async {
        final f = _tempFile(t.ext);
        await tester.pumpWidget(
            testApp(t.build((_) async => throw Exception('boom'))));
        await _setPath(tester, t.title, f.path);
        await _tapAction(tester, t.title);
        expect(find.textContaining('Import failed:'), findsOneWidget);
        expect(find.textContaining('boom'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final btn = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(btn.onPressed, isNotNull);
      });
    });
  }

  group('Generic CSV (net)', () {
    const title = 'Generic CSV';
    CsvPreviewData preview() =>
        CsvPreviewData(headers: ['a', 'b'], rows: [['1', '2']]);

    testWidgets('a file that is gone from disk is refused', (tester) async {
      var called = false;
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        onSniffCsv: (_) {
          called = true;
          return preview();
        },
      )));
      await _setPath(tester, title, '/nonexistent/x.csv');
      await _tapAction(tester, title);
      expect(find.text('File not found.'), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('a file over the size cap is refused', (tester) async {
      var called = false;
      final big = _tempFile('csv', sparseLength: kTextImportMaxBytes + 1);
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        onSniffCsv: (_) {
          called = true;
          return preview();
        },
      )));
      await _setPath(tester, title, big.path);
      await _tapAction(tester, title);
      expect(find.textContaining('exceeds the'), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('Next sniffs the file and opens the mapping screen',
        (tester) async {
      final f = _tempFile('csv');
      f.writeAsStringSync('a,b\n1,2\n');
      String? sniffed;
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        onSniffCsv: (s) {
          sniffed = s;
          return preview();
        },
      )));
      await _setPath(tester, title, f.path);
      await _tapAction(tester, title);
      expect(sniffed, 'a,b\n1,2\n');
      expect(find.byType(CsvMappingScreen), findsOneWidget);
    });

    testWidgets('a sniff failure shows the error and re-arms the button',
        (tester) async {
      final f = _tempFile('csv');
      await tester.pumpWidget(testApp(ImportScreen(
        isAndroid: false,
        onSniffCsv: (_) => throw Exception('boom'),
      )));
      await _setPath(tester, title, f.path);
      await _tapAction(tester, title);
      expect(find.textContaining('Import failed:'), findsOneWidget);
      expect(find.byType(CsvMappingScreen), findsNothing);
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });
  });
}
