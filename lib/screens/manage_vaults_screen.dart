import 'package:flutter/material.dart';
import 'package:gabbro/vault_registry.dart';

class _RenameDialog extends StatefulWidget {
  final String initialAlias;
  final Set<String> takenAliases;
  const _RenameDialog({
    required this.initialAlias,
    required this.takenAliases,
  });

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
  Widget build(BuildContext context) {
    final alias = _controller.text.trim();
    final isTaken = widget.takenAliases.contains(alias);

    return AlertDialog(
      title: const Text('Rename vault'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Alias'),
            onChanged: (_) => setState(() {}),
          ),
          if (isTaken && alias.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'A vault named "$alias" already exists.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (alias.isEmpty || isTaken)
              ? null
              : () => Navigator.of(context).pop(alias),
          child: const Text('Save'),
        ),
      ],
    );
  }
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
    final takenAliases = _registry.records
        .where((r) => r.path != record.path)
        .map((r) => r.alias)
        .toSet();
    final String? newAlias = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        initialAlias: record.alias,
        takenAliases: takenAliases,
      ),
    );
    if (newAlias != null) {
      setState(() => _registry = _registry.updateAlias(record.path, newAlias));
      await widget.onRename(record.path, newAlias);
    }
  }

  Future<void> _showDeleteDialog(VaultRecord record) async {
    // Step 1 — warning
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vault?'),
        content: Text(
          'This will permanently delete "${record.alias}" and all its data.\n\n'
          'File: ${record.path}\n\nThis cannot be undone.',
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
        builder: (ctx, setDialogState) => AlertDialog(
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
                onChanged: (_) => setDialogState(() {}),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => confirmController.dispose());
    if (step2 != true) return;

    setState(() => _registry = _registry.remove(record.path));
    await widget.onDelete(record.path);
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
