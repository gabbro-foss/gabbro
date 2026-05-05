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
//
// Both helpers use MaterialApp (no GabbroApp needed — these tests don't
// exercise clipboard timeout or settings). Width is controlled via
// tester.view.physicalSize so LayoutBuilder sees the correct constraint.

Widget _buildScreen(List<EntrySummaryData> Function() listEntries) =>
    MaterialApp(
      home: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: listEntries,
      ),
    );

void _setNarrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setWide(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
    'narrow: select icon is visible when not in selection mode',
    (tester) async {
      _setNarrow(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));

      expect(find.byIcon(Icons.checklist), findsOneWidget);
    },
  );

  testWidgets(
    'wide: select icon is absent — tablet layout has no checklist icon',
    (tester) async {
      _setWide(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));

      expect(find.byIcon(Icons.checklist), findsNothing);
    },
  );

  testWidgets(
    'narrow: tapping select icon enters selection mode and shows checkboxes',
    (tester) async {
      _setNarrow(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(find.byType(Checkbox), findsWidgets);
      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );

  testWidgets(
    'narrow: long-pressing a tile enters selection mode and selects that tile',
    (tester) async {
      _setNarrow(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));

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
      _setNarrow(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));

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
