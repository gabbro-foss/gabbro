import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:gabbro/control_scale.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/screens/section_index.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/focus_region.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// ---------------------------------------------------------------------------
// TabletVaultLayout
//
// Two-pane layout for screens ≥600dp wide.
//
// Structure (left → right):
//   AlphabetIndexBar (≈28dp) | list pane | detail pane
//
// Appearance / Security / About, and every vault operation (export, import,
// etc.), live in the app-bar popup menu owned by the parent VaultListScreen.
// A NavigationRail used to offer the first three as well; it was removed as a
// second way to the same screens.
//
// Interaction states:
//   browse   — list selection active, detail shows selected entry or empty state
//   editing  — detail pane is edit form; list pane dimmed + non-interactive
// ---------------------------------------------------------------------------

// Bottom padding reserved in the detail pane so its last item clears the
// Scaffold-level add-entry FAB (56dp diameter + 16dp margin) that floats over
// the bottom-right corner in two-pane mode. The FAB box is a fixed size — only
// its child icon scales at large text — so a constant clearance suffices.
const double _detailPaneFabClearance = 88;

class TabletVaultLayout extends StatefulWidget {
  /// All entries currently loaded (filtered + grouped by the parent).
  final List<dynamic> groupedEntries;

  /// The flat filtered list — needed for select-all count.
  final List<EntrySummaryData> filteredEntries;

  /// Letter → index map for the alphabet bar.
  final Map<String, int> letterIndex;

  /// Canonical alphabet (locale's script) for the index bar. Null = Latin.
  final List<String>? barLetters;

  /// Whether the locale's script supports an index bar (false for ja/zh).
  final bool showIndexBar;

  /// Called when the alphabet bar taps a letter.
  final void Function(String) onLetterSelected;

  /// Render the title for an entry (delegates to parent helper).
  final String Function(EntrySummaryData) displayTitle;

  /// Render the display type label (delegates to parent helper).
  final String Function(String) displayType;

  /// Icon for an entry type (delegates to parent helper).
  final IconData Function(String) entryTypeIcon;

  /// Search bar widget — built by parent, passed in to avoid duplication.
  final Widget searchBar;

  /// Filter chip row widget — built by parent, passed in.
  final Widget filterChipRow;

  /// Whether the search query is non-empty (hides alphabet bar when true).
  final bool searchActive;

  /// Called when an entry is tapped in the list (triggers detail reload).
  final void Function(String id) onEntryTap;

  /// Called when the list needs refreshing (after edit/delete).
  final void Function() onRefresh;

  /// Clipboard clear timeout from settings.
  final ClipboardClearTimeout clipboardClearTimeout;

  /// Optional override for fetching a full entry — used in tests to avoid
  /// hitting the Rust bridge.
  final VaultEntryData Function(String id)? getEntryFn;

  /// Optional override for deleting an entry — used in tests.
  final Future<void> Function(String id)? onDeleteEntryFn;

  /// Whether selection mode is active (driven by parent).
  final bool selectionMode;

  /// Currently selected entry ids (driven by parent).
  final Set<String> selectedIds;

  /// Called when a list tile is long-pressed or tapped in selection mode.
  final void Function(String id) onToggleSelection;

  /// Keyboard Tab-cycle regions for the list and detail panes (desktop only;
  /// null on Android, so the widget tree is unchanged there). The scopes are
  /// owned by the parent VaultListScreen — the regions span both widgets (see
  /// reference two-layout-paths). The detail scope is mounted only while an entry
  /// is selected, which is how the cycle knows detail is a reachable stop.
  final FocusScopeNode? listScope;
  final FocusScopeNode? detailScope;

  const TabletVaultLayout({
    super.key,
    required this.groupedEntries,
    required this.filteredEntries,
    required this.letterIndex,
    this.barLetters,
    this.showIndexBar = true,
    required this.onLetterSelected,
    required this.displayTitle,
    required this.displayType,
    required this.entryTypeIcon,
    required this.searchBar,
    required this.filterChipRow,
    required this.searchActive,
    required this.onEntryTap,
    required this.onRefresh,
    required this.clipboardClearTimeout,
    this.getEntryFn,
    this.onDeleteEntryFn,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelection,
    this.listScope,
    this.detailScope,
  });

