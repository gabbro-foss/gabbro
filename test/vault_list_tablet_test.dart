import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/screens/tablet_vault_layout.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/src/rust/api/vault.dart';

// ---------------------------------------------------------------------------
// Fake entry list — avoids hitting the Rust bridge in tests.
// Two entries so the list is non-empty and we can test selection.
// ---------------------------------------------------------------------------
List<EntrySummaryData> _fakeEntries() => [
  EntrySummaryData(
    id: 'id-1',
    entryType: 'Login',
    title: 'Alice',
    folder: 'Personal',
  ),
  EntrySummaryData(
    id: 'id-2',
    entryType: 'Note',
    title: 'Bob',
    folder: 'Personal',
  ),
];

// ---------------------------------------------------------------------------
// Fake VaultEntryData for detail pane injection in tests.
// ---------------------------------------------------------------------------
VaultEntryData _fakeLoginEntry() => VaultEntryData.login(
  LoginEntryData(
    id: 'id-1',
    title: 'Alice',
    url: 'https://alice.example.com',
    username: 'alice',
    password: 'secret',
    notes: null,
    customFields: [],
    createdAt: '2025-01-01T00:00:00Z',
    updatedAt: '2025-01-01T00:00:00Z',
    folder: 'Personal',
  ),
);

// ---------------------------------------------------------------------------
// Helper — builds VaultListScreen inside GabbroApp.
// Width is controlled via tester.view.physicalSize in each test — that is
// the only reliable way to make LayoutBuilder see a specific width inside
// MaterialApp, which otherwise expands to fill the full test surface.
// ---------------------------------------------------------------------------
Widget _buildScreen() => GabbroApp(
  vaultPath: '/tmp/test.gabbro',
  vaultExists: false,
  settings: const AppSettings(),
  initialScreen: VaultListScreen(
    vaultPath: '/tmp/test.gabbro',
    listEntries: _fakeEntries,
  ),
);

