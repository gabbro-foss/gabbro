import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/path_field.dart';

/// Sanitises a vault alias for use in a filename.
/// Spaces → `_`; non-alphanum except `-` and `_` are stripped.
/// Falls back to `'vault'` if the result is empty.
String sanitiseAlias(String? alias) {
  if (alias == null || alias.isEmpty) return 'vault';
  final sanitised = alias
      .replaceAll(' ', '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '');
  return sanitised.isEmpty ? 'vault' : sanitised;
}

String _defaultFilename(String? alias, bool isJson) {
  final base = sanitiseAlias(alias);
  final date = DateTime.now().toIso8601String().substring(0, 10);
  return isJson ? '${base}_$date.json' : '${base}_$date.gabbro';
}

enum _ExportFormat { gabbroVault, json }

Future<void> _defaultExport(String path) => exportVault(path: path);
Future<void> _defaultExportJson(String path) => exportVaultJson(path: path);

class ExportScreen extends StatefulWidget {
  final String? initialPath;
  final String? vaultAlias;
  final Future<void> Function(String path) onExport;
  final Future<void> Function(String path) onExportJson;
  final bool isAndroid;

  ExportScreen({
    super.key,
    this.initialPath,
    this.vaultAlias,
    this.onExport = _defaultExport,
    this.onExportJson = _defaultExportJson,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  // On Android: stores the chosen directory path (no filename appended yet).
  // On Linux:   stores the full file path including filename.
  String? _path;
  _ExportFormat _format = _ExportFormat.gabbroVault;
  bool _isExporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final filename = _defaultFilename(
        widget.vaultAlias,
        _format == _ExportFormat.json,
      );
      return '$_path/$filename';
    }
    return _path!;
  }

  Future<void> _export() async {
    if (_path == null || _path!.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).exportSelectDestination);
      return;
    }
    setState(() {
      _isExporting = true;
      _error = null;
    });
    try {
      final path = _exportPath;
      if (_format == _ExportFormat.json) {
        await widget.onExportJson(path);
      } else {
        await widget.onExport(path);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isJson = _format == _ExportFormat.json;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.exportTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.exportChooseFormat,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SegmentedButton<_ExportFormat>(
                segments: const [
                  ButtonSegment(
                    value: _ExportFormat.gabbroVault,
                    label: Text('.gabbro'),
                  ),
                  ButtonSegment(
                    value: _ExportFormat.json,
                    label: Text('JSON'),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: (selection) {
                  setState(() {
                    _format = selection.first;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (isJson)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.exportUnencryptedWarning,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onErrorContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  l.exportPassphraseOnlyNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              Text(
                isJson ? l.exportChooseDestinationJson : l.exportChooseDestinationVault,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!isJson) ...[
                const SizedBox(height: 4),
                Text(
                  l.exportTwoFilesNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              if (widget.isAndroid) ...[
                OutlinedButton.icon(
                  onPressed: _pickDirectory,
                  icon: const Icon(Icons.folder),
                  label: Text(l.chooseFolder),
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
                  key: ValueKey(_format),
                  mode: PathFieldMode.save,
                  hint: isJson ? '/home/user/vault.json' : '/home/user/vault.gabbro',
                  allowedExtensions: isJson ? ['json'] : ['gabbro'],
                  saveFileName: _defaultFilename(widget.vaultAlias, isJson),
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
                    color: colorScheme.error,
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
                    : Text(l.export),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
