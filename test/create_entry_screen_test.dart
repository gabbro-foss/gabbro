import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
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

// ── Widget helpers ────────────────────────────────────────────────────────────

Widget _buildCreateScreen(
  String entryType, {
  Future<void> Function(VaultEntryData)? onCreateEntry,
}) =>
    MaterialApp(
      home: CreateEntryScreen(
        entryType: entryType,
        onCreateEntry: onCreateEntry ?? (_) async {},
        onUpdateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
      ),
    );

Widget _buildEditScreen(VaultEntryData existing) => MaterialApp(
      home: CreateEntryScreen(
        entryType: 'Login',
        existing: existing,
        onCreateEntry: (_) async {},
        onUpdateEntry: (_) async {},
        onGetEntry: (_) => existing,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('required field validation fires on empty save', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Login'));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Title is required'), findsOneWidget);
    expect(find.text('URL is required'), findsOneWidget);
    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('edit mode pre-populates fields', (tester) async {
    await tester.pumpWidget(
      _buildEditScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.widgetWithText(TextFormField, 'Gneiss Bank'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'https://gneiss.example.com'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'rob@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('save button calls onCreateEntry with correct type',
      (tester) async {
    VaultEntryData? captured;

    await tester.pumpWidget(
      _buildCreateScreen(
        'Login',
        onCreateEntry: (entry) async => captured = entry,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Schist Site',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL'),
      'https://schist.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'testuser',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'p@ssw0rd',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured, isA<VaultEntryData_Login>());
  });
}