  @override
  State<TabletVaultLayout> createState() => _TabletVaultLayoutState();
}

class _TabletVaultLayoutState extends State<TabletVaultLayout> {
  // Currently selected entry id — null means empty state in detail pane.
  String? _selectedEntryId;

  final ItemScrollController _itemScrollController = ItemScrollController();

  double _listPaneWidth = 260.0;
  bool _listPaneWidthInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listPaneWidthInitialized) {
      _listPaneWidthInitialized = true;
      _listPaneWidth =
          GabbroApp.maybeOf(context)?.settings.tabletListPaneWidth ?? 260.0;
    }
  }

  @override
  void didUpdateWidget(TabletVaultLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedEntryId != null &&
        !widget.filteredEntries.any((e) => e.id == _selectedEntryId)) {
      setState(() => _selectedEntryId = null);
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final l = AppLocalizations.of(context);
    // At large text `selectEntry` wraps into enough lines to outgrow the detail
    // pane, and a Column cannot shrink to fit — it overflows and the message is
    // clipped. Scrolling keeps the whole placeholder readable (ADR-016).
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(l.selectEntry, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    if (_selectedEntryId == null || widget.filteredEntries.isEmpty) {
      return _buildEmptyState(context);
    }
    // R-03 P6: the detail fetch runs synchronously during build. If the
    // selected entry has vanished (deleted, or a refresh race against a
    // locked/corrupted vault — the summary list can briefly disagree with the
    // session), getEntry throws and crashes the whole layout build. Fall back
    // to the empty state instead, and clear the stale selection after the frame
    // so the list and detail pane agree again.
    final VaultEntryData entry;
    try {
      entry = (widget.getEntryFn ?? (id) => getEntry(id: id))(_selectedEntryId!);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedEntryId != null) {
          setState(() => _selectedEntryId = null);
        }
      });
      return _buildEmptyState(context);
    }
    // ValueKey forces Flutter to rebuild EntryDetailScreen whenever the
    // selected id changes — this is how we refresh after an edit without
    // adding an onChanged callback to EntryDetailScreen.
    return EntryDetailScreen(
      key: ValueKey(_selectedEntryId),
      entry: entry,
      // Clear the Scaffold-level add-entry FAB (56dp + 16dp margin) that floats
      // over the detail pane's bottom-right corner in two-pane mode.
      bottomReserve: _detailPaneFabClearance,
      clipboardClearTimeout: widget.clipboardClearTimeout,
      onDeleteEntry: widget.onDeleteEntryFn ?? (id) => deleteEntry(id: id),
      onDeleted: () {
        // Reload the list FIRST. It lives in the parent's state, so it must not
        // depend on this widget's own setState having succeeded — if that throws
        // (release builds swallow it), the deleted row would otherwise sit in
        // the list until something else forced a reload.
        widget.onRefresh();
        setState(() => _selectedEntryId = null);
        // The pane the user was working in vanishes and the empty state takes
        // its place. A Linux screen reader reads a node's NAME when focus
        // arrives at it, and nothing here moves focus, so the whole thing
        // happened in silence (round 27). Speaking the empty state's own
        // visible text says the entry is gone and what is there instead.
        // Linux only, on the same gate as the rest of the region layer.
        if (_keyboardNav) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            AppLocalizations.of(context).selectEntry,
            Directionality.of(context),
          );
        }
      },
      onEdited: () => widget.onRefresh(),
    );
  }

  Widget _buildListPane(BuildContext context) {
    final theme = Theme.of(context);
    // At a large text scale the search box and the filter chips grow tall
    // enough to fill the window on their own. Only the list below them could
    // give way, so the pane ran off the bottom and the last entries could not
    // be reached (262px over, at 4x text on a 900x700 window). Cap the header
    // at 60% of the pane and let it scroll within that, so the list always
    // keeps the remaining 40%. At normal text the header is far shorter than
    // the cap, so the constraint is inert and the layout is unchanged.
    return LayoutBuilder(builder: (context, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [widget.searchBar, widget.filterChipRow],
            ),
          ),
        ),
        Expanded(
          child: _region(
            widget.listScope,
            widget.groupedEntries.isEmpty
              ? Center(child: Text(AppLocalizations.of(context).noEntriesMatch))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.searchActive == false && widget.showIndexBar)
                      SizedBox(
                        width: 48,
                        child: AlphabetIndexBar(
                          letters: widget.barLetters ?? canonicalAlphabet(null),
                          presentLetters: widget.letterIndex.keys.toSet(),
                          highContrast:
                              GabbroApp.maybeOf(context)?.settings.highContrast ??
                              false,
                          scrollUpLabel:
                              AppLocalizations.of(context).tooltipPreviousPage,
                          scrollDownLabel:
                              AppLocalizations.of(context).tooltipNextPage,
                          onLetterSelected: (letter) {
                            final index = widget.letterIndex[letter];
                            if (index == null) return;
                            _itemScrollController.scrollTo(
                              index: index,
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOut,
                            );
                          },
                        ),
                      ),
                    Expanded(
                      child: ScrollConfiguration(
                        // No bar (ja/zh) -> keep the platform-default scrollbar.
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: widget.showIndexBar ? false : null,
                        ),
                        child: ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: widget.groupedEntries.length,
                          itemBuilder: (context, index) {
                            final item = widget.groupedEntries[index];
                            if (item is String) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            }
                            final entry = item as EntrySummaryData;
                            final isSelected = entry.id == _selectedEntryId;
                            final rowOutcome = widget.selectionMode
                                ? null
                                : AppLocalizations.of(context).hintEntryRow;
                            return Container(
                              // The decoration is ALWAYS present (transparent
                              // border, no fill, when unselected). Flipping it
                              // between null and non-null changes the widget
                              // tree's SHAPE, which rebuilds the ListTile's
                              // InkWell and disposes its focus node — so
                              // opening an entry with Enter threw keyboard
                              // focus onto a neighbouring row. Keeping the
                              // border reserved also stops the row shifting
                              // 3px sideways when it is selected.
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                color: isSelected
                                    ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.3)
                                    : null,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                // Selection mode taps the row to tick it, so
                                // "opens this entry" would then be a lie.
                                child: _saysWhatItDoes(
                                  ListTile(
                                dense: true,
                                leading: widget.selectionMode
                                    // Label the checkbox with the entry title so
                                    // a screen reader names the row, not a bare
                                    // "tick box".
                                    ? MergeSemantics(
                                        child: Semantics(
                                          label: widget.displayTitle(entry),
                                          child: scaledSelectionCheckbox(
                                            context,
                                            Checkbox(
                                              value: widget.selectedIds.contains(
                                                entry.id,
                                              ),
                                              onChanged: (_) => widget
                                                  .onToggleSelection(entry.id),
                                            ),
                                          ),
                                        ),
                                      )
                                    // No semanticLabel: the subtitle below
                                    // already says the type, and labelling the
                                    // icon too made a reader announce it twice
                                    // ("card, amex, card").
                                    : Icon(
                                        widget.entryTypeIcon(entry.entryType),
                                        size: scaledIconSize(context, 20),
                                        color: theme.colorScheme.primary,
                                      ),
                                title: Text(
                                  widget.displayTitle(entry),
                                  semanticsLabel: _ownNameLabel(
                                    outcome: rowOutcome,
                                  ),
                                ),
                                subtitle: Text(
                                  widget.displayType(entry.entryType),
                                ),
                                onLongPress: () =>
                                    widget.onToggleSelection(entry.id),
                                onTap: () {
                                  if (widget.selectionMode) {
                                    widget.onToggleSelection(entry.id);
                                    return;
                                  }
                                  setState(
                                    () => _selectedEntryId = entry.id,
                                  );
                                  widget.onEntryTap(entry.id);
                                },
                                  ),
                                  name: widget.displayTitle(entry),
                                  outcome: rowOutcome,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
            label: AppLocalizations.of(context).regionEntries,
          ),
        ),
      ],
    ));
  }

  /// Wrap a pane in its Tab-cycle region (FocusScope for identity + FocusRegion
  /// for the focus frame and the spoken region name). Pass-through when [scope]
  /// is null (Android) — so the announcement rides the same gate as the frame.
  Widget _region(FocusScopeNode? scope, Widget child, {String? label}) =>
      scope == null
      ? child
      : FocusScope(
          node: scope,
          child: FocusRegion(label: label, child: child),
        );

  /// Whether keyboard navigation is live. The parent nulls the region scopes on
  /// Android, where there is no keyboard — and then nothing keyboard-related,
  /// the focus frame included, may appear anywhere in the tree.
  bool get _keyboardNav => widget.listScope != null;

  /// Makes a control say what it DOES. A Linux screen reader is given only a
  /// node's NAME — the embedder never reads a semantics hint (LEARNINGS.md) —
  /// so there the outcome goes inside the name, after the control's own name.
  /// Android does read hints and keeps its own, unchanged. `_keyboardNav` is
  /// the same Linux gate the focus frame already rides on.
  ///
  /// [outcome] null means the control promises nothing right now (a row in
  /// selection mode ticks rather than opens), so nothing is added.
  Widget _saysWhatItDoes(
    Widget child, {
    required String name,
    String? outcome,
  }) {
    if (outcome == null) return child;
    return _keyboardNav
        ? Semantics(label: '$name. $outcome', child: child)
        : Semantics(hint: outcome, child: child);
  }

  /// The `semanticsLabel` for the Text showing a control's own name: blank
  /// where [_saysWhatItDoes] has already composed that name into the label,
  /// null otherwise. A blanked VALUE, not a wrapper — a wrapper would change
  /// the tree's shape, which is what disposed this row's focus node once.
  String? _ownNameLabel({String? outcome}) =>
      outcome != null && _keyboardNav ? '' : null;

  // Maximum list pane width: always leaves ≥200dp for the detail pane. Grows
  // naturally on wide screens. Was 300dp while the nav rail took ~100dp of the
  // row; with the rail gone that 100dp was reserved for nothing.
  double _maxListPaneWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width - 200.0).clamp(180.0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Clamp stored width to the contextual max on every build so that the
    // pane is never wider than the screen allows (e.g. after window resize
    // or orientation change).
    final effectiveWidth = _listPaneWidth.clamp(180.0, _maxListPaneWidth(context));

    return Row(
      children: [
        // ── List pane (resizable) ──────────────────────────────────────────
        SizedBox(
          key: const ValueKey('tablet-list-pane'),
          width: effectiveWidth,
          child: _buildListPane(context),
        ),
        // ── Drag handle ────────────────────────────────────────────────────
        // Screen-reader label + hover tooltip (ADR-015). Grip glyph grows with
        // the text scale, gently capped at 1.5x, as it lives in the fixed 20dp
        // divider (ADR-016).
        Semantics(
          label: l.resizeColumns,
          container: true,
          child: Tooltip(
            message: l.resizeColumns,
            child: GestureDetector(
              key: const ValueKey('list-pane-divider'),
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _listPaneWidth = (_listPaneWidth + details.delta.dx)
                      .clamp(180.0, _maxListPaneWidth(context));
                });
              },
              onHorizontalDragEnd: (_) {
                final appState = GabbroApp.maybeOf(context);
                appState?.updateSettings(
                  appState.settings
                      .copyWith(tabletListPaneWidth: _listPaneWidth),
                );
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Stack(
                  children: [
                    VerticalDivider(
                      width: 20,
                      thickness: 1,
                      color: theme.dividerColor,
                    ),
                    Center(
                      child: Container(
                        key: const ValueKey('list-pane-grip'),
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: RotatedBox(
                          quarterTurns: 1,
                          child: Icon(
                            Icons.drag_handle,
                            size: 16 *
                                controlScaleFor(context)
                                    .clamp(1.0, 1.5)
                                    .toDouble(),
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // ── Detail pane (flex) ─────────────────────────────────────────────
        // Always wrapped, selected or not. The cycle decides whether detail is
        // a Tab stop from the scope's FOCUSABLE DESCENDANTS, and the empty
        // pane has none (an icon and a line of text), so it is still never a
        // stop. Mounting the wrapper conditionally instead changed the widget
        // tree's SHAPE every time the selection cleared, which tore down and
        // rebuilt the whole detail subtree — see the round-17 delete bug.
        Expanded(
          child: _region(
            widget.detailScope,
            _buildDetailPane(context),
            label: AppLocalizations.of(context).regionDetails,
          ),
        ),
      ],
    );
  }
}
