import 'package:flutter/material.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

class VaultListScreen extends StatefulWidget {
  const VaultListScreen({super.key});

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen> {
  List<EntrySummaryData> _entries = [];
  String? _error;
  String _selectedFilter = 'All';
  Set<String> _selectedIds = {};
  bool _isDeleting = false;
  bool get _isSelecting => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  void _loadEntries() {
    try {
      final entries = listEntrySummaries();
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
    if (_selectedFilter == 'All') return _entries;
    final rustType = _selectedFilter == 'Password' ? 'Login' : _selectedFilter;
    return _entries.where((e) => e.entryType == rustType).toList();
  }

  List<dynamic> get _groupedEntries {
    final sorted = List<EntrySummaryData>.from(_filteredEntries)
      ..sort(
        (a, b) => _displayTitle(
          a,
        ).toLowerCase().compareTo(_displayTitle(b).toLowerCase()),
      );

    final result = <dynamic>[];
    String? currentLetter;

    for (final entry in sorted) {
      final letter = _displayTitle(entry).isNotEmpty
          ? _displayTitle(entry)[0].toUpperCase()
          : '#';
      if (letter != currentLetter) {
        result.add(letter);
        currentLetter = letter;
      }
      result.add(entry);
    }
    return result;
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
    for (final id in ids) {
      await deleteEntry(id: id);
    }
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
      floatingActionButton: _isSelecting
          ? null
          : FloatingActionButton(
              onPressed: _showTypePicker,
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
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
            child: ListView.builder(
              itemCount: _groupedEntries.length,
              itemBuilder: (context, index) {
                final item = _groupedEntries[index];
                if (item is String) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                        builder: (context) => EntryDetailScreen(entry: full),
                      ),
                    );
                    if (mounted) _loadEntries();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
