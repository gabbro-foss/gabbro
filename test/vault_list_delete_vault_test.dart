import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

EntrySummaryData _entry(String id, String title, String type) =>
    EntrySummaryData(
      id: id,
      entryType: type,
      title: title,
      folder: 'Personal',
      tags: [],
      favourite: false,
    );

List<EntrySummaryData> _oneEntry() => [_entry('1', 'Quartz', 'Login')];

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen({required Future<void> Function() deleteVault}) =>
    MaterialApp(
      home: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: _oneEntry,
        deleteVault: deleteVault,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('delete vault menu item is enabled', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final item = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Delete vault'),
    );
    expect(item.enabled, isTrue);
  });

  testWidgets('step 1 dialog appears on delete vault tap', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();

    expect(find.text('Delete vault?'), findsOneWidget);
    expect(
      find.text(
        'This will permanently delete all entries. This cannot be undone.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('cancel on step 1 dismisses dialog, vault intact', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete vault?'), findsNothing);
    expect(find.text('Quartz'), findsOneWidget);
  });

  testWidgets('step 2 dialog appears after continuing step 1', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Type DELETE to confirm'), findsOneWidget);
  });

  testWidgets('confirm button disabled until DELETE typed', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Confirm'),
    );
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('delete_vault_confirm_field')), 'DELETE');
    await tester.pump();

    final confirmButtonAfter = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Confirm'),
    );
    expect(confirmButtonAfter.onPressed, isNotNull);
  });

  testWidgets('wrong text keeps confirm button disabled', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('delete_vault_confirm_field')), 'delete');
    await tester.pump();

    final confirmButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Confirm'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('cancel on step 2 dismisses dialog, vault intact', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Type DELETE to confirm'), findsNothing);
    expect(find.text('Quartz'), findsOneWidget);
  });

  testWidgets('full confirm calls deleteVault and navigates to onboarding',
      (tester) async {
    var deleteCalled = false;
    await tester.pumpWidget(
      _buildScreen(deleteVault: () async => deleteCalled = true),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('delete_vault_confirm_field')), 'DELETE');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isTrue);
    expect(
      find.text('Your vault has been deleted. Create a new one to continue.'),
      findsOneWidget,
    );
  });
}