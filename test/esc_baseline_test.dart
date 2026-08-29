import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'test_helpers.dart';

// NET-FIRST baseline (do NOT delete): freezes the CURRENT Esc / focus behaviour
// of inline dialogs, so the global-Esc change can only IMPROVE it, never
// silently regress a dialog that already worked. Each pin documents what is
// true; change a pin only when its behaviour is deliberately changed (and say
// so in the commit).

void main() {
  testWidgets(
    'BASELINE: a default dialog closes on Esc; barrierDismissible:false ignores it',
    (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (ctx) => Scaffold(
          body: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => const AlertDialog(content: Text('dismissible')),
                ),
                child: const Text('open-yes'),
              ),
              ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (_) => const AlertDialog(content: Text('sticky')),
                ),
                child: const Text('open-no'),
              ),
            ],
          ),
        ),
      )));

      await tester.tap(find.text('open-yes'));
      await tester.pumpAndSettle();
      expect(find.text('dismissible'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('dismissible'), findsNothing,
          reason: 'a default (dismissible) dialog closes on Esc today');

      await tester.tap(find.text('open-no'));
      await tester.pumpAndSettle();
      expect(find.text('sticky'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('sticky'), findsOneWidget,
          reason: 'barrierDismissible:false ignores Esc today (sync-setup case)');
    },
  );

  testWidgets('BASELINE: the Quit confirm dialog closes on Esc today',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      isAndroid: false,
      listEntries: () => const <EntrySummaryData>[],
      onQuit: () {},
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Quit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quit'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'Quit confirm (default barrierDismissible) closes on Esc today');
  });

  testWidgets(
    'BASELINE: the sync-from-file setup dialog ignores Esc today',
    (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            // mirrors vault_list_screen.dart:792 (barrierDismissible: false).
            onPressed: () => showDialog<SyncCredentials>(
              context: ctx,
              barrierDismissible: false,
              builder: (_) => SyncPassphraseDialog(
                filePath: '/tmp/incoming.gabbro',
                sourceRecords: const <YubikeyRecordData>[],
                onGetYubikeyHmac: (records, pin, transport) async =>
                    throw UnimplementedError(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      )));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SyncPassphraseDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SyncPassphraseDialog), findsOneWidget,
          reason: 'the sync-setup dialog does not respond to Esc today (round-2 finding)');
    },
  );

  // The "Esc does not blur the search field" baseline flipped in Phase 1: Esc
  // now blurs it. That behaviour is pinned in keyboard_global_esc_test.dart.
}
