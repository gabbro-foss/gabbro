import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

EntrySummaryData _entry(String id, String title, String type) =>
    EntrySummaryData(
      id: id,
      entryType: type,
      title: title,
      folder: 'Personal',
      searchBlob: '',
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
    testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: listEntries,
    ));

Widget _buildScreenWithFolders({
  required List<EntrySummaryData> Function() listEntries,
  required List<String> Function() listFolders,
  required Future<void> Function(List<String> ids, String folder) onAssignFolder,
}) =>
    testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: listEntries,
      listFolders: listFolders,
      onAssignFolderFn: onAssignFolder,
    ));

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
    'wide: select icon is visible in tablet layout',
    (tester) async {
      _setWide(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));

      expect(find.byIcon(Icons.checklist), findsOneWidget);
    },
  );

  testWidgets(
    'wide: tapping select icon enters selection mode and shows checkboxes',
    (tester) async {
      _setWide(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(find.byType(Checkbox), findsWidgets);
      expect(find.byIcon(Icons.close), findsOneWidget);
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
    'wide: long-pressing a tile enters selection mode and selects that tile',
    (tester) async {
      _setWide(tester);
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
    'wide: close button exits selection mode and select icon reappears',
    (tester) async {
      _setWide(tester);
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

  testWidgets(
    'narrow: assign-folder button appears in selection mode and calls onAssignFolder',
    (tester) async {
      _setNarrow(tester);
      List<String>? assignedIds;
      String? assignedFolder;
      await tester.pumpWidget(_buildScreenWithFolders(
        listEntries: _twoEntries,
        listFolders: () => ['Personal', 'Work'],
        onAssignFolder: (ids, folder) async {
          assignedIds = ids;
          assignedFolder = folder;
        },
      ));

      // Enter selection mode and select first entry
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      // Assign-folder button must be visible
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);

      // Tap it — dialog appears
      await tester.tap(find.byIcon(Icons.folder_outlined));
      await tester.pumpAndSettle();

      // Open the dropdown inside the dialog
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButton<String>),
      ));
      await tester.pumpAndSettle();

      // Pick 'Work' from the dropdown menu
      await tester.tap(find.text('Work').last);
      await tester.pumpAndSettle();

      // Confirm via Assign button
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();

      expect(assignedFolder, 'Work');
      expect(assignedIds, isNotNull);
      expect(assignedIds!.length, 1);
    },
  );

  // ── Delete confirmation dialog ────────────────────────────────────────────

  testWidgets(
    'narrow: delete button opens confirmation dialog',
    (tester) async {
      _setNarrow(tester);
      await tester.pumpWidget(_buildScreen(_twoEntries));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets(
    'narrow: delete dialog Cancel dismissed without deleting',
    (tester) async {
      _setNarrow(tester);
      var deleteCallCount = 0;
      await tester.pumpWidget(testApp(VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: _twoEntries,
        onDeleteEntryFn: (_) async => deleteCallCount++,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(deleteCallCount, 0, reason: 'Cancel must not call delete');
    },
  );
}
