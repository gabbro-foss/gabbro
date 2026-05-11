import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

Widget _buildScreen() => MaterialApp(
      home: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: () => <EntrySummaryData>[],
        deleteVault: () async {},
      ),
    );

Future<void> _setNarrow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pump();
}

void main() {
  group('VaultListScreen menu items', () {
    testWidgets('all expected menu items are present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Export vault'), findsOneWidget);
      expect(find.text('Import entries'), findsOneWidget);
      expect(find.text('Add vault'), findsOneWidget);
      expect(find.text('Delete vault'), findsOneWidget);
      expect(find.text('Change passphrase'), findsOneWidget);
      expect(find.text('Manage YubiKeys'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Password generator'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });
  });
}