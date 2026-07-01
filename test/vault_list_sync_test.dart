import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/nfc_capability.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MergeSummary _summary({
  int added = 0,
  int updated = 0,
  List<AddedEntryItem> addedEntries = const [],
  List<BroughtOverItem> broughtOver = const [],
  List<PendingDeleteItem> pendingDeletes = const [],
  List<FolderConflictItem> folderConflicts = const [],
  List<FieldConflictItem> fieldConflicts = const [],
  List<PendingItemDeleteItem> pendingItemDeletes = const [],
}) => MergeSummary(
  added: added,
  updated: updated,
  addedEntries: addedEntries,
  broughtOver: broughtOver,
  pendingDeletes: pendingDeletes,
  folderConflicts: folderConflicts,
  fieldConflicts: fieldConflicts,
  pendingItemDeletes: pendingItemDeletes,
);

// Captures the single batched decision-set applied at the end of a granular
// review (one call for the whole review). Tests assert on the aggregated lists.
class _Applied {
  bool called = false;
  bool cancelCalled = false;
  List<SyncFieldResolutionInput> fields = const [];
  List<SyncHistoryReplacementInput> history = const [];
  List<SyncItemDeleteInput> items = const [];
  List<SyncFolderInput> folders = const [];
  List<String> entryDeletes = const [];
}

