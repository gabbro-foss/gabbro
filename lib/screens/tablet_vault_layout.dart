import 'package:flutter/material.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
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
class TabletVaultLayout extends StatefulWidget {
  /// All entries currently loaded (filtered + grouped by the parent).
  final List<dynamic> groupedEntries;

  /// The flat filtered list — needed for select-all count.
  final List<EntrySummaryData> filteredEntries;

  /// Letter → index map for the alphabet bar.
  final Map<String, int> letterIndex;

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

  const TabletVaultLayout({
    super.key,
    required this.groupedEntries,
    required this.filteredEntries,
    required this.letterIndex,
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
  });

  @override
  State<TabletVaultLayout> createState() => _TabletVaultLayoutState();
}

class _TabletVaultLayoutState extends State<TabletVaultLayout> {
  // Currently selected entry id — null means empty state in detail pane.
  String? _selectedEntryId;

  // True while the detail pane is in edit mode.
  // List pane is dimmed and non-interactive during editing.
  // ignore: prefer_final_fields — mutated via setState in edit phase
  bool _isEditing = false;

  // NavigationRail destination index.
  // 0 = Vault (default), 1 = Appearance, 2 = Security, 3 = About
  int _railIndex = 0;

  final ItemScrollController _itemScrollController = ItemScrollController();

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

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 48),
          SizedBox(height: 12),
          Text('Select an entry'),
        ],
      ),
    );
  }

  Widget _buildDetailPane() {
    if (_selectedEntryId == null) return _buildEmptyState();
    // ValueKey forces Flutter to rebuild EntryDetailScreen whenever the
    // selected id changes — this is how we refresh after an edit without
    // adding an onChanged callback to EntryDetailScreen.
    return EntryDetailScreen(
      key: ValueKey(_selectedEntryId),
      entry: getEntry(id: _selectedEntryId!),
      clipboardClearTimeout: widget.clipboardClearTimeout,
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
              ? const Center(child: Text('No entries match your search.'))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.searchActive == false)
                      SizedBox(
                        width: 48,
                        child: AlphabetIndexBar(
                          presentLetters: widget.letterIndex.keys.toSet(),
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
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
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
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  widget.entryTypeIcon(entry.entryType),
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                  semanticLabel: widget.displayType(
                                    entry.entryType,
                                  ),
                                ),
                                title: Text(widget.displayTitle(entry)),
                                subtitle: Text(
                                  widget.displayType(entry.entryType),
                                ),
                                onTap: () {
                                  if (_isEditing) return;
                                  setState(
                                    () => _selectedEntryId = entry.id,
                                  );
                                  widget.onEntryTap(entry.id);
                                },
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Navigation rail ────────────────────────────────────────────────
        NavigationRail(
          selectedIndex: _railIndex,
          onDestinationSelected: _onRailDestinationSelected,
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.lock_outline),
              selectedIcon: Icon(Icons.lock),
              label: Text('Vault'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.palette_outlined),
              selectedIcon: Icon(Icons.palette),
              label: Text('Appearance'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.security_outlined),
              selectedIcon: Icon(Icons.security),
              label: Text('Security'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.info_outline),
              selectedIcon: Icon(Icons.info),
              label: Text('About'),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
        // ── List pane (fixed width, dimmed during editing) ─────────────────
        SizedBox(
          width: 260,
          child: IgnorePointer(
            ignoring: _isEditing,
            child: AnimatedOpacity(
              opacity: _isEditing ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: _buildListPane(context),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // ── Detail pane (flex) ─────────────────────────────────────────────
        Expanded(child: _buildDetailPane()),
      ],
    );
  }
}
