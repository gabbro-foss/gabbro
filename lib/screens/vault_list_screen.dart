import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

class VaultListScreen extends StatefulWidget {
  final List<EntrySummaryData> Function() listEntries;

  const VaultListScreen({super.key, this.listEntries = listEntrySummaries});

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen> {
  List<EntrySummaryData> _entries = [];
  String? _error;
  String _selectedFilter = 'All';
  Set<String> _selectedIds = {};
  bool _isDeleting = false;
  bool _isImporting = false;
  bool get _isSelecting => _selectedIds.isNotEmpty;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadEntries() {
    try {
      final entries = widget.listEntries();
      setState(() {
        _entries = entries;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

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

    if (_searchQuery.isEmpty) return typeFiltered;
    final query = _searchQuery.toLowerCase();
    return typeFiltered
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

  void _scrollToLetter(String letter) {
    final index = _letterIndex[letter];
    if (index == null) return;
    _itemScrollController.jumpTo(index: index);
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

  Future<void> _importEnpass() async {
    final pathController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import from Enpass'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the path to your Enpass .json export file:'),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'File path',
                hintText: '/home/user/enpass_export.json',
              ),
              onSubmitted: (_) => Navigator.of(context).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final path = pathController.text.trim();
    if (path.isEmpty) return;

    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File not found: $path'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    try {
      setState(() => _isImporting = true);
      final bytes = await file.readAsBytes();
      final count = await importFromEnpass(data: bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $count entries from Enpass.')),
        );
        _loadEntries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }

    const filters = [
      'All',
      'Password',
      'Note',
      'Card',
      'Identity',
      'File',
      'Custom',
    ];

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
            )
          else if (!_isSelecting)
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Import from Enpass',
              onPressed: _importEnpass,
            ),
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
              onPressed: () => setState(() => _selectedIds.clear()),
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
      body: Column(
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
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: filters
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(f),
                        selected: _selectedFilter == f,
                        onSelected: (_) => setState(() => _selectedFilter = f),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: _groupedEntries.isEmpty
                ? const Center(child: Text('No entries match your search.'))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Index bar — fixed width column, clear of the FAB
                      // at the bottom via padding. Left of the list so it
                      // does not sit on top of the platform scrollbar.
                      if (_searchQuery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 80),
                          child: SizedBox(
                            width: 36,
                            child: AlphabetIndexBar(
                              presentLetters: _letterIndex.keys.toSet(),
                              onLetterSelected: _scrollToLetter,
                            ),
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
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: _groupedEntries.length,
                            itemBuilder: (context, index) {
                              final item = _groupedEntries[index];
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
                              return ListTile(
                                dense: true,
                                leading: Checkbox(
                                  visualDensity: VisualDensity.compact,
                                  value: _selectedIds.contains(entry.id),
                                  onChanged: (_) => setState(() {
                                    if (_selectedIds.contains(entry.id)) {
                                      _selectedIds.remove(entry.id);
                                    } else {
                                      _selectedIds.add(entry.id);
                                    }
                                  }),
                                ),
                                title: Text(_displayTitle(entry)),
                                subtitle: Text(_displayType(entry.entryType)),
                                onTap: () async {
                                  if (_isSelecting) {
                                    setState(() {
                                      if (_selectedIds.contains(entry.id)) {
                                        _selectedIds.remove(entry.id);
                                      } else {
                                        _selectedIds.add(entry.id);
                                      }
                                    });
                                    return;
                                  }
                                  final full = getEntry(id: entry.id);
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          EntryDetailScreen(entry: full),
                                    ),
                                  );
                                  if (mounted) _loadEntries();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
