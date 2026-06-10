import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/path_field.dart';

/// Picked export folder: the persisted SAF tree URI and a display label.
typedef ExportFolder = ({String treeUri, String displayName});

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

String _defaultFilename(String? alias, bool isJson, {bool includeDate = true}) {
  final base = sanitiseAlias(alias);
  if (includeDate) {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    return isJson ? '${base}_$date.json' : '${base}_$date.gabbro';
  }
  return isJson ? '$base.json' : '$base.gabbro';
}

enum _ExportFormat { gabbroVault, json }

Future<void> _defaultExport(String path) => exportVault(path: path);
Future<void> _defaultExportJson(String path) => exportVaultJson(path: path);
Future<void> _defaultExportPassphraseOnly(String path) =>
    exportVaultPassphraseOnly(path: path);

// ── Android SAF export (ADR-013) ──────────────────────────────────────────────
// Raw POSIX paths can't overwrite a file another app created under scoped storage,
// so Android `.gabbro` export writes via the Storage Access Framework: Rust builds
// the ciphertext bytes, Kotlin writes them into the user-granted directory tree.
const _exportChannel = MethodChannel('app.gabbro.gabbro/export');

Future<ExportFolder?> _defaultPickExportDir() async {
  final r = await _exportChannel.invokeMethod<Map<Object?, Object?>>(
    'pick_export_dir',
  );
  if (r == null) return null; // user cancelled
  return (
    treeUri: r['treeUri'] as String,
    displayName: r['displayName'] as String,
  );
}

Future<bool> _defaultHasGrant(String treeUri) async =>
    await _exportChannel.invokeMethod<bool>('has_grant', {
      'treeUri': treeUri,
    }) ??
    false;

Future<void> _defaultWriteExport(
  String treeUri,
  String filename,
  Uint8List data,
  String sha256Filename,
  String sha256Content,
) => _exportChannel.invokeMethod<void>('write_export_file', {
  'treeUri': treeUri,
  'filename': filename,
  'data': data,
  'sha256Filename': sha256Filename,
  'sha256Content': sha256Content,
});

Future<ExportArtifact> _defaultBuildExportBytes(String filename) =>
    buildExportBytes(vaultFilename: filename);
Future<ExportArtifact> _defaultBuildExportPassphraseOnlyBytes(
  String filename,
) => buildExportPassphraseOnlyBytes(vaultFilename: filename);

Future<void> _noopSaveFolder(String treeUri) async {}

class ExportScreen extends StatefulWidget {
  final String? initialPath;
  final String? vaultAlias;
  final Future<void> Function(String path) onExport;
  final Future<void> Function(String path) onExportJson;

  /// The protection-preserving default writes a passphrase-only copy of a
  /// key-protected vault only when the user opts in via the downgrade toggle.
  final Future<void> Function(String path) onExportPassphraseOnly;

  /// Whether the active vault is protected by a YubiKey (ADR-013). Drives the
  /// protection indicator and the opt-in passphrase-only downgrade toggle.
  final bool isKeyProtected;
  final bool isAndroid;

  // ── Android SAF `.gabbro` export seams (ADR-013) ──────────────────────────
  /// Remembered SAF tree URI of the export folder (from settings); empty if none.
  final String initialExportFolderUri;

  /// Persist the chosen folder URI (wired to settings by the caller).
  final Future<void> Function(String treeUri) onSaveExportFolderUri;

  /// Launch the SAF folder picker; null if the user cancels.
  final Future<ExportFolder?> Function() onPickExportDir;

  /// Whether a persisted write grant for `treeUri` is still held.
  final Future<bool> Function(String treeUri) onHasGrant;

  /// Write the export bytes + `.sha256` companion into the granted tree.
  final Future<void> Function(
    String treeUri,
    String filename,
    Uint8List data,
    String sha256Filename,
    String sha256Content,
  )
  onWriteExport;

  /// Build the protection-preserving export ciphertext + SHA line (no write).
  final Future<ExportArtifact> Function(String filename) onBuildExportBytes;

  /// Build the opt-in passphrase-only downgrade ciphertext + SHA line (no write).
  final Future<ExportArtifact> Function(String filename)
  onBuildExportPassphraseOnlyBytes;

