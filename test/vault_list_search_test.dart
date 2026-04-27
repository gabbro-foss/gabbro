import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

EntrySummaryData _entry(String id, String title, String type) =>
    EntrySummaryData(
      id: id,
      entryType: type,
      title: title,
      folder: 'Personal',
      tags: [],
      favourite: false,
    );

List<EntrySummaryData> _threeEntries() => [
  _entry('1', 'Quartz', 'Login'),
  _entry('2', 'Muscovite', 'Note'),
  _entry('3', 'Olivine', 'Login'),
];

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen(List<EntrySummaryData> Function() listEntries) =>
    MaterialApp(home: VaultListScreen(vaultPath: '/tmp/test.gabbro', listEntries: listEntries));

// ── Tests ─────────────────────────────────────────────────────────────────────
void main() {
  testWidgets('all entries shown when search query is empty', (tester) async {
    await tester.pumpWidget(_buildScreen(_threeEntries));

    expect(find.text('Quartz'), findsOneWidget);
    expect(find.text('Muscovite'), findsOneWidget);
    expect(find.text('Olivine'), findsOneWidget);
  });

  testWidgets('typing a query filters entries by title', (tester) async {
    await tester.pumpWidget(_buildScreen(_threeEntries));

    await tester.enterText(find.byType(TextField), 'musc');
    await tester.pump();

    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('Muscovite')),
      findsOneWidget,
    );
    expect(find.text('Quartz'), findsNothing);
    expect(find.text('Olivine'), findsNothing);
  });

  testWidgets('search is case-insensitive', (tester) async {
    await tester.pumpWidget(_buildScreen(_threeEntries));

    await tester.enterText(find.byType(TextField), 'QUARTZ');
    await tester.pump();

    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('Quartz')),
      findsOneWidget,
    );
    expect(find.text('Muscovite'), findsNothing);
  });

  testWidgets('clear button resets the list', (tester) async {
    await tester.pumpWidget(_buildScreen(_threeEntries));

    await tester.enterText(find.byType(TextField), 'musc');
    await tester.pump();
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('Muscovite')),
      findsOneWidget,
    );
    expect(find.text('Quartz'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text('Quartz'), findsOneWidget);
    expect(find.text('Muscovite'), findsOneWidget);
    expect(find.text('Olivine'), findsOneWidget);
  });

  testWidgets('filter chip filters by entry type', (tester) async {
    await tester.pumpWidget(_buildScreen(_threeEntries));

    await tester.tap(find.widgetWithText(FilterChip, 'Note'));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('Muscovite')),
      findsOneWidget,
    );
    expect(find.text('Quartz'), findsNothing);
    expect(find.text('Olivine'), findsNothing);
  });

  testWidgets('tapping checkbox enters selection mode', (tester) async {
    await tester.pumpWidget(_buildScreen(_threeEntries));

    final quartzTile = find.ancestor(
      of: find.text('Quartz'),
      matching: find.byType(ListTile),
    );
    final checkbox = find.descendant(
      of: quartzTile,
      matching: find.byType(Checkbox),
    );
    await tester.tap(checkbox);
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('empty query shows no results message', (tester) async {
    await tester.pumpWidget(_buildScreen(_threeEntries));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.text('Quartz'), findsNothing);
    expect(find.text('Muscovite'), findsNothing);
    expect(find.text('Olivine'), findsNothing);
    expect(find.text('No entries match your search.'), findsOneWidget);
  });
}
