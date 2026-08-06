import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/sync_review.dart';

import 'test_helpers.dart';

/// The net under the "incoming choice always first, always the default" change:
/// every tap must keep mapping to the same vault side after the two options are
/// reordered. Pins the decisions each tap produces, never the on-screen order —
/// the order itself is pinned separately, red-first.

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
  List<FolderConflictItem> folderConflicts = const [],
  List<PendingDeleteItem> pendingDeletes = const [],
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

/// A non-clashing incoming edit: the other device changed `username`, this vault
/// did not.
const _brought = BroughtOverItem(
  id: 'e1',
  title: 'Example',
  field: 'username',
  oldValue: 'old@example.com',
  newValue: 'new@example.com',
);

/// A same-field clash: both devices changed `url`.
const _clash = FieldConflictItem(
  id: 'e1',
  title: 'Example',
  field: 'url',
  localValue: 'https://local.example.com',
  incomingValue: 'https://incoming.example.com',
);

const _folder = FolderConflictItem(
  id: 'e1',
  title: 'Example',
  localFolder: 'Local',
  incomingFolder: 'Incoming',
);

const _itemDelete = PendingItemDeleteItem(
  id: 'e1',
  title: 'Example',
  field: 'custom_fields:Recovery code',
);

const _entryDelete = PendingDeleteItem(id: 'g', title: 'Gone');

const _newEntry = AddedEntryItem(id: 'n', title: 'New');

