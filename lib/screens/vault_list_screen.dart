import 'package:flutter/material.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/screens/export_screen.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/change_passphrase_screen.dart';
import 'package:gabbro/screens/generator_screen.dart';
import 'package:gabbro/screens/manage_folders_screen.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/tablet_vault_layout.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

Future<void> _defaultDeleteVault() => deleteWholeVault();
List<String> _defaultListFolders() => listFolders();

class VaultListScreen extends StatefulWidget {
  final String vaultPath;
  final List<EntrySummaryData> Function() listEntries;
  final List<String> Function()? listFolders;
  final Future<void> Function() deleteVault;

  final VaultEntryData Function(String id)? getEntryFn;
  final Future<void> Function(String id)? onDeleteEntryFn;
  final void Function()? onRefreshFn;
  final AlphabetBarPosition? alphabetBarPosition;

  const VaultListScreen({
    super.key,
    required this.vaultPath,
    this.listEntries = listEntrySummaries,
    this.listFolders,
    this.deleteVault = _defaultDeleteVault,
    this.getEntryFn,
    this.onDeleteEntryFn,
    this.onRefreshFn,
    this.alphabetBarPosition,
  });

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen> {
  static const _filters = [
    'All',
    'Password',
    'Note',
    'Card',
    'Identity',
    'File',
    'Custom',
  ];

  List<EntrySummaryData> _entries = [];
  List<String> _folders = [];
  String? _error;
  String _selectedFilter = 'All';
  String _selectedFolder = '';
  Set<String> _selectedIds = {};
  bool _selectionMode = false;
  bool _isDeleting = false;
  bool _isImporting = false;
  bool get _isSelecting => _selectionMode || _selectedIds.isNotEmpty;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ScrollController _chipScrollController = ScrollController();
  bool _showLeftChevron = false;
  bool _showRightChevron = false;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _chipScrollController.addListener(_updateChevrons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateChevrons());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateChevrons());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chipScrollController.removeListener(_updateChevrons);
    _chipScrollController.dispose();
    super.dispose();
  }

  void _updateChevrons() {
    if (!_chipScrollController.hasClients) return;
    final pos = _chipScrollController.position;
    final overflows = pos.maxScrollExtent > 0;
    setState(() {
      _showLeftChevron = overflows && pos.pixels > 1.0;
      _showRightChevron = overflows && pos.pixels < pos.maxScrollExtent - 1.0;
    });
  }

  void _scrollChips(bool toRight) {
    if (!_chipScrollController.hasClients) return;
    final pos = _chipScrollController.position;
    final target = (pos.pixels + (toRight ? 120.0 : -120.0)).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    _chipScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void _loadEntries() {
    try {
      final entries = widget.listEntries();
      List<String> folders = [];
      try {
        folders = (widget.listFolders ?? _defaultListFolders)();
      } catch (_) {
        // folders unavailable (e.g. vault locked) — degrade gracefully
      }
      setState(() {
        _entries = entries;
        _folders = folders;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  IconData _entryTypeIcon(String entryType) => switch (entryType) {
    'Login' => Icons.lock_outline,
    'Note' => Icons.note_outlined,
    'Identity' => Icons.person_outline,
    'Card' => Icons.credit_card_outlined,
    'File' => Icons.insert_drive_file_outlined,
    _ => Icons.tune,
  };

  String _displayType(String entryType) {
    switch (entryType) {
      case 'Login':
        return 'Password';
      case 'Note':
        return 'Note';
      case 'Identity':
        return 'Identity';
      case 'Card':
        return 'Card';
      case 'File':
        return 'File';
      case 'Custom':
        return 'Custom';
      default:
        return entryType;
    }
  }

  String _displayTitle(EntrySummaryData entry) {
    switch (entry.entryType) {
      case 'Login':
        return entry.title.isNotEmpty ? entry.title : '(no URL)';
      case 'Identity':
        return entry.title.isNotEmpty ? entry.title : '(no name)';
      default:
        return entry.title.isNotEmpty ? entry.title : '(untitled)';
    }
  }

  List<EntrySummaryData> get _filteredEntries {
    final typeFiltered = _selectedFilter == 'All'
        ? _entries
        : _entries.where((e) {
            final rustType = _selectedFilter == 'Password'
                ? 'Login'
                : _selectedFilter;
            return e.entryType == rustType;
          }).toList();

    final folderFiltered = _selectedFolder.isEmpty
        ? typeFiltered
        : typeFiltered.where((e) => e.folder == _selectedFolder).toList();

    if (_searchQuery.isEmpty) return folderFiltered;
    final query = _searchQuery.toLowerCase();
    return folderFiltered
        .where((e) => _displayTitle(e).toLowerCase().contains(query))
        .toList();
  }

  Map<String, int> get _letterIndex {
    final map = <String, int>{};
    final items = _groupedEntries;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is String) map[item] = i;
    }
    return map;
  }

  String _sectionLetter(EntrySummaryData entry) {
    final title = _displayTitle(entry);
    if (title.isEmpty) return '#';
    final first = title[0];
    return RegExp(r'[A-Za-z]').hasMatch(first) ? first.toUpperCase() : '#';
  }

  int _sortKey(EntrySummaryData entry) {
    final title = _displayTitle(entry);
    if (title.isEmpty) return 1;
    final first = title[0];
    return RegExp(r'[A-Za-z]').hasMatch(first) ? 0 : 1;
  }

  List<dynamic> get _groupedEntries {
    final sorted = List<EntrySummaryData>.from(_filteredEntries)
      ..sort((a, b) {
        final keyDiff = _sortKey(a) - _sortKey(b);
        if (keyDiff != 0) return keyDiff;
        return _displayTitle(
          a,
        ).toLowerCase().compareTo(_displayTitle(b).toLowerCase());
      });

    final result = <dynamic>[];
    String? currentLetter;

    for (final entry in sorted) {
      final letter = _sectionLetter(entry);
      if (letter != currentLetter) {
        result.add(letter);
        currentLetter = letter;
      }
      result.add(entry);
    }
    return result;
  }

  AlphabetBarPosition get _alphabetBarPosition =>
      widget.alphabetBarPosition ??
      GabbroApp.maybeOf(context)?.settings.alphabetBarPosition ??
      AlphabetBarPosition.left;

  void _scrollToLetter(String letter) {
    final index = _letterIndex[letter];
    if (index == null) return;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _showTypePicker() async {
    final types = [
      ('Login', 'Password'),
      ('Note', 'Note'),
      ('Identity', 'Identity'),
      ('Card', 'Card'),
      ('File', 'File'),
      ('Custom', 'Custom'),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'New entry',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ...types.map(
                (t) => ListTile(
                  leading: Icon(
                    _entryTypeIcon(t.$1),
                    color: Theme.of(context).colorScheme.primary,
                    semanticLabel: t.$2,
                  ),
                  title: Text(t.$2),
                  onTap: () => Navigator.of(context).pop(t.$1),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CreateEntryScreen(entryType: selected),
      ),
    );
    if (mounted) _loadEntries();
  }

  Future<void> _openExportScreen() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (context) => ExportScreen()));
  }

  Future<void> _openImportScreen() async {
    setState(() => _isImporting = true);
    final count = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute(builder: (context) => const ImportScreen()));
    if (mounted) {
      setState(() => _isImporting = false);
      if (count != null && count > 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported $count entries.')));
        _loadEntries();
      }
    }
  }

  Future<void> _confirmDelete(Set<String> ids) async {
    final count = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'entry' : 'entries'}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isDeleting = true);
    await deleteEntries(ids: ids.toList());
    setState(() {
      _selectedIds.clear();
      _isDeleting = false;
    });
    _loadEntries();
  }

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'export':
        _openExportScreen();
      case 'import':
        _openImportScreen();
      case 'change_passphrase':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const ChangePassphraseScreen(),
          ),
        );
      case 'appearance':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AppearanceScreen()),
        );
      case 'security':
        final appState = GabbroApp.of(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SecurityScreen(
              settings: appState.settings,
              onUpdate: (updated) => appState.updateSettings(updated),
            ),
          ),
        );
      case 'vault_delete':
        _deleteWholeVault();
      case 'generator':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const GeneratorScreen()),
        );
      case 'manage_folders':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ManageFoldersScreen(
              listFolders: () async => listFolders(),
              createFolder: (name) async => createFolder(name: name),
              renameFolder: (oldName, newName) async =>
                  renameFolder(oldName: oldName, newName: newName),
              deleteFolder: (name, reassignTo) async =>
                  deleteFolder(name: name, reassignTo: reassignTo),
            ),
          ),
        );
        if (mounted) _loadEntries();
      case 'about':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const AboutScreen()));
    }
  }

  Future<void> _deleteWholeVault() async {
    // Step 1 — warning confirmation
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vault?'),
        content: const Text(
          'This will permanently delete all entries. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (step1 != true) return;
    if (!mounted) return;

    // Step 2 — type DELETE to confirm
    final confirmController = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Are you sure?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Type DELETE to confirm'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('delete_vault_confirm_field'),
                controller: confirmController,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: confirmController.text == 'DELETE'
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    // Dispose after dialog is fully closed and removed from the tree.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => confirmController.dispose(),
    );
    if (step2 != true) return;
    if (!mounted) return;

    await widget.deleteVault();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => OnboardingScreen(
          initialPath: widget.vaultPath,
          postDeletionMessage:
              'Your vault has been deleted. Create a new one to continue.',
        ),
      ),
      (_) => false,
    );
  }

  void _lockAndExit() {
    lockVault();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => UnlockScreen(vaultPath: widget.vaultPath),
      ),
    );
  }

  Widget _buildFilterChipRow() {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _updateChevrons();
            return false;
          },
          child: SingleChildScrollView(
            controller: _chipScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: _filters
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(f),
                        selected: _selectedFilter == f,
                        onSelected: (_) =>
                            setState(() => _selectedFilter = f),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (_showRightChevron)
          Positioned(
            right: 0,
            child: _ChipRowFadeEdge(
              alignment: Alignment.centerRight,
              onTap: () => _scrollChips(true),
            ),
          ),
        if (_showLeftChevron)
          Positioned(
            left: 0,
            child: _ChipRowFadeEdge(
              alignment: Alignment.centerLeft,
              onTap: () => _scrollChips(false),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelecting ? '${_selectedIds.length} selected' : 'Gabbro',
        ),
        actions: [
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!_isSelecting) ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: 'Select entries',
              onPressed: () => setState(() => _selectionMode = true),
            ),
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Lock vault',
              onPressed: _lockAndExit,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              tooltip: 'Menu',
              onSelected: _onMenuSelected,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'export',
                  child: Row(children: [
                    Icon(Icons.upload_outlined, size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('Export vault')),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: Row(children: [
                    Icon(Icons.download_outlined, size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('Import entries')),
                  ]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  enabled: false,
                  value: 'vault_add',
                  child: Row(children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(width: 12),
                    Text('Add vault'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'vault_delete',
                  child: Row(children: [
                    Icon(Icons.delete_forever_outlined, size: 20,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 12),
                    Text('Delete vault',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'change_passphrase',
                  child: Row(children: [
                    Icon(Icons.key_outlined, size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('Change passphrase')),
                  ]),
                ),
                const PopupMenuItem(
                  enabled: false,
                  value: 'yubikeys',
                  child: Row(children: [
                    Icon(Icons.security_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Manage YubiKeys'),
                  ]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'appearance',
                  child: Row(children: [
                    Icon(Icons.palette_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Appearance'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'security',
                  child: Row(children: [
                    Icon(Icons.shield_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Security'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'manage_folders',
                  child: Row(children: [
                    Icon(Icons.folder_outlined, size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('Manage folders')),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'generator',
                  child: Row(children: [
                    Icon(Icons.casino_outlined, size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('Password generator')),
                  ]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'about',
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 12),
                    Text('About'),
                  ]),
                ),
              ],
            ),
          ],
          if (_isDeleting) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ] else if (_isSelecting) ...[
            IconButton(
              icon: Icon(
                _selectedIds.length == _filteredEntries.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: _selectedIds.length == _filteredEntries.length
                  ? 'Deselect all'
                  : 'Select all',
              onPressed: () => setState(() {
                if (_selectedIds.length == _filteredEntries.length) {
                  _selectedIds.clear();
                } else {
                  _selectedIds = _filteredEntries.map((e) => e.id).toSet();
                }
              }),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDelete(_selectedIds),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedIds.clear();
                _selectionMode = false;
              }),
            ),
          ],
        ],
      ),
      // FAB stays at default bottom-right but the index bar column ends
      // above it via padding, so they never overlap.
      floatingActionButton: _isSelecting
          ? null
          : FloatingActionButton(
              onPressed: _showTypePicker,
              child: const Icon(Icons.add),
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600) {
            return TabletVaultLayout(
              groupedEntries: _groupedEntries,
              filteredEntries: _filteredEntries,
              letterIndex: _letterIndex,
              onLetterSelected: _scrollToLetter,
              displayTitle: _displayTitle,
              displayType: _displayType,
              entryTypeIcon: _entryTypeIcon,
              searchBar: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search entries…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            }),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value),
                ),
              ),
              filterChipRow: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_folders.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedFolder,
                        onChanged: (value) =>
                            setState(() => _selectedFolder = value ?? ''),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All folders'),
                          ),
                          ..._folders.map(
                            (f) =>
                                DropdownMenuItem(value: f, child: Text(f)),
                          ),
                        ],
                      ),
                    ),
                  _buildFilterChipRow(),
                ],
              ),
              searchActive: _searchQuery.isNotEmpty,
              onEntryTap: (_) {},
              onRefresh: widget.onRefreshFn ?? _loadEntries,
              getEntryFn: widget.getEntryFn,
              onDeleteEntryFn: widget.onDeleteEntryFn,
              selectionMode: _selectionMode,
              selectedIds: _selectedIds,
              onToggleSelection: (id) => setState(() {
                if (_selectedIds.contains(id)) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                  _selectionMode = true;
                }
              }),
              vaultPath: widget.vaultPath,
              clipboardClearTimeout:
                  GabbroApp.maybeOf(context)?.settings.clipboardClearTimeout ??
                  ClipboardClearTimeout.sixtySeconds,
            );
          }
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search entries…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              }),
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (value) =>
                        setState(() => _searchQuery = value),
                  ),
                ),
                if (_folders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedFolder,
                      onChanged: (value) =>
                          setState(() => _selectedFolder = value ?? ''),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All folders'),
                        ),
                        ..._folders.map(
                          (f) => DropdownMenuItem(value: f, child: Text(f)),
                        ),
                      ],
                    ),
                  ),
                _buildFilterChipRow(),
                Expanded(
                  child: _groupedEntries.isEmpty
                      ? const Center(
                          child: Text('No entries match your search.'),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Index bar — fixed width column. Position (left or
                            // right) is read from settings or the test override.
                            if (_searchQuery.isEmpty &&
                                _alphabetBarPosition ==
                                    AlphabetBarPosition.left)
                              SizedBox(
                                width: 48,
                                child: AlphabetIndexBar(
                                  presentLetters: _letterIndex.keys.toSet(),
                                  onLetterSelected: _scrollToLetter,
                                ),
                              ),
                            // List takes all remaining width.
                            Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(
                                  context,
                                ).copyWith(scrollbars: false),
                                child: ScrollablePositionedList.builder(
                                  itemScrollController: _itemScrollController,
                                  padding:
                                      const EdgeInsets.only(bottom: 80),
                                  itemCount: _groupedEntries.length,
                                  itemBuilder: (context, index) {
                                    final item = _groupedEntries[index];
                                    if (item is String) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.fromLTRB(
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
                                    return ListTile(
                                      dense: true,
                                      leading: _isSelecting
                                          ? Checkbox(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              value: _selectedIds.contains(
                                                entry.id,
                                              ),
                                              onChanged: (_) =>
                                                  setState(() {
                                                if (_selectedIds.contains(
                                                  entry.id,
                                                )) {
                                                  _selectedIds.remove(
                                                    entry.id,
                                                  );
                                                } else {
                                                  _selectedIds.add(entry.id);
                                                }
                                              }),
                                            )
                                          : Icon(
                                              _entryTypeIcon(entry.entryType),
                                              size: 20,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              semanticLabel: _displayType(
                                                entry.entryType,
                                              ),
                                            ),
                                      title: Text(_displayTitle(entry)),
                                      subtitle: Text(
                                        _displayType(entry.entryType),
                                      ),
                                      onLongPress: () => setState(() {
                                        _selectionMode = true;
                                        _selectedIds.add(entry.id);
                                      }),
                                      onTap: () async {
                                        if (_isSelecting) {
                                          setState(() {
                                            if (_selectedIds.contains(
                                              entry.id,
                                            )) {
                                              _selectedIds.remove(entry.id);
                                            } else {
                                              _selectedIds.add(entry.id);
                                            }
                                          });
                                          return;
                                        }
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                EntryDetailScreen(
                                              entry: getEntry(id: entry.id),
                                              clipboardClearTimeout:
                                                  GabbroApp.of(
                                                context,
                                              ).settings.clipboardClearTimeout,
                                            ),
                                          ),
                                        );
                                        if (mounted) _loadEntries();
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (_searchQuery.isEmpty &&
                                _alphabetBarPosition ==
                                    AlphabetBarPosition.right)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 80),
                                child: SizedBox(
                                  width: 48,
                                  child: AlphabetIndexBar(
                                    presentLetters: _letterIndex.keys.toSet(),
                                    onLetterSelected: _scrollToLetter,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChipRowFadeEdge extends StatelessWidget {
  final Alignment alignment;
  final VoidCallback onTap;
  const _ChipRowFadeEdge({required this.alignment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRight = alignment == Alignment.centerRight;
    final color = Theme.of(context).scaffoldBackgroundColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
            end: isRight ? Alignment.centerRight : Alignment.centerLeft,
            colors: [color.withValues(alpha: 0), color],
          ),
        ),
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRight ? Icons.chevron_right : Icons.chevron_left,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
