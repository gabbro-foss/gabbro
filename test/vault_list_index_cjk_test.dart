import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// Cycle 4: Japanese and Chinese have no human-orderable index bar, so those
// locales drop the bar and section headers and show a plain title-sorted list.

EntrySummaryData _entry(String id, String title) => EntrySummaryData(
      id: id,
      entryType: 'Login',
      title: title,
      folder: 'Personal',
      searchBlob: '',
    );

Widget _screen(List<EntrySummaryData> entries, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: () => entries,
      ),
    );

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Section headers render at fontSize 12.
Finder _anyHeader() => find.byWidgetPredicate(
      (w) => w is Text && w.style?.fontSize == 12,
    );

void main() {
  testWidgets('ja locale: no alphabet bar, no headers, flat list',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([
      _entry('1', '北京'),
      _entry('2', '東京'),
    ], const Locale('ja')));
    await tester.pumpAndSettle();

    expect(find.byType(AlphabetIndexBar), findsNothing);
    expect(_anyHeader(), findsNothing);
    expect(find.text('北京'), findsOneWidget);
    expect(find.text('東京'), findsOneWidget);
  });

  testWidgets('zh locale: no alphabet bar', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', '北京')], const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.byType(AlphabetIndexBar), findsNothing);
  });

  testWidgets('en locale: bar and headers still present (regression)',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Quartz')], const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.byType(AlphabetIndexBar), findsOneWidget);
    expect(_anyHeader(), findsWidgets);
  });
}
