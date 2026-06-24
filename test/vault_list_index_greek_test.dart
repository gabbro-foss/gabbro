import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// Cycle 2: a Greek (el) locale shows the Greek alphabet and folds accents so
// 'Άλφα' buckets under 'Α'.

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

Finder _header(String s) => find.byWidgetPredicate(
      (w) => w is Text && w.data == s && w.style?.fontSize == 12,
    );

AlphabetIndexBar _bar(WidgetTester tester) =>
    tester.widget<AlphabetIndexBar>(find.byType(AlphabetIndexBar));

void main() {
  testWidgets('el locale: accented Greek title buckets under folded base header',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Άλφα')], const Locale('el')));
    await tester.pumpAndSettle();

    expect(_header('Α'), findsOneWidget);
    expect(_bar(tester).letters, contains('Ω'));
    expect(_bar(tester).letters, contains('Α'));
    expect(_bar(tester).letters, isNot(contains('Q')));
  });
}
