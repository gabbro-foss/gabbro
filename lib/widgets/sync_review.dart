import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/vault.dart';

/// What a single review step is about.
enum SyncStepKind {
  /// A whole entry that exists only on the other device (keep or drop).
  newEntry,

  /// An existing entry with incoming changes: brought-over values, clashes to
  /// pick, and/or items the other device deleted.
  changes,

  /// A whole entry the other device deleted (keep or delete).
  deleteEntry,
}

/// One step of the one-by-one sync review: everything to review for a single
/// entry, shown on a single screen.
class SyncReviewStep {
  final String id;
  final String title;
  final SyncStepKind kind;

  /// Set when [kind] is [SyncStepKind.newEntry].
  final AddedEntryItem? added;

  /// Set when [kind] is [SyncStepKind.deleteEntry].
  final PendingDeleteItem? entryDelete;

  /// Non-conflicting incoming values (keep by default, droppable).
  final List<BroughtOverItem> broughtOver;

  /// Same-field clashes the user must pick.
  final List<FieldConflictItem> conflicts;

  /// Items the other device deleted (keep or delete).
  final List<PendingItemDeleteItem> itemDeletes;

  /// A differing folder assignment, if any (the user must pick).
  final FolderConflictItem? folderConflict;

  const SyncReviewStep({
    required this.id,
    required this.title,
    required this.kind,
    this.added,
    this.entryDelete,
    this.broughtOver = const [],
    this.conflicts = const [],
    this.itemDeletes = const [],
    this.folderConflict,
  });

  /// True when this step has a choice with no safe default, so the user must act
  /// before moving on (a clash, or a folder difference).
  bool get needsChoice => conflicts.isNotEmpty || folderConflict != null;
}

/// Group a [MergeSummary] into ordered per-entry review steps: new entries first,
/// then entries with incoming changes, then whole-entry deletes. All of one
/// entry's changes land in a single step so the user reviews it in one place.
List<SyncReviewStep> buildSyncReviewSteps(MergeSummary summary) {
  final steps = <SyncReviewStep>[];

  for (final a in summary.addedEntries) {
    steps.add(
      SyncReviewStep(
        id: a.id,
        title: a.title,
        kind: SyncStepKind.newEntry,
        added: a,
      ),
    );
  }

  // Union of ids that carry incoming changes, in first-seen order.
  final changeIds = <String>[];
  final seen = <String>{};
  void note(String id) {
    if (seen.add(id)) changeIds.add(id);
  }

  for (final b in summary.broughtOver) {
    note(b.id);
  }
  for (final c in summary.fieldConflicts) {
    note(c.id);
  }
  for (final d in summary.pendingItemDeletes) {
    note(d.id);
  }
  for (final f in summary.folderConflicts) {
    note(f.id);
  }

  for (final id in changeIds) {
    final bo = summary.broughtOver.where((x) => x.id == id).toList();
    final cf = summary.fieldConflicts.where((x) => x.id == id).toList();
    final del = summary.pendingItemDeletes.where((x) => x.id == id).toList();
    final fc = summary.folderConflicts.where((x) => x.id == id).toList();
    final title = bo.isNotEmpty
        ? bo.first.title
        : cf.isNotEmpty
        ? cf.first.title
        : del.isNotEmpty
        ? del.first.title
        : fc.first.title;
    steps.add(
      SyncReviewStep(
        id: id,
        title: title,
        kind: SyncStepKind.changes,
        broughtOver: bo,
        conflicts: cf,
        itemDeletes: del,
        folderConflict: fc.isEmpty ? null : fc.first,
      ),
    );
  }

  for (final d in summary.pendingDeletes) {
    steps.add(
      SyncReviewStep(
        id: d.id,
        title: d.title,
        kind: SyncStepKind.deleteEntry,
        entryDelete: d,
      ),
    );
  }

  return steps;
}

// ── The user's decisions, applied by the caller via the existing FFI calls ─────

/// Set a field/pair to a value: keep-mine on a clash (`keepIncoming` false), or a
/// dropped brought-over EDIT (`keepIncoming` true with the OLD value to restore
/// it). Mirrors `onResolveFieldConflict`.
class SyncFieldResolution {
  final String id;
  final String field;
  final bool keepIncoming;
  final String value;
  const SyncFieldResolution(this.id, this.field, this.keepIncoming, this.value);
}

