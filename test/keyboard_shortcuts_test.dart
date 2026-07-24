import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/import_failures_dialog.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/sync_review.dart';

import 'screen_catalog.dart';

// Behaviour tests for the desktop keyboard shortcuts (canon-TDD phase):
//   A. Ctrl+L locks the vault from anywhere.
//   B. Ctrl+F focuses the vault-list search; Ctrl+Shift+F also turns on
//      full-text ("all fields") mode. Both phone and tablet layouts.
//   C. Escape cancels the two barrierDismissible:false review dialogs — and for
//      sync review it must cancel SAFELY (roll back, apply nothing).
//
// The keyboard_net sweep proves Escape dismisses dialogs generally; these add
// the value assertions a sweep can't: what focus/mode/result each shortcut
// produces.

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
  // ── A. Ctrl+L locks ──────────────────────────────────────────────────────
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

  // ── B. Ctrl+F search focus (both layouts) ────────────────────────────────
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
  });

  // ── C. Escape cancels the review dialogs ─────────────────────────────────
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
