import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'test_helpers.dart';

// Net-first characterization of the alphabet index bar wiring as it behaves
// TODAY (hardcoded Latin A-Z + '#', non-Latin titles collapse to '#'). These
// pin current behaviour green BEFORE the script-aware rework, so the rework's
// diff is visible and regressions in placement / FAB / nav are caught.

EntrySummaryData _entry(String id, String title, {String type = 'Login'}) =>
    EntrySummaryData(
      id: id,
      entryType: type,
      title: title,
      folder: 'Personal',
      searchBlob: '',
    );

Widget _screen(List<EntrySummaryData> entries,
        {AlphabetBarPosition position = AlphabetBarPosition.left}) =>
    testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => entries,
      alphabetBarPosition: position,
    ));

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Section headers render as bold fontSize-12 Text inside the list; the bar's
// letter slots render at fontSize 14. Matching on fontSize disambiguates a
// header 'Q' from the bar slot 'Q'.
Finder _header(String s) => find.byWidgetPredicate(
      (w) => w is Text && w.data == s && w.style?.fontSize == 12,
    );

void main() {
  // ── A. Bucketing (current Latin-only behaviour) ──────────────────────────

  testWidgets('Latin titles bucket under their uppercase first letter',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([
      _entry('1', 'Quartz'),
      _entry('2', 'Olivine'),
    ]));

    expect(_header('Q'), findsOneWidget);
    expect(_header('O'), findsOneWidget);
  });

  testWidgets('lowercase first letter buckets to the uppercase header',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'quartz')]));

    expect(_header('Q'), findsOneWidget);
  });

  testWidgets('empty title falls back and buckets under #', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', '', type: 'Note')]));

    expect(_header('#'), findsOneWidget);
  });

  testWidgets('digit-first title buckets under #', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', '7-Zip')]));

    expect(_header('#'), findsOneWidget);
  });

  testWidgets('non-Latin titles all collapse into # today (the breakage)',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([
      _entry('1', 'Άλφα'), // Greek
      _entry('2', 'Борис'), // Cyrillic
      _entry('3', '김치'), // Korean
      _entry('4', '北京'), // Chinese
    ]));

    // No script-specific headers exist; everything is under '#'.
    expect(_header('#'), findsOneWidget);
    expect(_header('Α'), findsNothing);
    expect(_header('Б'), findsNothing);
    expect(_header('ㄱ'), findsNothing);
  });

  testWidgets('# section sorts last, after Latin headers', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([
      _entry('1', 'Quartz'),
      _entry('2', '北京'), // -> #
    ]));

    final qy = tester.getTopLeft(_header('Q')).dy;
    final hashY = tester.getTopLeft(_header('#')).dy;
    expect(hashY, greaterThan(qy));
  });

  // ── C. Placement & FAB ───────────────────────────────────────────────────

  testWidgets('left placement: bar sits left of the list', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Quartz')],
        position: AlphabetBarPosition.left));

    final barX = tester.getCenter(find.byType(AlphabetIndexBar)).dx;
    final entryX = tester.getCenter(find.text('Quartz')).dx;
    expect(barX, lessThan(entryX));
  });

  testWidgets('right placement: bar sits right of the list', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Quartz')],
        position: AlphabetBarPosition.right));

    final barX = tester.getCenter(find.byType(AlphabetIndexBar)).dx;
    final entryX = tester.getCenter(find.text('Quartz')).dx;
    expect(barX, greaterThan(entryX));
  });

  testWidgets('right placement: bar does not overlap the FAB', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Quartz')],
        position: AlphabetBarPosition.right));

    final barRect = tester.getRect(find.byType(AlphabetIndexBar));
    final fabRect = tester.getRect(find.byType(FloatingActionButton));
    // The bar's bottom padding (80) must keep it clear of the FAB.
    expect(barRect.overlaps(fabRect), isFalse);
  });

  testWidgets('bar is hidden while searching', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_screen([_entry('1', 'Quartz')]));

    expect(find.byType(AlphabetIndexBar), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'qua');
    await tester.pump();
    expect(find.byType(AlphabetIndexBar), findsNothing);
  });
}
