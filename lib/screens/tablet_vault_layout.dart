import 'package:flutter/material.dart';
import 'package:gabbro/control_scale.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/screens/section_index.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// ---------------------------------------------------------------------------
// TabletVaultLayout
//
// Two-pane layout for screens ≥600dp wide.
//
// Structure (left → right):
//   NavigationRail (≈68dp) | AlphabetIndexBar (≈28dp) | list pane | detail pane
//
// The NavigationRail handles Vault / Appearance / Security / About.
// Vault operations (export, import, etc.) remain in the app-bar popup menu,
// which is owned by the parent VaultListScreen.
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

  /// The vault path — needed for navigation targets that require it.
  final String vaultPath;

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
    required this.vaultPath,
    required this.clipboardClearTimeout,
    this.getEntryFn,
    this.onDeleteEntryFn,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelection,
  });

  @override
  State<TabletVaultLayout> createState() => _TabletVaultLayoutState();
}

class _TabletVaultLayoutState extends State<TabletVaultLayout> {
  // Currently selected entry id — null means empty state in detail pane.
  String? _selectedEntryId;

  // NavigationRail destination index.
  // 0 = Vault (default), 1 = Appearance, 2 = Security, 3 = About
  int _railIndex = 0;

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

  void _onRailDestinationSelected(int index) {
    if (index == 0) {
      // Already on Vault — nothing to do.
      setState(() => _railIndex = 0);
      return;
    }
    setState(() => _railIndex = index);
    // Push the target screen. On return, reset to Vault tab.
    Widget screen;
    switch (index) {
      case 1:
        screen = const AppearanceScreen();
      case 2:
        final appState = GabbroApp.of(context);
        screen = SecurityScreen(
          settings: appState.settings,
          onUpdate: (updated) => appState.updateSettings(updated),
          vaultPath: widget.vaultPath,
        );
      case 3:
        screen = const AboutScreen();
      default:
        return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => setState(() => _railIndex = 0));
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
        setState(() => _selectedEntryId = null);
        widget.onRefresh();
      },
      onEdited: () => widget.onRefresh(),
    );
  }

  Widget _buildListPane(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        widget.searchBar,
        widget.filterChipRow,
        Expanded(
          child: widget.groupedEntries.isEmpty
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
                            return Container(
                              decoration: isSelected
                                  ? BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 3,
                                        ),
                                      ),
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.3),
                                    )
                                  : null,
                              child: Material(
                                color: Colors.transparent,
                                child: ListTile(
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
                                    : Icon(
                                        widget.entryTypeIcon(entry.entryType),
                                        size: scaledIconSize(context, 20),
                                        color: theme.colorScheme.primary,
                                        semanticLabel: widget.displayType(
                                          entry.entryType,
                                        ),
                                      ),
                                title: Text(widget.displayTitle(entry)),
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
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // Maximum list pane width: always leaves ≥200dp for the detail pane and
  // the navigation rail (~100dp combined). Grows naturally on wide screens.
  double _maxListPaneWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width - 300.0).clamp(180.0, double.infinity);

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
        // ── Navigation rail ────────────────────────────────────────────────
        NavigationRail(
          selectedIndex: _railIndex,
          onDestinationSelected: _onRailDestinationSelected,
          labelType: NavigationRailLabelType.all,
          destinations: [
            NavigationRailDestination(
              icon: Icon(Icons.lock_outline, size: scaledIconSize(context)),
              selectedIcon: Icon(Icons.lock, size: scaledIconSize(context)),
              label: Text(l.navVault),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.palette_outlined, size: scaledIconSize(context)),
              selectedIcon: Icon(Icons.palette, size: scaledIconSize(context)),
              label: Text(l.appearanceTitle),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.security_outlined, size: scaledIconSize(context)),
              selectedIcon: Icon(Icons.security, size: scaledIconSize(context)),
              label: Text(l.securityTitle),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.info_outline, size: scaledIconSize(context)),
              selectedIcon: Icon(Icons.info, size: scaledIconSize(context)),
              label: Text(l.navAbout),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
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
        Expanded(child: _buildDetailPane(context)),
      ],
    );
  }
}
