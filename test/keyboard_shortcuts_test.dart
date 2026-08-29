import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/import_failures_dialog.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/sync_review.dart';

import 'screen_catalog.dart';

// What each shortcut produces (focus, mode, result), which the keyboard_net
// sweep cannot assert. Escape on the sync review must roll back, not apply.

// --- Shared app harness for the global Ctrl+L shortcut (mirrors
// lock_timer_test): a registered temp vault, foreground lock set to never so the
// idle timer can't lock instead of the keystroke. ---------------------------

class _InitialScreen extends StatelessWidget {
  const _InitialScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('InitialScreen')));
}

Widget buildLockApp(String vaultPath) => GabbroApp(
  registry: VaultRegistry([
    VaultRecord(path: vaultPath, alias: 'KB Test', lastUsedAt: DateTime.now()),
  ]),
  vaultPath: vaultPath,
  settings: const AppSettings(foregroundLockTimeout: ForegroundLockTimeout.never),
  initialScreen: const _InitialScreen(),
);

Future<(String, Future<void> Function())> makeTempVault() async {
  final dir = await Directory.systemTemp.createTemp('gabbro_kb_test_');
  final file = File('${dir.path}/vault.gabbro');
  await file.create();
  return (file.path, () => dir.delete(recursive: true));
}

