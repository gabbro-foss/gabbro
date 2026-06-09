import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/vault_registry.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

VaultRecord _record({
  String path = '/tmp/test.gabbro',
  String alias = 'Test',
  VaultType type = VaultType.passphrase,
}) =>
    VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
      type: type,
    );

YubikeyRecordData _fakeYkRecord() => YubikeyRecordData(
      credentialId: Uint8List.fromList([1, 2, 3, 4]),
      salt: Uint8List(32),
    );

Widget _buildScreen({
  required VaultRegistry registry,
  String? activeVaultPath,
  Future<void> Function(String path, String alias)? onRename,
  Future<void> Function(String path)? onDelete,
  VoidCallback? onAddVault,
  void Function(String path, String alias)? onSwitchToVault,
  Future<void> Function(List<int>, List<int>, String, String)? onConfirmYubikey,
  Future<void> Function(List<YubikeyRecordData>, String, String)? onConfirmAnyYubikey,
  List<YubikeyRecordData> Function(String path)? listYubikeyRecords,
}) =>
    testApp(ManageVaultsScreen(
      registry: registry,
      activeVaultPath: activeVaultPath,
      onRename: onRename ?? (_, _) async {},
      onDelete: onDelete ?? (_) async {},
      onAddVault: onAddVault ?? () {},
      onSwitchToVault: onSwitchToVault ?? (_, _) {},
      onConfirmYubikey: onConfirmYubikey ?? (_, _, _, _) async {},
      onConfirmAnyYubikey: onConfirmAnyYubikey ?? (_, _, _) async {},
      listYubikeyRecords: listYubikeyRecords ?? (_) => [],
    ));

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

  // ── YubiKey delete flow ───────────────────────────────────────────────────

  Future<void> throughStep2(WidgetTester tester) async {
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
  }

  group('YubiKey delete step 3', () {
    final ykRegistry = VaultRegistry([
      _record(path: '/tmp/a.gabbro', alias: 'Alpha', type: VaultType.yubikey),
      _record(path: '/tmp/b.gabbro', alias: 'Beta'),
    ]);

    testWidgets('step 1 mentions YubiKey binding for YubiKey vault', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [_fakeYkRecord()],
      ));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('YubiKey binding'), findsOneWidget);
    });

    testWidgets('step 1 does not mention YubiKey for passphrase vault', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [],
      ));
      await tester.tap(find.byIcon(Icons.delete_outlined).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('YubiKey'), findsNothing);
    });

    testWidgets('shows step 3 YubiKey dialog after step 2 for YubiKey vault', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [_fakeYkRecord()],
      ));
      await throughStep2(tester);
      expect(find.text('Touch your YubiKey'), findsOneWidget);
      expect(
        find.text('Enter your PIN and touch your YubiKey to authorize this deletion.'),
        findsOneWidget,
      );
    });

    testWidgets('passphrase vault skips step 3', (tester) async {
      var deleteCalled = false;
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [],
        onDelete: (_) async => deleteCalled = true,
      ));
      await throughStep2(tester);
      expect(find.text('Touch your YubiKey'), findsNothing);
      expect(deleteCalled, isTrue);
    });

    testWidgets('single-key: calls onConfirmYubikey then onDelete on authorize', (tester) async {
      bool confirmCalled = false;
      bool deleteCalled = false;
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [_fakeYkRecord()],
        onConfirmYubikey: (_, _, _, _) async => confirmCalled = true,
        onDelete: (_) async => deleteCalled = true,
      ));
      await throughStep2(tester);
      await tester.enterText(
        find.byKey(const Key('delete_vault_yubikey_pin_field')),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Authorize'));
      await tester.pumpAndSettle();
      expect(confirmCalled, isTrue);
      expect(deleteCalled, isTrue);
    });

    testWidgets('multi-key: calls onConfirmAnyYubikey then onDelete on authorize', (tester) async {
      bool confirmAnyCalled = false;
      bool deleteCalled = false;
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [_fakeYkRecord(), _fakeYkRecord()],
        onConfirmAnyYubikey: (_, _, _) async => confirmAnyCalled = true,
        onDelete: (_) async => deleteCalled = true,
      ));
      await throughStep2(tester);
      await tester.enterText(
        find.byKey(const Key('delete_vault_yubikey_pin_field')),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Authorize'));
      await tester.pumpAndSettle();
      expect(confirmAnyCalled, isTrue);
      expect(deleteCalled, isTrue);
    });

    testWidgets('cancelling step 3 does not call onDelete', (tester) async {
      var deleteCalled = false;
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [_fakeYkRecord()],
        onDelete: (_) async => deleteCalled = true,
      ));
      await throughStep2(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleteCalled, isFalse);
    });

    testWidgets('a failed YubiKey authorization does not delete (ADR-012 invariant)',
        (tester) async {
      var deleteCalled = false;
      await tester.pumpWidget(_buildScreen(
        registry: ykRegistry,
        listYubikeyRecords: (_) => [_fakeYkRecord()],
        onConfirmYubikey: (_, _, _, _) async => throw Exception('wrong key'),
        onDelete: (_) async => deleteCalled = true,
      ));
      await throughStep2(tester);
      await tester.enterText(
        find.byKey(const Key('delete_vault_yubikey_pin_field')),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Authorize'));
      await tester.pumpAndSettle();
      expect(deleteCalled, isFalse,
          reason: 'a wrong/absent YubiKey must refuse deletion of a YubiKey vault');
    });
  });

  // ── Active-vault delete gating (ADR-012) ──────────────────────────────────
  //
  // The active vault may only be deleted when it is the sole one. While other
  // vaults exist its delete is blocked (a message explains why), so deletion
  // never navigates toward another vault and cannot leak its alias under
  // show_vault_list = OFF.
  group('active-vault delete gating (ADR-012)', () {
    final twoVaults = VaultRegistry([
      _record(path: '/tmp/a.gabbro', alias: 'Alpha'),
      _record(path: '/tmp/b.gabbro', alias: 'Beta'),
    ]);

    Finder deleteFor(String alias) => find.descendant(
          of: find.widgetWithText(ListTile, alias),
          matching: find.byIcon(Icons.delete_outlined),
        );

    testWidgets('active vault delete is blocked when others exist', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: twoVaults,
        activeVaultPath: '/tmp/a.gabbro', // Alpha is the active vault
      ));
      await tester.tap(deleteFor('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Delete vault?'), findsNothing,
          reason: 'the delete confirmation must not open for the active vault');
      expect(find.text('Open another vault to delete this one'), findsWidgets,
          reason: 'a message explains why deletion is blocked');
    });

    testWidgets('non-active vault delete is allowed when others exist', (tester) async {
      await tester.pumpWidget(_buildScreen(
        registry: twoVaults,
        activeVaultPath: '/tmp/a.gabbro', // Alpha active -> Beta is deletable
      ));
      await tester.tap(deleteFor('Beta'));
      await tester.pumpAndSettle();
      expect(find.text('Delete vault?'), findsOneWidget);
    });

    testWidgets('the sole vault may be deleted even though it is active',
        (tester) async {
      final soleVault =
          VaultRegistry([_record(path: '/tmp/a.gabbro', alias: 'Alpha')]);
      await tester.pumpWidget(_buildScreen(
        registry: soleVault,
        activeVaultPath: '/tmp/a.gabbro',
      ));
      await tester.tap(deleteFor('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Delete vault?'), findsOneWidget,
          reason: 'the last remaining vault deletes (then falls back to onboarding)');
    });
  });

  // ── Backup + emergency-wipe info (ADR-012) ────────────────────────────────
  group('backup & emergency-wipe info', () {
    testWidgets('info icon opens the backup + emergency-wipe dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(registry: registry));
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.text('Backups & emergency wipe'), findsWidgets);
      expect(find.textContaining('Gabbro does not back up'), findsOneWidget);
      // On the Linux host the Linux wipe instructions + commands are shown.
      expect(find.textContaining('rm -rf'), findsOneWidget,
          reason: 'the verbatim emergency-wipe commands are shown on desktop');
    });
  });
}
