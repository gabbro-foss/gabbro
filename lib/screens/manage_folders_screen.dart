import 'package:flutter/material.dart';

class ManageFoldersScreen extends StatefulWidget {
  const ManageFoldersScreen({
    super.key,
    required this.listFolders,
    required this.createFolder,
    required this.renameFolder,
    required this.deleteFolder,
  });

  final Future<List<String>> Function() listFolders;
  final Future<void> Function(String name) createFolder;
  final Future<void> Function(String oldName, String newName) renameFolder;
  final Future<void> Function(String name, String? reassignTo) deleteFolder;

  @override
  State<ManageFoldersScreen> createState() => _ManageFoldersScreenState();
}

class _ManageFoldersScreenState extends State<ManageFoldersScreen> {
  List<String> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await widget.listFolders();
    setState(() {
      _folders = folders;
      _loading = false;
    });
  }

  Future<void> _showDeleteDialog(String folder) async {
    final otherFolders = _folders.where((f) => f != folder).toList();
    final hasOthers = otherFolders.isNotEmpty;
    String? reassignTarget;
    bool clearToNone = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete "$folder"?'),
              if (hasOthers) ...[
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reassign entries to'),
                  value: reassignTarget != null,
                  onChanged: (v) => setState(() {
                    reassignTarget = v == true ? otherFolders.first : null;
                    if (v == true) clearToNone = false;
                  }),
                ),
                if (reassignTarget != null)
                  DropdownButton<String>(
                    value: reassignTarget,
                    items: otherFolders
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (v) => setState(() => reassignTarget = v),
                  ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Clear to "None"'),
                  value: clearToNone,
                  onChanged: (v) => setState(() {
                    clearToNone = v == true;
                    if (v == true) reassignTarget = null;
                  }),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await widget.deleteFolder(folder, reassignTarget);
      if (mounted) await _load();
    }
  }

  Future<void> _showRenameDialog(String folder) async {
    String newName = folder;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: folder);
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Rename folder'),
            content: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Folder name'),
              onChanged: (v) => newName = v,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && newName.trim().isNotEmpty) {
      await widget.renameFolder(folder, newName.trim());
      if (mounted) await _load();
    }
  }

  Future<void> _showAddDialog() async {
    String newName = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add folder'),
        content: TextFormField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onChanged: (v) => newName = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true && newName.trim().isNotEmpty) {
      await widget.createFolder(newName.trim());
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage folders')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _folders.length,
              itemBuilder: (context, index) {
                final folder = _folders[index];
                return ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showRenameDialog(folder),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _showDeleteDialog(folder),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}