import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/sync_review.dart';

import 'test_helpers.dart';

Future<void> openReview(WidgetTester tester, MergeSummary summary) async {
  final steps = buildSyncReviewSteps(summary);
  await tester.pumpWidget(
    testApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSyncReview(context: context, steps: steps),
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

void main() {
  testWidgets('every tappable control in the review dialog is labelled', (
    tester,
  ) async {
    // A step exercising all interactive controls: a brought-over secret
    // (checkbox + reveal eye), a clash (chips + eye), and an item-delete (chips),
    // plus the action button.
    final summary = MergeSummary(
      added: 0,
      updated: 0,
      addedEntries: const [],
      broughtOver: const [
        BroughtOverItem(
          id: 'x',
          title: 'Mail',
          field: 'password',
          oldValue: 'old',
          newValue: 'new',
        ),
      ],
      pendingDeletes: const [],
      folderConflicts: const [],
      fieldConflicts: const [
        FieldConflictItem(
          id: 'x',
          title: 'Mail',
          field: 'cvv',
          localValue: 'mine',
          incomingValue: 'theirs',
        ),
      ],
      pendingItemDeletes: const [
        PendingItemDeleteItem(
          id: 'x',
          title: 'Mail',
          field: 'custom_fields:OldNote',
        ),
      ],
    );

    final handle = tester.ensureSemantics();
    await openReview(tester, summary);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