Widget _buildScreen({
  required Future<MergeSummary> Function(String, List<int>) mergeVault,
  Future<MergeSummary> Function(String, List<int>)? fastMergeVault,
  String? pickedPath,
  Future<String?> Function()? onPickSyncFile,
  _Applied? applied,
}) => testApp(
  VaultListScreen(
    vaultPath: '/tmp/test.gabbro',
    listEntries: () => [],
    yubikeyRecords: [],
    onPickSyncFile: onPickSyncFile ?? () async => pickedPath,
    mergeVault: mergeVault,
    fastMergeVault: fastMergeVault ?? (_, _) async => _summary(),
    // Recording stand-in so tests never reach the real FFI; captures the batch.
    applySyncDecisions:
        ({
          required fieldResolutions,
          required historyReplacements,
          required itemDeletes,
          required folders,
          required entryDeletes,
        }) async {
          if (applied != null) {
            applied.called = true;
            applied.fields = fieldResolutions;
            applied.history = historyReplacements;
            applied.items = itemDeletes;
            applied.folders = folders;
            applied.entryDeletes = entryDeletes;
          }
        },
    cancelSync: () async {
      if (applied != null) applied.cancelCalled = true;
    },
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

// Open the menu, start a file sync, enter the passphrase, and let the merge land
// (and the review dialog open, if any).
Future<void> _startSync(WidgetTester tester) async {
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
  // The Quick-vs-Review chooser now appears; take the granular review path so the
  // existing assertions (review dialog + per-decision apply) still hold.
  await tester.tap(find.text('Review all changes'));
  await _settle(tester);
}

// Discrete pumps rather than pumpAndSettle: a transient sync spinner makes
// pumpAndSettle time out.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('VaultListScreen sync flow', () {
    testWidgets('no dialog when file picker returns null', (tester) async {
      await tester.pumpWidget(
        _buildScreen(pickedPath: null, mergeVault: (_, _) async => _summary()),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(find.text('Sync from file'), findsNothing);
    });

    // Sync-from-file has no manual path fallback, so an unavailable picker
    // (sandbox/no portal) must show the no-portal SnackBar, not crash and not
    // open the passphrase dialog.
    testWidgets('unavailable picker shows a SnackBar and opens no dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          onPickSyncFile: () async => throw const SocketException('no bus'),
          mergeVault: (_, _) async => _summary(),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "File dialog unavailable here. The system file portal isn't reachable.",
        ),
        findsOneWidget,
      );
      expect(
        find.text('Cancel'),
        findsNothing,
        reason: 'the passphrase dialog must not open',
      );
    });

    testWidgets('passphrase dialog appears after file is picked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(find.text('Sync from file'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('/tmp/other.gabbro'), findsOneWidget);
    });

    testWidgets('Merge automatically runs the fast merge, no review dialog', (
      tester,
    ) async {
      var fastCalled = false;
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          // The review-path merge must NOT run when the user picks automatic.
          mergeVault: (_, _) async =>
              throw StateError('review merge must not run in fast mode'),
          fastMergeVault: (_, _) async {
            fastCalled = true;
            return _summary(added: 2, updated: 1);
          },
        ),
      );
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

      // The Quick-vs-Review chooser appears.
      expect(find.text('How should this sync apply?'), findsOneWidget);
      await tester.tap(find.text('Merge automatically'));
      await _settle(tester);

      expect(fastCalled, isTrue, reason: 'fast merge FFI must run');
      expect(
        find.text('Review changes  1/1'),
        findsNothing,
        reason: 'automatic merge shows no per-change review',
      );
      expect(
        find.text('Sync failed'),
        findsNothing,
        reason: 'the review-path merge must not have been called',
      );
      expect(find.textContaining('synced'), findsOneWidget);
    });

    testWidgets('passphrase dialog announces the safe-to-retry hint', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(find.textContaining('run it again'), findsOneWidget);
      // Exposed to screen readers, not just painted.
      expect(find.bySemanticsLabel(RegExp('run it again')), findsOneWidget);
      handle.dispose();
    });

    // Net-first: pin the passphrase show/hide eye toggle so the later a11y
    // label work cannot regress the flip. Field starts obscured -> the eye
    // icon offers "show" (Icons.visibility); tapping flips to visibility_off.
    testWidgets('passphrase eye toggle flips in the sync dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);
    });

    testWidgets('Cancel dismisses dialog without calling mergeVault', (
      tester,
    ) async {
      bool mergeCalled = false;
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async {
            mergeCalled = true;
            return _summary();
          },
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(mergeCalled, isFalse);
      expect(find.text('Vault synced'), findsNothing);
    });

    testWidgets('identical vaults shows nothing-to-sync snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(),
        ),
      );
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
      await tester.tap(find.text('Review all changes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing to sync'), findsOneWidget);
    });

    testWidgets('successful merge shows synced snackbar', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(added: 3, updated: 1),
        ),
      );
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
      await tester.tap(find.text('Review all changes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Vault synced'), findsOneWidget);
      expect(find.textContaining('3 added'), findsOneWidget);
      expect(find.textContaining('1 updated'), findsOneWidget);
    });

    testWidgets('granular snackbar offers a Details action after a review', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            addedEntries: [
              const AddedEntryItem(id: 'new-1', title: 'Bank login'),
            ],
          ),
        ),
      );
      await _startSync(tester);
      // One step (the new entry): keep the default, finish.
      await tester.tap(find.text('OK'));
      await _settle(tester);

      expect(find.textContaining('Vault synced'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Details'), findsOneWidget);
    });

    testWidgets('Details opens a dialog listing changed entries by group', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            addedEntries: [
              const AddedEntryItem(id: 'new-1', title: 'Bank login'),
            ],
            pendingDeletes: [
              const PendingDeleteItem(id: 'g', title: 'Old note'),
            ],
          ),
        ),
      );
      await _startSync(tester);
      // Step 1 (new entry): keep -> Continue. Step 2 (delete): confirm -> OK.
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Details'));
      await tester.pumpAndSettle();

      // Grouped list: the kept new entry under Added, the delete under Deleted.
      expect(find.textContaining('Bank login'), findsOneWidget);
      expect(find.textContaining('Old note'), findsOneWidget);
      expect(find.textContaining('Added'), findsWidgets);
      expect(find.textContaining('Deleted'), findsWidgets);
    });

    testWidgets('passphrase is passed to mergeVault', (tester) async {
      List<int>? capturedPassphrase;
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, passphrase) async {
            capturedPassphrase = passphrase;
            return _summary(added: 1);
          },
        ),
      );
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
      await tester.tap(find.text('Review all changes'));
      await tester.pumpAndSettle();

      expect(capturedPassphrase, equals(utf8.encode('mypassword')));
    });

    testWidgets('passphrase mismatch shows error dialog', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => throw Exception(
            'decryption failed: wrong key or tampered ciphertext',
          ),
        ),
      );
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review all changes'));
      // Use explicit pumps: cursor blink timer prevents pumpAndSettle from
      // settling while the passphrase dialog exit animation is in progress.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350)); // chooser exit
      await tester.pump(
        const Duration(milliseconds: 350),
      ); // error dialog enter

      expect(find.text('Sync failed'), findsOneWidget);
      expect(find.textContaining('different passphrase'), findsOneWidget);
    });

    testWidgets('whole-entry delete shows keep/delete chips in the review', (
      tester,
    ) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            pendingDeletes: [
              const PendingDeleteItem(id: 'uuid-1', title: 'Example'),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);

      expect(find.textContaining('Review changes'), findsOneWidget);
      expect(find.textContaining('Example'), findsOneWidget);

      // Pick Delete, then finish.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      expect(applied.entryDeletes, ['uuid-1']);
    });

    testWidgets('a kept whole-entry delete is not deleted', (tester) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            pendingDeletes: [
              const PendingDeleteItem(id: 'uuid-1', title: 'Example'),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);
      await tester.tap(find.text('OK')); // leave delete off (keep)
      await _settle(tester);
      expect(applied.entryDeletes, isEmpty);
    });

    testWidgets('folder conflict shows folder chips in the review', (
      tester,
    ) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            folderConflicts: [
              const FolderConflictItem(
                id: 'uuid-2',
                title: 'Work note',
                localFolder: 'Work',
                incomingFolder: 'Personal',
              ),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);

      expect(find.textContaining('Work note'), findsOneWidget);
      expect(find.text('Keep "Work"'), findsOneWidget);
      expect(find.text('Move to "Personal"'), findsOneWidget);

      // Must pick before finishing; pick the incoming folder.
      await tester.tap(find.text('Move to "Personal"'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      expect(applied.folders, [
        const SyncFolderInput(id: 'uuid-2', folder: 'Personal'),
      ]);
    });

    testWidgets(
      'field clash shows a pick in the review (not nothing-to-sync)',
      (tester) async {
        final applied = _Applied();
        await tester.pumpWidget(
          _buildScreen(
            pickedPath: '/tmp/other.gabbro',
            mergeVault: (_, _) async => _summary(
              fieldConflicts: [
                const FieldConflictItem(
                  id: 'uuid-3',
                  title: 'Example',
                  field: 'password',
                  localValue: 'mine',
                  incomingValue: 'theirs',
                ),
              ],
            ),
            applied: applied,
          ),
        );
        await _startSync(tester);

        expect(find.textContaining('Nothing to sync'), findsNothing);
        expect(
          find.textContaining('Use other vault'),
          findsOneWidget,
        );
        expect(find.textContaining('Example'), findsOneWidget);
        // A password is secret, so neither value is shown in the clear.
        expect(find.textContaining('mine'), findsNothing);
        expect(find.textContaining('theirs'), findsNothing);

        // Pick keep-mine, then finish (keepIncoming == false).
        await tester.tap(find.textContaining('Use this vault'));
        await _settle(tester);
        await tester.tap(find.text('OK'));
        await _settle(tester);
        expect(applied.fields.single.field, 'password');
        expect(applied.fields.single.keepIncoming, false);
      },
    );

    testWidgets('cancelling the review rolls back and applies nothing', (
      tester,
    ) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            addedEntries: [
              const AddedEntryItem(id: 'new-1', title: 'Bank login'),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);
      await tester.tap(find.text('Cancel')); // bail button
      await _settle(tester);
      await tester.tap(find.text('Cancel sync')); // chooser: discard
      await _settle(tester);

      expect(applied.cancelCalled, isTrue, reason: 'cancel FFI runs');
      expect(applied.called, isFalse, reason: 'no decisions applied on cancel');
      expect(find.textContaining('Sync cancelled'), findsOneWidget);
    });

    testWidgets('Merge the rest applies remaining changes incoming-wins', (
      tester,
    ) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            fieldConflicts: [
              const FieldConflictItem(
                id: 'x',
                title: 'Mail',
                field: 'username',
                localValue: 'mine',
                incomingValue: 'theirs',
              ),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);
      await tester.tap(find.text('Cancel')); // bail button
      await _settle(tester);
      await tester.tap(find.text('Merge automatically')); // finish rest fast
      await _settle(tester);

      expect(applied.cancelCalled, isFalse, reason: 'this commits, not cancels');
      expect(applied.called, isTrue, reason: 'decisions applied once');
      expect(applied.history.single.field, 'username');
      expect(applied.history.single.newValue, 'theirs');
    });

    testWidgets('a new entry can be dropped', (tester) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            addedEntries: [
              const AddedEntryItem(id: 'new-1', title: 'Bank login'),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);

      expect(find.textContaining('Bank login'), findsOneWidget);
      // Default is keep; pick Skip to drop.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Skip'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      expect(applied.entryDeletes, ['new-1']);
    });

    testWidgets('a kept new entry is not deleted', (tester) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            addedEntries: [const AddedEntryItem(id: 'new-1', title: 'Bank')],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      expect(applied.entryDeletes, isEmpty);
    });

    testWidgets(
      'a brought-over field can be dropped to restore the old value',
      (tester) async {
        final applied = _Applied();
        await tester.pumpWidget(
          _buildScreen(
            pickedPath: '/tmp/other.gabbro',
            mergeVault: (_, _) async => _summary(
              broughtOver: [
                const BroughtOverItem(
                  id: 'x',
                  title: 'Mail',
                  field: 'url',
                  oldValue: 'old.example.com',
                  newValue: 'new.example.com',
                ),
              ],
            ),
            applied: applied,
          ),
        );
        await _startSync(tester);

        expect(find.textContaining('Mail'), findsOneWidget);
        // A url is not secret, so the new value is visible.
        expect(find.textContaining('new.example.com'), findsOneWidget);
        // Drop it (uncheck).
        await tester.tap(find.textContaining('Use this vault'));
        await _settle(tester);
        await tester.tap(find.text('OK'));
        await _settle(tester);
        final r = applied.fields.single;
        expect(r.field, 'url');
        expect(
          r.keepIncoming,
          true,
          reason: 'restore sets the field to the old value',
        );
        expect(r.value, 'old.example.com');
      },
    );

    testWidgets('a kept brought-over edit retains the old value in history', (
      tester,
    ) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            broughtOver: [
              const BroughtOverItem(
                id: 'x',
                title: 'Mail',
                field: 'url',
                oldValue: 'a',
                newValue: 'b',
              ),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);
      await tester.tap(find.text('OK')); // keep (default)
      await _settle(tester);
      expect(applied.fields, isEmpty);
      final h = applied.history.single;
      expect(h.field, 'url');
      expect(h.newValue, 'b');
      expect(h.replacedValue, 'a', reason: 'old value goes to recovery history');
    });

    testWidgets('use-theirs keeps the losing local value in history', (
      tester,
    ) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            fieldConflicts: [
              const FieldConflictItem(
                id: 'x',
                title: 'Note',
                field: 'content',
                localValue: 'mine',
                incomingValue: 'theirs',
              ),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);
      await tester.tap(find.textContaining('Use other vault'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      final h = applied.history.single;
      expect(h.field, 'content');
      expect(h.newValue, 'theirs');
      expect(
        h.replacedValue,
        'mine',
        reason: 'the losing local value is recoverable',
      );
    });

    testWidgets('dropping a brought-over added pair removes it', (tester) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            broughtOver: [
              const BroughtOverItem(
                id: 'x',
                title: 'Mail',
                field: 'custom_fields:Tag',
                oldValue: '', // empty old -> a newly added pair
                newValue: 'blue',
              ),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);
      await tester.tap(find.textContaining('Use this vault')); // pick Revert = drop
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      final d = applied.items.single;
      expect(d.field, 'custom_fields:Tag');
      expect(d.delete, true, reason: 'a dropped add is removed, not restored');
    });

    testWidgets('a brought-over attachment shows its name', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            broughtOver: [
              const BroughtOverItem(
                id: 'x',
                title: 'Doc',
                field: 'attachments:uuid-9',
                oldValue: '',
                newValue: 'passport.pdf',
              ),
            ],
          ),
        ),
      );
      await _startSync(tester);
      expect(find.textContaining('passport.pdf'), findsOneWidget);
    });

    testWidgets('an item-delete shows keep/delete chips in the entry step', (
      tester,
    ) async {
      final applied = _Applied();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            pendingItemDeletes: [
              const PendingItemDeleteItem(
                id: 'x',
                title: 'Mail',
                field: 'custom_fields:OldNote',
              ),
            ],
          ),
          applied: applied,
        ),
      );
      await _startSync(tester);

      expect(find.textContaining('OldNote'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      final d = applied.items.single;
      expect(d.field, 'custom_fields:OldNote');
      expect(d.delete, true);
    });

    testWidgets('finishing is blocked until a clash is picked', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) async => _summary(
            addedEntries: [const AddedEntryItem(id: 'a', title: 'First')],
            fieldConflicts: [
              const FieldConflictItem(
                id: 'b',
                title: 'Second',
                field: 'content',
                localValue: 'm',
                incomingValue: 't',
              ),
            ],
          ),
        ),
      );
      await _startSync(tester);

      // Step 1 of 2: the new entry (Continue advances).
      expect(find.textContaining('First'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await _settle(tester);

      // Step 2: the clash. OK is disabled until a value is picked.
      expect(find.textContaining('Second'), findsOneWidget);
      TextButton okButton() => tester.widget<TextButton>(
        find.ancestor(of: find.text('OK'), matching: find.byType(TextButton)),
      );
      expect(okButton().onPressed, isNull);
      await tester.tap(find.textContaining('Use other vault'));
      await _settle(tester);
      expect(okButton().onPressed, isNotNull);
    });

    // A passphrase-only source never taps a YubiKey, so the "tap now" note must
    // not appear while the merge is in flight.
    testWidgets('passphrase-only sync shows no tap note', (tester) async {
      final mergeGate = Completer<MergeSummary>();
      await tester.pumpWidget(
        _buildScreen(
          pickedPath: '/tmp/other.gabbro',
          mergeVault: (_, _) => mergeGate.future,
        ),
      );
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

      expect(find.text('Tap your YubiKey now…'), findsNothing);

      mergeGate.complete(_summary());
      await tester.pumpAndSettle();
    });
  });

  // ── ADR-013: key-protected source sync ──────────────────────────────────────
  group('VaultListScreen key-protected sync flow', () {
    final sourceRecords = [
      YubikeyRecordData(
        credentialId: Uint8List.fromList([0xA1, 0xA1]),
        salt: Uint8List.fromList([0x12, 0x12]),
      ),
    ];

    Widget buildKeyProtectedScreen({
      required Future<MergeSummary> Function(
        String,
        List<int>,
        List<int>,
        List<int>,
      )
      mergeVaultWithKey,
      Future<YubikeyHmacMatch> Function(
        List<YubikeyRecordData>,
        String,
        String,
      )?
      onGetSyncYubikeyHmac,
      bool isAndroid = false,
    }) => testApp(
      VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: () => [],
        yubikeyRecords: [],
        onPickSyncFile: () async => '/tmp/keyprotected.gabbro',
        // Passphrase-only merge must never be reached for a key-protected source.
        mergeVault: (_, _) async =>
            throw StateError('passphrase-only merge must not be called'),
        // These tests take the granular review path; the fast keyed variant
        // should never fire.
        fastMergeVault: (_, _) async =>
            throw StateError('passphrase-only fast merge must not be called'),
        fastMergeVaultWithKey: (_, _, _, _) async =>
            throw StateError('fast keyed merge must not be called'),
        onDetectSyncSourceRecords: (_) => sourceRecords,
        onGetSyncYubikeyHmac:
            onGetSyncYubikeyHmac ??
            (records, pin, transport) async =>
                (hmac: const [0x11], credentialId: const [0xA1]),
        mergeVaultWithKey: mergeVaultWithKey,
        isAndroid: isAndroid,
      ),
    );

    testWidgets('transport selector follows NFC capability (Android)', (
      tester,
    ) async {
      addTearDown(() => nfcAvailable = false);

      nfcAvailable = false; // non-NFC tablet -> no USB/NFC selector
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
          isAndroid: true,
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();
      expect(find.text('NFC'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      nfcAvailable = true; // NFC present -> selector appears
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
          isAndroid: true,
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();
      expect(find.text('NFC'), findsOneWidget);
    });

    testWidgets('key-protected source prompts for YubiKey PIN', (tester) async {
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      // Both the passphrase and the YubiKey PIN field must be present.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        findsNWidgets(2),
      );
      expect(find.text('YubiKey PIN'), findsOneWidget);
    });

    // Net-first: pin the PIN eye toggle (key-protected mode adds a second eye
    // below the passphrase eye). Both start showing Icons.visibility; tapping
    // the PIN one (last) flips it to visibility_off, leaving the passphrase eye.
    testWidgets('PIN eye toggle flips independently of the passphrase eye', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.visibility).last);
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    // A11y: the passphrase + PIN eye toggles in the sync dialog (and the
    // add-entry FAB behind it) must carry semantic labels.
    testWidgets('sync dialog meets labelled-tap-target guideline', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('keyed merge receives tapped key material', (tester) async {
      List<int>? capturedHmac;
      List<int>? capturedCred;
      List<int>? capturedPassphrase;
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          onGetSyncYubikeyHmac: (records, pin, transport) async =>
              (hmac: const [0x42], credentialId: const [0xAB]),
          mergeVaultWithKey: (path, passphrase, hmac, cred) async {
            capturedPassphrase = passphrase;
            capturedHmac = hmac;
            capturedCred = cred;
            return _summary(added: 2);
          },
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'sharedpass');
      await tester.enterText(fields.at(1), '123456');
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review all changes'));
      await tester.pumpAndSettle();

      expect(capturedPassphrase, equals(utf8.encode('sharedpass')));
      expect(capturedHmac, equals(const [0x42]));
      expect(capturedCred, equals(const [0xAB]));
      expect(find.textContaining('Vault synced'), findsOneWidget);
    });

    testWidgets('missing PIN blocks the keyed merge', (tester) async {
      bool mergeCalled = false;
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          mergeVaultWithKey: (_, _, _, _) async {
            mergeCalled = true;
            return _summary(added: 1);
          },
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      // Enter passphrase but leave the PIN empty, then try to sync.
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .at(0),
        'sharedpass',
      );
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(mergeCalled, isFalse);
      // The dialog stays open with a PIN-required error.
      expect(find.text('Sync'), findsOneWidget);
    });

    // The key tap runs while the sync dialog stays open; mirror the import
    // screen by showing the inline "tap your YubiKey now" note under the PIN
    // field, then clearing it once the tap returns and the merge runs.
    testWidgets('key-protected sync shows the tap note then clears it', (
      tester,
    ) async {
      final tapGate = Completer<YubikeyHmacMatch>();
      await tester.pumpWidget(
        buildKeyProtectedScreen(
          onGetSyncYubikeyHmac: (_, _, _) => tapGate.future,
          mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
        ),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'sharedpass');
      await tester.enterText(fields.at(1), '123456');
      await tester.tap(find.text('Sync'));
      await tester.pump();

      // The note shows inside the still-open dialog while the tap is awaited.
      expect(find.text('Tap your YubiKey now…'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      tapGate.complete((hmac: const [0x11], credentialId: const [0xA1]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review all changes'));
      await tester.pumpAndSettle();

      // Tap done: note gone, dialog closed, merge reported.
      expect(find.text('Tap your YubiKey now…'), findsNothing);
      expect(find.textContaining('Vault synced'), findsOneWidget);
    });

    // A failed tap (no key, wrong PIN, timeout) must clear the note, keep the
    // dialog open with the error, and never reach the merge.
    testWidgets(
      'tap failure clears the note and shows the error in the dialog',
      (tester) async {
        bool mergeCalled = false;
        await tester.pumpWidget(
          buildKeyProtectedScreen(
            onGetSyncYubikeyHmac: (_, _, _) async =>
                throw Exception('no key tapped'),
            mergeVaultWithKey: (_, _, _, _) async {
              mergeCalled = true;
              return _summary(added: 1);
            },
          ),
        );
        await _openMenu(tester);
        await tester.tap(find.text('Sync from file'));
        await tester.pumpAndSettle();

        final fields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(fields.at(0), 'sharedpass');
        await tester.enterText(fields.at(1), '123456');
        await tester.tap(find.text('Sync'));
        await tester.pumpAndSettle();

        expect(find.text('Tap your YubiKey now…'), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('no key tapped'), findsOneWidget);
        expect(mergeCalled, isFalse);
      },
    );
  });
}