/// Set `field` to `newValue` and keep `replacedValue` in the entry's recovery
/// history: a kept brought-over EDIT (old local value retained) or a clash
/// resolved to the other device's value (losing local value retained). Mirrors
/// `onReplaceFieldWithHistory`.
class SyncHistoryReplacement {
  final String id;
  final String field;
  final String newValue;
  final String replacedValue;
  const SyncHistoryReplacement(
      this.id, this.field, this.newValue, this.replacedValue);
}

/// Keep or delete an item (custom pair / attachment). Mirrors `onResolveItemDelete`.
class SyncItemDeleteResolution {
  final String id;
  final String field;
  final bool delete;
  const SyncItemDeleteResolution(this.id, this.field, this.delete);
}

/// Assign a chosen folder to an entry.
class SyncFolderResolution {
  final String id;
  final String folder;
  const SyncFolderResolution(this.id, this.folder);
}

/// The full set of decisions to apply after the review completes.
class SyncReviewDecisions {
  final List<SyncFieldResolution> fieldResolutions;
  final List<SyncHistoryReplacement> historyReplacements;
  final List<SyncItemDeleteResolution> itemDeletes;
  final List<SyncFolderResolution> folders;

  /// Entries to delete: dropped new entries and confirmed whole-entry deletes.
  final List<String> entryDeletes;

  /// Tallies reflecting what the user actually kept, for the post-sync summary:
  /// new entries kept, entries changed, and whole-entry deletes confirmed. A
  /// skipped new entry counts as none of these.
  final int added;
  final int updated;
  final int deleted;

  /// The entry titles behind each tally, for the itemized "Details" summary.
  /// Same membership as [added] / [updated] / [deleted] respectively.
  final List<String> addedTitles;
  final List<String> updatedTitles;
  final List<String> deletedTitles;

  /// True when the user cancelled the whole sync from the review. The caller must
  /// then roll back to the pre-sync state (apply nothing).
  final bool cancelled;

  const SyncReviewDecisions({
    this.fieldResolutions = const [],
    this.historyReplacements = const [],
    this.itemDeletes = const [],
    this.folders = const [],
    this.entryDeletes = const [],
    this.added = 0,
    this.updated = 0,
    this.deleted = 0,
    this.addedTitles = const [],
    this.updatedTitles = const [],
    this.deletedTitles = const [],
    this.cancelled = false,
  });
}

bool _isAddedItem(String field, String oldValue) =>
    field.startsWith('attachments:') ||
    (field.startsWith('custom_fields:') && oldValue.isEmpty);

String _fieldLabel(String field) {
  for (final prefix in const ['custom_fields:', 'attachments:']) {
    if (field.startsWith(prefix)) return field.substring(prefix.length);
  }
  return field;
}

const _secretFields = {'password', 'cvv', 'pin', 'transaction_password'};

bool _isSecret(String field) => _secretFields.contains(field);

/// Binary fields whose value rides the resolution path as base64 (File
/// contents). They must never render their raw value — always `<binary>`.
bool _isBinary(String field) => field == 'data';

/// Show the one-by-one review and return the user's decisions, or null if there
/// is nothing to review. Non-dismissible: the user steps to the end.
Future<SyncReviewDecisions?> showSyncReview({
  required BuildContext context,
  required List<SyncReviewStep> steps,
}) {
  if (steps.isEmpty) return Future.value(null);
  return showDialog<SyncReviewDecisions>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SyncReviewSheet(steps: steps),
  );
}

class _SyncReviewSheet extends StatefulWidget {
  final List<SyncReviewStep> steps;
  const _SyncReviewSheet({required this.steps});

  @override
  State<_SyncReviewSheet> createState() => _SyncReviewSheetState();
}

class _SyncReviewSheetState extends State<_SyncReviewSheet> {
  int _index = 0;

  // Keyed "id field" or by id, as noted. Defaults favour keeping everything.
  final Map<String, bool> _keepBrought = {}; // default true
  final Map<String, bool> _keepNewEntry = {}; // default true
  final Map<String, bool> _deleteItem = {}; // default false
  final Map<String, bool?> _conflictUseTheirs = {}; // null until picked
  final Map<String, String?> _folderChoice = {}; // null until picked
  final Map<String, bool> _confirmEntryDelete = {}; // default false

