import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/screens/help_screen.dart';
import 'package:gabbro/screens/export_screen.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/screens/language_screen.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/change_passphrase_screen.dart';
import 'package:gabbro/screens/generator_screen.dart';
import 'package:gabbro/screens/manage_folders_screen.dart';
import 'package:gabbro/screens/manage_yubikeys_screen.dart';

import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/tablet_vault_layout.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/fido_bridge.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
List<String> _defaultListFolders() => listFolders();
Future<MergeSummary> _defaultMergeVault(String path, List<int> passphrase) =>
    mergeVaultFromFile(path: path, passphrase: passphrase);
Future<String?> _defaultPickSyncFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['gabbro'],
  );
  return result?.files.single.path;
}

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> confirmYubikey(
  List<int> credentialId,
  List<int> salt,
  String pin,
  String transport,
) async {
  if (Platform.isLinux) {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      throw PlatformException(
        code: 'NO_FIDO2_DEVICE',
        message: 'No FIDO2 device found. Insert your YubiKey and try again.',
      );
    }
    await fidoGetHmacSecret(
      devicePath: devices.first,
      credentialId: credentialId,
      salt: salt,
      pin: pin,
    );
    return;
  }
  await _yubikeyChannel.invokeMethod<String>(
    'get_hmac_secret',
    {'credentialId': _toHex(credentialId), 'salt': _toHex(salt), 'pin': pin, 'transport': transport},
  );
}

Future<void> confirmAnyYubikey(
  List<YubikeyRecordData> records,
  String pin,
  String transport,
) async {
  if (Platform.isLinux) {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      throw PlatformException(
        code: 'NO_FIDO2_DEVICE',
        message: 'No FIDO2 device found. Insert your YubiKey and try again.',
      );
    }
    await fidoGetHmacSecretAny(
      devicePath: devices.first,
      records: records
          .map((r) => FidoRecordInput(credentialId: r.credentialId, salt: r.salt))
          .toList(),
      pin: pin,
    );
    return;
  }
  final recordsArg = records
      .map((r) => {'credentialId': _toHex(r.credentialId), 'salt': _toHex(r.salt)})
      .toList();
  await _yubikeyChannel.invokeMethod<Map<Object?, Object?>>(
    'get_hmac_secret_multi',
    {'records': recordsArg, 'pin': pin, 'transport': transport},
  );
}

class VaultListScreen extends StatefulWidget {
  final String vaultPath;
  final String? vaultAlias;
  final List<EntrySummaryData> Function() listEntries;
  final List<String> Function()? listFolders;
  final Future<MergeSummary> Function(String path, List<int> passphrase) mergeVault;
  final Future<String?> Function() onPickSyncFile;

  final VaultEntryData Function(String id)? getEntryFn;
  final Future<void> Function(String id)? onDeleteEntryFn;
  final void Function()? onRefreshFn;
  final AlphabetBarPosition? alphabetBarPosition;
  final Future<void> Function(List<String> ids, String folder)? onAssignFolderFn;

  /// Pre-injected YubiKey records. `null` = auto-detect from vault file at
  /// construction time. Pass `[]` to force passphrase-only mode (tests).
  final List<YubikeyRecordData>? yubikeyRecords;