// Sets the test surface to [width]×900 logical pixels (devicePixelRatio=1)
// and registers a teardown to reset it after the test.
void _setWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('VaultListScreen — tablet two-pane layout', () {
    // -----------------------------------------------------------------------
    // Test 1: NavigationRail present at ≥600dp
    // -----------------------------------------------------------------------
    testWidgets('NavigationRail visible at ≥600dp', (tester) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 2: NavigationBar (bottom) absent at ≥600dp
    // -----------------------------------------------------------------------
    testWidgets('NavigationBar absent at ≥600dp', (tester) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationBar), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 3: NavigationRail absent below 600dp (phone layout unchanged)
    // -----------------------------------------------------------------------
    testWidgets('NavigationRail absent below 600dp', (tester) async {
      _setWidth(tester, 400);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationRail), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 4: List pane present at ≥600dp — search field is the landmark.
    // -----------------------------------------------------------------------
    testWidgets('list pane present at ≥600dp (search field visible)', (
      tester,
    ) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.widgetWithIcon(TextField, Icons.search), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 5: Empty state shown in detail pane when no entry is selected.
    // -----------------------------------------------------------------------
    testWidgets('detail pane shows empty state when no entry selected', (
      tester,
    ) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Select an entry'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 6: Tapping the pencil on a selected entry navigates to
    // CreateEntryScreen (edit mode uses full-screen push navigation —
    // Option 2 from the wireframe decisions; in-place dim is not needed
    // because the two-pane layout is not visible while editing).
    // -----------------------------------------------------------------------
    testWidgets('pencil tap on selected entry navigates to edit screen', (
      tester,
    ) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(
        GabbroApp(
          vaultPath: '/tmp/test.gabbro',
          vaultExists: false,
          settings: const AppSettings(),
          initialScreen: VaultListScreen(
            vaultPath: '/tmp/test.gabbro',
            listEntries: _fakeEntries,
            getEntryFn: (_) => _fakeLoginEntry(),
          ),
        ),
      );
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 7: Delete from detail pane returns to empty state (no crash).
    // -----------------------------------------------------------------------
    testWidgets('delete from detail pane shows empty state', (tester) async {
      _setWidth(tester, 700);
      bool deleteEntryCalled = false;
      bool refreshCalled = false;
      await tester.pumpWidget(
        GabbroApp(
          vaultPath: '/tmp/test.gabbro',
          vaultExists: false,
          settings: const AppSettings(),
          initialScreen: VaultListScreen(
            vaultPath: '/tmp/test.gabbro',
            listEntries: _fakeEntries,
            getEntryFn: (_) => _fakeLoginEntry(),
            onDeleteEntryFn: (_) async {
              deleteEntryCalled = true;
            },
            onRefreshFn: () {
              refreshCalled = true;
            },
          ),
        ),
      );

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('Select an entry'), findsNothing);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Select an entry'), findsOneWidget);
      expect(deleteEntryCalled, isTrue);
      expect(refreshCalled, isTrue);
    });

    // -----------------------------------------------------------------------
    // Test 8: Layout switches when width crosses 600dp threshold.
    // -----------------------------------------------------------------------
    testWidgets('layout switches across 600dp threshold', (tester) async {
      _setWidth(tester, 400);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationRail), findsNothing);

      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 9: Delete all entries — detail pane shows empty state (not grey).
    // Regression test for: bulk delete left _selectedEntryId set while
    // filteredEntries became empty, causing the detail pane to render blank.
    //
    // Drives TabletVaultLayout directly: first render with one entry and
    // tap it so _selectedEntryId is set, then rebuild with filteredEntries
    // empty — the detail pane must show the empty state.
    // -----------------------------------------------------------------------
    testWidgets('detail pane shows empty state after delete-all', (
      tester,
    ) async {
      _setWidth(tester, 700);

      // StatefulWrapper lets us swap filteredEntries between pumps.
      final entries = _fakeEntries();
      final grouped = <dynamic>['A', entries[0], 'B', entries[1]];

      Widget buildLayout(List<EntrySummaryData> filtered) =>
          MaterialApp(
            home: Scaffold(
              body: TabletVaultLayout(
                groupedEntries: filtered.isEmpty ? [] : grouped,
                filteredEntries: filtered,
                letterIndex: filtered.isEmpty ? {} : {'A': 0},
                onLetterSelected: (_) {},
                displayTitle: (e) => e.title,
                displayType: (_) => 'Password',
                entryTypeIcon: (_) => Icons.lock_outline,
                searchBar: const SizedBox.shrink(),
                filterChipRow: const SizedBox.shrink(),
                searchActive: false,
                onEntryTap: (_) {},
                onRefresh: () {},
                vaultPath: '/tmp/test.gabbro',
                clipboardClearTimeout: ClipboardClearTimeout.sixtySeconds,
                getEntryFn: (_) => _fakeLoginEntry(),
                onDeleteEntryFn: (_) async {},
                selectionMode: false,
                selectedIds: const {},
                onToggleSelection: (_) {},
              ),
            ),
          );

      // First render — two entries present.
      await tester.pumpWidget(buildLayout(entries));
      await tester.pumpAndSettle();

      // Tap Alice so _selectedEntryId is non-null inside the layout.
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('Select an entry'), findsNothing);

      // Rebuild with empty list — simulates parent after delete-all + refresh.
      await tester.pumpWidget(buildLayout([]));
      await tester.pumpAndSettle();

      // Detail pane must show empty state, not a blank grey widget.
      expect(find.text('Select an entry'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 10: Stale _selectedEntryId reset after import/vault reload.
    //
    // Drives TabletVaultLayout directly. Tap id-1 to set _selectedEntryId,
    // then rebuild with a new entry list that does NOT contain id-1 —
    // simulating a vault reload after import. Detail pane must revert to
    // empty state rather than trying to fetch a ghost entry.
    // -----------------------------------------------------------------------
    testWidgets('detail pane resets to empty state after vault reload removes selected entry', (
      tester,
    ) async {
      _setWidth(tester, 700);

      final originalEntries = _fakeEntries(); // id-1 Alice, id-2 Bob
      final grouped = <dynamic>['A', originalEntries[0], 'B', originalEntries[1]];

      // After reload: only Bob (id-2) remains — Alice (id-1) is gone.
      final reloadedEntries = [
        EntrySummaryData(
          id: 'id-2',
          entryType: 'Note',
          title: 'Bob',
          folder: 'Personal',
        ),
      ];
      final reloadedGrouped = <dynamic>['B', reloadedEntries[0]];

      Widget buildLayout(
        List<EntrySummaryData> filtered,
        List<dynamic> groupedList,
      ) =>
          MaterialApp(
            home: Scaffold(
              body: TabletVaultLayout(
                groupedEntries: groupedList,
                filteredEntries: filtered,
                letterIndex: {'A': 0},
                onLetterSelected: (_) {},
                displayTitle: (e) => e.title,
                displayType: (_) => 'Password',
                entryTypeIcon: (_) => Icons.lock_outline,
                searchBar: const SizedBox.shrink(),
                filterChipRow: const SizedBox.shrink(),
                searchActive: false,
                onEntryTap: (_) {},
                onRefresh: () {},
                vaultPath: '/tmp/test.gabbro',
                clipboardClearTimeout: ClipboardClearTimeout.sixtySeconds,
                getEntryFn: (_) => _fakeLoginEntry(),
                onDeleteEntryFn: (_) async {},
                selectionMode: false,
                selectedIds: const {},
                onToggleSelection: (_) {},
              ),
            ),
          );

      // Initial render — two entries.
      await tester.pumpWidget(buildLayout(originalEntries, grouped));
      await tester.pumpAndSettle();

      // Tap Alice → _selectedEntryId = 'id-1'.
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('Select an entry'), findsNothing);

      // Vault reload: rebuild without id-1.
      await tester.pumpWidget(buildLayout(reloadedEntries, reloadedGrouped));
      await tester.pumpAndSettle();

      // _selectedEntryId ('id-1') is no longer in filteredEntries — must reset.
      expect(find.text('Select an entry'), findsOneWidget);
    });
  });
}
