import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

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
  Future<void> Function(String value)? onCopyToClipboard,
  ClipboardClearTimeout clipboardClearTimeout =
      ClipboardClearTimeout.sixtySeconds,
  Future<void> Function(String url)? onLaunchUrl,
  Future<String?> Function(String filename)? exportFilePicker,
  Future<List<HistoryRecordData>> Function(String id)? onFetchHistory,
}) =>
    testApp(EntryDetailScreen(
      entry: entry,
      onDeleteEntry: onDeleteEntry ?? (_) async {},
      onCopyToClipboard: onCopyToClipboard ?? (_) async {},
      clipboardClearTimeout: clipboardClearTimeout,
      onLaunchUrl: onLaunchUrl ?? (_) async {},
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
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Copied'), findsOneWidget);
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
    await tester.pumpWidget(
      _buildScreen(
        VaultEntryData.login(_loginEntry()),
        clipboardClearTimeout: ClipboardClearTimeout.thirtySeconds,
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('30s'), findsOneWidget);
  });

  testWidgets('copy snackbar says "never clears" when timeout is never',
      (tester) async {
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
        onCopyToClipboard: (_) async {},
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
                  onCopyToClipboard: (_) async {},
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
        onLaunchUrl: (url) async => launched = url,
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
        onLaunchUrl: (_) async => launched = true,
      ),
    );

    await tester.tap(find.byIcon(Icons.open_in_browser_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(launched, isFalse);
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
      onCopyToClipboard: (_) async {},
      onLaunchUrl: (_) async {},
      exportFilePicker: (_) async => null,
      onFetchHistory: (_) async => const [],
      bottomReserve: 88,
    )));
    await tester.pumpAndSettle();
    expect(bodyScrollPadding(tester).bottom, 16 + 88);
  });
}

/// Installs a mock for the `Clipboard` platform channel and returns a growing
/// list of every text written via `Clipboard.setData` — the auto-clear writes
/// an empty string, which is what the pin tests assert on.
List<String> recordClipboardWrites(WidgetTester tester) {
  final writes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add((call.arguments as Map)['text'] as String? ?? '');
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return writes;
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