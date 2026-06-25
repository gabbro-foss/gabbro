import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/tablet_vault_layout.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'test_helpers.dart';

// Builds a TabletVaultLayout with one entry and an injected getEntryFn. The
// detail pane fetches the full entry synchronously during build; this lets us
// drive the "entry vanished / session race" path that crashed on hardware.
TabletVaultLayout _layout({
  required VaultEntryData Function(String id) getEntryFn,
}) {
  final entry = EntrySummaryData(
    id: 'e1',
    entryType: 'Login',
    title: 'Example',
    folder: '',
    searchBlob: 'example',
  );
  return TabletVaultLayout(
    groupedEntries: [entry],
    filteredEntries: [entry],
    letterIndex: const {},
    onLetterSelected: (_) {},
    displayTitle: (e) => e.title,
    displayType: (t) => t,
    entryTypeIcon: (_) => Icons.lock,
    searchBar: const SizedBox.shrink(),
    filterChipRow: const SizedBox.shrink(),
    searchActive: false,
    onEntryTap: (_) {},
    onRefresh: () {},
    vaultPath: '/tmp/v.gabbro',
    clipboardClearTimeout: ClipboardClearTimeout.thirtySeconds,
    getEntryFn: getEntryFn,
    selectionMode: false,
    selectedIds: const {},
    onToggleSelection: (_) {},
  );
}

void main() {
  testWidgets(
      'R-03 P6: selecting an entry whose getEntry throws falls back to the '
      'empty state instead of crashing the build', (tester) async {
    await tester.pumpWidget(testApp(_layout(
      // The selected entry no longer exists in the session (deleted, or a
      // refresh race against a locked/corrupted vault).
      getEntryFn: (id) => throw Exception('No entry found with id: $id'),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a failed entry fetch must not throw during build');
    expect(find.text('Select an entry'), findsOneWidget,
        reason: 'the detail pane must fall back to the empty state');
  });
}
