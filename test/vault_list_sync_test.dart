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
  List<PendingDeleteItem> pendingDeletes = const [],
  List<FolderConflictItem> folderConflicts = const [],
  List<FieldConflictItem> fieldConflicts = const [],
  List<PendingItemDeleteItem> pendingItemDeletes = const [],
}) =>
    MergeSummary(
      added: added,
      updated: updated,
      pendingDeletes: pendingDeletes,
      folderConflicts: folderConflicts,
      fieldConflicts: fieldConflicts,
      pendingItemDeletes: pendingItemDeletes,
    );

Widget _buildScreen({
  required Future<MergeSummary> Function(String, List<int>) mergeVault,
  String? pickedPath,
  Future<String?> Function()? onPickSyncFile,
  Future<void> Function(String, String, bool, String)? onResolveFieldConflict,
}) =>
    testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => [],
      yubikeyRecords: [],
      onPickSyncFile: onPickSyncFile ?? () async => pickedPath,
      mergeVault: mergeVault,
      // No-op by default so tests never reach the real FFI resolution path.
      onResolveFieldConflict: onResolveFieldConflict ?? (_, _, _, _) async {},
    ));

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

    // Sync-from-file has no manual path fallback, so an unavailable picker
    // (sandbox/no portal) must show the no-portal SnackBar, not crash and not
    // open the passphrase dialog.
    testWidgets('unavailable picker shows a SnackBar and opens no dialog',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        onPickSyncFile: () async => throw const SocketException('no bus'),
        mergeVault: (_, _) async => _summary(),
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            "File dialog unavailable here. The system file portal isn't reachable."),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsNothing,
          reason: 'the passphrase dialog must not open');
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

    // Net-first: pin the passphrase show/hide eye toggle so the later a11y
    // label work cannot regress the flip. Field starts obscured -> the eye
    // icon offers "show" (Icons.visibility); tapping flips to visibility_off.
    testWidgets('passphrase eye toggle flips in the sync dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async => _summary(),
      ));
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
        mergeVault: (_, _) async => _summary(added: 3, updated: 1),
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
      expect(find.textContaining('3 added'), findsOneWidget);
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

    testWidgets('pending delete shows Delete/Keep dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) async => _summary(
          pendingDeletes: [
            const PendingDeleteItem(id: 'uuid-1', title: 'Example'),
          ],
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
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Delete entry?'), findsOneWidget);
      expect(find.textContaining("'Example'"), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('folder conflict shows folder picker dialog', (tester) async {
      await tester.pumpWidget(_buildScreen(
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
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Folder conflict'), findsOneWidget);
      expect(find.textContaining("'Work note'"), findsOneWidget);
      expect(find.textContaining('Work'), findsWidgets);
      expect(find.textContaining('Personal'), findsWidgets);
    });

    testWidgets('field clash surfaces a keep/use-theirs dialog (not nothing-to-sync)',
        (tester) async {
      String? gotField;
      bool? gotKeepIncoming;
      await tester.pumpWidget(_buildScreen(
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
        onResolveFieldConflict: (id, field, keepIncoming, incomingValue) async {
          gotField = field;
          gotKeepIncoming = keepIncoming;
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
        'passphrase',
      );
      await tester.tap(find.text('Sync'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      // The clash is surfaced, not swallowed as "nothing to sync".
      expect(find.textContaining('Nothing to sync'), findsNothing);
      expect(find.text("Use the other device's value"), findsOneWidget);
      expect(find.textContaining("'Example'"), findsOneWidget);

      // Tapping Keep applies keep-mine (keepIncoming == false).
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(gotField, 'password');
      expect(gotKeepIncoming, false);
    });

    // A passphrase-only source never taps a YubiKey, so the "tap now" note must
    // not appear while the merge is in flight.
    testWidgets('passphrase-only sync shows no tap note', (tester) async {
      final mergeGate = Completer<MergeSummary>();
      await tester.pumpWidget(_buildScreen(
        pickedPath: '/tmp/other.gabbro',
        mergeVault: (_, _) => mergeGate.future,
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
              String, List<int>, List<int>, List<int>)
          mergeVaultWithKey,
      Future<YubikeyHmacMatch> Function(List<YubikeyRecordData>, String, String)?
          onGetSyncYubikeyHmac,
      bool isAndroid = false,
    }) =>
        testApp(VaultListScreen(
          vaultPath: '/tmp/test.gabbro',
          listEntries: () => [],
          yubikeyRecords: [],
          onPickSyncFile: () async => '/tmp/keyprotected.gabbro',
          // Passphrase-only merge must never be reached for a key-protected source.
          mergeVault: (_, _) async =>
              throw StateError('passphrase-only merge must not be called'),
          onDetectSyncSourceRecords: (_) => sourceRecords,
          onGetSyncYubikeyHmac: onGetSyncYubikeyHmac ??
              (records, pin, transport) async =>
                  (hmac: const [0x11], credentialId: const [0xA1]),
          mergeVaultWithKey: mergeVaultWithKey,
          isAndroid: isAndroid,
        ));

    testWidgets('transport selector follows NFC capability (Android)',
        (tester) async {
      addTearDown(() => nfcAvailable = false);

      nfcAvailable = false; // non-NFC tablet -> no USB/NFC selector
      await tester.pumpWidget(buildKeyProtectedScreen(
        mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
        isAndroid: true,
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();
      expect(find.text('NFC'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      nfcAvailable = true; // NFC present -> selector appears
      await tester.pumpWidget(buildKeyProtectedScreen(
        mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
        isAndroid: true,
      ));
      await _openMenu(tester);
      await tester.tap(find.text('Sync from file'));
      await tester.pumpAndSettle();
      expect(find.text('NFC'), findsOneWidget);
    });

    testWidgets('key-protected source prompts for YubiKey PIN', (tester) async {
      await tester.pumpWidget(buildKeyProtectedScreen(
        mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
      ));
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
    testWidgets('PIN eye toggle flips independently of the passphrase eye',
        (tester) async {
      await tester.pumpWidget(buildKeyProtectedScreen(
        mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
      ));
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
    testWidgets('sync dialog meets labelled-tap-target guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(buildKeyProtectedScreen(
        mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
      ));
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
      await tester.pumpWidget(buildKeyProtectedScreen(
        onGetSyncYubikeyHmac: (records, pin, transport) async =>
            (hmac: const [0x42], credentialId: const [0xAB]),
        mergeVaultWithKey: (path, passphrase, hmac, cred) async {
          capturedPassphrase = passphrase;
          capturedHmac = hmac;
          capturedCred = cred;
          return _summary(added: 2);
        },
      ));
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

      expect(capturedPassphrase, equals(utf8.encode('sharedpass')));
      expect(capturedHmac, equals(const [0x42]));
      expect(capturedCred, equals(const [0xAB]));
      expect(find.textContaining('Vault synced'), findsOneWidget);
    });

    testWidgets('missing PIN blocks the keyed merge', (tester) async {
      bool mergeCalled = false;
      await tester.pumpWidget(buildKeyProtectedScreen(
        mergeVaultWithKey: (_, _, _, _) async {
          mergeCalled = true;
          return _summary(added: 1);
        },
      ));
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
    testWidgets('key-protected sync shows the tap note then clears it',
        (tester) async {
      final tapGate = Completer<YubikeyHmacMatch>();
      await tester.pumpWidget(buildKeyProtectedScreen(
        onGetSyncYubikeyHmac: (_, _, _) => tapGate.future,
        mergeVaultWithKey: (_, _, _, _) async => _summary(added: 1),
      ));
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

      // Tap done: note gone, dialog closed, merge reported.
      expect(find.text('Tap your YubiKey now…'), findsNothing);
      expect(find.textContaining('Vault synced'), findsOneWidget);
    });

    // A failed tap (no key, wrong PIN, timeout) must clear the note, keep the
    // dialog open with the error, and never reach the merge.
    testWidgets('tap failure clears the note and shows the error in the dialog',
        (tester) async {
      bool mergeCalled = false;
      await tester.pumpWidget(buildKeyProtectedScreen(
        onGetSyncYubikeyHmac: (_, _, _) async =>
            throw Exception('no key tapped'),
        mergeVaultWithKey: (_, _, _, _) async {
          mergeCalled = true;
          return _summary(added: 1);
        },
      ));
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
    });
  });
}