/// Tap a dialog action by label, scrolling it into view first: the review dialog
/// is `scrollable`, so its actions sit below the viewport on a busy step.
Future<void> _tapAction(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _tapThenOk(WidgetTester tester, Finder choice) async {
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Position of the first rendered `Text` containing [needle], in widget-tree
/// order. Layout-agnostic: a choice pair renders as a `Wrap` of chips at normal
/// text and a `Column` of rows at large text, so comparing coordinates would
/// pin the layout rather than the order.
/// Set [exact] for a bare label (Keep / Delete / Skip): the step's own body text
/// says "Delete it here too, or keep it?", so a substring match would find that
/// sentence instead of the choice and pass for the wrong widget.
int _order(WidgetTester tester, String needle, {bool exact = false}) {
  final labels = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
  final i = labels.indexWhere(
    (s) => exact ? s == needle : s.contains(needle),
  );
  expect(i, isNonNegative, reason: 'no rendered choice matches "$needle"');
  return i;
}

/// Assert [incoming] renders before [local].
void _incomingFirst(
  WidgetTester tester,
  String incoming,
  String local, {
  bool exact = false,
}) => expect(
  _order(tester, incoming, exact: exact),
  lessThan(_order(tester, local, exact: exact)),
  reason: '"$incoming" must render before "$local"',
);

/// Every decision in [d], as sorted comparable strings.
List<String> _fingerprint(SyncReviewDecisions d) => <String>[
  for (final r in d.fieldResolutions)
    'field ${r.id} ${r.field} ${r.keepIncoming} ${r.value}',
  for (final r in d.historyReplacements)
    'history ${r.id} ${r.field} ${r.newValue} ${r.replacedValue}',
  for (final r in d.itemDeletes) 'item ${r.id} ${r.field} ${r.delete}',
  for (final r in d.folders) 'folder ${r.id} ${r.folder}',
  for (final e in d.entryDeletes) 'entryDelete $e',
  'added ${d.added}',
  'updated ${d.updated}',
  'deleted ${d.deleted}',
]..sort();

void main() {
  group('sync review choice outcomes', () {
    testWidgets('N1 brought-over: this vault restores the old value', (
      tester,
    ) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(broughtOver: [_brought]), (r) => d = r);
      await _tapThenOk(tester, find.textContaining('Use this vault'));

      final res = d!.fieldResolutions.singleWhere((r) => r.field == 'username');
      expect(res.id, 'e1');
      expect(res.keepIncoming, isTrue, reason: 'drop path restores oldValue');
      expect(res.value, 'old@example.com');
      expect(d!.historyReplacements, isEmpty);
      expect(d!.updated, 0);
    });

    testWidgets('N2 brought-over untouched: incoming kept, old value in history',
        (tester) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(broughtOver: [_brought]), (r) => d = r);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(d!.fieldResolutions, isEmpty);
      final h = d!.historyReplacements.singleWhere((r) => r.field == 'username');
      expect(h.newValue, 'new@example.com');
      expect(h.replacedValue, 'old@example.com');
      expect(d!.updated, 1);
    });

    testWidgets('N3 clash: other vault applies incoming, local goes to history',
        (tester) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(fieldConflicts: [_clash]), (r) => d = r);
      await _tapThenOk(tester, find.textContaining('Use other vault'));

      expect(d!.fieldResolutions, isEmpty);
      final h = d!.historyReplacements.singleWhere((r) => r.field == 'url');
      expect(h.newValue, 'https://incoming.example.com');
      expect(h.replacedValue, 'https://local.example.com');
      expect(d!.updated, 1);
    });

    testWidgets('N4 clash: this vault keeps the local value', (tester) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(fieldConflicts: [_clash]), (r) => d = r);
      await _tapThenOk(tester, find.textContaining('Use this vault'));

      expect(d!.historyReplacements, isEmpty);
      final res = d!.fieldResolutions.singleWhere((r) => r.field == 'url');
      expect(res.keepIncoming, isFalse);
      expect(res.value, 'https://incoming.example.com',
          reason: 'stamps the seen incoming value so it stops re-clashing');
      expect(d!.updated, 0);
    });

    testWidgets('N5 folder: each choice yields that folder', (tester) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(folderConflicts: [_folder]), (r) => d = r);
      await _tapThenOk(tester, find.text('Move to "Incoming"'));
      expect(d!.folders.single.folder, 'Incoming');
      expect(d!.updated, 1);

      d = null;
      await openReview(tester, _summary(folderConflicts: [_folder]), (r) => d = r);
      await _tapThenOk(tester, find.text('Keep "Local"'));
      expect(d!.folders.single.folder, 'Local');
      expect(d!.updated, 0);
    });
  });

  group('R1 incoming choice renders first', () {
    testWidgets('brought-over field', (tester) async {
      await openReview(tester, _summary(broughtOver: [_brought]), (_) {});
      _incomingFirst(tester, 'Use other vault', 'Use this vault');
    });

    testWidgets('clashing field', (tester) async {
      await openReview(tester, _summary(fieldConflicts: [_clash]), (_) {});
      _incomingFirst(tester, 'Use other vault', 'Use this vault');
    });

    testWidgets('folder clash', (tester) async {
      await openReview(tester, _summary(folderConflicts: [_folder]), (_) {});
      _incomingFirst(tester, 'Move to "Incoming"', 'Keep "Local"');
    });

    testWidgets('item delete', (tester) async {
      await openReview(
        tester,
        _summary(pendingItemDeletes: [_itemDelete]),
        (_) {},
      );
      _incomingFirst(tester, 'Delete', 'Keep', exact: true);
    });

    // "Unfoldered" is not English anyone says; every other locale already reads
    // "keep without folder" / "move to no folder". These pin the English to the
    // wording the translators used, in both directions.
    testWidgets('folder clash, this vault has no folder', (tester) async {
      await openReview(
        tester,
        _summary(
          folderConflicts: [
            const FolderConflictItem(
              id: 'e1',
              title: 'Example',
              localFolder: '',
              incomingFolder: 'Work',
            ),
          ],
        ),
        (_) {},
      );
      _incomingFirst(tester, 'Move to "Work"', 'Keep without folder');
    });

    testWidgets('folder clash, other vault has no folder', (tester) async {
      await openReview(
        tester,
        _summary(
          folderConflicts: [
            const FolderConflictItem(
              id: 'e1',
              title: 'Example',
              localFolder: 'Work',
              incomingFolder: '',
            ),
          ],
        ),
        (_) {},
      );
      _incomingFirst(tester, 'Move to no folder', 'Keep "Work"');
    });

    testWidgets('whole-entry delete', (tester) async {
      await openReview(tester, _summary(pendingDeletes: [_entryDelete]), (_) {});
      _incomingFirst(tester, 'Delete', 'Keep', exact: true);
    });

    testWidgets('R7 new entry: Keep is the incoming side, so it comes first', (
      tester,
    ) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(addedEntries: [_newEntry]), (r) => d = r);
      _incomingFirst(tester, 'Keep', 'Skip', exact: true);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(d!.entryDeletes, isNot(contains('n')));
      expect(d!.added, 1);
    });
  });

  group('untouched choices default to incoming', () {
    testWidgets('R4 an untouched clash no longer blocks Continue', (
      tester,
    ) async {
      await openReview(tester, _summary(fieldConflicts: [_clash]), (_) {});
      final ok = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'OK'),
      );
      expect(ok.onPressed, isNotNull);
    });

    testWidgets('R2 clash untouched applies the incoming value', (tester) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(fieldConflicts: [_clash]), (r) => d = r);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(d, isNotNull, reason: 'OK must be enabled with no choice made');
      expect(d!.fieldResolutions, isEmpty);
      final h = d!.historyReplacements.singleWhere((r) => r.field == 'url');
      expect(h.newValue, 'https://incoming.example.com');
      expect(h.replacedValue, 'https://local.example.com');
      expect(d!.updated, 1);
    });

    testWidgets('R3 folder untouched moves to the incoming folder', (
      tester,
    ) async {
      SyncReviewDecisions? d;
      await openReview(tester, _summary(folderConflicts: [_folder]), (r) => d = r);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(d, isNotNull, reason: 'OK must be enabled with no choice made');
      expect(d!.folders.single.folder, 'Incoming');
      expect(d!.updated, 1);
    });

    testWidgets('R5 item delete untouched deletes the item', (tester) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(pendingItemDeletes: [_itemDelete]),
        (r) => d = r,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(d!.itemDeletes.single.delete, isTrue);
      expect(d!.updated, 1);
    });

    testWidgets('R6 whole-entry delete untouched deletes the entry', (
      tester,
    ) async {
      SyncReviewDecisions? d;
      await openReview(
        tester,
        _summary(pendingDeletes: [_entryDelete]),
        (r) => d = r,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(d!.entryDeletes, contains('g'));
      expect(d!.deleted, 1);
    });
  });

  testWidgets('R8 a zero-tap review equals merging the rest automatically', (
    tester,
  ) async {
    MergeSummary everything() => _summary(
      addedEntries: [_newEntry],
      broughtOver: [_brought],
      fieldConflicts: [_clash],
      folderConflicts: [_folder],
      pendingDeletes: [_entryDelete],
      pendingItemDeletes: [_itemDelete],
    );

    // Step through every step touching nothing. Bounded: a disabled Continue
    // would otherwise spin forever instead of failing.
    SyncReviewDecisions? stepped;
    await openReview(tester, everything(), (r) => stepped = r);
    for (var i = 0; i < 8 && find.text('Continue').evaluate().isNotEmpty; i++) {
      await _tapAction(tester, 'Continue');
    }
    expect(find.text('Continue'), findsNothing, reason: 'stuck on a step');
    await _tapAction(tester, 'OK');

    // Bail out on the first step instead.
    SyncReviewDecisions? bailed;
    await openReview(tester, everything(), (r) => bailed = r);
    await _tapAction(tester, 'Cancel');
    await _tapAction(tester, 'Merge automatically');

    expect(stepped, isNotNull);
    expect(bailed, isNotNull);
    expect(_fingerprint(stepped!), _fingerprint(bailed!));
  });
}
