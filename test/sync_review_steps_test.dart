import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/sync_review.dart';

MergeSummary _summary({
  List<AddedEntryItem> addedEntries = const [],
  List<BroughtOverItem> broughtOver = const [],
  List<PendingDeleteItem> pendingDeletes = const [],
  List<FolderConflictItem> folderConflicts = const [],
  List<FieldConflictItem> fieldConflicts = const [],
  List<PendingItemDeleteItem> pendingItemDeletes = const [],
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
  group('buildSyncReviewSteps', () {
    test('a new entry becomes a newEntry step', () {
      final steps = buildSyncReviewSteps(
        _summary(
          addedEntries: [const AddedEntryItem(id: 'a', title: 'Bank')],
        ),
      );
      expect(steps, hasLength(1));
      expect(steps.single.kind, SyncStepKind.newEntry);
      expect(steps.single.title, 'Bank');
      expect(steps.single.needsChoice, isFalse);
    });

    test('all of one entry\'s changes land in a single step', () {
      final steps = buildSyncReviewSteps(
        _summary(
          broughtOver: [
            const BroughtOverItem(
              id: 'x',
              title: 'Mail',
              field: 'url',
              oldValue: 'a',
              newValue: 'b',
            ),
            const BroughtOverItem(
              id: 'x',
              title: 'Mail',
              field: 'username',
              oldValue: 'u',
              newValue: 'u2',
            ),
          ],
          fieldConflicts: [
            const FieldConflictItem(
              id: 'x',
              title: 'Mail',
              field: 'password',
              localValue: 'mine',
              incomingValue: 'theirs',
            ),
          ],
          pendingItemDeletes: [
            const PendingItemDeleteItem(
              id: 'x',
              title: 'Mail',
              field: 'custom_fields:OldNote',
            ),
          ],
        ),
      );
      expect(steps, hasLength(1));
      final s = steps.single;
      expect(s.kind, SyncStepKind.changes);
      expect(s.broughtOver, hasLength(2));
      expect(s.conflicts, hasLength(1));
      expect(s.itemDeletes, hasLength(1));
      expect(s.needsChoice, isTrue, reason: 'has a clash to pick');
    });

    test('a brought-over-only entry needs no forced choice', () {
      final steps = buildSyncReviewSteps(
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
      );
      expect(steps.single.needsChoice, isFalse);
    });

    test('a folder difference forces a choice', () {
      final steps = buildSyncReviewSteps(
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
      );
      expect(steps.single.kind, SyncStepKind.changes);
      expect(steps.single.needsChoice, isTrue);
    });

    test('a whole-entry delete becomes a deleteEntry step', () {
      final steps = buildSyncReviewSteps(
        _summary(
          pendingDeletes: [const PendingDeleteItem(id: 'd', title: 'Gone')],
        ),
      );
      expect(steps.single.kind, SyncStepKind.deleteEntry);
      expect(steps.single.title, 'Gone');
    });

    test('order is new entries, then changes, then deletes', () {
      final steps = buildSyncReviewSteps(
        _summary(
          addedEntries: [const AddedEntryItem(id: 'a', title: 'New')],
          broughtOver: [
            const BroughtOverItem(
              id: 'c',
              title: 'Changed',
              field: 'url',
              oldValue: '',
              newValue: 'b',
            ),
          ],
          pendingDeletes: [const PendingDeleteItem(id: 'd', title: 'Gone')],
        ),
      );
      expect(steps.map((s) => s.kind).toList(), [
        SyncStepKind.newEntry,
        SyncStepKind.changes,
        SyncStepKind.deleteEntry,
      ]);
    });

    test('two changed entries make two separate steps', () {
      final steps = buildSyncReviewSteps(
        _summary(
          broughtOver: [
            const BroughtOverItem(
              id: 'x',
              title: 'X',
              field: 'url',
              oldValue: '',
              newValue: '1',
            ),
            const BroughtOverItem(
              id: 'y',
              title: 'Y',
              field: 'url',
              oldValue: '',
              newValue: '2',
            ),
          ],
        ),
      );
      expect(steps.map((s) => s.id).toList(), ['x', 'y']);
    });

    test('empty summary yields no steps', () {
      expect(buildSyncReviewSteps(_summary()), isEmpty);
    });
  });
}
