import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/sync_review.dart';

import 'test_helpers.dart';

// ADR-016 large-text: the sync-review dialogs must scroll as a whole so no
// button or content is stranded off-screen at large text (hardware: on a phone
// the review sheet showed nothing and the bail-out "Merge automatically" button
// could not be reached). The structural guarantee is `AlertDialog.scrollable`.

MergeSummary _summary() => MergeSummary(
  added: 1,
  updated: 0,
  addedEntries: const [AddedEntryItem(id: 'n', title: 'New')],
  broughtOver: const [],
  pendingDeletes: const [],
  folderConflicts: const [],
  fieldConflicts: const [],
  pendingItemDeletes: const [],
);

// A long non-secret value (url) that would clip in a single-line chip.
const _longValue =
    'https://accounts.example.com/very/long/path/that/overflows/a/chip?token=abcdefghijklmnopqrstuvwxyz0123456789';

// A long generated password: the hardware case behind the value-choice fix (a
// revealed secret in a chip could not be read at normal text).
const _longSecret = 'hunter2xK9#mQvL3pR8sTwY6zA1bC4dE7fG0hJ2kM';

// A whole-entry delete: its choices are bare Keep/Delete labels carrying no
// value, so they stay compact chips (ADR-016).
MergeSummary _deleteSummary() => const MergeSummary(
  added: 0,
  updated: 0,
  addedEntries: [],
  broughtOver: [],
  pendingDeletes: [PendingDeleteItem(id: 'd1', title: 'Old login')],
  folderConflicts: [],
  fieldConflicts: [],
  pendingItemDeletes: [],
);

MergeSummary _secretConflictSummary() => const MergeSummary(
  added: 0,
  updated: 1,
  addedEntries: [],
  broughtOver: [],
  pendingDeletes: [],
  folderConflicts: [],
  fieldConflicts: [
    FieldConflictItem(
      id: 'e1',
      title: 'Mail',
      field: 'password',
      localValue: _longSecret,
      incomingValue: 'shortpw',
    ),
  ],
  pendingItemDeletes: [],
);

MergeSummary _folderConflictSummary() => const MergeSummary(
  added: 0,
  updated: 1,
  addedEntries: [],
  broughtOver: [],
  pendingDeletes: [],
  folderConflicts: [
    FolderConflictItem(
      id: 'e1',
      title: 'Login',
      localFolder: 'Personal/Banking/Long folder name that will not fit',
      incomingFolder: 'Work',
    ),
  ],
  fieldConflicts: [],
  pendingItemDeletes: [],
);

MergeSummary _conflictSummary() => const MergeSummary(
  added: 0,
  updated: 1,
  addedEntries: [],
  broughtOver: [],
  pendingDeletes: [],
  folderConflicts: [],
  fieldConflicts: [
    FieldConflictItem(
      id: 'e1',
      title: 'Login',
      field: 'url',
      localValue: _longValue,
      incomingValue: 'https://other.example.org/short',
    ),
  ],
  pendingItemDeletes: [],
);

Future<void> _openReview(WidgetTester tester) async {
  final steps = buildSyncReviewSteps(_summary());
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

// Opens the review at [scale] via MaterialApp.builder so the pushed dialog
// (a root-navigator route) inherits the scaled textScaler.
Future<void> _openReviewScaled(
  WidgetTester tester,
  double scale, {
  MergeSummary? summary,
}) async {
  final steps = buildSyncReviewSteps(summary ?? _summary());
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Builder(
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

Finder _chipsInWraps() => find.descendant(
  of: find.byType(Wrap),
  matching: find.byType(ChoiceChip),
);

AlertDialog _dialogContaining(WidgetTester tester, String text) =>
    tester.widget<AlertDialog>(
      find.ancestor(
        of: find.text(text),
        matching: find.byType(AlertDialog),
      ),
    );

void main() {
  testWidgets('review sheet is a fully scrollable dialog', (tester) async {
    await _openReview(tester);
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
  });

  testWidgets('bail-out dialog is fully scrollable and reaches Merge automatically',
      (tester) async {
    await _openReview(tester);
    // Cancel on the review sheet opens the bail-out chooser.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Merge automatically'), findsOneWidget);
    expect(_dialogContaining(tester, 'Stop reviewing?').scrollable, isTrue);
  });

  // Was 'choices are chips in a Wrap at normal text', pinned against a value
  // choice. That is the behaviour being removed: a value choice is now a
  // wrapping row at every text size (see the red tests below). Retargeted
  // deliberately onto the choices that DO stay chips — bare Keep/Delete labels
  // that carry no value and so can never clip.
  testWidgets('bare keep/delete choices stay chips at normal text', (
    tester,
  ) async {
    await _openReviewScaled(tester, 1.0, summary: _deleteSummary());
    expect(_chipsInWraps(), findsWidgets);
    expect(find.widgetWithText(ChoiceChip, 'Keep'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Delete'), findsOneWidget);
  });

  testWidgets('long value shows as a full wrapping row, not a clipped chip, at large text',
      (tester) async {
    // A ChoiceChip is single-line and clips a long value; the choice becomes a
    // radio row whose value is real wrapping text you can read
    // (hardware: phone portrait review-all, could not see the values).
    await _openReviewScaled(tester, 2.0, summary: _conflictSummary());
    expect(find.byType(ChoiceChip), findsNothing);
    // Radio-style rows carry the full value as visible text.
    expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);
    expect(find.textContaining(_longValue), findsOneWidget);
  });

  // A chip is a single 48px line with no way to scroll it, so a long value is
  // clipped at NORMAL text too — the user picks between two values they cannot
  // read (hardware: sync review on a phone). Value choices therefore drop the
  // chip at every text size.
  testWidgets('a value choice is a wrapping row at normal text, not a chip', (
    tester,
  ) async {
    await _openReviewScaled(tester, 1.0, summary: _conflictSummary());
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);
    expect(find.textContaining(_longValue), findsOneWidget);
  });

  testWidgets('a revealed long secret is readable in full at normal text', (
    tester,
  ) async {
    await _openReviewScaled(tester, 1.0, summary: _secretConflictSummary());
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.textContaining(_longSecret), findsOneWidget);
  });

  testWidgets('a folder choice is a wrapping row at normal text', (
    tester,
  ) async {
    // Folder names are user data and can be long, so they clip like any value.
    await _openReviewScaled(tester, 1.0, summary: _folderConflictSummary());
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);
  });
}
