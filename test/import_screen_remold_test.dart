// Red for the import screen remold (Bikeshed step 2): one path field and a
// type dropdown replace six stacked sections. R1-R8, R11, R12 of the approved
// list; R9 lives in the re-targeted suites, R10 in l10n_test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart' show gabbroLocalizationsDelegates;
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/widgets/path_field.dart';

import 'test_helpers.dart';

const _types = [
  'Gabbro vault',
  'Generic CSV',
  'Google Password Manager',
  'Dashlane',
  'Enpass',
  'Bitwarden',
];

const _subtitle = {
  'Gabbro vault': 'Import entries from a different Gabbro vault',
  'Generic CSV': 'CSV export from any password manager',
  'Google Password Manager': 'CSV export from Google Password Manager',
  'Dashlane': 'CSV export from Dashlane',
  'Enpass': 'JSON export from Enpass',
  'Bitwarden': 'Unencrypted JSON export from Bitwarden',
};

const _filter = {
  'Gabbro vault': 'gabbro',
  'Generic CSV': 'csv',
  'Google Password Manager': 'csv',
  'Dashlane': 'csv',
  'Enpass': 'json',
  'Bitwarden': 'json',
};

Finder _dropdown() => find.byType(DropdownButton<ImportType>);

/// Opens the type dropdown and picks [title].
Future<void> _selectType(WidgetTester tester, String title) async {
  await tester.ensureVisible(_dropdown());
  await tester.tap(_dropdown());
  await tester.pumpAndSettle();
  await tester.tap(find.text(title).last);
  await tester.pumpAndSettle();
}

Widget _screen() => testApp(ImportScreen(isAndroid: false));

void main() {
  testWidgets('R1 one path field, never six', (tester) async {
    await tester.pumpWidget(_screen());
    expect(find.byType(PathField), findsOneWidget);
    for (final t in _types) {
      await _selectType(tester, t);
      expect(find.byType(PathField), findsOneWidget, reason: t);
    }
  });

  testWidgets('R2 the type dropdown lists six types, Gabbro vault first',
      (tester) async {
    await tester.pumpWidget(_screen());
    final dd = tester.widget<DropdownButton<ImportType>>(_dropdown());
    expect(dd.items, hasLength(6));
    expect(dd.value, ImportType.gabbro);
    expect(find.text('Gabbro vault'), findsOneWidget);
    // Labelled like every other field on the screen.
    expect(find.text('Source'), findsOneWidget);
  });

  testWidgets('R3 the banner and the size note stay for every type',
      (tester) async {
    await tester.pumpWidget(_screen());
    for (final t in _types) {
      await _selectType(tester, t);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget,
          reason: t);
      expect(find.textContaining('Maximum file size'), findsOneWidget,
          reason: t);
    }
  });

  testWidgets('R4 each type shows its own explanation only', (tester) async {
    await tester.pumpWidget(_screen());
    for (final t in _types) {
      await _selectType(tester, t);
      for (final other in _types) {
        expect(find.textContaining(_subtitle[other]!),
            other == t ? findsOneWidget : findsNothing,
            reason: '$t shows ${other == t ? '' : 'no '}$other text');
      }
    }
  });

  testWidgets('R5 the action label follows the type', (tester) async {
    await tester.pumpWidget(_screen());
    for (final t in _types) {
      await _selectType(tester, t);
      expect(find.byType(FilledButton), findsOneWidget, reason: t);
      final label = t == 'Generic CSV' ? 'Next: map columns' : 'Import';
      expect(find.widgetWithText(FilledButton, label), findsOneWidget,
          reason: t);
    }
  });

  testWidgets('R6 the file filter follows the type', (tester) async {
    await tester.pumpWidget(_screen());
    for (final t in _types) {
      await _selectType(tester, t);
      final pf = tester.widget<PathField>(find.byType(PathField));
      expect(pf.mode, PathFieldMode.open, reason: t);
      expect(pf.allowedExtensions, [_filter[t]], reason: t);
    }
  });

  testWidgets('R7 changing the type clears the path and the error',
      (tester) async {
    await tester.pumpWidget(_screen());
    await _selectType(tester, 'Enpass');
    await tester.enterText(find.byType(TextFormField), '/nonexistent/a.json');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('File not found.'), findsOneWidget);

    await _selectType(tester, 'Bitwarden');
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller
        ?.text, isEmpty);
    expect(find.text('File not found.'), findsNothing);
    // A stale .json path must not arm Bitwarden on Enpass's file: the
    // cleared path is refused before any import.
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Select a file.'), findsOneWidget);
  });

  testWidgets('R8 the passphrase field exists for Gabbro vault only',
      (tester) async {
    await tester.pumpWidget(_screen());
    expect(find.widgetWithText(TextField, 'Vault passphrase'), findsOneWidget);
    for (final t in _types.skip(1)) {
      await _selectType(tester, t);
      expect(find.widgetWithText(TextField, 'Vault passphrase'), findsNothing,
          reason: t);
    }
    await _selectType(tester, 'Gabbro vault');
    expect(find.widgetWithText(TextField, 'Vault passphrase'), findsOneWidget);
  });

  testWidgets('R11 labelled tap targets; the dropdown announces its value',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // The collapsed dropdown is a button: 48dp like every other target.
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    expect(find.bySemanticsLabel(RegExp('Gabbro vault')), findsWidgets);
    await _selectType(tester, 'Enpass');
    expect(find.bySemanticsLabel(RegExp('Enpass')), findsWidgets);
    handle.dispose();
  });

  group('R12 large text', () {
    Future<Object?> overflowFor(
      WidgetTester tester,
      Locale locale,
      double scale,
      String type,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImportScreen(isAndroid: false),
      ));
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      final title = switch (type) {
        'Gabbro vault' => l.gabbroVaultSection,
        'Generic CSV' => l.genericCsvSection,
        _ => type,
      };
      await _selectType(tester, title);
      return tester.takeException();
    }

    void surface(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('no overflow in any locale at 2x on a 360dp phone',
        (tester) async {
      surface(tester, const Size(360, 800));
      final failed = <String>[];
      for (final locale in AppLocalizations.supportedLocales) {
        for (final t in _types) {
          if (await overflowFor(tester, locale, kPhoneMaxScale, t) != null) {
            failed.add('${locale.toLanguageTag()}/$t');
          }
        }
      }
      expect(failed, isEmpty, reason: 'overflowing at 2x: $failed');
    });

    testWidgets('no overflow in any locale at 3x on a 600dp tablet',
        (tester) async {
      surface(tester, const Size(600, 960));
      final failed = <String>[];
      for (final locale in AppLocalizations.supportedLocales) {
        for (final t in _types) {
          if (await overflowFor(tester, locale, kTabletMaxScale, t) != null) {
            failed.add('${locale.toLanguageTag()}/$t');
          }
        }
      }
      expect(failed, isEmpty, reason: 'overflowing at 3x: $failed');
    });
  });
}