  ExportScreen({
    super.key,
    this.initialPath,
    this.vaultAlias,
    this.onExport = _defaultExport,
    this.onExportJson = _defaultExportJson,
    this.onExportPassphraseOnly = _defaultExportPassphraseOnly,
    this.isKeyProtected = false,
    this.initialExportFolderUri = '',
    this.onSaveExportFolderUri = _noopSaveFolder,
    this.onPickExportDir = _defaultPickExportDir,
    this.onHasGrant = _defaultHasGrant,
    this.onWriteExport = _defaultWriteExport,
    this.onBuildExportBytes = _defaultBuildExportBytes,
    this.onBuildExportPassphraseOnlyBytes =
        _defaultBuildExportPassphraseOnlyBytes,
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
  bool _includeDate = true;
  // ADR-013: opt-in downgrade — export a key-protected vault as passphrase-only.
  // Default OFF (the protection-preserving default); only shown for key-protected
  // vaults exporting to .gabbro.
  bool _passphraseOnly = false;
  bool _isExporting = false;
  String? _error;

  // Android `.gabbro` SAF destination (remembered across runs). Separate from
  // `_path`, which holds the file_picker dir used by the JSON + Linux paths.
  String _exportFolderUri = '';
  String? _folderDisplayName;

  // Android `.gabbro` export goes through SAF; JSON + Linux keep raw paths.
  bool get _useSaf => widget.isAndroid && _format != _ExportFormat.json;

  bool get _destinationReady => _useSaf
      ? _exportFolderUri.isNotEmpty
      : (_path != null && _path!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _exportFolderUri = widget.initialExportFolderUri;
    if (widget.isAndroid && _exportFolderUri.isNotEmpty) {
      _validateGrant();
    }
  }

  // Drop a remembered folder whose grant the user has revoked in Android Settings,
  // so the UI re-prompts instead of failing at write time.
  Future<void> _validateGrant() async {
    final held = await widget.onHasGrant(_exportFolderUri);
    if (!held && mounted) setState(() => _exportFolderUri = '');
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

  Future<void> _pickExportFolder() async {
    final picked = await widget.onPickExportDir();
    if (picked == null || !mounted) return;
    setState(() {
      _exportFolderUri = picked.treeUri;
      _folderDisplayName = picked.displayName;
      _error = null;
    });
    await widget.onSaveExportFolderUri(picked.treeUri);
  }

  /// Human-readable label for a SAF tree URI, e.g.
  /// `content://…/tree/primary%3ADownload%2FGabbroSync` -> `primary:Download/GabbroSync`.
  String _folderLabel() {
    if (_folderDisplayName != null && _folderDisplayName!.isNotEmpty) {
      return _folderDisplayName!;
    }
    final marker = '/tree/';
    final i = _exportFolderUri.indexOf(marker);
    if (i < 0) return _exportFolderUri;
    return Uri.decodeComponent(_exportFolderUri.substring(i + marker.length));
  }

  String get _exportPath {
    if (widget.isAndroid) {
      final filename = _defaultFilename(
        widget.vaultAlias,
        _format == _ExportFormat.json,
        includeDate: _includeDate,
      );
      return '$_path/$filename';
    }
    return _path!;
  }

  Future<void> _export() async {
    if (!_destinationReady) {
      setState(
        () => _error = AppLocalizations.of(context).exportSelectDestination,
      );
      return;
    }
    setState(() {
      _isExporting = true;
      _error = null;
    });
    try {
      if (_useSaf) {
        // Android `.gabbro`: Rust builds ciphertext bytes, Kotlin writes them into
        // the granted folder tree (overwrites a same-named file even if the sync
        // app created it — raw paths can't under scoped storage).
        final filename = _defaultFilename(
          widget.vaultAlias,
          false,
          includeDate: _includeDate,
        );
        final artifact = (widget.isKeyProtected && _passphraseOnly)
            ? await widget.onBuildExportPassphraseOnlyBytes(filename)
            : await widget.onBuildExportBytes(filename);
        await widget.onWriteExport(
          _exportFolderUri,
          filename,
          artifact.vaultBytes,
          '$filename.sha256',
          artifact.sha256Line,
        );
      } else {
        final path = _exportPath;
        if (_format == _ExportFormat.json) {
          await widget.onExportJson(path);
        } else if (widget.isKeyProtected && _passphraseOnly) {
          // Opt-in downgrade: write a passphrase-only copy (ADR-013).
          await widget.onExportPassphraseOnly(path);
        } else {
          // Protection-preserving default.
          await widget.onExport(path);
        }
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
        child: SingleChildScrollView(
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
                        Icon(
                          Icons.warning_amber_rounded,
                          color: colorScheme.onErrorContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l.exportUnencryptedWarning,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // ADR-013 protection indicator: always state what protection the
                  // exported copy will carry.
                  Text(
                    widget.isKeyProtected && !_passphraseOnly
                        ? l.exportProtectionKeyProtected
                        : l.exportPassphraseOnlyNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  // Opt-in passphrase-only downgrade — key-protected vaults only.
                  if (widget.isKeyProtected) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.exportWithoutYubikey),
                      value: _passphraseOnly,
                      onChanged: (v) => setState(() {
                        _passphraseOnly = v;
                        _error = null;
                      }),
                    ),
                    if (_passphraseOnly)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: colorScheme.onErrorContainer,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l.exportWithoutYubikeyWarning,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onErrorContainer,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.exportIncludeDate),
                  value: _includeDate,
                  onChanged: (v) => setState(() => _includeDate = v),
                ),
                Text(
                  isJson
                      ? l.exportChooseDestinationJson
                      : l.exportChooseDestinationVault,
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
                if (widget.isAndroid && !isJson) ...[
                  // `.gabbro`: SAF folder (overwrites work inside the granted tree).
                  OutlinedButton.icon(
                    onPressed: _pickExportFolder,
                    icon: const Icon(Icons.folder),
                    label: Text(l.chooseFolder),
                  ),
                  if (_exportFolderUri.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _folderLabel(),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ] else if (widget.isAndroid) ...[
                  // JSON: unchanged raw-path folder picker (plaintext stays Rust-side).
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
                    key: ValueKey((_format, _includeDate)),
                    mode: PathFieldMode.save,
                    hint: isJson
                        ? '/home/user/vault.json'
                        : '/home/user/vault.gabbro',
                    allowedExtensions: isJson ? ['json'] : ['gabbro'],
                    saveFileName: _defaultFilename(
                      widget.vaultAlias,
                      isJson,
                      includeDate: _includeDate,
                    ),
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
                    style: TextStyle(color: colorScheme.error, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (_isExporting || !_destinationReady)
                      ? null
                      : _export,
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
      ),
    );
  }
}
