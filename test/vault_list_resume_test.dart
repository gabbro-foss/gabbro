import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

EntrySummaryData _entry(String id, String title) => EntrySummaryData(
      id: id,
      entryType: 'Login',
      title: title,
      folder: 'Personal',
      searchBlob: '',
    );

void main() {
  testWidgets('reloads entries on app resume (e.g. after an autofill save)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The session starts empty; then an entry appears — as if the autofill
    // SaveActivity wrote one into the shared session while we were backgrounded.
    var entries = <EntrySummaryData>[];
    await tester.pumpWidget(testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => entries,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Practice'), findsNothing);

    entries = [_entry('1', 'Practice')];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Practice'), findsOneWidget);
  });
}
