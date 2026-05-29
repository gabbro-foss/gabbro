import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/password_history_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

LoginEntryData _entryWithHistory() => LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com',
      username: 'rob@example.com',
      password: '********',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-05-01T00:00:00Z',
      folder: 'Personal',
      previousPassword: PreviousSecretData(
        value: '********',
        savedAt: '2025-04-01T00:00:00Z',
        expiresAt: '2025-05-01T00:00:00Z',
      ),
    );

LoginEntryData _entryWithoutHistory() => LoginEntryData(
      id: 'test-id-2',
      title: 'GitHub',
      url: 'https://github.com',
      username: 'rob@example.com',
      password: '********',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      previousPassword: null,
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildHistoryScreen({
  required LoginEntryData entry,
  Future<void> Function()? onDeleteHistory,
  Future<void> Function()? onRevert,
}) =>
    testApp(PasswordHistoryScreen(
      entry: entry,
      onDeleteHistory: onDeleteHistory ?? () async {},
      onRevert: onRevert ?? () async {},
    ));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('shows current password row', (tester) async {
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithHistory(),
    ));

    expect(find.text('Current'), findsOneWidget);
  });

  testWidgets('shows previous password row when history exists',
      (tester) async {
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithHistory(),
    ));

    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Delete previous entry'), findsOneWidget);
  });

  testWidgets('does not show previous section when no history', (tester) async {
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithoutHistory(),
    ));

    expect(find.text('Previous'), findsNothing);
    expect(find.text('Delete previous entry'), findsNothing);
  });

  testWidgets('shows expiry date when present', (tester) async {
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithHistory(),
    ));

    expect(find.textContaining('expires'), findsOneWidget);
  });

  testWidgets('delete history button calls onDeleteHistory', (tester) async {
    var called = false;
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithHistory(),
      onDeleteHistory: () async => called = true,
    ));

    await tester.tap(find.text('Delete previous entry'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets('revert button calls onRevert', (tester) async {
    var called = false;
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithHistory(),
      onRevert: () async => called = true,
    ));

    await tester.tap(find.text('Revert'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets('both password values are hidden by default', (tester) async {
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithHistory(),
    ));

    expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));
  });

  testWidgets('Revert is a standalone button below Delete previous entry',
      (tester) async {
    await tester.pumpWidget(_buildHistoryScreen(
      entry: _entryWithHistory(),
    ));

    // Both buttons must exist as OutlinedButtons (not TextButton)
    expect(find.widgetWithText(OutlinedButton, 'Delete previous entry'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Revert'), findsOneWidget);

    // Revert must appear below Delete — check render order in the Column
    final deletePos =
        tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Delete previous entry'));
    final revertPos =
        tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Revert'));
    expect(revertPos.dy, greaterThan(deletePos.dy));
  });
}