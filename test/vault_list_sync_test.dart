import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MergeSummary _summary({
  int added = 0,
  int updated = 0,
  int deleted = 0,
  List<String> editSurvivedDelete = const [],
}) =>
    MergeSummary(
      added: added,
      updated: updated,
      deleted: deleted,
      editSurvivedDelete: editSurvivedDelete,
    );

Widget _buildScreen({
  required Future<MergeSummary> Function(String, List<int>) mergeVault,
  String? pickedPath,
}) =>
    MaterialApp(
      home: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: () => [],
        deleteVault: () async {},
        yubikeyRecords: [],
        onPickSyncFile: () async => pickedPath,
        mergeVault: mergeVault,
      ),
    );

Future<void> _openMenu(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('VaultListScreen sync flow', () {
    testWidgets('no dialog when file picker returns null', (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: null,
        mergeVault: (_, _) async => _summary(),
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(find.text('Sync from file'), findsNothing);
    });

    testWidgets('passphrase dialog appears after file is picked', (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async => _summary(),
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(find.text('Sync from file'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('/tmp/other.gabbro'), findsOneWidget);
    });

    testWidgets('Cancel dismisses dialog without calling mergeVault',
        (tester) async {
      bool mergeCalled = false;
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async {
          mergeCalled = true;
          return _summary();
        },
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(mergeCalled, isFalse);
      expect(find.text('Vault synced'), findsNothing);
    });

    testWidgets('identical vaults shows nothing-to-sync snackbar', (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async => _summary(),
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'passphrase',
      );
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nothing to sync'),
        findsOneWidget,
      );
    });

    testWidgets('successful merge shows synced snackbar', (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async => _summary(added: 3, updated: 1, deleted: 0),
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'passphrase',
      );
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Vault synced'), findsOneWidget);
      expect(find.textContaining('3 entries added'), findsOneWidget);
      expect(find.textContaining('1 updated'), findsOneWidget);
    });

    testWidgets('passphrase is passed to mergeVault', (tester) async {
      List<int>? capturedPassphrase;
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, passphrase) async {
          capturedPassphrase = passphrase;
          return _summary(added: 1);
        },
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'mypassword',
      );
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(capturedPassphrase, equals(utf8.encode('mypassword')));
    });

    testWidgets('passphrase mismatch shows error dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async =>
            throw Exception('decryption failed: wrong key or tampered ciphertext'),
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'wrongpassword',
      );
      await tester.tap(find.text('Sync'));
      // Use explicit pumps: cursor blink timer prevents pumpAndSettle from
      // settling while the passphrase dialog exit animation is in progress.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350)); // passphrase exit
      await tester.pump(const Duration(milliseconds: 350)); // error dialog enter

      expect(find.text('Sync failed'), findsOneWidget);
      expect(
        find.textContaining('different passphrase'),
        findsOneWidget,
      );
    });

    testWidgets('edit-survived-delete warning shown in result dialog',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async => _summary(
          added: 0,
          updated: 1,
          deleted: 0,
          editSurvivedDelete: ['GitHub'],
        ),
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'passphrase',
      );
      await tester.tap(find.text('Sync'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350)); // passphrase exit
      await tester.pump(const Duration(milliseconds: 350)); // result dialog enter

      expect(find.text('Vault synced'), findsOneWidget);
      expect(find.textContaining("'GitHub' was deleted"), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });
  });
}
