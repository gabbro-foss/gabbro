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
}) =>
    MaterialApp(
      home: EntryDetailScreen(
        entry: entry,
        onDeleteEntry: onDeleteEntry ?? (_) async {},
        onCopyToClipboard: onCopyToClipboard ?? (_) async {},
        clipboardClearTimeout: clipboardClearTimeout,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
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

  testWidgets('note entry renders title and content', (tester) async {
    await tester.pumpWidget(
      _buildScreen(VaultEntryData.note(_noteEntry())),
    );

    expect(find.text('Basalt Notes'), findsWidgets);
    expect(find.text('Some important note content.'), findsOneWidget);
  });
}