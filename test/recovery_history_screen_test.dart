import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/recovery_history_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';

HistoryRecordData _rec(String field, String value) => HistoryRecordData(
  field: field,
  value: value,
  savedAt: '2026-01-01T00:00:00Z',
);

void main() {
  testWidgets('shows field labels and masks secret values', (tester) async {
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [
            _rec('url', 'old.example.com'),
            _rec('password', 'hunter2'),
            _rec('custom_fields:Tag', 'blue'),
          ],
          onRestore: (_) async {},
          onDelete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('url'), findsOneWidget);
    expect(find.text('old.example.com'), findsOneWidget);
    // Custom pair shows its label, not the raw key.
    expect(find.text('Tag'), findsOneWidget);
    // A password is masked.
    expect(find.text('hunter2'), findsNothing);
    expect(find.textContaining('••••'), findsOneWidget);
  });

  testWidgets('a masked secret reveals and re-hides with the eye', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [_rec('password', 'hunter2')],
          onRestore: (_) async {},
          onDelete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hunter2'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pumpAndSettle();
    expect(find.text('hunter2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();
    expect(find.text('hunter2'), findsNothing);
  });

  testWidgets('file-data history shows <binary>, not the base64', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [_rec('data', 'RAWBASE64VALUE')],
          onRestore: (_) async {},
          onDelete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('<binary>'), findsOneWidget);
    expect(find.textContaining('RAWBASE64VALUE'), findsNothing);
  });

  testWidgets('Revert calls onRestore and removes the row', (tester) async {
    int? restored;
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [_rec('url', 'a'), _rec('content', 'b')],
          onRestore: (i) async => restored = i,
          onDelete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Revert'), findsNWidgets(2));
    await tester.tap(find.text('Revert').first);
    await tester.pumpAndSettle();

    expect(restored, 0);
    expect(find.text('Revert'), findsOneWidget, reason: 'restored row removed');
  });

  testWidgets('Delete calls onDelete and removes the row', (tester) async {
    int? deleted;
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [_rec('url', 'a')],
          onRestore: (_) async {},
          onDelete: (i) async => deleted = i,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(deleted, 0);
    expect(find.text('url'), findsNothing);
  });
}