Future<void> sendCtrl(WidgetTester tester, LogicalKeyboardKey key,
    {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Text fields on screen that currently hold primary focus.
Iterable<EditableText> focusedFields(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .where((w) => w.focusNode.hasFocus);

void setSurface(WidgetTester tester, Surface surface) {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// A merge with one field clash, so there is a real step to review (and cancel).
MergeSummary conflictSummary() => const MergeSummary(
  added: 0,
  updated: 1,
  addedEntries: [],
  broughtOver: [],
  pendingDeletes: [],
  folderConflicts: [],
  fieldConflicts: [
    FieldConflictItem(
      id: 'e1',
      title: 'Mail',
      field: 'password',
      localValue: 'local-secret',
      incomingValue: 'incoming-secret',
    ),
  ],
  pendingItemDeletes: [],
);

void main() {
  group('Ctrl+L lock', () {
    late String vaultPath;
    late Future<void> Function() cleanup;
    setUp(() async => (vaultPath, cleanup) = await makeTempVault());
    tearDown(() async => cleanup());

    testWidgets('Ctrl+L locks the vault', (tester) async {
      await tester.pumpWidget(buildLockApp(vaultPath));
      expect(find.text('InitialScreen'), findsOneWidget);

      await sendCtrl(tester, LogicalKeyboardKey.keyL);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('InitialScreen'), findsNothing);
      expect(find.byType(UnlockScreen), findsOneWidget);
    });

    testWidgets('plain L does not lock', (tester) async {
      await tester.pumpWidget(buildLockApp(vaultPath));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('InitialScreen'), findsOneWidget);
      expect(find.byType(UnlockScreen), findsNothing);
    });
  });

  group('Ctrl+F search focus', () {
    testWidgets('Ctrl+F focuses the search field (phone)', (tester) async {
      setSurface(tester, phone);
      await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
      await tester.pump(const Duration(milliseconds: 300));

      await sendCtrl(tester, LogicalKeyboardKey.keyF);

      expect(focusedFields(tester), isNotEmpty,
          reason: 'Ctrl+F did not focus the search field');
      expect(find.byIcon(Icons.manage_search), findsNothing,
          reason: 'plain Ctrl+F must not turn on full-text mode');
    });

    testWidgets('Ctrl+Shift+F focuses search and turns on full-text mode',
        (tester) async {
      setSurface(tester, phone);
      await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
      await tester.pump(const Duration(milliseconds: 300));

      await sendCtrl(tester, LogicalKeyboardKey.keyF, shift: true);
      await tester.pump();

      expect(focusedFields(tester), isNotEmpty,
          reason: 'Ctrl+Shift+F did not focus the search field');
      expect(find.byIcon(Icons.manage_search), findsWidgets,
          reason: 'Ctrl+Shift+F must turn on full-text (all fields) mode');
    });

    testWidgets('Ctrl+F focuses the search field (tablet layout)',
        (tester) async {
      setSurface(tester, tablet);
      await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
      await tester.pump(const Duration(milliseconds: 300));

      await sendCtrl(tester, LogicalKeyboardKey.keyF);

      expect(focusedFields(tester), isNotEmpty,
          reason: 'Ctrl+F did not focus the search field on the tablet layout');
    });

    // Hardware bug: Ctrl+F worked once, then not - a screen-local shortcut dies
    // once focus leaves the screen subtree. Must keep working like Ctrl+L.
    testWidgets('Ctrl+F works again after focus leaves the field', (tester) async {
      setSurface(tester, phone);
      await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
      await tester.pump(const Duration(milliseconds: 300));

      await sendCtrl(tester, LogicalKeyboardKey.keyF);
      expect(focusedFields(tester), isNotEmpty, reason: 'first Ctrl+F');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(focusedFields(tester), isEmpty);

      await sendCtrl(tester, LogicalKeyboardKey.keyF);
      expect(focusedFields(tester), isNotEmpty,
          reason: 'Ctrl+F must work again after focus left the field');
    });

    testWidgets('Ctrl+F forces normal mode, Ctrl+Shift+F forces all-fields',
        (tester) async {
      setSurface(tester, phone);
      await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
      await tester.pump(const Duration(milliseconds: 300));

      await sendCtrl(tester, LogicalKeyboardKey.keyF, shift: true);
      await tester.pump();
      expect(find.byIcon(Icons.manage_search), findsWidgets,
          reason: 'Ctrl+Shift+F turns all-fields mode on');

      await sendCtrl(tester, LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(find.byIcon(Icons.manage_search), findsNothing,
          reason: 'plain Ctrl+F must reset to normal (title) search mode');
    });
  });

  // Both mirror Ctrl+L: a global handler routed to a vault-list hook, matched on
  // the PHYSICAL key. They exist so keyboard-only users can still reach the two
  // controls the region Tab-cycle deliberately excludes (the FAB / new entry and
  // the overflow menu). Both self-gate: inert behind a dialog / pushed route and
  // in selection mode. Layout labels are narrow / wide (two-pane) - Linux-only.
  group('Ctrl+N new entry and Ctrl+M menu', () {
    Future<void> pumpVaultList(WidgetTester tester, Surface surface) async {
      setSurface(tester, surface);
      await tester.pumpWidget(
          appShell(screens['vault_list']!(), textScale: 1.0));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // The type picker uses the Note type's icon; a login list entry uses the
    // lock icon, so this icon is unique to the open picker.
    final pickerOpen = find.byIcon(Icons.note_outlined);
    // The overflow menu's Export item icon - unique to the open menu.
    final menuOpen = find.byIcon(Icons.upload_outlined);

    testWidgets('Ctrl+N opens the new-entry type picker (narrow layout)',
        (tester) async {
      await pumpVaultList(tester, phone);
      expect(pickerOpen, findsNothing);
      await sendCtrl(tester, LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(pickerOpen, findsOneWidget, reason: 'Ctrl+N opens the type picker');
    });

    testWidgets('Ctrl+N opens the type picker (wide two-pane layout)',
        (tester) async {
      await pumpVaultList(tester, tablet);
      await sendCtrl(tester, LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(pickerOpen, findsOneWidget);
    });

    testWidgets('plain N does not open the type picker', (tester) async {
      await pumpVaultList(tester, phone);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(pickerOpen, findsNothing);
    });

    testWidgets('Ctrl+N works regardless of where focus is (global)',
        (tester) async {
      await pumpVaultList(tester, phone);
      await sendCtrl(tester, LogicalKeyboardKey.keyF); // focus the search field
      expect(focusedFields(tester), isNotEmpty);
      await sendCtrl(tester, LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(pickerOpen, findsOneWidget);
    });

    testWidgets('Ctrl+M opens the overflow menu (narrow layout)',
        (tester) async {
      await pumpVaultList(tester, phone);
      expect(menuOpen, findsNothing);
      await sendCtrl(tester, LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(menuOpen, findsOneWidget, reason: 'Ctrl+M opens the overflow menu');
    });

    testWidgets('Ctrl+M opens the overflow menu (wide two-pane layout)',
        (tester) async {
      await pumpVaultList(tester, tablet);
      await sendCtrl(tester, LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(menuOpen, findsOneWidget);
    });

    testWidgets('plain M does not open the menu', (tester) async {
      await pumpVaultList(tester, phone);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(menuOpen, findsNothing);
    });

    testWidgets('shortcuts are inert while a dialog / route is on top',
        (tester) async {
      await pumpVaultList(tester, phone);
      await sendCtrl(tester, LogicalKeyboardKey.keyN); // open picker (modal route)
      await tester.pumpAndSettle();
      expect(pickerOpen, findsOneWidget);
      await sendCtrl(tester, LogicalKeyboardKey.keyM); // must NOT open the menu
      await tester.pumpAndSettle();
      expect(menuOpen, findsNothing,
          reason: 'inert when the vault list is not the current route');
    });

    testWidgets('Ctrl+N and Ctrl+M are inert in selection mode', (tester) async {
      await pumpVaultList(tester, phone);
      await tester.tap(find.byIcon(Icons.checklist)); // enter selection mode
      await tester.pumpAndSettle();
      await sendCtrl(tester, LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(pickerOpen, findsNothing,
          reason: 'no new-entry picker in selection mode');
      await sendCtrl(tester, LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(menuOpen, findsNothing, reason: 'no menu in selection mode');
    });
  });

  // Same shape as Ctrl+N / Ctrl+M: a global handler routed to a vault-list hook,
  // matched on the PHYSICAL key, self-gating. It must open the SAME confirm
  // dialog as the menu's Quit item - an accidental keystroke must not end a live
  // session.
  group('Ctrl+Q lock and quit', () {
    Widget quitList(
      List<String> calls, {
      bool isAndroid = false,
      bool withEntry = false,
    }) =>
        appShell(
          VaultListScreen(
            vaultPath: '/tmp/probe.gabbro',
            isAndroid: isAndroid,
            yubikeyRecords: const [],
            listEntries: () => withEntry
                ? const [
                    EntrySummaryData(
                      id: 'e1',
                      entryType: 'login',
                      title: 'Alpha',
                      folder: '',
                      searchBlob: 'alpha',
                    ),
                  ]
                : const <EntrySummaryData>[],
            onLock: () => calls.add('lock'),
            onQuit: () => calls.add('quit'),
          ),
          textScale: 1.0,
        );

    Future<List<String>> pumpQuitList(
      WidgetTester tester, {
      bool isAndroid = false,
      bool withEntry = false,
    }) async {
      setSurface(tester, phone);
      final calls = <String>[];
      await tester.pumpWidget(
          quitList(calls, isAndroid: isAndroid, withEntry: withEntry));
      await tester.pump(const Duration(milliseconds: 300));
      return calls;
    }

    // The menu item's own dialog title - the same one Ctrl+Q must raise.
    Finder confirmDialog(WidgetTester tester) => find.text(
        AppLocalizations.of(tester.element(find.byType(VaultListScreen)))
            .quitConfirmTitle);

    testWidgets('Ctrl+Q opens the confirm dialog and quits nothing yet',
        (tester) async {
      final calls = await pumpQuitList(tester);
      await sendCtrl(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(confirmDialog(tester), findsOneWidget,
          reason: 'Ctrl+Q must raise the same confirm as the menu item');
      expect(calls, isEmpty, reason: 'nothing happens until it is confirmed');
    });

    testWidgets('confirming locks then exits', (tester) async {
      final calls = await pumpQuitList(tester);
      await sendCtrl(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Quit'));
      await tester.pumpAndSettle();

      expect(calls, ['lock', 'quit'],
          reason: 'keys must be wiped before the process exits');
    });

    testWidgets('cancelling neither locks nor exits', (tester) async {
      final calls = await pumpQuitList(tester);
      await sendCtrl(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
    });

    testWidgets('plain Q does nothing', (tester) async {
      final calls = await pumpQuitList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(confirmDialog(tester), findsNothing);
      expect(calls, isEmpty);
    });

    testWidgets('Ctrl+Q is inert on Android', (tester) async {
      final calls = await pumpQuitList(tester, isAndroid: true);
      await sendCtrl(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(confirmDialog(tester), findsNothing,
          reason: 'no physical keyboard on Android');
      expect(calls, isEmpty);
    });

    testWidgets('Ctrl+Q is inert in selection mode', (tester) async {
      final calls = await pumpQuitList(tester, withEntry: true);
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
      await sendCtrl(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(confirmDialog(tester), findsNothing);
      expect(calls, isEmpty);
    });

    testWidgets('Ctrl+Q is inert while another route is on top', (tester) async {
      final calls = await pumpQuitList(tester);
      await sendCtrl(tester, LogicalKeyboardKey.keyN); // type picker
      await tester.pumpAndSettle();
      await sendCtrl(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(confirmDialog(tester), findsNothing,
          reason: 'inert when the vault list is not the current route');
      expect(calls, isEmpty);
    });

    testWidgets('Ctrl+Q is inert once the vault list is gone', (tester) async {
      final calls = await pumpQuitList(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await sendCtrl(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the global hook must be cleared when the screen disposes');
      expect(calls, isEmpty);
    });
  });

  group('Escape cancels review dialogs', () {
    testWidgets('Escape cancels sync review SAFELY (rollback, no apply)',
        (tester) async {
      SyncReviewDecisions? result;
      var returned = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showSyncReview(
                    context: ctx,
                    steps: buildSyncReviewSteps(conflictSummary()),
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(returned, isTrue, reason: 'Escape did not close the sync review');
      expect(result, const SyncReviewDecisions(cancelled: true),
          reason: 'Escape must cancel-with-rollback, never apply a merge');
    });

    testWidgets('Escape closes the import-failures dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showImportFailuresDialog(ctx, const [
                  ImportFailureData(
                    title: 'Broken card',
                    category: 'creditcard',
                    reason: 'unparseable',
                    rawFields: [('card_number', '4111111111111111')],
                  ),
                ]),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'Escape did not close the import-failures dialog');
    });
  });
}
