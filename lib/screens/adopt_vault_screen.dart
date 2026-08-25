import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/safe_file_picker.dart' show FilePickerUnavailable;
import 'package:gabbro/screens/unlock_screen.dart' show vaultUpgradePathUrl;
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/path_field.dart';
import 'package:gabbro/widgets/url_link.dart';

/// Adopt: register an exported `.gabbro` file as a vault on this device,
/// without creating an empty vault and importing into it. Adopting grants no
/// access — the vault still asks for full credentials at unlock.
// Production defaults: the real bridge. The format probes mirror the unlock
// screen's defaults — a probe that cannot run must never masquerade as a
// diagnosis, so they report false and the generic invalid message stands.
Future<VaultHeaderData> _defaultReadHeader(String path) async =>
    readVaultHeader(path: path);

Future<bool> _defaultFormatTooOld(String path) async {
  try {
    return await vaultFormatTooOld(path: path);
  } catch (_) {
    return false;
  }
}

Future<bool> _defaultFormatTooNew(String path) async {
  try {
    return await vaultFormatTooNew(path: path);
  } catch (_) {
    return false;
  }
}

Future<void> _defaultAdoptCopy(String source, String dest) =>
    adoptVaultFile(source: source, dest: dest);

class AdoptVaultScreen extends StatefulWidget {
  final VaultRegistry registry;

  /// The native open dialog (PathField's `openPicker` seam): a path, null on
  /// cancel, or throws [FilePickerUnavailable] — PathField handles the latter
  /// two itself. Null → PathField's real file dialog.
  final Future<String?> Function()? onPickFile;

  /// Full-parses the picked file and returns its header (alias + YubiKey
  /// records). Throws when the file is not a usable vault.
  final Future<VaultHeaderData> Function(String path) onReadHeader;

  /// Asked only after the header read fails, to tell an intact-but-old or
  /// intact-but-newer vault apart from a corrupt file (same triage order as
  /// the unlock screen).
  final Future<bool> Function(String path) onFormatTooOld;
  final Future<bool> Function(String path) onFormatTooNew;

  /// Called once the file is accepted: registers `path` as a vault under
  /// `alias` (main.dart wires `_onVaultCreated`, which also detects the
  /// YubiKey type from the header).
  final Future<void> Function(String path, String alias) onRegistered;

  /// Android only: copy the picker's cache file into app storage (the Rust
  /// `adopt_vault_file` — validates, refuses an occupied dest, creates the
  /// `.bak`). Linux registers the picked path in place and never calls this.
  final Future<void> Function(String source, String dest) onAdoptCopy;

  /// Android only: the app-storage directory adopted vaults are copied into.
  final Future<String> Function() onDefaultVaultDir;

  /// Test seam; null → [Platform.isAndroid].
  final bool? isAndroid;

  const AdoptVaultScreen({
    super.key,
    required this.registry,
    required this.onRegistered,
    this.onPickFile,
    this.onReadHeader = _defaultReadHeader,
    this.onFormatTooOld = _defaultFormatTooOld,
    this.onFormatTooNew = _defaultFormatTooNew,
    this.onAdoptCopy = _defaultAdoptCopy,
    this.onDefaultVaultDir = GabbroPaths.dataDir,
    this.isAndroid,
  });

  @override
  State<AdoptVaultScreen> createState() => _AdoptVaultScreenState();
}

enum _AdoptError { invalid, tooOld, tooNew, alreadyRegistered }

class _AdoptVaultScreenState extends State<AdoptVaultScreen> {
  final _aliasController = TextEditingController();
  String? _pickedPath;
  _AdoptError? _error;

  /// The alias a confirm was refused for (already registered); null = none.
  String? _collisionAlias;

  /// A free path in `dir` for `basename`, suffixing `-2`, `-3`, … before the
  /// extension when the plain name is taken — the Rust copy refuses an
  /// occupied destination, so the free name must be found here.
  static String _freeDestPath(String dir, String basename) {
    var candidate = '$dir/$basename';
    if (!File(candidate).existsSync()) return candidate;
    final dot = basename.lastIndexOf('.');
    final stem = dot > 0 ? basename.substring(0, dot) : basename;
    final ext = dot > 0 ? basename.substring(dot) : '';
    var n = 2;
    while (true) {
      candidate = '$dir/$stem-$n$ext';
      if (!File(candidate).existsSync()) return candidate;
      n++;
    }
  }

