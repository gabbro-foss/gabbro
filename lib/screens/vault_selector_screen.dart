import 'package:flutter/material.dart';
import 'package:gabbro/vault_registry.dart';

class _RenameDialog extends StatefulWidget {
  final String initialAlias;
  const _RenameDialog({required this.initialAlias});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAlias);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename vault'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Alias'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(null),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          final alias = _controller.text.trim();
          Navigator.of(context).pop(alias.isEmpty ? null : alias);
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class VaultSelectorScreen extends StatefulWidget {
  final VaultRegistry registry;
  final bool showVaultList;
  final void Function(String path, String alias) onVaultSelected;
  final VoidCallback onAddVault;

  /// Called after a rename is confirmed. Should persist the new alias.
  final Future<void> Function(String path, String alias)? onRename;

  /// Called after remove is confirmed. Should persist the registry change.
  final Future<void> Function(String path)? onRemove;

  const VaultSelectorScreen({
    super.key,
    required this.registry,
    required this.showVaultList,
    required this.onVaultSelected,
    required this.onAddVault,
    this.onRename,
    this.onRemove,
  });

  @override
  State<VaultSelectorScreen> createState() => _VaultSelectorScreenState();
}

class _VaultSelectorScreenState extends State<VaultSelectorScreen> {
  late VaultRegistry _registry;

  @override
  void initState() {
    super.initState();
    _registry = widget.registry;
  }

  Future<void> _showRenameDialog(VaultRecord record) async {
    final String? newAlias = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialAlias: record.alias),
    );

    if (newAlias != null) {
      setState(() {
        _registry = _registry.updateAlias(record.path, newAlias);
      });
      await widget.onRename?.call(record.path, newAlias);
    }
  }

  Future<void> _remove(VaultRecord record) async {
    setState(() {
      _registry = _registry.remove(record.path);
    });
    await widget.onRemove?.call(record.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vaults')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showVaultList)
              Expanded(
                child: ListView.builder(
                  itemCount: _registry.records.length,
                  itemBuilder: (_, i) {
                    final record = _registry.records[i];
                    return ListTile(
                      title: Text(record.alias),
                      onTap: () =>
                          widget.onVaultSelected(record.path, record.alias),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Rename',
                            onPressed: () => _showRenameDialog(record),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: 'Remove from list',
                            onPressed: () => _remove(record),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: widget.onAddVault,
                icon: const Icon(Icons.add),
                label: const Text('Add vault'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
