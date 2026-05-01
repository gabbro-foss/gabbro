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

List<EntrySummaryData> _twoEntries() => [
  _entry('1', 'Gabbro', 'Login'),
  _entry('2', 'Basalt', 'Note'),
];

// ── Widget helpers ────────────────────────────────────────────────────────────

Widget _buildNarrow(List<EntrySummaryData> Function() listEntries) =>
    MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: MaterialApp(
        home: VaultListScreen(
          vaultPath: '/tmp/test.gabbro',
          listEntries: listEntries,
        ),
      ),
    );

Widget _buildWide(List<EntrySummaryData> Function() listEntries) =>
    MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: MaterialApp(
        home: VaultListScreen(
          vaultPath: '/tmp/test.gabbro',
          listEntries: listEntries,
        ),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
    'narrow: select icon is visible when not in selection mode',
    (tester) async {
      await tester.pumpWidget(_buildNarrow(_twoEntries));

      expect(find.byIcon(Icons.checklist), findsOneWidget);
    },
  );

  testWidgets(
    'wide: select icon is absent — checkboxes are always visible',
    (tester) async {
      await tester.pumpWidget(_buildWide(_twoEntries));

      expect(find.byIcon(Icons.checklist), findsNothing);
    },
  );

  testWidgets(
    'narrow: tapping select icon enters selection mode and shows checkboxes',
    (tester) async {
      await tester.pumpWidget(_buildNarrow(_twoEntries));

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(find.byType(Checkbox), findsWidgets);
      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );

  testWidgets(
    'narrow: long-pressing a tile enters selection mode and selects that tile',
    (tester) async {
      await tester.pumpWidget(_buildNarrow(_twoEntries));

      final gabbroTile = find.ancestor(
        of: find.text('Gabbro'),
        matching: find.byType(ListTile),
      );
      await tester.longPress(gabbroTile);
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
    },
  );

  testWidgets(
    'narrow: close button exits selection mode and select icon reappears',
    (tester) async {
      await tester.pumpWidget(_buildNarrow(_twoEntries));

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      expect(find.byIcon(Icons.checklist), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.byIcon(Icons.checklist), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    },
  );
}