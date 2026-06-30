import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/sync_review.dart';

import 'test_helpers.dart';

/// Pump a one-step review for [summary] and open the dialog.
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

MergeSummary _summary({
  List<BroughtOverItem> broughtOver = const [],
  List<FieldConflictItem> fieldConflicts = const [],
}) => MergeSummary(
  added: 0,
  updated: 0,
  addedEntries: const [],
  broughtOver: broughtOver,
  pendingDeletes: const [],
  folderConflicts: const [],
  fieldConflicts: fieldConflicts,
  pendingItemDeletes: const [],
);

void main() {
  group('sync review secret reveal', () {
    testWidgets('a file-data clash shows <binary>, never the raw value', (
      tester,
    ) async {
      await openReview(
        tester,
        _summary(
          fieldConflicts: [
            const FieldConflictItem(
              id: 'x',
              title: 'key.txt',
              field: 'data',
              localValue: 'RAWLOCALBASE64',
              incomingValue: 'RAWINCOMINGBASE64',
            ),
          ],
        ),
      );
      expect(find.textContaining('<binary>'), findsWidgets);
      expect(find.textContaining('RAWLOCALBASE64'), findsNothing);
      expect(find.textContaining('RAWINCOMINGBASE64'), findsNothing);
    });

    testWidgets('a secret conflict field is masked by default', (tester) async {
      await openReview(
        tester,
        _summary(
          fieldConflicts: [
            const FieldConflictItem(
              id: 'x',
              title: 'Mail',
              field: 'password',
              localValue: 'mine_secret',
              incomingValue: 'theirs_secret',
            ),
          ],
        ),
      );
      expect(find.textContaining('mine_secret'), findsNothing);
      expect(find.textContaining('theirs_secret'), findsNothing);
    });

    testWidgets('a non-secret brought-over field shows values, no eye', (
      tester,
    ) async {
      await openReview(
        tester,
        _summary(
          broughtOver: [
            const BroughtOverItem(
              id: 'x',
              title: 'Mail',
              field: 'url',
              oldValue: 'old.example',
              newValue: 'new.example',
            ),
          ],
        ),
      );
      expect(find.textContaining('old.example'), findsOneWidget);
      expect(find.textContaining('new.example'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
      expect(find.byIcon(Icons.visibility), findsNothing);
    });

    testWidgets('secret brought-over row reveals and re-hides', (tester) async {
      await openReview(
        tester,
        _summary(
          broughtOver: [
            const BroughtOverItem(
              id: 'x',
              title: 'Mail',
              field: 'password',
              oldValue: 'oldpw',
              newValue: 'newpw',
            ),
          ],
        ),
      );
      expect(find.textContaining('oldpw'), findsNothing);
      expect(find.textContaining('newpw'), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();
      expect(find.textContaining('oldpw'), findsOneWidget);
      expect(find.textContaining('newpw'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();
      expect(find.textContaining('oldpw'), findsNothing);
      expect(find.textContaining('newpw'), findsNothing);
    });

    testWidgets('secret conflict row reveals and re-hides', (tester) async {
      await openReview(
        tester,
        _summary(
          fieldConflicts: [
            const FieldConflictItem(
              id: 'x',
              title: 'Mail',
              field: 'password',
              localValue: 'mineSecret',
              incomingValue: 'theirsSecret',
            ),
          ],
        ),
      );
      expect(find.textContaining('mineSecret'), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();
      expect(find.textContaining('mineSecret'), findsOneWidget);
      expect(find.textContaining('theirsSecret'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();
      expect(find.textContaining('mineSecret'), findsNothing);
      expect(find.textContaining('theirsSecret'), findsNothing);
    });

    testWidgets('reveal is per-field within a step', (tester) async {
      await openReview(
        tester,
        _summary(
          broughtOver: [
            const BroughtOverItem(
              id: 'x',
              title: 'Card',
              field: 'password',
              oldValue: 'pwOld',
              newValue: 'pwNew',
            ),
            const BroughtOverItem(
              id: 'x',
              title: 'Card',
              field: 'pin',
              oldValue: 'pinOld',
              newValue: 'pinNew',
            ),
          ],
        ),
      );
      // Two secret rows -> two eye icons. Reveal the first only.
      await tester.tap(find.byIcon(Icons.visibility_off).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('pwOld'), findsOneWidget);
      expect(find.textContaining('pinOld'), findsNothing);
    });
  });
}
