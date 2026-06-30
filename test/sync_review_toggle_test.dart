import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/sync_review.dart';

import 'test_helpers.dart';

/// Open a one-step review for [summary]; [onResult] receives the decisions when
/// the user finishes (taps OK).
Future<void> openReview(
  WidgetTester tester,
  MergeSummary summary,
  void Function(SyncReviewDecisions?) onResult,
) async {
  final steps = buildSyncReviewSteps(summary);
  await tester.pumpWidget(
    testApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  onResult(await showSyncReview(context: context, steps: steps)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

MergeSummary _summary({
  List<AddedEntryItem> addedEntries = const [],
  List<PendingDeleteItem> pendingDeletes = const [],
  List<PendingItemDeleteItem> pendingItemDeletes = const [],
}) => MergeSummary(
  added: addedEntries.length,
  updated: 0,
  addedEntries: addedEntries,
  broughtOver: const [],
  pendingDeletes: pendingDeletes,
  folderConflicts: const [],
  fieldConflicts: const [],
  pendingItemDeletes: pendingItemDeletes,
);

void main() {
  group('sync review keep/delete labels', () {
    testWidgets('whole-entry delete defaults to keep', (tester) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(pendingDeletes: [const PendingDeleteItem(id: 'g', title: 'Gone')]),
        (r) => d = r,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(d!.entryDeletes, isNot(contains('g')));
    });

    testWidgets('per-item delete defaults to keep', (tester) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(
          pendingItemDeletes: [
            const PendingItemDeleteItem(
              id: 'x',
              title: 'Mail',
              field: 'custom_fields:OldNote',
            ),
          ],
        ),
        (r) => d = r,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final res = d!.itemDeletes.singleWhere((r) => r.field == 'custom_fields:OldNote');
      expect(res.delete, isFalse);
    });

    testWidgets('new entry defaults to keep', (tester) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(addedEntries: [const AddedEntryItem(id: 'n', title: 'New')]),
        (r) => d = r,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(d!.entryDeletes, isNot(contains('n')));
    });

    testWidgets('whole-entry delete shows other-device context and Keep/Delete', (
      tester,
    ) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(pendingDeletes: [const PendingDeleteItem(id: 'g', title: 'Gone')]),
        (r) => d = r,
      );
      expect(find.textContaining('other device'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Keep'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Delete'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(d!.entryDeletes, contains('g'));
    });

    testWidgets('per-item delete shows context and Keep/Delete', (tester) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(
          pendingItemDeletes: [
            const PendingItemDeleteItem(
              id: 'x',
              title: 'Mail',
              field: 'custom_fields:OldNote',
            ),
          ],
        ),
        (r) => d = r,
      );
      expect(find.textContaining('other device'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Delete'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final res = d!.itemDeletes.singleWhere((r) => r.field == 'custom_fields:OldNote');
      expect(res.delete, isTrue);
    });

    testWidgets('new entry shows context and Keep/Skip; Skip drops it', (
      tester,
    ) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(addedEntries: [const AddedEntryItem(id: 'n', title: 'New')]),
        (r) => d = r,
      );
      expect(find.textContaining('New entry'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Keep'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Skip'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(d!.entryDeletes, contains('n'));
    });
  });
}
