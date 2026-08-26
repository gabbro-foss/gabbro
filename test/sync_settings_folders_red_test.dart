// Red for step 3, Sync settings (R9): the export and import folders shown
// read-only, with the note saying where they are changed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/sync_settings_screen.dart';
import 'package:gabbro/settings.dart';

import 'test_helpers.dart';

Widget _screen(AppSettings s) => testApp(SyncSettingsScreen(
      settings: s,
      onUpdate: (_) {},
      onPickFolder: () async => null,
      isAndroid: false,
      vaultAlias: 'example',
    ));

void main() {
  testWidgets('R9 both rows show the remembered folders', (tester) async {
    await tester.pumpWidget(_screen(const AppSettings(
      exportFolder: '/home/user/GabbroSync',
      importFolder: 'content://docs/document/primary%3ADownload%2Fx.json',
    )));
    await tester.pumpAndSettle();
    expect(find.text('Export folder'), findsOneWidget);
    expect(find.text('Import folder'), findsOneWidget);
    expect(find.text('/home/user/GabbroSync'), findsOneWidget);
    // An Android location reads as a folder, not a raw URI.
    expect(find.textContaining('Download'), findsOneWidget);
    expect(find.textContaining('content://'), findsNothing);
    expect(find.text('Changed on Export and Import entries.'), findsOneWidget);
  });

  testWidgets('R9 an empty folder reads Not set', (tester) async {
    await tester.pumpWidget(_screen(const AppSettings()));
    await tester.pumpAndSettle();
    expect(find.text('Not set'), findsNWidgets(2));
  });

  testWidgets('R9 the rows are display only: no button, no box for them',
      (tester) async {
    await tester.pumpWidget(_screen(const AppSettings(exportFolder: '/x')));
    await tester.pumpAndSettle();
    // One Choose folder button and one Remember box: the sync folder's.
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });
}
