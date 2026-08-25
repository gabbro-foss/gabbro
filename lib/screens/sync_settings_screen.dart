import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gabbro/folder_label.dart';
import 'package:gabbro/gabbro_file_picker.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/saf_tree.dart';
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
/// click: the file in that folder carrying this vault's name is merged with
/// no picker, no chooser and no review.
class SyncSettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(AppSettings) onUpdate;

  /// Folder picker; returns a Linux path or an Android tree URI, null on
  /// cancel. Seam for tests.
  final Future<String?> Function() onPickFolder;

  /// Injected for testing; production code uses [Platform.isAndroid].
  final bool isAndroid;

  SyncSettingsScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
    this.onPickFolder = _defaultPickFolder,
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

  Future<void> _pickFolder() async {
    final picked = await widget.onPickFolder();
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
              Text(l.syncFolderDescription, style: small),
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
            ],
          ),
        ),
      ),
    );
  }
}
