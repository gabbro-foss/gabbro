import 'package:flutter/material.dart';
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
      case 'Login': return 'Password';
      case 'Note': return 'Note';
      case 'Identity': return 'Identity';
      case 'Card': return 'Card';
      case 'File': return 'File';
      case 'Custom': return 'Custom';
      default: return entryType;
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
      ..sort((a, b) => _displayTitle(a).toLowerCase()
          .compareTo(_displayTitle(b).toLowerCase()));

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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Error: $_error')),
      );
    }

    const filters = ['All', 'Password', 'Note', 'Card', 'Identity', 'File', 'Custom'];

    return Scaffold(
      appBar: AppBar(title: const Text('Gabbro')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: filters.map((f) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(f),
                  selected: _selectedFilter == f,
                  onSelected: (_) => setState(() => _selectedFilter = f),
                ),
              )).toList(),
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
                  title: Text(_displayTitle(entry)),
                  subtitle: Text(_displayType(entry.entryType)),
                  onTap: () {
                    final full = getEntry(id: entry.id);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => EntryDetailScreen(entry: full),
                      ),
                    );
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