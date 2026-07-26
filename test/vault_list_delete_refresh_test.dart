// Deleting an entry from the detail view must remove it from the list there
// and then — not on the next reload.
//
// This flow had no test in either layout. Round 17 found the two-pane case
// broken on hardware: the entry was deleted, the detail pane cleared, and the
// row sat in the list until the window was refocused. The existing tests all
// asserted that the delete CALLBACK fired; none asserted what the user sees
// afterwards, which is the only thing that matters here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'screen_catalog.dart';

List<EntrySummaryData> seedEntries() => [
  const EntrySummaryData(
    id: 'e1',
    entryType: 'login',
    title: 'Alpha',
    folder: 'Work',
    searchBlob: 'alpha',
  ),
  const EntrySummaryData(
    id: 'e2',
    entryType: 'login',
    title: 'Bravo',
    folder: 'Work',
    searchBlob: 'bravo',
  ),
];

/// A vault list backed by a mutable store, so a delete really removes the
/// entry and the next read reflects it — as the real vault does.
Future<List<EntrySummaryData>> pumpList(
  WidgetTester t, {
  required Surface surface,
  Duration deleteDelay = Duration.zero,
}) async {
  final store = seedEntries();
  t.view.physicalSize = surface.physical;
  t.view.devicePixelRatio = surface.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    appShell(
      VaultListScreen(
        vaultPath: '/tmp/probe.gabbro',
        isAndroid: false,
        yubikeyRecords: const [],
        listEntries: () => List.of(store),
        listFolders: () => const ['Work', 'Personal'],
        getEntryFn: (_) => login('secret', 'notes'),
        onDeleteEntryFn: (id) async {
          // The real delete crosses the FFI, so it takes a frame or more; an
          // instant closure would hide anything that depends on that gap.
          if (deleteDelay > Duration.zero) await Future.delayed(deleteDelay);
          store.removeWhere((e) => e.id == id);
        },
      ),
      textScale: 1.0,
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return store;
}

void main() {
  for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
    testWidgets('$name: a deleted entry leaves the list immediately', (
      t,
    ) async {
      final store = await pumpList(
        t,
        surface: surface,
        deleteDelay: const Duration(milliseconds: 50),
      );
      expect(find.text('Alpha'), findsWidgets, reason: 'sanity: row is listed');

      await t.tap(find.text('Alpha'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();

      expect(
        store.any((e) => e.id == 'e1'),
        isFalse,
        reason: 'sanity: the delete itself ran, so the check below is real',
      );
      expect(
        find.text('Alpha'),
        findsNothing,
        reason: 'the deleted entry is still in the list',
      );
      expect(
        find.text('Bravo'),
        findsWidgets,
        reason: 'the other entries must survive the refresh',
      );
    });
  }
}
