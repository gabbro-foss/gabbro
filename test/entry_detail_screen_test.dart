import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'test_helpers.dart';
import 'package:gabbro/autotype_target.dart';
import 'package:gabbro/gabbro_file_picker.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';
import 'package:gabbro/clipboard_clear.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/text_scale.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

LoginEntryData _loginEntry() => LoginEntryData(
      id: 'test-id-1',
      title: 'Gneiss Bank',
      url: 'https://gneiss.example.com',
      username: 'user@example.com',
      password: 's3cr3tP@ss',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );

NoteEntryData _noteEntry() => NoteEntryData(
      id: 'test-id-2',
      title: 'Basalt Notes',
      content: 'Some important note content.',
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      customFields: const [],
    );

CardEntryData _cardEntry() => CardEntryData(
      id: 'card-id-1',
      cardholderName: 'Alex Doe',
      cardNumber: '4111111111111111',
      expiry: '12/28',
      cvv: '123',
      status: 'active',
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
      customFields: const [],
    );

CustomEntryData _customEntry() => CustomEntryData(
      id: 'custom-id-1',
      title: 'My Custom Secret',
      fields: const [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen(
  VaultEntryData entry, {
  Future<void> Function(String id)? onDeleteEntry,
  ClipboardClearTimeout clipboardClearTimeout =
      ClipboardClearTimeout.sixtySeconds,
  Future<UrlOpenResult> Function(String url)? onLaunchUrl,
  Future<String?> Function(String filename)? exportFilePicker,
  Future<List<HistoryRecordData>> Function(String id)? onFetchHistory,
  bool isAndroid = false,
}) =>
    testApp(EntryDetailScreen(
      entry: entry,
      isAndroid: isAndroid,
      onDeleteEntry: onDeleteEntry ?? (_) async {},
      clipboardClearTimeout: clipboardClearTimeout,
      onLaunchUrl: onLaunchUrl ?? (_) async => UrlOpenResult.opened,
      exportFilePicker: exportFilePicker ?? (_) async => null,
      onFetchHistory: onFetchHistory ?? (_) async => const [],
    ));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('formatTimestamp', () {
    setUpAll(() => initializeDateFormatting('en'));

    test('formats valid ISO 8601 UTC string', () {
      final dt = DateTime.parse('2025-04-21T14:32:07Z').toLocal();
      final expected = DateFormat('d MMM yyyy, HH:mm', 'en').format(dt);
      expect(formatTimestamp('2025-04-21T14:32:07Z'), expected);
    });

    test('returns Unknown for empty string', () {
      expect(formatTimestamp(''), 'Unknown');
    });

    test('returns Unknown for invalid string', () {
      expect(formatTimestamp('not-a-date'), 'Unknown');
    });
  });

  group('auto-type target registration (ADR-017)', () {
    setUp(autotypeTarget.clear);
    tearDown(autotypeTarget.clear);

    testWidgets('opening a Login detail registers it as the target',
        (tester) async {
      await tester.pumpWidget(_buildScreen(VaultEntryData.login(_loginEntry())));
      expect(autotypeTarget.loginId, 'test-id-1');
    });

    testWidgets('opening a non-Login detail leaves the target unset',
        (tester) async {
      await tester.pumpWidget(_buildScreen(VaultEntryData.card(_cardEntry())));
      expect(autotypeTarget.loginId, isNull);
    });

    testWidgets('disposing the Login detail clears the target', (tester) async {
      await tester.pumpWidget(_buildScreen(VaultEntryData.login(_loginEntry())));
      expect(autotypeTarget.loginId, 'test-id-1');
      // Replace the tree so the detail screen is disposed.
      await tester.pumpWidget(const SizedBox());
      expect(autotypeTarget.loginId, isNull);
    });
  });

  testWidgets('recovery-history tile appears when history exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onFetchHistory: (_) async => [
          const HistoryRecordData(
            field: 'password',
            value: 'old',
            savedAt: '2025-01-02T00:00:00Z',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.history), findsOneWidget);
  });

  testWidgets('no recovery-history tile when history is empty', (tester) async {
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onFetchHistory: (_) async => const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.history), findsNothing);
  });

  testWidgets('login entry renders fields correctly', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.text('Gneiss Bank'), findsWidgets);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('s3cr3tP@ss'), findsNothing);
  });

  testWidgets('toggle button reveals password', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.text('••••••••'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();

    expect(find.text('s3cr3tP@ss'), findsOneWidget);
    expect(find.text('••••••••'), findsNothing);
  });

  testWidgets('breakdown button appears on the revealed password and opens the sheet',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );
    // Hidden -> no breakdown affordance.
    expect(find.byKey(const Key('breakdown_button')), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();
    expect(find.byKey(const Key('breakdown_button')), findsOneWidget);

    // ADR-015: announced as a button with an accessible name (its tooltip),
    // not a bare "button".
    expect(find.byTooltip('Password breakdown'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('breakdown_button')))
          .flagsCollection
          .isButton,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('breakdown_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordBreakdownSheet), findsOneWidget);
    handle.dispose();
  });

  testWidgets('card fields never show the breakdown button, even when revealed',
      (tester) async {
    await tester.pumpWidget(_buildScreen(VaultEntryData.card(_cardEntry())));
    // Reveal every obscured card field (number / CVV / PIN).
    while (find.byIcon(Icons.visibility_off).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.visibility_off).first);
      await tester.pump();
    }
    expect(find.byKey(const Key('breakdown_button')), findsNothing);
  });

  testWidgets('copy button shows copied snackbar', (tester) async {
    recordClipboardWrites(tester); // the copy now goes through the real channel
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Copied'), findsOneWidget);
    clipboardWiper.cancelPending(); // this test is about the snackbar, not the wipe
  });

  // Round 26 (Orca): copying from the detail pane said nothing — the snackbar
  // that confirms it is invisible to a Linux screen reader, which reads only a
  // node's name and never sees a snackbar appear. Copying moves no focus, so an
  // announcement of the same text has nothing competing with it.
  testWidgets('copying says so out loud', (tester) async {
    final said = recordAnnouncements(tester);
    recordClipboardWrites(tester);
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pumpAndSettle();

    expect(
      said.where((s) => s.contains('Copied')),
      hasLength(1),
      reason: 'nothing tells a screen-reader user the copy happened: $said',
    );
    clipboardWiper.cancelPending(); // about the announcement, not the wipe
  });

  testWidgets('Android: copying announces nothing', (tester) async {
    final said = recordAnnouncements(tester);
    recordClipboardWrites(tester);
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry()), isAndroid: true),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pumpAndSettle();

    expect(
      said,
      isEmpty,
      reason: 'TalkBack reads the snackbar itself and drops its queue for an '
          'announcement: $said',
    );
    clipboardWiper.cancelPending(); // about the announcement, not the wipe
  });

  testWidgets('delete icon shows confirmation dialog', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete entry?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);
  });

  testWidgets('copy button snackbar mentions clear timeout', (tester) async {
    recordClipboardWrites(tester);
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        clipboardClearTimeout: ClipboardClearTimeout.thirtySeconds,
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('30s'), findsOneWidget);
    clipboardWiper.cancelPending(); // about the snackbar text, not the wipe
  });

  testWidgets('copy snackbar says "never clears" when timeout is never',
      (tester) async {
    recordClipboardWrites(tester);
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        clipboardClearTimeout: ClipboardClearTimeout.never,
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('never'), findsOneWidget);
  });

  // ── Clipboard auto-clear (net-first pin, ADR-017 Phase 3.1) ───────────────
  // These pin the *actual* clear (existing tests only checked the snackbar
  // label). The copy goes through the injected stub, so the only writes that
  // reach the platform channel are the auto-clear's empty writes.

  testWidgets('copy clears the clipboard after a finite timeout',
      (tester) async {
    final writes = recordClipboardWrites(tester);
    await tester.pumpWidget(_buildScreen(
      VaultEntryData.login(_loginEntry()),
      clipboardClearTimeout: ClipboardClearTimeout.thirtySeconds,
    ));
    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pump(); // run the async copy + register the clear timer
    expect(writes, isNot(contains('')), reason: 'must not clear immediately');
    await tester.pump(const Duration(seconds: 30));
    expect(writes, contains(''),
        reason: 'clipboard is emptied when the timer fires');
  });

  testWidgets('copy never clears the clipboard when timeout is never',
      (tester) async {
    final writes = recordClipboardWrites(tester);
    await tester.pumpWidget(_buildScreen(
      VaultEntryData.login(_loginEntry()),
      clipboardClearTimeout: ClipboardClearTimeout.never,
    ));
    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(writes, isNot(contains('')),
        reason: 'a never timeout must not clear the clipboard');
  });

  testWidgets('re-copying resets the clear timer', (tester) async {
    final writes = recordClipboardWrites(tester);
    await tester.pumpWidget(_buildScreen(
      VaultEntryData.login(_loginEntry()),
      clipboardClearTimeout: ClipboardClearTimeout.thirtySeconds,
    ));
    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await tester.tap(find.byIcon(Icons.copy_outlined).first); // cancels first
    await tester.pump();
    // 35s since the first copy (its timer would have fired at 30s), but only
    // 20s since the second: nothing should have cleared yet.
    await tester.pump(const Duration(seconds: 20));
    expect(writes, isNot(contains('')),
        reason: 'the first timer was cancelled and the second has not elapsed');
    await tester.pump(const Duration(seconds: 15)); // 35s since the second copy
    expect(writes, contains(''),
        reason: 'the reset timer clears once it elapses');
  });

  testWidgets('timestamps section shows Created and Updated labels',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
  });

  testWidgets('folder label shows folder name when entry has a folder',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
  });

  testWidgets('folder label shows None when entry folder is empty',
      (tester) async {
    final entry = LoginEntryData(
      id: 'test-id-folder',
      title: 'Schist Service',
      url: 'https://schist.example.com',
      username: 'user@example.com',
      password: 'p@ss',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(entry)),
    );

    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('note entry renders title and content', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.note(_noteEntry())),
    );

    expect(find.text('Basalt Notes'), findsWidgets);
    expect(find.text('Some important note content.'), findsOneWidget);
  });

  testWidgets('onDeleted callback is called on delete confirm when provided',
      (tester) async {
    bool deletedCalled = false;
    bool deleteEntryCalled = false;
    await tester.pumpWidget(
      testApp(EntryDetailScreen(
        entry: VaultEntryData.login(_loginEntry()),
        onDeleteEntry: (_) async { deleteEntryCalled = true; },
        onDeleted: () { deletedCalled = true; },
      )),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleteEntryCalled, isTrue);
    expect(deletedCalled, isTrue);
  });

  testWidgets('Navigator.pop called on delete confirm when onDeleted is null',
      (tester) async {
    bool deleteEntryCalled = false;
    bool popped = false;
    await tester.pumpWidget(
      testApp(Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EntryDetailScreen(
                  entry: VaultEntryData.login(_loginEntry()),
                  onDeleteEntry: (_) async { deleteEntryCalled = true; },
                ),
              ),
            );
            popped = true;
          },
          child: const Text('Open'),
        ),
      )),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleteEntryCalled, isTrue);
    expect(popped, isTrue);
  });

  // Round 19 proved the two-pane delete fault: the layout drops the detail
  // pane the moment the entry leaves the filtered list, so by the time the
  // vault delete returns this screen is gone and the parent is never told —
  // the row sits in the list until something else forces a reload. The parent
  // callback must not depend on this screen surviving; only the Navigator use
  // below does.
  testWidgets('the parent is still told when the detail pane is torn down '
      'mid-delete', (tester) async {
    final deleteRunning = Completer<void>();
    int deletedCalls = 0;
    await tester.pumpWidget(
      testApp(EntryDetailScreen(
        entry: VaultEntryData.login(_loginEntry()),
        onDeleteEntry: (_) => deleteRunning.future,
        onDeleted: () => deletedCalls++,
      )),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump(); // dialog closes; the vault delete is still running

    // What the two-pane layout does while the delete is in flight.
    await tester.pumpWidget(testApp(const SizedBox.shrink()));
    deleteRunning.complete();
    await tester.pumpAndSettle();

    expect(deletedCalls, 1,
        reason: 'the parent must be told exactly once, mounted or not');
  });

  testWidgets('a detail route torn down mid-delete does not try to navigate',
      (tester) async {
    final deleteRunning = Completer<void>();
    await tester.pumpWidget(
      testApp(Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EntryDetailScreen(
                entry: VaultEntryData.login(_loginEntry()),
                onDeleteEntry: (_) => deleteRunning.future,
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      )),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();

    // A bare root, not another app shell: a pushed route survives a swap that
    // keeps the same Navigator, so the screen would never actually go away.
    await tester.pumpWidget(const SizedBox.shrink());
    deleteRunning.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'navigating from a dead context must not throw');
  });

  testWidgets('URL field shows launch icon when URL is non-empty',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.byIcon(Icons.open_in_browser_outlined), findsOneWidget);
  });

  testWidgets('tapping launch icon shows confirmation dialog', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    await tester.tap(find.byIcon(Icons.open_in_browser_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Open in browser?'), findsOneWidget);
    expect(find.text('https://gneiss.example.com'), findsWidgets);
  });

  testWidgets('confirming launch dialog calls onLaunchUrl', (tester) async {
    String? launched;
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onLaunchUrl: (url) async {
          launched = url;
          return UrlOpenResult.opened;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.open_in_browser_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(launched, 'https://gneiss.example.com');
  });

  testWidgets('cancelling launch dialog does not call onLaunchUrl',
      (tester) async {
    bool launched = false;
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onLaunchUrl: (_) async {
          launched = true;
          return UrlOpenResult.opened;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.open_in_browser_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(launched, isFalse);
  });

  // N4 moved to gabbro_url_opener_test.dart with browserUri itself.

  // 7b: this screen showed nothing at all when opening failed, so a refused or
  // failed link was a button that did nothing.
  testWidgets('7b: a link that will not open says so', (tester) async {
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onLaunchUrl: (_) async => UrlOpenResult.failed,
      ),
    );

    await tester.tap(find.byIcon(Icons.open_in_browser_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open'), findsOneWidget);
  });

  testWidgets('7b: a link that is not a web page gets the other message',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onLaunchUrl: (_) async => UrlOpenResult.notAWebLink,
      ),
    );

    await tester.tap(find.byIcon(Icons.open_in_browser_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(find.text('Only web links can be opened'), findsOneWidget);
  });

  testWidgets('long-pressing revealed password shows breakdown sheet',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    // Reveal the password first
    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();
    expect(find.text('s3cr3tP@ss'), findsOneWidget);

    // Long-press the revealed password text
    await tester.longPress(find.text('s3cr3tP@ss'));
    await tester.pumpAndSettle();

    expect(find.text('Password breakdown'), findsOneWidget);
  });

  testWidgets('file export dialog shows text field and picker button',
      (tester) async {
    final entry = FileEntryData(
      id: 'test-id-file',
      filename: 'secret.txt',
      data: Uint8List.fromList([104, 101, 108, 108, 111]), // b"hello"
      notes: null,
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
      customFields: const [],
    );
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.file(entry)),
    );

    // Tap the Export file button to open the dialog
    await tester.tap(find.text('Export file'));
    await tester.pumpAndSettle();

    // Dialog title is present
    expect(find.text('Export file'), findsWidgets);
    // Manual path TextField is present
    expect(find.byType(TextField), findsOneWidget);
    // Picker IconButton is present
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
  });

  // Net: a failed export write must tell the user why. Pins the message text,
  // not its container. The path points below a plain file, so the directory
  // create fails with a real FileSystemException. The write is real IO, so
  // the confirm tap runs inside runAsync (a fake-clock await never resolves).
  testWidgets('a failed export shows the failure message', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('gabbro_export_net');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final blocker = File('${tmp.path}/blocker')..writeAsStringSync('x');

    final entry = FileEntryData(
      id: 'test-id-file-net',
      filename: 'secret.txt',
      data: Uint8List.fromList([104, 105]),
      notes: null,
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
      customFields: const [],
    );
    await tester.pumpWidget(_buildScreen(VaultEntryData.file(entry)));
    await tester.tap(find.text('Export file'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField), '${blocker.path}/sub/secret.txt');
    // Confirm via onPressed inside runAsync: the failing write is real IO,
    // which the fake-clock test zone never completes (see LEARNINGS "Async
    // dart:io inside testWidgets"); a plain pump after - pumpAndSettle would
    // run the message's auto-dismiss timer to the end and report it missing.
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export'),
    );
    await tester.runAsync(() async {
      confirm.onPressed!();
      // Real-time beats WITH pumps, all inside one runAsync window: the IO
      // completion arrives on the real event loop but is queued on the fake
      // zone's microtask queue, which only a pump flushes.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    expect(find.textContaining('Export failed:'), findsOneWidget);
  });

  // Red (SnackBar clip): the failure explanation must be fully readable in
  // the worst supported case - largest reachable text, narrowest phone, a
  // long path in the FileSystemException (nothing caps its length).
  testWidgets(
      'a failed export message is fully reachable at 2x on a 360dp phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = kPhoneMaxScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final tmp = Directory.systemTemp.createTempSync('gabbro_export_red');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final blocker = File(
      '${tmp.path}/a_rather_long_export_folder_name_the_user_chose_for_'
      'their_decrypted_documents_archive_backup_august_2026',
    )..writeAsStringSync('x');

    final entry = FileEntryData(
      id: 'test-id-file-red',
      filename: 'secret.txt',
      data: Uint8List.fromList([104, 105]),
      notes: null,
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
      customFields: const [],
    );
    await tester.pumpWidget(_buildScreen(VaultEntryData.file(entry)));
    await tester.tap(find.text('Export file'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField), '${blocker.path}/sub/secret.txt');
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export'),
    );
    await tester.runAsync(() async {
      confirm.onPressed!();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    final message = find.textContaining('Export failed:');
    expect(messageIsReachable(tester, message), isTrue,
        reason: 'the failure explanation must be fully readable at 2x');
  });

  // The file-export picker must degrade gracefully when the native dialog can't
  // open (sandbox/no portal): a SnackBar pointing at the editable path field,
  // not an unhandled SocketException.
  testWidgets('file export: an unavailable picker shows a SnackBar, no crash',
      (tester) async {
    final entry = FileEntryData(
      id: 'test-id-file2',
      filename: 'secret.txt',
      data: Uint8List.fromList([104, 105]),
      notes: null,
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
      customFields: const [],
    );
    await tester.pumpWidget(_buildScreen(
      VaultEntryData.file(entry),
      exportFilePicker: (_) async => throw const SocketException('no bus'),
    ));
    await tester.tap(find.text('Export file'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pump();
    expect(
      find.text('File dialog unavailable here. Type or paste the path instead.'),
      findsOneWidget,
    );
  });

  testWidgets('identity hidden custom field has eye icon toggle',
      (tester) async {
    final entry = IdentityEntryData(
      id: 'test-id-3',
      firstName: 'Alex',
      lastName: 'Example',
      email: '',
      phone: null,
      address: null,
      customFields: [
        CustomFieldData(label: 'Passport', value: 'AB123456', hidden: true),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.identity(entry)),
    );

    // Value is masked by default
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('AB123456'), findsNothing);
    // Eye icon toggle is present
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    // Tapping it reveals the value
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(find.text('AB123456'), findsOneWidget);
  });

  // ── Card entry ───────────────────────────────────────────────────────────────

  testWidgets('card entry renders cardholder and obscures card number and CVV',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.card(_cardEntry())),
    );

    expect(find.text('Alex Doe'), findsWidgets);
    // Both card number and CVV start obscured.
    expect(find.text('••••••••'), findsNWidgets(2));
    expect(find.text('4111111111111111'), findsNothing);
    expect(find.text('123'), findsNothing);
    // Two visibility_off icons — one per toggle field.
    expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));
  });

  testWidgets('card number toggle reveals card number', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.card(_cardEntry())),
    );

    // Card number toggle is the first visibility_off icon.
    await tester.tap(find.byIcon(Icons.visibility_off).at(0));
    await tester.pump();

    expect(find.text('4111111111111111'), findsOneWidget);
    // CVV still obscured.
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('123'), findsNothing);
  });

  testWidgets('card CVV toggle reveals CVV value', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.card(_cardEntry())),
    );

    // CVV toggle is the second visibility_off icon.
    await tester.tap(find.byIcon(Icons.visibility_off).at(1));
    await tester.pump();

    expect(find.text('123'), findsOneWidget);
    // Card number still obscured.
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('4111111111111111'), findsNothing);
  });

  // ── Custom entry ─────────────────────────────────────────────────────────────

  testWidgets('custom entry renders title', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.custom(_customEntry())),
    );

    // Title appears in AppBar and as a body field value.
    expect(find.text('My Custom Secret'), findsWidgets);
  });

  // ── Delete dialog cancel path ─────────────────────────────────────────────────

  testWidgets('cancel delete dialog does not call onDeleteEntry',
      (tester) async {
    bool deleteCalled = false;
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onDeleteEntry: (_) async {
          deleteCalled = true;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isFalse,
        reason: 'Cancel must not trigger delete');
    // Screen is still alive.
    expect(find.byType(EntryDetailScreen), findsOneWidget);
  });

  // ── Empty URL ────────────────────────────────────────────────────────────────

  testWidgets('login with empty URL shows no browser launch icon',
      (tester) async {
    final entry = LoginEntryData(
      id: 'no-url-id',
      title: 'No URL Login',
      url: '',
      username: 'user',
      password: 'pw',
      notes: null,
      customFields: const [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(entry)),
    );

    expect(find.byIcon(Icons.open_in_browser_outlined), findsNothing);
  });

  // ── Note hidden custom field ──────────────────────────────────────────────────

  testWidgets('note hidden custom field toggles visible', (tester) async {
    final entry = NoteEntryData(
      id: 'test-note-cf',
      title: 'Secret Note',
      content: 'Note content',
      customFields: [
        CustomFieldData(label: 'Token', value: 'secret_token', hidden: true),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.note(entry)),
    );

    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('secret_token'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();

    expect(find.text('secret_token'), findsOneWidget);
    expect(find.text('••••••••'), findsNothing);
  });

  testWidgets('login detail shows the Android app ID when set', (tester) async {
    final entry = LoginEntryData(
      id: 'test-id-1',
      title: 'Example',
      url: 'https://example.com',
      username: 'user',
      password: 'secret',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      appId: 'com.company.app',
    );
    await tester.pumpWidget(_buildScreen(VaultEntryData.login(entry)));
    expect(find.text('com.company.app'), findsOneWidget);
  });

  testWidgets('login detail omits the Android app ID when unset',
      (tester) async {
    await tester.pumpWidget(_buildScreen(VaultEntryData.login(_loginEntry())));
    expect(find.text('Android app ID (optional)'), findsNothing);
  });

  testWidgets('login detail shows the email when set', (tester) async {
    final entry = LoginEntryData(
      id: 'test-id-1',
      title: 'Example',
      url: 'https://example.com',
      username: 'user',
      password: 'secret',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      email: 'user@example.com',
    );
    await tester.pumpWidget(_buildScreen(VaultEntryData.login(entry)));
    expect(find.text('user@example.com'), findsOneWidget);
  });

  // ADR-016 accessibility follow-up: app-bar action icons grow with the text
  // scale so a low-vision user gets bigger targets (24 at normal text).
  group('app-bar action icons scale at large text', () {
    double iconSizeOf(WidgetTester tester, IconData icon) => tester
        .widget<IconButton>(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
              .first,
        )
        .iconSize!;

    testWidgets('edit and delete icons scale up', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_buildScreen(VaultEntryData.login(_loginEntry())));
      await tester.pumpAndSettle();

      expect(iconSizeOf(tester, Icons.edit_outlined), greaterThan(24));
      expect(iconSizeOf(tester, Icons.delete_outline), greaterThan(24));
      expect(tester.takeException(), isNull);
    });

    testWidgets('file-export download icon scales up', (tester) async {
      final entry = FileEntryData(
        id: 'test-id-file-scale',
        filename: 'secret.txt',
        data: Uint8List.fromList([104, 105]),
        notes: null,
        createdAt: '2025-01-01T00:00:00Z',
        updatedAt: '2025-01-01T00:00:00Z',
        folder: '',
        customFields: const [],
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_buildScreen(VaultEntryData.file(entry)));
      await tester.pumpAndSettle();

      expect(iconSizeOf(tester, Icons.download_outlined), greaterThan(24));
      expect(tester.takeException(), isNull);
    });
  });

  // ADR-016 reveal-eye: the show/hide password toggle (an action-row button,
  // base 18) grows with the text scale — full control-scale, not the suffix cap.
  testWidgets('reveal-eye toggle scales up at large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_buildScreen(VaultEntryData.login(_loginEntry())));
    await tester.pumpAndSettle();

    final eye = tester.widget<IconButton>(revealEyeButtons().first);
    expect(eye.iconSize, isNotNull);
    expect(eye.iconSize, greaterThan(18));
    expect(tester.takeException(), isNull);
  });

  // ADR-016 accessibility follow-up: the History tile's trailing chevron grows
  // with the text scale (free ListTile, full control-scale, no strip cap).
  testWidgets('history-tile chevron scales up at large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        onFetchHistory: (_) async => [
          const HistoryRecordData(
            field: 'password',
            value: 'old',
            savedAt: '2025-01-02T00:00:00Z',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final chevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
    expect(chevron.size, greaterThan(18));
    expect(tester.takeException(), isNull);
  });

  // ── Bottom reserve (tablet FAB clearance) ─────────────────────────────────
  // The shared screen is used both as the phone full-screen route (no FAB) and
  // as the tablet detail pane (a Scaffold-level FAB floats over its bottom).
  // A tablet-only bottomReserve keeps content clear of the FAB without leaking
  // padding into the phone route.

  // Net-first: phone route reserves no extra bottom padding (default 16 all).
  testWidgets('detail body has 16 bottom padding by default (phone route)',
      (tester) async {
    await tester.pumpWidget(_buildScreen(VaultEntryData.login(_loginEntry())));
    await tester.pumpAndSettle();
    expect(bodyScrollPadding(tester).bottom, 16);
  });

  // New: bottomReserve adds to the scroll view's bottom padding.
  testWidgets('bottomReserve adds to the detail body bottom padding',
      (tester) async {
    await tester.pumpWidget(testApp(EntryDetailScreen(
      entry: VaultEntryData.login(_loginEntry()),
      onDeleteEntry: (_) async {},
      onLaunchUrl: (_) async => UrlOpenResult.opened,
      exportFilePicker: (_) async => null,
      onFetchHistory: (_) async => const [],
      bottomReserve: 88,
    )));
    await tester.pumpAndSettle();
    expect(bodyScrollPadding(tester).bottom, 16 + 88);
  });

  // Net for the file_picker replacement: pins the export-dialog picker's
  // success and cancel behaviour, and that it receives the entry's filename.
  group('file export picker wiring (net)', () {
    FileEntryData fileEntry() => FileEntryData(
          id: 'test-id-file-net',
          filename: 'secret.txt',
          data: Uint8List.fromList([104, 105]),
          notes: null,
          createdAt: '2025-01-01T00:00:00Z',
          updatedAt: '2025-01-01T00:00:00Z',
          folder: '',
          customFields: const [],
        );

    testWidgets(
        'a picked path fills the path field; the picker gets the filename',
        (tester) async {
      String? askedFilename;
      await tester.pumpWidget(_buildScreen(
        VaultEntryData.file(fileEntry()),
        exportFilePicker: (filename) async {
          askedFilename = filename;
          return '/tmp/out/secret.txt';
        },
      ));
      await tester.tap(find.text('Export file'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(askedFilename, 'secret.txt');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '/tmp/out/secret.txt');
    });

    testWidgets('a cancelled picker leaves the path field untouched',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        VaultEntryData.file(fileEntry()),
        exportFilePicker: (_) async => null,
      ));
      await tester.tap(find.text('Export file'));
      await tester.pumpAndSettle();

      final before =
          tester.widget<TextField>(find.byType(TextField)).controller?.text;
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, before);
      expect(find.byType(SnackBar), findsNothing);
    });

    // N4: drives the real default picker, not an injected seam. On Android the
    // folder picker gives a directory; the entry's filename is appended to it.
    testWidgets('android appends the filename to the picked folder',
        (tester) async {
      final origPickDir = GabbroFilePicker.androidPickDirectory;
      addTearDown(() => GabbroFilePicker.androidPickDirectory = origPickDir);
      GabbroFilePicker.androidPickDirectory =
          () async => '/storage/emulated/0/Download/Gabbro';

      await tester.pumpWidget(testApp(EntryDetailScreen(
        entry: VaultEntryData.file(fileEntry()),
        isAndroid: true,
        onDeleteEntry: (_) async {},
        onLaunchUrl: (_) async => UrlOpenResult.opened,
        onFetchHistory: (_) async => const [],
      )));
      await tester.tap(find.text('Export file'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text,
          '/storage/emulated/0/Download/Gabbro/secret.txt');
    });

    testWidgets('android: a cancelled folder pick leaves the path untouched',
        (tester) async {
      final origPickDir = GabbroFilePicker.androidPickDirectory;
      addTearDown(() => GabbroFilePicker.androidPickDirectory = origPickDir);
      GabbroFilePicker.androidPickDirectory = () async => null;

      await tester.pumpWidget(testApp(EntryDetailScreen(
        entry: VaultEntryData.file(fileEntry()),
        isAndroid: true,
        onDeleteEntry: (_) async {},
        onLaunchUrl: (_) async => UrlOpenResult.opened,
        onFetchHistory: (_) async => const [],
      )));
      await tester.tap(find.text('Export file'));
      await tester.pumpAndSettle();

      final before =
          tester.widget<TextField>(find.byType(TextField)).controller?.text;
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, before);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

/// The bottom [EdgeInsets] of the detail body's scroll view (the SafeArea >
/// SingleChildScrollView in [EntryDetailScreen.build]).
EdgeInsets bodyScrollPadding(WidgetTester tester) {
  final scroll = tester.widget<SingleChildScrollView>(
    find.descendant(
      of: find.byType(SafeArea),
      matching: find.byType(SingleChildScrollView),
    ),
  );
  return scroll.padding as EdgeInsets;
}