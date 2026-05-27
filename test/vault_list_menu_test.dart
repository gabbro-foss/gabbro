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
      expect(find.text('Sync from file'), findsOneWidget);
      expect(find.text('Manage vaults'), findsOneWidget);
      expect(find.text('Delete vault'), findsOneWidget);
      expect(find.text('Change passphrase'), findsOneWidget);
      expect(find.text('Manage YubiKeys'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Password generator'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Manage folders'), findsOneWidget);
    });
  testWidgets('each menu item has an icon', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Every PopupMenuItem child is a Row — each must contain at least one Icon.
      final rows = find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.byType(Row),
      );
      expect(rows, findsWidgets);
      for (final row in tester.widgetList(rows)) {
        final icons = find.descendant(
          of: find.byElementPredicate((e) => e.widget == row),
          matching: find.byType(Icon),
        );
        expect(icons, findsAtLeastNWidgets(1));
      }
    });

    testWidgets('delete vault icon uses error colour', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      final deleteItem = find.ancestor(
        of: find.text('Delete vault'),
        matching: find.byType(PopupMenuItem<String>),
      );
      expect(deleteItem, findsOneWidget);

      final icon = tester.widget<Icon>(
        find.descendant(of: deleteItem, matching: find.byType(Icon)).first,
      );
      final expectedColor =
          Theme.of(tester.element(deleteItem)).colorScheme.error;
      expect(icon.color, expectedColor);
    });
  });
}