  const VaultListScreen({
    super.key,
    required this.vaultPath,
    this.vaultAlias,
    this.listEntries = listEntrySummaries,
    this.listFolders,
    this.mergeVault = _defaultMergeVault,
    this.onPickSyncFile = _defaultPickSyncFile,
    this.getEntryFn,
    this.onDeleteEntryFn,
    this.onRefreshFn,
    this.alphabetBarPosition,
    this.onAssignFolderFn,
    this.yubikeyRecords,
  });

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen> {
  static const _filters = [
    'All',
    'Password',
    'Note',
    'Card',
    'Identity',
    'File',
    'Custom',
  ];

  List<EntrySummaryData> _entries = [];
  List<String> _folders = [];
  String? _error;
  String _selectedFilter = 'All';
  String _selectedFolder = '';
  Set<String> _selectedIds = {};
  bool _selectionMode = false;
  bool _isDeleting = false;
  bool _isImporting = false;
  bool _isSyncing = false;
  bool get _isSelecting => _selectionMode || _selectedIds.isNotEmpty;
  final String _transport = 'usb';
  late final List<YubikeyRecordData> _yubikeyRecords;
  bool get _isYubikeyVault => _yubikeyRecords.isNotEmpty;

  String _searchQuery = '';
  bool _fullTextSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ScrollController _chipScrollController = ScrollController();
  bool _showLeftChevron = false;
  bool _showRightChevron = false;

  List<YubikeyRecordData> _detectYubikeyRecords() {
    try {
      return listVaultYubikeyRecords(path: widget.vaultPath);
    } catch (_) {
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    _yubikeyRecords = widget.yubikeyRecords ?? _detectYubikeyRecords();
    _loadEntries();
    _chipScrollController.addListener(_updateChevrons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateChevrons());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateChevrons());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chipScrollController.removeListener(_updateChevrons);
    _chipScrollController.dispose();
    super.dispose();
  }

  void _updateChevrons() {
    if (!_chipScrollController.hasClients) return;
    final pos = _chipScrollController.position;
    final overflows = pos.maxScrollExtent > 0;
    setState(() {
      _showLeftChevron = overflows && pos.pixels > 1.0;
      _showRightChevron = overflows && pos.pixels < pos.maxScrollExtent - 1.0;
    });
  }

  void _scrollChips(bool toRight) {
    if (!_chipScrollController.hasClients) return;
    final pos = _chipScrollController.position;
    final target = (pos.pixels + (toRight ? 120.0 : -120.0)).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    _chipScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void _loadEntries() {
    try {
      final entries = widget.listEntries();
      List<String> folders = [];
      try {
        folders = (widget.listFolders ?? _defaultListFolders)();
      } catch (_) {
        // folders unavailable (e.g. vault locked) — degrade gracefully
      }
      setState(() {
        _entries = entries;
        _folders = folders;
        if (!folders.contains(_selectedFolder)) {
          _selectedFolder = '';
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  IconData _entryTypeIcon(String entryType) => switch (entryType) {
    'Login' => Icons.lock_outline,
    'Note' => Icons.note_outlined,
    'Identity' => Icons.person_outline,
    'Card' => Icons.credit_card_outlined,
    'File' => Icons.insert_drive_file_outlined,
    _ => Icons.tune,
  };

  String _displayType(String entryType, AppLocalizations l) => switch (entryType) {
    'Login' => l.entryTypePassword,
    'Note' => l.entryTypeNote,
    'Identity' => l.entryTypeIdentity,
    'Card' => l.entryTypeCard,
    'File' => l.entryTypeFile,
    'Custom' => l.entryTypeCustom,
    _ => entryType,
  };

  // Used internally for sort/group/search — English fallbacks are fine here.
  String _displayTitle(EntrySummaryData entry) {
    return switch (entry.entryType) {
      'Login' => entry.title.isNotEmpty ? entry.title : '(no URL)',
      'Identity' => entry.title.isNotEmpty ? entry.title : '(no name)',
      _ => entry.title.isNotEmpty ? entry.title : '(untitled)',
    };
  }

  // Used for display in build() — returns localized fallbacks.
  String _localizedDisplayTitle(EntrySummaryData entry, AppLocalizations l) =>
      switch (entry.entryType) {
        'Login' => entry.title.isNotEmpty ? entry.title : l.noUrlFallback,
        'Identity' => entry.title.isNotEmpty ? entry.title : l.noNameFallback,
        _ => entry.title.isNotEmpty ? entry.title : l.untitledFallback,
      };

  String _filterLabel(String f, AppLocalizations l) => switch (f) {
    'All' => l.entryTypeAll,
    'Password' => l.entryTypePassword,
    'Note' => l.entryTypeNote,
    'Card' => l.entryTypeCard,
    'Identity' => l.entryTypeIdentity,
    'File' => l.entryTypeFile,
    'Custom' => l.entryTypeCustom,
    _ => f,
  };

  List<EntrySummaryData> get _filteredEntries {
    final typeFiltered = _selectedFilter == 'All'
        ? _entries
        : _entries.where((e) {
            final rustType = _selectedFilter == 'Password'
                ? 'Login'
                : _selectedFilter;
            return e.entryType == rustType;
          }).toList();

    final folderFiltered = _selectedFolder.isEmpty
        ? typeFiltered
        : typeFiltered.where((e) => e.folder == _selectedFolder).toList();

    if (_searchQuery.isEmpty) return folderFiltered;
    final query = _searchQuery.toLowerCase();
    return folderFiltered
        .where((e) => _fullTextSearch
            ? e.searchBlob.contains(query)
            : _displayTitle(e).toLowerCase().contains(query))
        .toList();
  }

  Map<String, int> get _letterIndex {
    final map = <String, int>{};
    final items = _groupedEntries;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is String) map[item] = i;
    }
    return map;
  }

  String _sectionLetter(EntrySummaryData entry) {
    final title = _displayTitle(entry);
    if (title.isEmpty) return '#';
    final first = title[0];
    return RegExp(r'[A-Za-z]').hasMatch(first) ? first.toUpperCase() : '#';
  }

  int _sortKey(EntrySummaryData entry) {
    final title = _displayTitle(entry);
    if (title.isEmpty) return 1;
    final first = title[0];
    return RegExp(r'[A-Za-z]').hasMatch(first) ? 0 : 1;
  }

  List<dynamic> get _groupedEntries {
    final sorted = List<EntrySummaryData>.from(_filteredEntries)
      ..sort((a, b) {
        final keyDiff = _sortKey(a) - _sortKey(b);
        if (keyDiff != 0) return keyDiff;
        return _displayTitle(
          a,
        ).toLowerCase().compareTo(_displayTitle(b).toLowerCase());
      });

    final result = <dynamic>[];
    String? currentLetter;

    for (final entry in sorted) {
      final letter = _sectionLetter(entry);
      if (letter != currentLetter) {
        result.add(letter);
        currentLetter = letter;
      }
      result.add(entry);
    }
    return result;
  }

  AlphabetBarPosition get _alphabetBarPosition =>
      widget.alphabetBarPosition ??
      GabbroApp.maybeOf(context)?.settings.alphabetBarPosition ??
      AlphabetBarPosition.left;

  void _scrollToLetter(String letter) {
    final index = _letterIndex[letter];
    if (index == null) return;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _showTypePicker() async {
    final l = AppLocalizations.of(context);
    final types = [
      ('Login', l.entryTypePassword),
      ('Note', l.entryTypeNote),
      ('Identity', l.entryTypeIdentity),
      ('Card', l.entryTypeCard),
      ('File', l.entryTypeFile),
      ('Custom', l.entryTypeCustom),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  AppLocalizations.of(context).newEntryTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ...types.map(
                (t) => ListTile(
                  leading: Icon(
                    _entryTypeIcon(t.$1),
                    color: Theme.of(context).colorScheme.primary,
                    semanticLabel: t.$2,
                  ),
                  title: Text(t.$2),
                  onTap: () => Navigator.of(context).pop(t.$1),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CreateEntryScreen(entryType: selected),
      ),
    );
    if (mounted) _loadEntries();
  }

  Future<void> _openExportScreen() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExportScreen(vaultAlias: widget.vaultAlias),
      ),
    );
  }

  Future<void> _openImportScreen() async {
    setState(() => _isImporting = true);
    final count = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute(builder: (context) => const ImportScreen()));
    if (mounted) {
      setState(() => _isImporting = false);
      if (count != null && count > 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).importedEntries(count))));
        _loadEntries();
      }
    }
  }

  Future<void> _confirmAssignFolder(Set<String> ids) async {
    if (_folders.isEmpty) return;
    String? selected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.assignToFolderTitle),
            content: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              hint: Text(l.selectFolder),
              items: _folders
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => setLocal(() => selected = v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                child: Text(l.assign),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || selected == null) return;
    final fn = widget.onAssignFolderFn;
    if (fn != null) {
      await fn(ids.toList(), selected!);
    } else {
      await assignFolderToEntries(ids: ids.toList(), folder: selected!);
    }
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    _loadEntries();
  }

  Future<void> _confirmDelete(Set<String> ids) async {
    final count = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.deleteEntriesTitle(count)),
          content: Text(l.cannotBeUndone),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _isDeleting = true);
    await deleteEntries(ids: ids.toList());
    setState(() {
      _selectedIds.clear();
      _isDeleting = false;
    });
    _loadEntries();
  }

  Future<void> _syncFromFile() async {
    final path = await widget.onPickSyncFile();
    if (path == null || !mounted) return;

    // _SyncPassphraseDialog owns the controller; returns passphrase or null.
    final passphraseText = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SyncPassphraseDialog(filePath: path),
    );
    if (passphraseText == null || !mounted) return;

    final passphraseBytes = utf8.encode(passphraseText);
      setState(() => _isSyncing = true);
      try {
        final summary = await widget.mergeVault(path, passphraseBytes);
        if (!mounted) return;

        final isIdentical = summary.added == 0 &&
            summary.updated == 0 &&
            summary.pendingDeletes.isEmpty &&
            summary.folderConflicts.isEmpty;

        if (isIdentical) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).nothingToSync),
            ),
          );
          return;
        }

        _loadEntries();

        // --- Pending deletes: ask user to confirm each deletion ---
        var deletedCount = 0;
        for (final item in summary.pendingDeletes) {
          if (!mounted) break;
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) {
              final l = AppLocalizations.of(ctx);
              return AlertDialog(
                title: Text(l.deleteEntryTitle),
                content: Text(l.syncDeleteEntryContent(item.title)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l.keep),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(ctx).colorScheme.error,
                    ),
                    child: Text(l.delete),
                  ),
                ],
              );
            },
          );
          if (confirmed == true) {
            await deleteEntry(id: item.id);
            deletedCount++;
          }
        }

        // --- Folder conflicts: ask user to pick which folder ---
        var folderChangedCount = 0;
        for (final conflict in summary.folderConflicts) {
          if (!mounted) break;
          final chosenFolder = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) {
              final l = AppLocalizations.of(ctx);
              final noFolder = l.noFolder;
              return AlertDialog(
                title: Text(l.folderConflictTitle),
                content: Text(l.folderConflictContent(
                  conflict.title,
                  conflict.localFolder.isEmpty ? noFolder : conflict.localFolder,
                  conflict.incomingFolder.isEmpty ? noFolder : conflict.incomingFolder,
                )),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(conflict.localFolder),
                    child: Text(conflict.localFolder.isEmpty
                        ? l.folderConflictKeepUnfoldered
                        : l.folderConflictKeepLocal(conflict.localFolder)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(conflict.incomingFolder),
                    child: Text(conflict.incomingFolder.isEmpty
                        ? l.folderConflictMoveUnfoldered
                        : l.folderConflictMoveIncoming(conflict.incomingFolder)),
                  ),
                ],
              );
            },
          );
          if (chosenFolder != null) {
            await assignFolderToEntries(
                ids: [conflict.id], folder: chosenFolder);
            if (chosenFolder != conflict.localFolder) folderChangedCount++;
          }
        }

        if (deletedCount > 0 || summary.folderConflicts.isNotEmpty) {
          _loadEntries();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).vaultSynced(
                summary.added,
                summary.updated + folderChangedCount,
                deletedCount,
              )),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        final msg = e.toString();
        final isPassphraseMismatch = msg.contains('decryption failed');
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            final l = AppLocalizations.of(ctx);
            return AlertDialog(
              title: Text(l.syncFailedTitle),
              content: Text(
                isPassphraseMismatch ? l.syncPassphraseMismatch : msg,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.dismiss),
                ),
              ],
            );
          },
        );
      } finally {
        if (mounted) setState(() => _isSyncing = false);
      }
  }

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'export':
        _openExportScreen();
      case 'import':
        _openImportScreen();
      case 'sync':
        _syncFromFile();
      case 'change_passphrase':
        final cpAppState = GabbroApp.of(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChangePassphraseScreen(
              vaultPath: widget.vaultPath,
              blockPassphraseCopyPaste: cpAppState.settings.blockPassphraseCopyPaste,
            ),
          ),
        );
      case 'appearance':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AppearanceScreen()),
        );
      case 'language':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const LanguageScreen()),
        );
      case 'security':
        final appState = GabbroApp.of(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SecurityScreen(
              settings: appState.settings,
              onUpdate: (updated) => appState.updateSettings(updated),
              vaultPath: widget.vaultPath,
            ),
          ),
        );
      case 'yubikeys':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ManageYubiKeysScreen(
              vaultPath: widget.vaultPath,
              transport: _transport,
            ),
          ),
        );
      case 'manage_vaults':
        GabbroApp.maybeOf(context)?.navigateToManageVaults();
      case 'generator':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const GeneratorScreen()),
        );
      case 'manage_folders':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ManageFoldersScreen(
              listFolders: () async => listFolders(),
              createFolder: (name) async => createFolder(name: name),
              renameFolder: (oldName, newName) async =>
                  renameFolder(oldName: oldName, newName: newName),
              deleteFolder: (name, reassignTo) async =>
                  deleteFolder(name: name, reassignTo: reassignTo),
            ),
          ),
        );
        if (mounted) _loadEntries();
      case 'help':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const HelpScreen()),
        );
      case 'about':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const AboutScreen()));
    }
  }

  void _lockAndExit() {
    lockVault();
    final appState = GabbroApp.of(context);
    final settings = appState.settings;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => UnlockScreen(
          vaultPath: widget.vaultPath,
          vaultAlias: widget.vaultAlias,
          blockPassphraseCopyPaste: settings.blockPassphraseCopyPaste,
          registry: settings.showVaultList ? appState.registry : null,
          showVaultList: settings.showVaultList,
          biometricEnabled: settings.biometricUnlock,
          onBiometricInvalidated: () => appState.updateSettings(
            settings.copyWith(biometricUnlock: false),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChipRow() {
    final l = AppLocalizations.of(context);
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _updateChevrons();
            return false;
          },
          child: SingleChildScrollView(
            controller: _chipScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: _filters
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(_filterLabel(f, l)),
                        selected: _selectedFilter == f,
                        onSelected: (_) =>
                            setState(() => _selectedFilter = f),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (_showRightChevron)
          Positioned(
            right: 0,
            child: _ChipRowFadeEdge(
              alignment: Alignment.centerRight,
              onTap: () => _scrollChips(true),
            ),
          ),
        if (_showLeftChevron)
          Positioned(
            left: 0,
            child: _ChipRowFadeEdge(
              alignment: Alignment.centerLeft,
              onTap: () => _scrollChips(false),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_error != null) {
      return Scaffold(body: Center(child: Text(l.errorPrefix(_error!))));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelecting
              ? l.selectedCount(_selectedIds.length)
              : widget.vaultAlias != null
                  ? l.gabbroVaultTitle(widget.vaultAlias!)
                  : l.gabbroTitle,
        ),
        actions: [
          if (_isImporting || _isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!_isSelecting) ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: l.tooltipSelectEntries,
              onPressed: () => setState(() => _selectionMode = true),
            ),
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: l.tooltipLockVault,
              onPressed: _lockAndExit,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              tooltip: l.tooltipMenu,
              onSelected: _onMenuSelected,
              itemBuilder: (context) {
                final ml = AppLocalizations.of(context);
                return [
                  PopupMenuItem(
                    value: 'export',
                    child: Row(children: [
                      const Icon(Icons.upload_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ml.menuExportVault)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'import',
                    child: Row(children: [
                      const Icon(Icons.download_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ml.menuImportEntries)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'sync',
                    child: Row(children: [
                      const Icon(Icons.sync, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ml.menuSyncFromFile)),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'manage_vaults',
                    child: Row(children: [
                      const Icon(Icons.folder_special_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ml.menuManageVaults)),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'change_passphrase',
                    child: Row(children: [
                      const Icon(Icons.key_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ml.menuChangePassphrase)),
                    ]),
                  ),
                  PopupMenuItem(
                    enabled: _isYubikeyVault,
                    value: 'yubikeys',
                    child: Row(children: [
                      const Icon(Icons.security_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(ml.menuManageYubiKeys),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'appearance',
                    child: Row(children: [
                      const Icon(Icons.palette_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(ml.menuAppearance),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'language',
                    child: Row(children: [
                      const Icon(Icons.language_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(ml.sectionLanguage),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'security',
                    child: Row(children: [
                      const Icon(Icons.shield_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(ml.menuSecurity),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'manage_folders',
                    child: Row(children: [
                      const Icon(Icons.folder_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ml.menuManageFolders)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'generator',
                    child: Row(children: [
                      const Icon(Icons.casino_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ml.menuPasswordGenerator)),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'help',
                    child: Row(children: [
                      const Icon(Icons.help_outline, size: 20),
                      const SizedBox(width: 12),
                      Text(ml.menuHelp),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'about',
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 20),
                      const SizedBox(width: 12),
                      Text(ml.menuAbout),
                    ]),
                  ),
                ];
              },
            ),
          ],
          if (_isDeleting) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ] else if (_isSelecting) ...[
            IconButton(
              icon: Icon(
                _selectedIds.length == _filteredEntries.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: _selectedIds.length == _filteredEntries.length
                  ? l.tooltipDeselectAll
                  : l.tooltipSelectAll,
              onPressed: () => setState(() {
                if (_selectedIds.length == _filteredEntries.length) {
                  _selectedIds.clear();
                } else {
                  _selectedIds = _filteredEntries.map((e) => e.id).toSet();
                }
              }),
            ),
            if (_folders.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.folder_outlined),
                tooltip: l.tooltipAssignToFolder,
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _confirmAssignFolder(_selectedIds),
              ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDelete(_selectedIds),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedIds.clear();
                _selectionMode = false;
              }),
            ),
          ],
        ],
      ),
      // FAB stays at default bottom-right but the index bar column ends
      // above it via padding, so they never overlap.
      floatingActionButton: _isSelecting
          ? null
          : FloatingActionButton(
              onPressed: _showTypePicker,
              child: const Icon(Icons.add),
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600) {
            return TabletVaultLayout(
              groupedEntries: _groupedEntries,
              filteredEntries: _filteredEntries,
              letterIndex: _letterIndex,
              onLetterSelected: _scrollToLetter,
              displayTitle: (e) => _localizedDisplayTitle(e, l),
              displayType: (t) => _displayType(t, l),
              entryTypeIcon: _entryTypeIcon,
              searchBar: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _fullTextSearch
                        ? l.searchAllFieldsHint
                        : l.searchEntriesHint,
                    prefixIcon: IconButton(
                      icon: Icon(_fullTextSearch
                          ? Icons.manage_search
                          : Icons.search),
                      tooltip: _fullTextSearch
                          ? l.searchAllFieldsTooltip
                          : l.searchByTitleTooltip,
                      onPressed: () =>
                          setState(() => _fullTextSearch = !_fullTextSearch),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            }),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value),
                ),
              ),
              filterChipRow: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_folders.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedFolder,
                        onChanged: (value) =>
                            setState(() => _selectedFolder = value ?? ''),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(l.allFolders),
                          ),
                          ..._folders.map(
                            (f) =>
                                DropdownMenuItem(value: f, child: Text(f)),
                          ),
                        ],
                      ),
                    ),
                  _buildFilterChipRow(),
                ],
              ),
              searchActive: _searchQuery.isNotEmpty,
              onEntryTap: (_) {},
              onRefresh: widget.onRefreshFn ?? _loadEntries,
              getEntryFn: widget.getEntryFn,
              onDeleteEntryFn: widget.onDeleteEntryFn,
              selectionMode: _selectionMode,
              selectedIds: _selectedIds,
              onToggleSelection: (id) => setState(() {
                if (_selectedIds.contains(id)) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                  _selectionMode = true;
                }
              }),
              vaultPath: widget.vaultPath,
              clipboardClearTimeout:
                  GabbroApp.maybeOf(context)?.settings.clipboardClearTimeout ??
                  ClipboardClearTimeout.sixtySeconds,
            );
          }
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: _fullTextSearch
                          ? l.searchAllFieldsHint
                          : l.searchEntriesHint,
                      prefixIcon: IconButton(
                        icon: Icon(_fullTextSearch
                            ? Icons.manage_search
                            : Icons.search),
                        tooltip: _fullTextSearch
                            ? l.searchAllFieldsTooltip
                            : l.searchByTitleTooltip,
                        onPressed: () =>
                            setState(() => _fullTextSearch = !_fullTextSearch),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              }),
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (value) =>
                        setState(() => _searchQuery = value),
                  ),
                ),
                if (_folders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedFolder,
                      onChanged: (value) =>
                          setState(() => _selectedFolder = value ?? ''),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(l.allFolders),
                        ),
                        ..._folders.map(
                          (f) => DropdownMenuItem(value: f, child: Text(f)),
                        ),
                      ],
                    ),
                  ),
                _buildFilterChipRow(),
                Expanded(
                  child: _groupedEntries.isEmpty
                      ? Center(child: Text(l.noEntriesMatch))
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Index bar — fixed width column. Position (left or
                            // right) is read from settings or the test override.
                            if (_searchQuery.isEmpty &&
                                _alphabetBarPosition ==
                                    AlphabetBarPosition.left)
                              SizedBox(
                                width: 48,
                                child: AlphabetIndexBar(
                                  presentLetters: _letterIndex.keys.toSet(),
                                  onLetterSelected: _scrollToLetter,
                                ),
                              ),
                            // List takes all remaining width.
                            Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(
                                  context,
                                ).copyWith(scrollbars: false),
                                child: ScrollablePositionedList.builder(
                                  itemScrollController: _itemScrollController,
                                  padding:
                                      const EdgeInsets.only(bottom: 80),
                                  itemCount: _groupedEntries.length,
                                  itemBuilder: (context, index) {
                                    final item = _groupedEntries[index];
                                    if (item is String) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          4,
                                        ),
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    }
                                    final entry = item as EntrySummaryData;
                                    final el = AppLocalizations.of(context);
                                    return ListTile(
                                      dense: true,
                                      leading: _isSelecting
                                          ? Checkbox(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              value: _selectedIds.contains(
                                                entry.id,
                                              ),
                                              onChanged: (_) =>
                                                  setState(() {
                                                if (_selectedIds.contains(
                                                  entry.id,
                                                )) {
                                                  _selectedIds.remove(
                                                    entry.id,
                                                  );
                                                } else {
                                                  _selectedIds.add(entry.id);
                                                }
                                              }),
                                            )
                                          : Icon(
                                              _entryTypeIcon(entry.entryType),
                                              size: 20,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              semanticLabel: _displayType(
                                                entry.entryType, el,
                                              ),
                                            ),
                                      title: Text(_localizedDisplayTitle(entry, el)),
                                      subtitle: Text(
                                        _displayType(entry.entryType, el),
                                      ),
                                      onLongPress: () => setState(() {
                                        _selectionMode = true;
                                        _selectedIds.add(entry.id);
                                      }),
                                      onTap: () async {
                                        if (_isSelecting) {
                                          setState(() {
                                            if (_selectedIds.contains(
                                              entry.id,
                                            )) {
                                              _selectedIds.remove(entry.id);
                                            } else {
                                              _selectedIds.add(entry.id);
                                            }
                                          });
                                          return;
                                        }
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                EntryDetailScreen(
                                              entry: getEntry(id: entry.id),
                                              clipboardClearTimeout:
                                                  GabbroApp.of(
                                                context,
                                              ).settings.clipboardClearTimeout,
                                            ),
                                          ),
                                        );
                                        if (mounted) _loadEntries();
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (_searchQuery.isEmpty &&
                                _alphabetBarPosition ==
                                    AlphabetBarPosition.right)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 80),
                                child: SizedBox(
                                  width: 48,
                                  child: AlphabetIndexBar(
                                    presentLetters: _letterIndex.keys.toSet(),
                                    onLetterSelected: _scrollToLetter,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Passphrase dialog for "Sync from file".
///
/// Owns its TextEditingController so Flutter can dispose it safely during the
/// dialog exit animation via State.dispose(), avoiding use-after-dispose errors.
/// Returns the entered passphrase text on confirm, or null on cancel.
class _SyncPassphraseDialog extends StatefulWidget {
  final String filePath;
  const _SyncPassphraseDialog({required this.filePath});

  @override
  State<_SyncPassphraseDialog> createState() => _SyncPassphraseDialogState();
}

class _SyncPassphraseDialogState extends State<_SyncPassphraseDialog> {
  final _ctrl = TextEditingController();
  bool _showPass = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.syncFromFileTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.filePath,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: !_showPass,
            decoration: InputDecoration(
              labelText: l.vaultPassphraseLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: Text(l.sync),
        ),
      ],
    );
  }
}

class _ChipRowFadeEdge extends StatelessWidget {
  final Alignment alignment;
  final VoidCallback onTap;
  const _ChipRowFadeEdge({required this.alignment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRight = alignment == Alignment.centerRight;
    final color = Theme.of(context).scaffoldBackgroundColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
            end: isRight ? Alignment.centerRight : Alignment.centerLeft,
            colors: [color.withValues(alpha: 0), color],
          ),
        ),
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRight ? Icons.chevron_right : Icons.chevron_left,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
