import 'dart:ui' show CheckedState;

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

  // ADR-016 Phase 3 (Slice A): selection checkboxes must NOT force
  // VisualDensity.compact — compact shrinks the tap target below the standard
  // 48dp, the opposite of the accessibility goal.
  testWidgets('narrow: selection checkbox does not force compact density',
      (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_twoEntries));
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();

    final box = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(box.visualDensity, isNot(VisualDensity.compact));
  });

  // ADR-016 Phase 3 Slice C: at large text the selection checkbox scales up
  // (gently, so it stays visible without crowding the row).
  testWidgets('narrow: selection checkbox scales up at large text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_twoEntries));
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();

    expect(find.byKey(const Key('scaledSelectionCheckbox')), findsWidgets);
  });

  testWidgets('narrow: selection checkbox is NOT scaled at normal text',
      (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_twoEntries));
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();

    expect(find.byType(Checkbox), findsWidgets);
    expect(find.byKey(const Key('scaledSelectionCheckbox')), findsNothing);
  });

  // A11y: the selection-mode app-bar actions (delete, close) carry semantic
  // labels (tooltips). A full labelledTapTargetGuideline assertion is NOT made
  // here: selection mode also exposes the per-row checkboxes and the alphabet
  // index bar as unlabelled tappables — deeper a11y debt tracked in the Bikeshed,
  // out of scope for the show/hide-eye-toggle work.
  testWidgets('selection-mode delete and close actions carry tooltips',
      (tester) async {
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_twoEntries));

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete)).tooltip,
      isNotNull,
    );
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close)).tooltip,
      isNotNull,
    );
  });

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

  // ── A11y: selection checkbox carries the entry title ──────────────────────
  // Without a label a screen reader announces a bare "tick box" with no entry
  // name. The checkbox role + checked state come free from the Checkbox; we add
  // the entry title so the reader says e.g. "Gabbro, tick box, not ticked".

  testWidgets('narrow: selection checkbox is labelled with the entry title',
      (tester) async {
    final handle = tester.ensureSemantics();
    _setNarrow(tester);
    await tester.pumpWidget(_buildScreen(_twoEntries));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    final cb = find.descendant(
      of: find.ancestor(
          of: find.text('Gabbro'), matching: find.byType(ListTile)),
      matching: find.byType(Checkbox),
    );
    final node = tester.getSemantics(cb);
    expect(node.label, 'Gabbro');
    expect(node.flagsCollection.isChecked, isNot(CheckedState.none),
        reason: 'checkbox role must survive the Semantics wrapper');
    handle.dispose();
  });

  testWidgets('wide: selection checkbox is labelled with the entry title',
      (tester) async {
    final handle = tester.ensureSemantics();
    _setWide(tester);
    await tester.pumpWidget(_buildScreen(_twoEntries));
    await tester.pumpAndSettle();

    // The two-pane layout also renders the title in the detail pane, so scope
    // to the master ListTile (the only 'Gabbro' inside a ListTile).
    final gabbroTile = find.ancestor(
      of: find.text('Gabbro'),
      matching: find.byType(ListTile),
    );
    await tester.longPress(gabbroTile);
    await tester.pumpAndSettle();

    final cb =
        find.descendant(of: gabbroTile, matching: find.byType(Checkbox));
    final node = tester.getSemantics(cb);
    expect(node.label, 'Gabbro');
    expect(node.flagsCollection.isChecked, isNot(CheckedState.none),
        reason: 'checkbox role must survive the Semantics wrapper');
    handle.dispose();
  });
}
