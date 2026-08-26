import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gabbro/folder_label.dart';
import 'package:gabbro/gabbro_file_picker.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/saf_tree.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:gabbro/screens/export_screen.dart' show exportVaultFileName;
import 'package:gabbro/settings.dart';
import 'package:gabbro/widgets/segmented_row.dart';

// Android: the SAF tree picker, whose grant Kotlin persists, so the file can
// be read later without asking again. Linux: the portal folder dialog.
Future<String?> _defaultPickFolder() async {
  if (!Platform.isAndroid) return GabbroFilePicker.pickDirectory();
  return (await pickSafTree())?.treeUri;
}

/// Sync settings (S5): the auto-merge policy and the remembered sync folder.
///
/// With a folder remembered and auto-merge on, `menu > Sync from vault` is one
/// click: the file in that folder carrying this vault's export name is merged
/// with no file picker, no how-to-apply question and no review.
class SyncSettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(AppSettings) onUpdate;

  /// Folder picker; returns a Linux path or an Android tree URI, null on
  /// cancel. Seam for tests.
  final Future<String?> Function() onPickFolder;

  /// This vault's alias: the sync folder text names the file it expects,
  /// `<alias>.gabbro`, the name the other device's export carries.
  final String? vaultAlias;

  /// Injected for testing; production code uses [Platform.isAndroid].
  final bool isAndroid;

  SyncSettingsScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
    this.onPickFolder = _defaultPickFolder,
    this.vaultAlias,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(AppSettings updated) {
    widget.onUpdate(updated);
    setState(() => _settings = updated);
  }

  bool get _remembered => _settings.syncFolder.isNotEmpty;

  // runPicker raises the dumpable flag for the dialog's duration: the XDG
  // portal refuses a request from a process it cannot inspect (hardening
  // lowers the flag), and any failure becomes the one "unavailable" message.
  Future<void> _pickFolder() async {
    final String? picked;
    try {
      picked = await runPicker(widget.onPickFolder);
    } on FilePickerUnavailable {
      if (mounted) showPickerUnavailable(context, hasManualEntry: false);
      return;
    }
    if (picked == null || !mounted) return;
    _update(_settings.copyWith(syncFolder: picked));
  }

  // Remember is the folder's on/off switch: unticked forgets it, ticked with
  // nothing remembered is a request to choose one.
  Future<void> _onRememberChanged(bool? value) async {
    if (value == true) {
      if (!_remembered) await _pickFolder();
    } else {
      _update(_settings.copyWith(syncFolder: ''));
    }
  }

  /// The folder sentence with the expected file name in bold: that name is
  /// the one thing the user must match on the other device.
  Widget _folderDescription(AppLocalizations l, TextStyle style) {
    final name = exportVaultFileName(widget.vaultAlias);
    final text = l.syncFolderDescription(name);
    final i = text.indexOf(name);
    if (i < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, i)),
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: text.substring(i + name.length)),
        ],
      ),
    );
  }

  Widget _folderRow(
      String label, String folder, AppLocalizations l, TextStyle note) {
    final set = folder.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: label),
        const SizedBox(height: 4),
        Text(
          set ? folderDisplayLabel(folder) : l.folderNotSet,
          style: set ? null : note,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const small = TextStyle(fontSize: 12);
    const note = TextStyle(fontSize: 11);

    return Scaffold(
      appBar: AppBar(title: Text(l.syncSettingsTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Automatic merge ───────────────────────────────────────
              SectionHeader(label: l.sectionAutoMerge),
              const SizedBox(height: 4),
              Text(l.autoMergeDescription, style: small),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l.autoMergeTitle),
                value: _settings.autoMergeSync,
                onChanged: (v) => _update(_settings.copyWith(autoMergeSync: v)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              // The chooser that carried this warning is skipped when the
              // toggle is on, so it has to live here.
              Text(l.syncSamePassphraseWarning, style: note),
              Text(l.autoMergeNote, style: note),
              const SizedBox(height: 32),

              // ── Sync folder ───────────────────────────────────────────
              SectionHeader(label: l.sectionSyncFolder),
              const SizedBox(height: 4),
              _folderDescription(l, small),
              const SizedBox(height: 8),
              Text(
                _remembered
                    ? folderDisplayLabel(_settings.syncFolder)
                    : l.syncFolderNotSet,
                style: _remembered ? null : note,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_open),
                  label: Text(l.chooseFolder),
                ),
              ),
              CheckboxListTile(
                title: Text(l.rememberFolder),
                value: _remembered,
                onChanged: _onRememberChanged,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),

              // ── Export and import folders, read-only (S5) ─────────────
              // One place to see every folder; each is changed on its own
              // screen, so no button and no box here.
              _folderRow(l.exportFolderLabel, _settings.exportFolder, l, note),
              const SizedBox(height: 8),
              _folderRow(l.importFolderLabel, _settings.importFolder, l, note),
              const SizedBox(height: 8),
              Text(l.foldersChangedNote, style: note),
            ],
          ),
        ),
      ),
    );
  }
}
