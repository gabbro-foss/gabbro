import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/review_changes_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

LoginEntryData _original() => LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com',
      username: 'rob@example.com',
      password: 'old_password',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
      previousPassword: null,
    );

LoginEntryData _updatedPasswordAndUrl() => LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com/login',
      username: 'rob@example.com',
      password: 'new_password',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
      previousPassword: null,
    );

LoginEntryData _updatedUrlOnly() => LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com/login',
      username: 'rob@example.com',
      password: 'old_password',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
      previousPassword: null,
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildReviewScreen({
  required VaultEntryData original,
  required VaultEntryData updated,
  Future<void> Function(VaultEntryData, int?)? onSave,
}) =>
    MaterialApp(
      home: ReviewChangesScreen(
        original: original,
        updated: updated,
        expiryDays: 30,
        onSave: onSave ?? _noOpSave,
      ),
    );

Future<void> _noOpSave(VaultEntryData entry, int? days) async {}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('shows sensitive fields section when password changed',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedPasswordAndUrl()),
    ));

    expect(find.text('Sensitive fields'), findsOneWidget);
    expect(find.text('Password changed'), findsOneWidget);
  });

  testWidgets('does not show sensitive fields section when password unchanged',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    expect(find.text('Sensitive fields'), findsNothing);
    expect(find.text('Password changed'), findsNothing);
  });

  testWidgets('shows before and after values for changed non-sensitive fields',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    expect(find.text('https://github.com'), findsOneWidget);
    expect(find.text('https://github.com/login'), findsOneWidget);
  });

  testWidgets('does not show unchanged fields in diff', (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    // Title and username unchanged — must not appear in diff grid
    expect(find.text('Title'), findsNothing);
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('save button calls onSave with updated entry', (tester) async {
    VaultEntryData? saved;
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
      onSave: (entry, _) async => saved = entry,
    ));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved, isA<VaultEntryData_Login>());
  });

  testWidgets('cancel button pops the screen', (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewChangesScreen), findsNothing);
  });
}