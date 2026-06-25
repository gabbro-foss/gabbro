import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// The entry-type filter chip row (All/Password/Note/...) overflows on a narrow
// phone surface and grows left/right scroll chevrons. These pin their scroll
// wiring and the a11y label + desktop hover tooltip, matching the alphabet
// index bar and the password-breakdown sheet.

EntrySummaryData _entry(String id, String title, String type) =>
    EntrySummaryData(
      id: id,
      entryType: type,
      title: title,
      folder: 'Personal',
      searchBlob: '',
    );

List<EntrySummaryData> _entries() => [
      _entry('1', 'Quartz', 'Login'),
      _entry('2', 'Olivine', 'Note'),
    ];

// A narrow surface forces the 7-chip filter row to overflow (so the right
// chevron appears) and keeps the screen in its phone layout.
Future<void> _pumpNarrow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(testApp(VaultListScreen(
    vaultPath: '/tmp/test.gabbro',
    listEntries: _entries,
  )));
  await tester.pumpAndSettle();
}

void main() {
  group('VaultListScreen - filter chip scroll chevrons', () {
    testWidgets('right chevron appears on overflow; tapping it scrolls the row',
        (tester) async {
      await _pumpNarrow(tester);

      // At rest the row is scrolled fully left: only the right chevron shows.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);

      // Tapping it scrolls right, which reveals the left chevron — proves the
      // onTap wiring still reaches _scrollChips end to end.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    // The alphabet index bar on this same screen also tooltips its up/down
    // chevrons with "Next/Previous page", so the finders below are scoped to
    // the chip-row chevron icon (chevron_right/left), not the bar's
    // keyboard_arrow_* icons.
    Finder tooltipAround(IconData icon) => find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(Tooltip),
        );

    Finder buttonLabelAround(IconData icon, String label) => find.ancestor(
          of: find.byIcon(icon),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.button == true &&
                w.properties.label == label,
          ),
        );

    testWidgets('right chevron carries a tooltip and a button label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpNarrow(tester);

      final tip = tooltipAround(Icons.chevron_right);
      expect(tip, findsOneWidget);
      expect(tester.widget<Tooltip>(tip).message, 'Next page');
      expect(buttonLabelAround(Icons.chevron_right, 'Next page'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('left chevron carries a tooltip and a button label once shown',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpNarrow(tester);

      // Scroll right so the left chevron is inserted into the tree.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      final tip = tooltipAround(Icons.chevron_left);
      expect(tip, findsOneWidget);
      expect(tester.widget<Tooltip>(tip).message, 'Previous page');
      expect(buttonLabelAround(Icons.chevron_left, 'Previous page'),
          findsOneWidget);
      handle.dispose();
    });
  });
}
