import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_selector_screen.dart';
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
  bool showVaultList = true,
  void Function(String path, String alias)? onVaultSelected,
  VoidCallback? onAddVault,
  Future<void> Function(String path, String alias)? onRename,
  Future<void> Function(String path)? onRemove,
}) =>
    MaterialApp(
      home: VaultSelectorScreen(
        registry: registry,
        showVaultList: showVaultList,
        onVaultSelected: onVaultSelected ?? (_, _) {},
        onAddVault: onAddVault ?? () {},
        onRename: onRename,
        onRemove: onRemove,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final registry = VaultRegistry([
    _record(path: '/tmp/a.gabbro', alias: 'Alpha'),
    _record(path: '/tmp/b.gabbro', alias: 'Beta'),
  ]);

  // ── Vault list visibility ─────────────────────────────────────────────────

  group('vault list visibility', () {
    testWidgets('shows aliases when showVaultList is true', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry, showVaultList: true));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('hides vault list when showVaultList is false', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry, showVaultList: false));
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsNothing);
    });
  });

  // ── Add vault button ──────────────────────────────────────────────────────

  testWidgets('always shows Add vault button when list shown', (tester) async {
    await tester.pumpWidget(_buildScreen(registry: registry, showVaultList: true));
    expect(find.text('Add vault'), findsOneWidget);
  });

  testWidgets('always shows Add vault button when list hidden', (tester) async {
    await tester.pumpWidget(_buildScreen(registry: registry, showVaultList: false));
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

  // ── Vault selection ───────────────────────────────────────────────────────

  testWidgets('tapping vault row calls onVaultSelected with path and alias', (tester) async {
    String? selectedPath;
    String? selectedAlias;
    await tester.pumpWidget(_buildScreen(
      registry: registry,
      onVaultSelected: (p, a) {
        selectedPath = p;
        selectedAlias = a;
      },
    ));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(selectedPath, '/tmp/a.gabbro');
    expect(selectedAlias, 'Alpha');
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

    testWidgets('confirming empty alias does not call onRename', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onRename: (_, _) async => called = true,
      ));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('confirming valid alias calls onRename with path and new alias', (tester) async {
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
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(renamedPath, '/tmp/a.gabbro');
      expect(renamedAlias, 'New Name');
    });

    testWidgets('rename updates the displayed alias in the list', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onRename: (_, _) async {},
      ));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New Name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('New Name'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });
  });

  // ── Remove ────────────────────────────────────────────────────────────────

  group('remove', () {
    testWidgets('remove icon present for each vault', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(2));
    });

    testWidgets('tapping remove removes vault from list', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onRemove: (_) async {},
      ));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('tapping remove calls onRemove with correct path', (tester) async {
      String? removedPath;
      await tester.pumpWidget(_buildScreen(
        registry: registry,
        onRemove: (p) async => removedPath = p,
      ));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();
      expect(removedPath, '/tmp/a.gabbro');
    });
  });
}
