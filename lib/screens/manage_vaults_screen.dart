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

class ManageVaultsScreen extends StatefulWidget {
  final VaultRegistry registry;
  final Future<void> Function(String path, String alias) onRename;
  final Future<void> Function(String path) onDelete;
  final VoidCallback onAddVault;
  final void Function(String path, String alias) onSwitchToVault;

  const ManageVaultsScreen({
    super.key,
    required this.registry,
    required this.onRename,
    required this.onDelete,
    required this.onAddVault,
    required this.onSwitchToVault,
  });

  @override
  State<ManageVaultsScreen> createState() => _ManageVaultsScreenState();
}

class _ManageVaultsScreenState extends State<ManageVaultsScreen> {
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
      setState(() => _registry = _registry.updateAlias(record.path, newAlias));
      await widget.onRename(record.path, newAlias);
    }
  }

  Future<void> _showDeleteDialog(VaultRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete vault?'),
        content: Text(
          'This will permanently delete "${record.alias}" and all its data.\n\n'
          'File: ${record.path}\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _registry = _registry.remove(record.path));
      await widget.onDelete(record.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage vaults')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _registry.records.isEmpty
                  ? const Center(child: Text('No vaults registered.'))
                  : ListView.builder(
                      itemCount: _registry.records.length,
                      itemBuilder: (_, i) {
                        final record = _registry.records[i];
                        return ListTile(
                          leading: const Icon(Icons.lock_outlined),
                          title: Text(record.alias),
                          subtitle: Text(
                            record.path,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () =>
                              widget.onSwitchToVault(record.path, record.alias),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Rename',
                                onPressed: () => _showRenameDialog(record),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outlined,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                tooltip: 'Delete vault',
                                onPressed: () => _showDeleteDialog(record),
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
