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
  List<BroughtOverItem> broughtOver = const [],
  List<FieldConflictItem> fieldConflicts = const [],
  List<PendingDeleteItem> pendingDeletes = const [],
  List<PendingItemDeleteItem> pendingItemDeletes = const [],
  List<FolderConflictItem> folderConflicts = const [],
}) => MergeSummary(
  added: addedEntries.length,
  updated: 0,
  addedEntries: addedEntries,
  broughtOver: broughtOver,
  pendingDeletes: pendingDeletes,
  folderConflicts: folderConflicts,
  fieldConflicts: fieldConflicts,
  pendingItemDeletes: pendingItemDeletes,
);

void main() {
  testWidgets('skipping a new entry counts as neither added nor deleted', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(addedEntries: [const AddedEntryItem(id: 'n', title: 'New')]),
      (r) => d = r,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.added, 0);
    expect(d!.deleted, 0);
  });

  testWidgets('keeping a new entry counts as added, not deleted', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(addedEntries: [const AddedEntryItem(id: 'n', title: 'New')]),
      (r) => d = r,
    );
    // Leave the default (Keep), finish.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.added, 1);
    expect(d!.deleted, 0);
  });

  testWidgets('keeping a brought-over change marks the entry updated', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(
        broughtOver: [
          const BroughtOverItem(
            id: 'x',
            title: 'Mail',
            field: 'url',
            oldValue: 'a',
            newValue: 'b',
          ),
        ],
      ),
      (r) => d = r,
    );
    // Leave the default (Keep), finish.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.updated, 1);
  });

  testWidgets('dropping the only brought-over change leaves updated 0', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(
        broughtOver: [
          const BroughtOverItem(
            id: 'x',
            title: 'Mail',
            field: 'url',
            oldValue: 'a',
            newValue: 'b',
          ),
        ],
      ),
      (r) => d = r,
    );
    // Uncheck the brought-over tile (drop it), finish.
    await tester.tap(find.textContaining('Use this vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.updated, 0);
  });

  testWidgets('resolving a clash to theirs marks the entry updated', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(
        fieldConflicts: [
          const FieldConflictItem(
            id: 'x',
            title: 'Mail',
            field: 'username',
            localValue: 'mine',
            incomingValue: 'theirs',
          ),
        ],
      ),
      (r) => d = r,
    );
    await tester.tap(find.textContaining('Use other vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.updated, 1);
  });

  testWidgets('keeping mine on a clash leaves the entry not updated', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(
        fieldConflicts: [
          const FieldConflictItem(
            id: 'x',
            title: 'Mail',
            field: 'username',
            localValue: 'mine',
            incomingValue: 'theirs',
          ),
        ],
      ),
      (r) => d = r,
    );
    await tester.tap(find.textContaining('Use this vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.updated, 0);
  });

  testWidgets('confirming a whole-entry delete counts as deleted', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(pendingDeletes: [const PendingDeleteItem(id: 'g', title: 'Gone')]),
      (r) => d = r,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.deleted, 1);
    expect(d!.added, 0);
    expect(d!.updated, 0);
  });

  testWidgets('confirming an item-delete marks the entry updated', (
    tester,
  ) async {
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
    await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.updated, 1);
  });

  testWidgets('collects entry titles per group for the itemized summary', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(
        addedEntries: [const AddedEntryItem(id: 'n', title: 'New')],
        broughtOver: [
          const BroughtOverItem(
            id: 'x',
            title: 'Mail',
            field: 'url',
            oldValue: 'a',
            newValue: 'b',
          ),
        ],
        pendingDeletes: [const PendingDeleteItem(id: 'g', title: 'Gone')],
      ),
      (r) => d = r,
    );
    // Step 1 (New): keep. Step 2 (Mail): keep the brought-over change.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    // Step 3 (Gone): confirm the delete, then finish.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.addedTitles, ['New']);
    expect(d!.updatedTitles, ['Mail']);
    expect(d!.deletedTitles, ['Gone']);
    // Counts stay consistent with the title lists.
    expect(d!.added, 1);
    expect(d!.updated, 1);
    expect(d!.deleted, 1);
  });

  testWidgets('Cancel sync returns cancelled decisions', (tester) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(addedEntries: [const AddedEntryItem(id: 'n', title: 'New')]),
      (r) => d = r,
    );
    await tester.tap(find.text('Cancel')); // bail button in the review
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel sync')); // chooser: discard everything
    await tester.pumpAndSettle();
    expect(d!.cancelled, isTrue);
  });

  testWidgets('Merge the rest resolves undecided clashes incoming-wins', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(
        fieldConflicts: [
          const FieldConflictItem(
            id: 'x',
            title: 'Mail',
            field: 'username',
            localValue: 'mine',
            incomingValue: 'theirs',
          ),
        ],
      ),
      (r) => d = r,
    );
    await tester.tap(find.text('Cancel')); // bail
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge automatically')); // finish the rest fast
    await tester.pumpAndSettle();
    expect(d!.cancelled, isFalse);
    // The undecided clash is resolved to theirs, losing local kept in history.
    expect(d!.historyReplacements.single.field, 'username');
    expect(d!.historyReplacements.single.newValue, 'theirs');
    expect(d!.historyReplacements.single.replacedValue, 'mine');
  });

  testWidgets('moving an entry to the incoming folder marks it updated', (
    tester,
  ) async {
    SyncReviewDecisions? d;
    await openReview(
      tester,
      _summary(
        folderConflicts: [
          const FolderConflictItem(
            id: 'x',
            title: 'Mail',
            localFolder: 'Work',
            incomingFolder: 'Home',
          ),
        ],
      ),
      (r) => d = r,
    );
    await tester.tap(find.textContaining('Move to'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(d!.updated, 1);
  });
}
