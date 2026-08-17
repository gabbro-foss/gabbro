// What the vault list does with the number the import flow hands back.
//
// The import screen returns how many entries it added, or null when the user
// backed out. Hardware 2026-08-17 (D2): a run that added nothing left the
// screen completely unchanged — no message, no refresh — so a user who
// re-imported a file they already had could not tell the button from a broken
// one. These pin all three outcomes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'test_helpers.dart';

const _entry = EntrySummaryData(
  id: 'e1',
  entryType: 'login',
  title: 'Alpha',
  folder: '',
  searchBlob: 'alpha',
);

/// Pumps the vault list with the import flow stubbed to return [importResult],
/// and reports how many times the list re-read its entries.
Future<int Function()> _pumpAndImport(
  WidgetTester tester, {
  required int? importResult,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  var reads = 0;
  await tester.pumpWidget(testApp(VaultListScreen(
    vaultPath: '/tmp/probe.gabbro',
    isAndroid: false,
    yubikeyRecords: const [],
    listEntries: () {
      reads++;
      return const [_entry];
    },
    openImport: (_) async => importResult,
  )));
  await tester.pumpAndSettle();

  final readsBeforeImport = reads;
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import entries'));
  await tester.pumpAndSettle();

  return () => reads - readsBeforeImport;
}

void main() {
  testWidgets('an import that added entries is reported and refreshes the list',
      (tester) async {
    final rereads = await _pumpAndImport(tester, importResult: 4);

    expect(find.text('Imported 4 entries.'), findsOneWidget);
    expect(rereads(), greaterThan(0), reason: 'the list must be re-read');
  });

  testWidgets('backing out of the import screen says nothing', (tester) async {
    final rereads = await _pumpAndImport(tester, importResult: null);

    expect(find.byType(SnackBar), findsNothing);
    expect(rereads(), 0);
  });

  // D2: the defect. An import where every entry was already present returns 0.
  testWidgets('an import that added nothing still tells the user',
      (tester) async {
    final rereads = await _pumpAndImport(tester, importResult: 0);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Imported 0 entries.'), findsOneWidget);
    expect(rereads(), greaterThan(0), reason: 'the list must match disk');
  });
}
