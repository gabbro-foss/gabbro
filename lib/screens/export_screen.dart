import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/path_field.dart';

Future<void> _defaultExport(String path) => exportVault(path: path);

class ExportScreen extends StatefulWidget {
  final String? initialPath;
  final Future<void> Function(String path) onExport;
  final bool isAndroid;

  ExportScreen({
    super.key,
    this.initialPath,
    this.onExport = _defaultExport,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  // On Android: stores the chosen directory path (no filename appended yet).
  // On Linux:   stores the full file path including filename.
  String? _path;
  bool _isExporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // initialPath is used by tests to inject a pre-chosen directory on Android
    // or a full file path on Linux.
    _path = widget.initialPath;
  }

  Future<void> _pickDirectory() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir != null && mounted) {
      setState(() {
        _path = dir;
        _error = null;
      });
    }
  }

  String get _exportPath {
    if (widget.isAndroid) {
      return '$_path/vault.gabbro';
    }
    return _path!;
  }

  Future<void> _export() async {
    if (_path == null || _path!.isEmpty) {
      setState(() => _error = 'Select a destination.');
      return;
    }
    setState(() {
      _isExporting = true;
      _error = null;
    });
    try {
      await widget.onExport(_exportPath);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export vault')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a destination for your exported vault file.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Two files will be written: vault.gabbro and vault.gabbro.sha256',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (widget.isAndroid) ...[
                OutlinedButton.icon(
                  onPressed: _pickDirectory,
                  icon: const Icon(Icons.folder),
                  label: const Text('Choose folder'),
                ),
                if (_path != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _path!,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ] else
                PathField(
                  mode: PathFieldMode.save,
                  hint: '/home/user/vault.gabbro',
                  allowedExtensions: ['gabbro'],
                  saveFileName: 'vault.gabbro',
                  initialPath: _path,
                  onPathSelected: (p) => setState(() {
                    _path = p;
                    _error = null;
                  }),
                ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (_isExporting || _path == null) ? null : _export,
                child: _isExporting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Export'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
