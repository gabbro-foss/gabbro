import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/vault_registry.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

VaultRecord _record({String path = '/tmp/test.gabbro', String alias = 'Test'}) =>
    VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

Widget _buildScreen({
  required VaultRegistry registry,
  Future<void> Function(String path, String alias)? onRename,
  Future<void> Function(String path)? onDelete,
  VoidCallback? onAddVault,
  void Function(String path, String alias)? onSwitchToVault,
}) =>
    MaterialApp(
      home: ManageVaultsScreen(
        registry: registry,
        onRename: onRename ?? (_, _) async {},
        onDelete: onDelete ?? (_) async {},
        onAddVault: onAddVault ?? () {},
        onSwitchToVault: onSwitchToVault ?? (_, _) {},
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final registry = VaultRegistry([
    _record(path: '/tmp/a.gabbro', alias: 'Alpha'),
    _record(path: '/tmp/b.gabbro', alias: 'Beta'),
  ]);

  // ── Vault list display ────────────────────────────────────────────────────

  group('vault list display', () {
    testWidgets('shows all vault aliases', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('shows vault path as subtitle', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      expect(find.text('/tmp/a.gabbro'), findsOneWidget);
    });

    testWidgets('shows empty state when registry has no vaults', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: VaultRegistry([])));
      expect(find.text('No vaults registered.'), findsOneWidget);
    });

    testWidgets('always shows vault list regardless of registry size', (tester) async {
      final single = VaultRegistry([_record(alias: 'Solo')]);
      await tester.pumpWidget(_buildScreen(registry: single));
      expect(find.text('Solo'), findsOneWidget);
    });
  });

  // ── Switch to vault ───────────────────────────────────────────────────────

  testWidgets('tapping vault row calls onSwitchToVault with path and alias',
      (tester) async {
    String? selectedPath;
    String? selectedAlias;
    await tester.pumpWidget(_buildScreen(
      registry: registry,
      onSwitchToVault: (p, a) {
        selectedPath = p;
        selectedAlias = a;
      },
    ));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(selectedPath, '/tmp/a.gabbro');
    expect(selectedAlias, 'Alpha');
  });

  // ── Add vault ─────────────────────────────────────────────────────────────

  testWidgets('shows Add vault button', (tester) async {
    await tester.pumpWidget(_buildScreen(registry: registry));
    expect(find.text('Add vault'), findsOneWidget);
  });

  testWidgets('tapping Add vault calls onAddVault', (tester) async {
    var called = false;
    await tester.pumpWidget(_buildScreen(
      registry: registry,
      onAddVault: () => called = true,
    ));
    await tester.tap(find.text('Add vault'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });

  // ── Rename dialog ─────────────────────────────────────────────────────────

  group('rename dialog', () {
    testWidgets('edit icon opens rename dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('Rename vault'), findsOneWidget);
    });

    testWidgets('rename dialog pre-fills with current alias', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Alpha'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('save button disabled when alias matches another vault',
        (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();
      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('duplicate alias shows error text in rename dialog',
        (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();
      expect(find.textContaining('already exists'), findsOneWidget);
    });

    testWidgets('confirming empty alias does not call onRename', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onRename: (_, _) async => called = true,
      ));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('confirming valid alias calls onRename with path and alias',
        (tester) async {
      String? renamedPath;
      String? renamedAlias;
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onRename: (p, a) async {
          renamedPath = p;
          renamedAlias = a;
        },
      ));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New Name');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(renamedPath, '/tmp/a.gabbro');
      expect(renamedAlias, 'New Name');
    });

    testWidgets('rename updates the displayed alias', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onRename: (_, _) async {},
      ));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });
  });

  // ── Delete dialog (2-step) ────────────────────────────────────────────────

  group('delete dialog', () {
    testWidgets('delete icon present for each vault', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      expect(find.byIcon(Icons.delete_outlined), findsNWidgets(2));
    });

    testWidgets('tapping delete icon shows step 1 warning dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('Delete vault?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('step 1 dialog mentions vault alias', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Alpha'), findsWidgets);
    });

    testWidgets('cancelling step 1 does not call onDelete', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onDelete: (_) async => called = true,
      ));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('continuing step 1 shows step 2 confirm dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.text('Type DELETE to confirm'), findsOneWidget);
    });

    testWidgets('step 2 confirm button disabled until DELETE is typed',
        (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final confirmButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Confirm'),
      );
      expect(confirmButton.onPressed, isNull);
    });

    testWidgets('step 2 confirm button enabled when DELETE is typed',
        (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('delete_vault_confirm_field')),
        'DELETE',
      );
      await tester.pumpAndSettle();
      final confirmButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Confirm'),
      );
      expect(confirmButton.onPressed, isNotNull);
    });

    testWidgets('cancelling step 2 does not call onDelete', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onDelete: (_) async => called = true,
      ));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('confirming step 2 calls onDelete with correct path',
        (tester) async {
      String? deletedPath;
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onDelete: (p) async => deletedPath = p,
      ));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('delete_vault_confirm_field')),
        'DELETE',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(deletedPath, '/tmp/a.gabbro');
    });

    testWidgets('confirming step 2 removes vault from displayed list',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onDelete: (_) async {},
      ));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('delete_vault_confirm_field')),
        'DELETE',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });
  });
}
