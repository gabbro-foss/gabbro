import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

LoginEntryData _loginEntry() => LoginEntryData(
      id: 'test-id-1',
      title: 'Gneiss Bank',
      url: 'https://gneiss.example.com',
      username: 'rob@example.com',
      password: 's3cr3tP@ss',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
    );

NoteEntryData _noteEntry() => NoteEntryData(
      id: 'test-id-2',
      title: 'Basalt Notes',
      content: 'Some important note content.',
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildScreen(
  VaultEntryData entry, {
  Future<void> Function(String id)? onDeleteEntry,
  Future<void> Function(String value)? onCopyToClipboard,
  ClipboardClearTimeout clipboardClearTimeout =
      ClipboardClearTimeout.sixtySeconds,
  Future<void> Function(String url)? onLaunchUrl,
}) =>
    MaterialApp(
      home: EntryDetailScreen(
        entry: entry,
        onDeleteEntry: onDeleteEntry ?? (_) async {},
        onCopyToClipboard: onCopyToClipboard ?? (_) async {},
        clipboardClearTimeout: clipboardClearTimeout,
        onLaunchUrl: onLaunchUrl ?? (_) async {},
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('formatTimestamp', () {
    test('formats valid ISO 8601 UTC string', () {
      final dt = DateTime.parse('2025-04-21T14:32:07Z').toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final expected =
          '21 ${months[dt.month - 1]} ${dt.year}, '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
      expect(formatTimestamp('2025-04-21T14:32:07Z'), expected);
    });

    test('returns Unknown for empty string', () {
      expect(formatTimestamp(''), 'Unknown');
    });

    test('returns Unknown for invalid string', () {
      expect(formatTimestamp('not-a-date'), 'Unknown');
    });
  });
  testWidgets('login entry renders fields correctly', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.text('Gneiss Bank'), findsWidgets);
    expect(find.text('rob@example.com'), findsOneWidget);
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

  testWidgets('timestamps section shows Created and Updated labels',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
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
      MaterialApp(
        home: EntryDetailScreen(
          entry: VaultEntryData.login(_loginEntry()),
          onDeleteEntry: (_) async { deleteEntryCalled = true; },
          onCopyToClipboard: (_) async {},
          onDeleted: () { deletedCalled = true; },
        ),
      ),
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
      MaterialApp(
        home: Builder(
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
        ),
      ),
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

  testWidgets('identity hidden custom field has eye icon toggle',
      (tester) async {
    final entry = IdentityEntryData(
      id: 'test-id-3',
      firstName: 'Rob',
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
      tags: [],
      favourite: false,
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
}