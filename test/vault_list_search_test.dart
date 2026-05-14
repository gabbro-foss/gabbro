import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

EntrySummaryData _entry(String id, String title, String type,
        {String folder = 'Personal'}) =>
    EntrySummaryData(
      id: id,
      entryType: type,
      title: title,
      folder: folder,
    );

List<EntrySummaryData> _threeEntries() => [
  _entry('1', 'Quartz', 'Login'),
  _entry('2', 'Muscovite', 'Note'),
  _entry('3', 'Olivine', 'Login'),
];

List<EntrySummaryData> _folderEntries() => [
  _entry('1', 'Quartz', 'Login', folder: 'Work'),
  _entry('2', 'Muscovite', 'Note', folder: 'Private'),
  _entry('3', 'Olivine', 'Login', folder: 'Work'),
  _entry('4', 'Feldspar', 'Login', folder: ''),
];

// ── Widget helper ─────────────────────────────────────────────────────────────
//
// Forces a narrow (phone) surface so LayoutBuilder picks the phone layout.
// The tablet layout has a different widget tree that would break these tests.

Widget _buildScreen(
  List<EntrySummaryData> Function() listEntries, {
  List<String> Function()? listFolders,
}) =>
    MaterialApp(
      home: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: listEntries,
        listFolders: listFolders,
      ),
    );

void _setNarrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('all entries shown when search query is empty', (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_threeEntries));

    expect(find.text('Quartz'), findsOneWidget);
    expect(find.text('Muscovite'), findsOneWidget);
    expect(find.text('Olivine'), findsOneWidget);
  });

  testWidgets('typing a query filters entries by title', (tester) async {
    _setNarrow(tester);
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
    _setNarrow(tester);
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
    _setNarrow(tester);
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
    _setNarrow(tester);
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

  testWidgets('tapping checklist icon then checkbox enters selection mode',
      (tester) async {
    // On the phone layout, checkboxes only appear after entering selection mode
    // via the checklist icon. The old isWide behaviour (always-visible checkboxes)
    // has been removed — phone layout is now checkbox-on-select only.
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_threeEntries));

    // Enter selection mode first.
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();

    // Now tap the checkbox next to 'Quartz'.
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

  testWidgets('alphabet bar is first Row child when position is left',
      (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_threeEntries));

    final row = tester.widget<Row>(
      find.ancestor(
        of: find.byType(AlphabetIndexBar),
        matching: find.byType(Row),
      ).first,
    );
    expect(row.children.first, isA<SizedBox>());
    expect(row.children.last, isA<Expanded>());
  });

  testWidgets('alphabet bar is last Row child when position is right',
      (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: VaultListScreen(
            vaultPath: '/tmp/test.gabbro',
            listEntries: _threeEntries,
            alphabetBarPosition: AlphabetBarPosition.right,
          ),
        ),
      ),
    );

    final row = tester.widget<Row>(
      find.ancestor(
        of: find.byType(AlphabetIndexBar),
        matching: find.byType(Row),
      ).first,
    );
    expect(row.children.first, isA<Expanded>());
    expect(row.children.last, isA<Padding>());
  });

  testWidgets('empty query shows no results message', (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_threeEntries));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.text('Quartz'), findsNothing);
    expect(find.text('Muscovite'), findsNothing);
    expect(find.text('Olivine'), findsNothing);
    expect(find.text('No entries match your search.'), findsOneWidget);
  });

  testWidgets('folder dropdown renders with All folders option',
      (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(
      _buildScreen(
        _folderEntries,
        listFolders: () => ['Work', 'Private'],
      ),
    );

    expect(find.text('All folders'), findsOneWidget);
  });

  testWidgets('selecting a folder shows only entries in that folder',
      (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(
      _buildScreen(
        _folderEntries,
        listFolders: () => ['Work', 'Private'],
      ),
    );

    await tester.tap(find.text('All folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(ListTile), matching: find.text('Quartz')), findsOneWidget);
    expect(find.descendant(of: find.byType(ListTile), matching: find.text('Olivine')), findsOneWidget);
    expect(find.text('Muscovite'), findsNothing);
  });

  testWidgets('selecting a folder hides unfoldered entries', (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(
      _buildScreen(
        _folderEntries,
        listFolders: () => ['Work', 'Private'],
      ),
    );

    await tester.tap(find.text('All folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    expect(find.text('Feldspar'), findsNothing);
  });

  testWidgets('folder filter and type filter work together', (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(
      _buildScreen(
        _folderEntries,
        listFolders: () => ['Work', 'Private'],
      ),
    );

    // Select Work folder
    await tester.tap(find.text('All folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    // Also filter by Note type — Work has no notes
    await tester.tap(find.widgetWithText(FilterChip, 'Note'));
    await tester.pump();

    expect(find.text('Quartz'), findsNothing);
    expect(find.text('Olivine'), findsNothing);
    expect(find.text('No entries match your search.'), findsOneWidget);
  });

  testWidgets('selecting All folders restores all entries', (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(
      _buildScreen(
        _folderEntries,
        listFolders: () => ['Work', 'Private'],
      ),
    );

    // Select Work folder
    await tester.tap(find.text('All folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    expect(find.text('Muscovite'), findsNothing);

    // Back to All folders
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All folders').last);
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(ListTile), matching: find.text('Muscovite')), findsOneWidget);
  });
}