  Future<void> _confirm() async {
    final alias = _aliasController.text.trim();
    if (widget.registry.records.any((r) => r.alias == alias)) {
      setState(() => _collisionAlias = alias);
      _announce(AppLocalizations.of(context).vaultNameAlreadyExists(alias));
      return;
    }
    setState(() => _collisionAlias = null);
    var path = _pickedPath!;
    final onAndroid = widget.isAndroid ?? Platform.isAndroid;
    if (onAndroid) {
      // The picker only handed out a cache copy: move it into app storage
      // under its own name (or the nearest free one).
      final dir = await widget.onDefaultVaultDir();
      final dest = _freeDestPath(dir, path.split('/').last);
      await widget.onAdoptCopy(path, dest);
      path = dest;
    }
    await widget.onRegistered(path, alias);
  }

  /// N4: an error card appears without any focus move, so on Linux the reader
  /// is otherwise silent about it. Linux-only, same gate as everywhere else
  /// (Android's announcement events are deprecated; TalkBack reads the card).
  void _announce(String message) {
    final onAndroid = widget.isAndroid ?? Platform.isAndroid;
    if (onAndroid || !mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  String _errorMessage(AppLocalizations l, _AdoptError error) =>
      switch (error) {
        _AdoptError.invalid => l.restoreFromFileInvalidError,
        _AdoptError.tooOld => l.vaultFormatTooOld,
        _AdoptError.tooNew => l.vaultFormatTooNew,
        _AdoptError.alreadyRegistered => l.adoptAlreadyRegistered,
      };

  // Triage a definite choice: a picker result or a submitted typed path —
  // never a keystroke (the header read parses the whole file).
  Future<void> _triage(String path) async {
    if (path.isEmpty || !mounted) return;
    // Refuse before touching the file: this vault is already in the list, and
    // adopting it again would only produce a second entry for the same file.
    if (widget.registry.records.any((r) => r.path == path)) {
      setState(() {
        _pickedPath = null;
        _error = _AdoptError.alreadyRegistered;
      });
      _announce(
        _errorMessage(AppLocalizations.of(context), _AdoptError.alreadyRegistered),
      );
      return;
    }
    try {
      final header = await widget.onReadHeader(path);
      if (!mounted) return;
      setState(() {
        _pickedPath = path;
        _error = null;
        _aliasController.text = header.alias ?? '';
      });
    } catch (_) {
      // Same triage order as the unlock screen: an intact old or newer vault
      // must be explained, not reported as damaged.
      var error = _AdoptError.invalid;
      try {
        if (await widget.onFormatTooOld(path)) {
          error = _AdoptError.tooOld;
        } else if (await widget.onFormatTooNew(path)) {
          error = _AdoptError.tooNew;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _pickedPath = null;
        _error = error;
      });
      _announce(_errorMessage(AppLocalizations.of(context), error));
    }
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  Widget _errorCard(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (key, linkLabel) = switch (_error!) {
      _AdoptError.invalid => (const Key('adopt_error_invalid'), null),
      _AdoptError.tooOld => (
        const Key('adopt_error_too_old'),
        l.vaultFormatUpgradeLink,
      ),
      _AdoptError.tooNew => (
        const Key('adopt_error_too_new'),
        l.vaultFormatTooNewLink,
      ),
      _AdoptError.alreadyRegistered => (
        const Key('adopt_error_already_registered'),
        null,
      ),
    };
    final text = _errorMessage(l, _error!);
    return Card(
      key: key,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            if (linkLabel != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('adopt_upgrade_link'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(linkLabel),
                onPressed: () => showUrlDialog(
                  context,
                  title: linkLabel,
                  url: vaultUpgradePathUrl,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.adoptTitle)),
      // SafeArea: an explicit ListView padding disables Flutter's automatic
      // system-bar inset (edge-to-edge Android, 2026-08-25).
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Editable + browse: a typed or pasted path keeps working where the
          // native dialog cannot open (portal-less WM); PathField itself
          // surfaces the cancel/unavailable cases.
          PathField(
            key: const Key('adopt_path_field'),
            mode: PathFieldMode.open,
            hint: l.onboardingPathHint,
            allowedExtensions: const ['gabbro'],
            openPicker: widget.onPickFile,
            onPathSelected: (_) {},
            onPathPicked: _triage,
            onSubmitted: _triage,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _errorCard(context),
          ],
          if (_pickedPath != null) ...[
            const SizedBox(height: 16),
            TextField(
              key: const Key('adopt_alias_field'),
              controller: _aliasController,
              decoration: InputDecoration(
                labelText: l.onboardingVaultName,
                errorText: _collisionAlias != null
                    ? l.vaultNameAlreadyExists(_collisionAlias!)
                    : null,
                errorMaxLines: 3,
              ),
            ),
            if (_collisionAlias != null)
              // Key target only: the visible message is the errorText above.
              const SizedBox.shrink(key: Key('adopt_alias_collision')),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('adopt_confirm_button'),
              onPressed: _confirm,
              child: Text(l.adoptConfirm),
            ),
          ],
        ],
      ),
      ),
    );
  }
}
