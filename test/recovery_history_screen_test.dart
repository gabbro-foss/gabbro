import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/recovery_history_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/text_scale.dart';

HistoryRecordData _rec(String field, String value) => HistoryRecordData(
  field: field,
  value: value,
  savedAt: '2026-01-01T00:00:00Z',
);

void main() {
  // ADR-016 reveal-eye: the show/hide toggle scales fully with the text
  // (unconstrained ListTile trailing row).
  testWidgets('reveal-eye toggle scales up at large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

    final eye = tester.widget<IconButton>(revealEyeButtons().first);
    expect(eye.iconSize, isNotNull);
    expect(eye.iconSize, greaterThan(24));
  });

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

  // Scenario 9 (attachments task): an attachment history row is titled by its
  // FILENAME (the record's value) — never the uuid or the raw key.
  testWidgets('an attachment history row is titled by filename', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [_rec('attachments:uuid-9', 'passport.pdf')],
          onRestore: (_) async {},
          onDelete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('passport.pdf'), findsOneWidget);
    expect(find.textContaining('uuid-9'), findsNothing);
    expect(find.textContaining('attachments:'), findsNothing);
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

  // Net: a failed action must tell the user why and keep the row (nothing was
  // restored or deleted). Pins the message text, not its container.
  testWidgets('a failed action shows the failure message and keeps the row',
      (tester) async {
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [_rec('url', 'a')],
          onRestore: (_) async => throw Exception('boom'),
          onDelete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revert'));
    await tester.pumpAndSettle();

    expect(
      find.text('Recovery action failed: Exception: boom'),
      findsOneWidget,
    );
    expect(find.text('Revert'), findsOneWidget, reason: 'failed row stays');
  });

  // Red (SnackBar clip): the failure explanation must be fully readable in
  // the worst supported case - largest reachable text, narrowest phone, a
  // realistic FileSystemException carrying the full path.
  testWidgets(
      'a failed action message is fully reachable at 2x on a 360dp phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = kPhoneMaxScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const err = FileSystemException(
      'Cannot open file',
      '/storage/emulated/0/Documents/Recovery/Very long folder name for the '
          'archive of restored entries/backup-2026-08-11/entry.dat',
      OSError('Permission denied', 13),
    );
    await tester.pumpWidget(
      testApp(
        RecoveryHistoryScreen(
          records: [_rec('url', 'a')],
          onRestore: (_) async => throw err,
          onDelete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Revert'));
    await tester.tap(find.text('Revert'));
    await tester.pumpAndSettle();

    final message = find.textContaining('Recovery action failed:');
    expect(messageIsReachable(tester, message), isTrue,
        reason: 'the failure explanation must be fully readable at 2x');
  });
}
