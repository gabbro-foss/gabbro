import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/control_scale.dart';

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
      builder: (context) {
        final l = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            // scrollable scrolls title + content + actions together (ADR-016).
            scrollable: true,
            title: Text(l.deleteFolderTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.deleteFolderConfirm(folder)),
                if (hasOthers) ...[
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.reassignEntriesTo),
                    value: reassignTarget != null,
                    onChanged: (v) => setState(() {
                      reassignTarget = v == true ? otherFolders.first : null;
                      if (v == true) clearToNone = false;
                    }),
                  ),
                  if (reassignTarget != null)
                    DropdownButton<String>(
                      isExpanded: true,
                      itemHeight:
                          null, // menu items grow to wrapped height at large text
                      value: reassignTarget,
                      // Collapsed selection ellipsizes instead of hard-clipping (ADR-016).
                      selectedItemBuilder: (context) => otherFolders
                          .map(
                            (f) => Text(
                              f,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                          .toList(),
                      items: otherFolders
                          .map(
                            (f) => DropdownMenuItem(value: f, child: Text(f)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => reassignTarget = v),
                    ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.clearToNone),
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
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.delete),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final l = AppLocalizations.of(context);
      try {
        await widget.deleteFolder(folder, reassignTarget);
        if (mounted) await _load();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString()))),
        );
      }
    }
  }

  Future<void> _showRenameDialog(String folder) async {
    String newName = folder;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        final controller = TextEditingController(text: folder);
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l.renameFolderTitle),
            content: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: l.folderName),
              onChanged: (v) => newName = v,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.save),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && newName.trim().isNotEmpty) {
      final trimmed = newName.trim();
      if (trimmed == folder) return; // unchanged name: nothing to do
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final l = AppLocalizations.of(context);
      try {
        await widget.renameFolder(folder, trimmed);
        if (mounted) await _load();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString()))),
        );
      }
    }
  }

  Future<void> _showAddDialog() async {
    String newName = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.addFolderTitle),
          content: TextFormField(
            autofocus: true,
            decoration: InputDecoration(labelText: l.folderName),
            onChanged: (v) => newName = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.save),
            ),
          ],
        );
      },
    );
    if (confirmed == true && newName.trim().isNotEmpty) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final l = AppLocalizations.of(context);
      try {
        await widget.createFolder(newName.trim());
        if (mounted) await _load();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.manageFoldersTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: l.addFolderTitle,
        child: Icon(Icons.add, size: scaledIconSize(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    l.manageFoldersDefaultNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
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
                              tooltip: l.rename,
                              onPressed: () => _showRenameDialog(folder),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: l.delete,
                              onPressed: () => _showDeleteDialog(folder),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
