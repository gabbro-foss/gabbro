import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// Cycle 1: the index bar + bucketing follow the active UI locale's script.
// A Cyrillic locale (ru) shows the Cyrillic alphabet; a Latin locale is
// unchanged.

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

// Section headers render at fontSize 12 (vs the bar's fontSize-14 slots).
Finder _header(String s) => find.byWidgetPredicate(
      (w) => w is Text && w.data == s && w.style?.fontSize == 12,
    );

AlphabetIndexBar _bar(WidgetTester tester) =>
    tester.widget<AlphabetIndexBar>(find.byType(AlphabetIndexBar));

void main() {
  testWidgets('ru locale: Cyrillic header + Cyrillic bar canon',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Борис')], const Locale('ru')));
    await tester.pumpAndSettle();

    expect(_header('Б'), findsOneWidget);
    expect(_bar(tester).letters, contains('Я'));
    expect(_bar(tester).letters, contains('Б'));
    expect(_bar(tester).letters, isNot(contains('Q')));
  });

  testWidgets('en locale: Latin bar canon unchanged (regression)',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Quartz')], const Locale('en')));
    await tester.pumpAndSettle();

    expect(_header('Q'), findsOneWidget);
    expect(_bar(tester).letters, contains('Q'));
    expect(_bar(tester).letters, isNot(contains('Б')));
  });
}
