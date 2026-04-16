import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

class VaultListScreen extends StatefulWidget {
  const VaultListScreen({super.key});

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen> {
  List<EntrySummaryData> _entries = [];
  String? _error;

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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Error: $_error')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gabbro')),
      body: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return ListTile(
            title: Text(entry.title),
            subtitle: Text(_displayType(entry.entryType)),
          );
        },
      ),
    );
  }
}