  /// Secret fields the user has revealed, keyed by "id field". Default hidden.
  final Set<String> _revealed = {};

  String _k(String id, String field) => '$id $field';

  bool _stepSatisfied(SyncReviewStep step) {
    for (final c in step.conflicts) {
      if (_conflictUseTheirs[_k(c.id, c.field)] == null) return false;
    }
    if (step.folderConflict != null && _folderChoice[step.id] == null) {
      return false;
    }
    return true;
  }

  String _disp(
    String field,
    String value,
    AppLocalizations l, {
    bool revealed = false,
  }) {
    if (_isSecret(field) && !revealed) return '••••';
    if (_isBinary(field)) return '<binary>';
    return value.isEmpty ? l.reviewEmpty : value;
  }

  /// A two-choice keep-vs-other picker (keep / delete or keep / skip), matching
  /// the clash picker so every keep/remove decision is explicitly labelled.
  // A ChoiceChip is locked to a single 48px line, so at large text it silently
  // clips a long field value (a URL, a password) and it can't be read or
  // compared (hardware: phone portrait, review-all). Past 1.5x render each
  // choice as a full-width row — a radio marker + the value as wrapping Text
  // (Flutter char-wraps even an unbroken password) — instead of a chip. Compact
  // chips stay at normal text (ADR-016).
  Widget _choiceRow(
    List<({String label, bool selected, VoidCallback onSelect})> choices,
  ) {
    if (MediaQuery.textScalerOf(context).scale(1) <= 1.5) {
      return Wrap(
        spacing: 8,
        children: [
          for (final c in choices)
            ChoiceChip(
              label: Text(c.label),
              selected: c.selected,
              onSelected: (_) => c.onSelect(),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in choices)
          InkWell(
            onTap: c.onSelect,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    c.selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.label)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _keepDeleteChips({
    required bool keepSelected,
    required String keepLabel,
    required String otherLabel,
    required VoidCallback onKeep,
    required VoidCallback onOther,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: _choiceRow([
      (label: keepLabel, selected: keepSelected, onSelect: onKeep),
      (label: otherLabel, selected: !keepSelected, onSelect: onOther),
    ]),
  );

  /// Eye toggle for a secret field, mirroring the entry-detail reveal idiom.
  Widget _eye(String key, bool revealed, AppLocalizations l) => IconButton(
    icon: Icon(revealed ? Icons.visibility : Icons.visibility_off),
    tooltip: revealed ? l.tooltipHide : l.tooltipShow,
    onPressed: () => setState(() {
      if (revealed) {
        _revealed.remove(key);
      } else {
        _revealed.add(key);
      }
    }),
  );

  /// Build and return the decisions. [fastRest] resolves every step the user has
  /// NOT explicitly decided in favour of the incoming vault (the "merge the rest
  /// automatically" bail-out); hand-made picks are always honoured.
  void _finish({bool fastRest = false}) {
    final fields = <SyncFieldResolution>[];
    final history = <SyncHistoryReplacement>[];
    final items = <SyncItemDeleteResolution>[];
    final folders = <SyncFolderResolution>[];
    final entryDeletes = <String>[];
    final addedTitles = <String>[];
    final updatedTitles = <String>[];
    final deletedTitles = <String>[];

    for (final step in widget.steps) {
      switch (step.kind) {
        case SyncStepKind.newEntry:
          // Both modes keep a new entry unless the user chose Skip.
          if (_keepNewEntry[step.id] == false) {
            entryDeletes.add(step.id);
          } else {
            addedTitles.add(step.title);
          }
          break;
        case SyncStepKind.deleteEntry:
          // Fast-rest applies the incoming delete; normal keeps unless confirmed.
          if (_confirmEntryDelete[step.id] ?? fastRest) {
            entryDeletes.add(step.id);
            deletedTitles.add(step.title);
          }
          break;
        case SyncStepKind.changes:
          var stepChanged = false;
          for (final b in step.broughtOver) {
            final kept = _keepBrought[_k(b.id, b.field)] ?? true;
            final isAdd = _isAddedItem(b.field, b.oldValue);
            if (!kept) {
              // Drop: an added item is removed; an edit is restored to its old
              // value.
              if (isAdd) {
                items.add(SyncItemDeleteResolution(b.id, b.field, true));
              } else {
                fields.add(SyncFieldResolution(b.id, b.field, true, b.oldValue));
              }
            } else {
              // Kept the incoming value: the entry ends up changed.
              stepChanged = true;
              if (!isAdd && b.oldValue.isNotEmpty) {
                // Keep an edit: retain the replaced old value in history.
                history.add(SyncHistoryReplacement(
                    b.id, b.field, b.newValue, b.oldValue));
              }
            }
          }
          for (final c in step.conflicts) {
            // Undecided clashes take theirs under fast-rest, mine otherwise.
            final useTheirs = _conflictUseTheirs[_k(c.id, c.field)] ?? fastRest;
            if (useTheirs) {
              // Apply theirs; keep the losing local value in history.
              stepChanged = true;
              history.add(SyncHistoryReplacement(
                  c.id, c.field, c.incomingValue, c.localValue));
            } else {
              // Keep mine: stamp the choice so it stops re-clashing.
              fields.add(
                SyncFieldResolution(c.id, c.field, false, c.incomingValue),
              );
            }
          }
          for (final d in step.itemDeletes) {
            // Undecided item-deletes apply the incoming delete under fast-rest.
            final del = _deleteItem[_k(d.id, d.field)] ?? fastRest;
            if (del) stepChanged = true;
            items.add(SyncItemDeleteResolution(d.id, d.field, del));
          }
          final fc = step.folderConflict;
          if (fc != null) {
            // Undecided folder clashes take the incoming folder under fast-rest.
            final chosen = _folderChoice[step.id] ??
                (fastRest ? fc.incomingFolder : fc.localFolder);
            if (chosen != fc.localFolder) stepChanged = true;
            folders.add(SyncFolderResolution(fc.id, chosen));
          }
          if (stepChanged) updatedTitles.add(step.title);
          break;
      }
    }

    Navigator.of(context).pop(
      SyncReviewDecisions(
        fieldResolutions: fields,
        historyReplacements: history,
        itemDeletes: items,
        folders: folders,
        entryDeletes: entryDeletes,
        added: addedTitles.length,
        updated: updatedTitles.length,
        deleted: deletedTitles.length,
        addedTitles: addedTitles,
        updatedTitles: updatedTitles,
        deletedTitles: deletedTitles,
      ),
    );
  }

  /// Bail-out chooser: stop stepping through and either cancel the whole sync or
  /// merge everything remaining automatically (incoming wins). "Keep reviewing"
  /// just dismisses the chooser.
  Future<void> _bail() async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Scroll the whole dialog so the three choices stay reachable at large
        // text (ADR-016).
        scrollable: true,
        title: Text(l.syncStopTitle),
        content: Text(l.syncStopBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.syncStopKeepReviewing),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _finish(fastRest: true);
            },
            child: Text(l.syncMergeAutomatically),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(
                context,
              ).pop(const SyncReviewDecisions(cancelled: true));
            },
            child: Text(l.syncStopCancel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final step = widget.steps[_index];
    final isLast = _index == widget.steps.length - 1;
    final canAdvance = _stepSatisfied(step);

    return AlertDialog(
      // Scroll the whole dialog (title + content + actions) so nothing is
      // stranded off-screen at large text (ADR-016). A plain Column here, not an
      // inner SingleChildScrollView, which would nest scrollables and throw.
      scrollable: true,
      title: Text(
        '${l.reviewChangesTitle}  ${_index + 1}/${widget.steps.length}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildStep(step, l),
      ),
      actions: [
        TextButton(onPressed: _bail, child: Text(l.cancel)),
        TextButton(
          onPressed: canAdvance
              ? (isLast ? _finish : () => setState(() => _index++))
              : null,
          child: Text(isLast ? l.ok : l.continueAction),
        ),
      ],
    );
  }

  List<Widget> _buildStep(SyncReviewStep step, AppLocalizations l) {
    switch (step.kind) {
      case SyncStepKind.newEntry:
        final keepNew = _keepNewEntry[step.id] ?? true;
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('${l.newEntryTitle}: ${step.title}'),
          ),
          _keepDeleteChips(
            keepSelected: keepNew,
            keepLabel: l.keep,
            otherLabel: l.skip,
            onKeep: () => setState(() => _keepNewEntry[step.id] = true),
            onOther: () => setState(() => _keepNewEntry[step.id] = false),
          ),
        ];
      case SyncStepKind.deleteEntry:
        final confirmDel = _confirmEntryDelete[step.id] ?? false;
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l.syncDeleteEntryContent(step.title)),
          ),
          _keepDeleteChips(
            keepSelected: !confirmDel,
            keepLabel: l.keep,
            otherLabel: l.delete,
            onKeep: () => setState(() => _confirmEntryDelete[step.id] = false),
            onOther: () => setState(() => _confirmEntryDelete[step.id] = true),
          ),
        ];
      case SyncStepKind.changes:
        final widgets = <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text(
              step.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ];
        for (final b in step.broughtOver) {
          final key = _k(b.id, b.field);
          final secret = _isSecret(b.field);
          final revealed = _revealed.contains(key);
          final keep = _keepBrought[key] ?? true;
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Row(
                children: [
                  Text(
                    _fieldLabel(b.field),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (secret) _eye(key, revealed, l),
                ],
              ),
            ),
          );
          widgets.add(
            _keepDeleteChips(
              keepSelected: keep,
              keepLabel:
                  '${l.syncOtherVault}: ${_disp(b.field, b.newValue, l, revealed: revealed)}',
              otherLabel:
                  '${l.syncThisVault}: ${_disp(b.field, b.oldValue, l, revealed: revealed)}',
              onKeep: () => setState(() => _keepBrought[key] = true),
              onOther: () => setState(() => _keepBrought[key] = false),
            ),
          );
        }
        for (final c in step.conflicts) {
          final key = _k(c.id, c.field);
          final pick = _conflictUseTheirs[key];
          final secret = _isSecret(c.field);
          final revealed = _revealed.contains(key);
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Row(
                children: [
                  Text(
                    _fieldLabel(c.field),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (secret) _eye(key, revealed, l),
                ],
              ),
            ),
          );
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _choiceRow([
                (
                  label:
                      '${l.syncThisVault}: ${_disp(c.field, c.localValue, l, revealed: revealed)}',
                  selected: pick == false,
                  onSelect: () =>
                      setState(() => _conflictUseTheirs[key] = false),
                ),
                (
                  label:
                      '${l.syncOtherVault}: ${_disp(c.field, c.incomingValue, l, revealed: revealed)}',
                  selected: pick == true,
                  onSelect: () =>
                      setState(() => _conflictUseTheirs[key] = true),
                ),
              ]),
            ),
          );
        }
        for (final d in step.itemDeletes) {
          final key = _k(d.id, d.field);
          final del = _deleteItem[key] ?? false;
          widgets.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l.syncDeleteEntryContent(_fieldLabel(d.field))),
            ),
          );
          widgets.add(
            _keepDeleteChips(
              keepSelected: !del,
              keepLabel: l.keep,
              otherLabel: l.delete,
              onKeep: () => setState(() => _deleteItem[key] = false),
              onOther: () => setState(() => _deleteItem[key] = true),
            ),
          );
        }
        final fc = step.folderConflict;
        if (fc != null) {
          final choice = _folderChoice[step.id];
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Text(
                l.folderConflictTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _choiceRow([
                (
                  label: fc.localFolder.isEmpty
                      ? l.folderConflictKeepUnfoldered
                      : l.folderConflictKeepLocal(fc.localFolder),
                  selected: choice == fc.localFolder,
                  onSelect: () =>
                      setState(() => _folderChoice[step.id] = fc.localFolder),
                ),
                (
                  label: fc.incomingFolder.isEmpty
                      ? l.folderConflictMoveUnfoldered
                      : l.folderConflictMoveIncoming(fc.incomingFolder),
                  selected: choice == fc.incomingFolder,
                  onSelect: () => setState(
                    () => _folderChoice[step.id] = fc.incomingFolder,
                  ),
                ),
              ]),
            ),
          );
        }
        return widgets;
    }
  }
}
