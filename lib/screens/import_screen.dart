import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gabbro/control_scale.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/nfc_capability.dart';
import 'package:gabbro/screens/csv_mapping_screen.dart';
import 'package:gabbro/screens/import_failures_dialog.dart';
import 'package:gabbro/screens/unlock_screen.dart' show vaultUpgradePathUrl;
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/path_field.dart';
import 'package:gabbro/widgets/url_link.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';

/// Import size caps, mirrored from `rust/src/import/mod.rs` - keep in sync. A
/// malicious export file could otherwise exhaust memory while being read, before
/// the Rust parser's own cap is reached, so we reject oversized files here too
/// (before reading them) and announce the limits on screen (S-02).
const int kTextImportMaxBytes = 25 * 1024 * 1024;
const int kEnpassImportMaxBytes = 128 * 1024 * 1024;

/// Whether a file of [sizeBytes] exceeds the import cap for its format.
bool importSizeExceeded(int sizeBytes, {required bool isEnpass}) =>
    sizeBytes > (isEnpass ? kEnpassImportMaxBytes : kTextImportMaxBytes);

/// Human-readable MB label for a cap, e.g. `25 * 1024 * 1024` -> "25 MB".
String importLimitLabel(int bytes) => '${bytes ~/ (1024 * 1024)} MB';

Future<ImportResult> _defaultImportEnpass(List<int> data) =>
    importFromEnpass(data: data);
Future<ImportResult> _defaultImportBitwarden(List<int> data) =>
    importFromBitwarden(data: data);
Future<ImportResult> _defaultImportGooglePm(List<int> data) =>
    importFromGooglePm(data: data);
Future<ImportResult> _defaultImportDashlane(List<int> data) =>
    importFromDashlane(data: data);
CsvPreviewData _defaultSniffCsv(String input) => sniffCsvFile(input: input);
Future<GabbroImportResult> _defaultImportGabbro(
  String path,
  List<int> passphrase,
) => importFromGabbro(path: path, passphrase: passphrase);

/// Sync from a key-protected source: passphrase + a tapped registered YubiKey
/// (ADR-013).
Future<GabbroImportResult> _defaultImportGabbroWithKey(
  String path,
  List<int> passphrase,
  List<int> hmac,
  List<int> credentialId,
) => importFromGabbroWithKey(
  path: path,
  passphrase: passphrase,
  hmacSecret: hmac,
  credentialId: credentialId,
);

/// Reads the source vault's YubiKey records to decide whether a key is required.
/// Non-empty means key-protected. Header read only.
List<YubikeyRecordData> _defaultDetectSourceRecords(String path) =>
    listVaultYubikeyRecords(path: path);

Future<YubikeyHmacMatch> _defaultGetYubikeyHmac(
  List<YubikeyRecordData> records,
  String pin,
  String transport,
) => getAnyYubikeyHmacSecret(records: records, pin: pin, transport: transport);

// Same shape as the unlock screen's probe: "cannot tell" must never claim the
// file is merely old, or a genuinely corrupt source would be mis-explained.
Future<bool> _defaultSourceFormatTooOld(String path) async {
  try {
    return await vaultFormatTooOld(path: path);
  } catch (_) {
    return false;
  }
}

// A source written by a newer Gabbro build. Explained (update Gabbro) rather
// than dumping the English-only Rust text.
Future<bool> _defaultSourceFormatTooNew(String path) async {
  try {
    return await vaultFormatTooNew(path: path);
  } catch (_) {
    return false;
  }
}

Future<void> _noopSaveFolder(String folder) async {}

/// What the chosen file is. One picker serves all six; the type decides the
/// file filter, the explanation, the action, and (Gabbro only) the passphrase
/// and YubiKey sub-form.
enum ImportType { gabbro, csv, googlePm, dashlane, enpass, bitwarden }

class ImportScreen extends StatefulWidget {
  final Future<ImportResult> Function(List<int> data) onImportEnpass;
  final Future<ImportResult> Function(List<int> data) onImportBitwarden;
  final Future<ImportResult> Function(List<int> data) onImportGooglePm;
  final Future<ImportResult> Function(List<int> data) onImportDashlane;
  final CsvPreviewData Function(String input) onSniffCsv;
  final Future<GabbroImportResult> Function(String path, List<int> passphrase)
  onImportGabbro;

  /// Sync from a key-protected source: passphrase + tapped YubiKey (ADR-013).
  final Future<GabbroImportResult> Function(
    String path,
    List<int> passphrase,
    List<int> hmac,
    List<int> credentialId,
  )
  onImportGabbroWithKey;

  /// Detects whether the chosen `.gabbro` source is key-protected.
  final List<YubikeyRecordData> Function(String path) onDetectSourceRecords;

  /// Prompts for a YubiKey tap and returns the hmac + matched credential.
  final Future<YubikeyHmacMatch> Function(
    List<YubikeyRecordData> records,
    String pin,
    String transport,
  )
  onGetYubikeyHmac;

  /// Whether the chosen `.gabbro` source is intact but predates the readable
  /// floor. Asked only after an import fails, to tell "too old" apart from a
  /// wrong passphrase or a damaged file - an old vault is undamaged and needs
  /// explaining, never a raw error string. Mirrors the unlock screen's
  /// `onVaultFormatTooOld` so both refusals behave the same.
  final Future<bool> Function(String path) onSourceFormatTooOld;

  /// Whether the chosen `.gabbro` source was written by a newer Gabbro build.
  /// Mirrors [onSourceFormatTooOld]; the fix is to update Gabbro.
  final Future<bool> Function(String path) onSourceFormatTooNew;

  final bool isAndroid;

  /// Remembered import folder (from settings): where the file dialog opens.
  /// A Linux path or the Android location the picker last reported.
  final String initialImportFolder;

  /// Persist the folder to remember; an empty string forgets it.
  final Future<void> Function(String folder) onSaveImportFolder;

  /// Pre-selected Gabbro source path. Mainly a test seam (the path is otherwise
  /// chosen via the native picker); when set, source protection is detected at
  /// construction so the YubiKey fields render without a picker round-trip.
  final String? initialGabbroPath;

  ImportScreen({
    super.key,
    this.onImportEnpass = _defaultImportEnpass,
    this.onImportBitwarden = _defaultImportBitwarden,
    this.onImportGooglePm = _defaultImportGooglePm,
    this.onImportDashlane = _defaultImportDashlane,
    this.onSniffCsv = _defaultSniffCsv,
    this.onImportGabbro = _defaultImportGabbro,
    this.onImportGabbroWithKey = _defaultImportGabbroWithKey,
    this.onDetectSourceRecords = _defaultDetectSourceRecords,
    this.onGetYubikeyHmac = _defaultGetYubikeyHmac,
    this.onSourceFormatTooOld = _defaultSourceFormatTooOld,
    this.onSourceFormatTooNew = _defaultSourceFormatTooNew,
    this.initialGabbroPath,
    this.initialImportFolder = '',
    this.onSaveImportFolder = _noopSaveFolder,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportType _type = ImportType.gabbro;
  String? _path;

  // The Remember box (ticked by default): the folder of the picked file is
  // remembered, and the next dialog opens there. Unticking forgets it.
  bool _remember = true;
  late String _importFolder = widget.initialImportFolder;
  String? _lastPickedFolder;
  bool _isImporting = false;
  String? _error;

  // Source intact but written by a newer build: explain "update Gabbro".
  bool _gabbroFormatTooNew = false;

  /// Distinct from [_error]: the source is intact, just older than this
  /// build reads. Explained with a link, never shown as a raw failure.
  bool _gabbroFormatTooOld = false;

  final _passphraseController = TextEditingController();
  bool _showPassphrase = false;

  // ADR-013: when the chosen Gabbro source is key-protected, the user must tap a
  // registered YubiKey (plus a PIN, and a transport choice on Android) to sync.
  List<YubikeyRecordData> _gabbroSourceRecords = [];
  final _yubikeyPinController = TextEditingController();
  final _yubikeyPinFocus = FocusNode();
  bool _yubikeyPinObscured = true;
  String _gabbroTransport = 'usb';

  bool get _gabbroSourceIsKeyProtected => _gabbroSourceRecords.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialGabbroPath;
    if (initial != null && initial.isNotEmpty) {
      _path = initial;
      try {
        _gabbroSourceRecords = widget.onDetectSourceRecords(initial);
      } catch (_) {
        _gabbroSourceRecords = [];
      }
    }
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _yubikeyPinController.dispose();
    _yubikeyPinFocus.dispose();
    super.dispose();
  }

  /// Extensions differ per type, so a path chosen for one type would arm the
  /// button on a file the new type cannot parse: the path goes with the type.
  void _setType(ImportType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _path = null;
      _error = null;
      _gabbroFormatTooOld = false;
      _gabbroFormatTooNew = false;
      _gabbroSourceRecords = [];
    });
  }

  void _onFolderPicked(String folder) {
    _lastPickedFolder = folder;
    if (!_remember) return;
    _importFolder = folder;
    widget.onSaveImportFolder(folder);
  }

  Future<void> _onRememberChanged(bool? value) async {
    final on = value == true;
    setState(() => _remember = on);
    if (!on) {
      await widget.onSaveImportFolder('');
      return;
    }
    // Re-ticked: remember what is on screen, or what was last picked.
    final folder = _lastPickedFolder ?? _importFolder;
    if (folder.isEmpty) return;
    _importFolder = folder;
    await widget.onSaveImportFolder(folder);
  }

  void _setPath(String p) => setState(() {
    _path = p;
    _error = null;
    _gabbroFormatTooOld = false;
    _gabbroFormatTooNew = false;
    if (_type == ImportType.gabbro) {
      try {
        _gabbroSourceRecords = widget.onDetectSourceRecords(p);
      } catch (_) {
        _gabbroSourceRecords = [];
      }
    }
  });

  String _typeTitle(AppLocalizations l, ImportType t) => switch (t) {
    ImportType.gabbro => l.gabbroVaultSection,
    ImportType.csv => l.genericCsvSection,
    ImportType.googlePm => 'Google Password Manager',
    ImportType.dashlane => 'Dashlane',
    ImportType.enpass => 'Enpass',
    ImportType.bitwarden => 'Bitwarden',
  };

  String _typeSubtitle(AppLocalizations l) => switch (_type) {
    ImportType.gabbro => l.importGabbroSubtitle,
    ImportType.csv => l.importCsvSubtitle,
    ImportType.googlePm => l.importGooglePmSubtitle,
    ImportType.dashlane => l.importDashlaneSubtitle,
    ImportType.enpass => l.importEnpassSubtitle,
    ImportType.bitwarden => l.importBitwardenSubtitle,
  };

  String get _extension => switch (_type) {
    ImportType.gabbro => 'gabbro',
    ImportType.csv || ImportType.googlePm || ImportType.dashlane => 'csv',
    ImportType.enpass || ImportType.bitwarden => 'json',
  };

  String get _hint => switch (_type) {
    ImportType.gabbro => '/home/user/vault.gabbro',
    ImportType.csv => '/home/user/passwords.csv',
    ImportType.googlePm => '/home/user/Google Passwords.csv',
    ImportType.dashlane => '/home/user/dashlane_credentials.csv',
    ImportType.enpass => '/home/user/enpass_export.json',
    ImportType.bitwarden => '/home/user/bitwarden_export.json',
  };

  Future<void> _runAction() => switch (_type) {
    ImportType.gabbro => _importGabbro(),
    ImportType.csv => _sniffAndPushCsvMapping(),
    ImportType.googlePm => _importJsonOrCsv(widget.onImportGooglePm),
    ImportType.dashlane => _importJsonOrCsv(widget.onImportDashlane),
    ImportType.enpass => _importJsonOrCsv(widget.onImportEnpass),
    ImportType.bitwarden => _importJsonOrCsv(widget.onImportBitwarden),
  };

  /// The chosen file, once it exists and fits the cap; else the error is set.
  File? _checkedFile(AppLocalizations l) {
    final path = _path;
    if (path == null || path.isEmpty) {
      setState(() => _error = l.importSelectFile);
      return null;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _error = l.importFileNotFound);
      return null;
    }
    if (_type != ImportType.gabbro) {
      final isEnpass = _type == ImportType.enpass;
      if (importSizeExceeded(file.lengthSync(), isEnpass: isEnpass)) {
        final cap = isEnpass ? kEnpassImportMaxBytes : kTextImportMaxBytes;
        setState(
          () => _error = l.importFileTooLarge(importLimitLabel(cap)),
        );
        return null;
      }
    }
    return file;
  }

  Future<void> _importJsonOrCsv(
    Future<ImportResult> Function(List<int> data) importer,
  ) async {
    final file = _checkedFile(AppLocalizations.of(context));
    if (file == null) return;
    setState(() {
      _isImporting = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final result = await importer(bytes);
      var editedCount = 0;
      if (result.failures.isNotEmpty && mounted) {
        editedCount = await showImportFailuresDialog(context, result.failures);
      }
      if (mounted) {
        Navigator.of(context).pop(result.imported.toInt() + editedCount);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).importFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _importGabbro() async {
    final l = AppLocalizations.of(context);
    final file = _checkedFile(l);
    if (file == null) return;
    final path = file.path;
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) {
      setState(() => _error = l.importEnterPassphrase);
      return;
    }
    // A key-protected source also needs a YubiKey PIN (ADR-013).
    if (_gabbroSourceIsKeyProtected && _yubikeyPinController.text.isEmpty) {
      setState(() => _error = l.yubiKeyPinRequired);
      return;
    }
    setState(() {
      _isImporting = true;
      _error = null;
      _gabbroFormatTooOld = false;
      _gabbroFormatTooNew = false;
    });
    try {
      final passphraseBytes = utf8.encode(passphrase);
      final GabbroImportResult result;
      if (_gabbroSourceIsKeyProtected) {
        // Tap a registered key to open the key-protected source, then sync.
        final match = await widget.onGetYubikeyHmac(
          _gabbroSourceRecords,
          _yubikeyPinController.text,
          _gabbroTransport,
        );
        result = await widget.onImportGabbroWithKey(
          path,
          passphraseBytes,
          match.hmac,
          match.credentialId,
        );
      } else {
        result = await widget.onImportGabbro(path, passphraseBytes);
      }
      if (mounted) Navigator.of(context).pop(result.imported.toInt());
    } catch (e) {
      if (!mounted) return;
      // An intact pre-v11 source fails here too. It is not corrupt and the user
      // did not mistype, so explain the format instead of dumping the Rust text
      // (which is English-only and renders its URL as dead plain text).
      final tooOld = await widget.onSourceFormatTooOld(path);
      final tooNew = tooOld ? false : await widget.onSourceFormatTooNew(path);
      if (!mounted) return;
      setState(() {
        _gabbroFormatTooOld = tooOld;
        _gabbroFormatTooNew = tooNew;
        _error = (tooOld || tooNew)
            ? null
            : AppLocalizations.of(context).importFailed(e.toString());
      });
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _sniffAndPushCsvMapping() async {
    final file = _checkedFile(AppLocalizations.of(context));
    if (file == null) return;
    setState(() {
      _isImporting = true;
      _error = null;
    });
    try {
      final content = await file.readAsString();
      final preview = widget.onSniffCsv(content);
      if (!mounted) return;
      final count = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (context) =>
              CsvMappingScreen(csvContent: content, preview: preview),
        ),
      );
      if (mounted && count != null) Navigator.of(context).pop(count);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).importFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Widget _duplicateWarningBanner(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.importDuplicateWarning,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.importTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _duplicateWarningBanner(context),
              const SizedBox(height: 12),
              Text(
                l.importSizeLimitNote(
                  importLimitLabel(kTextImportMaxBytes),
                  importLimitLabel(kEnpassImportMaxBytes),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              _typeDropdown(l),
              const SizedBox(height: 8),
              Text(_typeSubtitle(l), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              // Keyed by type: a new type gets a fresh, empty field (the path
              // was cleared with the type).
              PathField(
                key: ValueKey(_type),
                mode: PathFieldMode.open,
                hint: _hint,
                initialPath: _path,
                allowedExtensions: [_extension],
                startFolder:
                    _remember && _importFolder.isNotEmpty ? _importFolder : null,
                onPathSelected: _setPath,
                onFolderPicked: _onFolderPicked,
              ),
              CheckboxListTile(
                title: Text(l.rememberFolder),
                subtitle: Text(l.rememberFolderNote),
                value: _remember,
                onChanged: _onRememberChanged,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_type == ImportType.gabbro) ..._gabbroFields(l),
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
              if (_type == ImportType.gabbro) ..._gabbroFormatNotes(l),
              const SizedBox(height: 12),
              // While syncing a key-protected source we are blocked on a
              // hardware tap. Surface the "tap now" prompt (matching the
              // change-passphrase / manage-vaults screens) so the spinner is
              // never silent - on Android the tap call blocks until a key is
              // presented; the user can also back out to cancel.
              if (_type == ImportType.gabbro &&
                  _isImporting &&
                  _gabbroSourceIsKeyProtected) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.tapYubiKeyNow,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _isImporting ? null : _runAction,
                child: _isImporting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_type == ImportType.csv ? l.next : l.import),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeDropdown(AppLocalizations l) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l.importSourceLabel,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButton<ImportType>(
        isExpanded: true,
        underline: const SizedBox.shrink(),
        itemHeight: null, // menu items grow to wrapped height at large text
        value: _type,
        // Collapsed selection ellipsizes instead of hard-clipping (ADR-016).
        // minHeight 48 so the collapsed button is a 48dp tap target (a11y
        // net); open menu items still grow via itemHeight: null.
        selectedItemBuilder: (context) => ImportType.values
            .map(
              (t) => Container(
                alignment: AlignmentDirectional.centerStart,
                constraints: const BoxConstraints(minHeight: 48),
                child: Text(
                  _typeTitle(l, t),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        items: ImportType.values
            .map(
              (t) => DropdownMenuItem(value: t, child: Text(_typeTitle(l, t))),
            )
            .toList(),
        onChanged: (t) {
          if (t != null) _setType(t);
        },
      ),
    );
  }

  List<Widget> _gabbroFields(AppLocalizations l) => [
    const SizedBox(height: 12),
    TextField(
      controller: _passphraseController,
      obscureText: !_showPassphrase,
      // A key-protected source still needs a PIN, so advance to it;
      // otherwise Enter runs the import.
      onSubmitted: (_) => _gabbroSourceIsKeyProtected
          ? _yubikeyPinFocus.requestFocus()
          : _importGabbro(),
      decoration: InputDecoration(
        labelText: l.vaultPassphraseLabel,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          iconSize: scaledSuffixIconSize(context),
          icon: Icon(
            _showPassphrase ? Icons.visibility_off : Icons.visibility,
            semanticLabel: _showPassphrase ? l.tooltipHide : l.tooltipShow,
          ),
          tooltip: _showPassphrase ? l.tooltipHide : l.tooltipShow,
          onPressed: () => setState(() => _showPassphrase = !_showPassphrase),
        ),
      ),
    ),
    if (_gabbroSourceIsKeyProtected) ...[
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.usb, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.importSourceKeyProtected,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _yubikeyPinController,
        focusNode: _yubikeyPinFocus,
        obscureText: _yubikeyPinObscured,
        onSubmitted: (_) => _importGabbro(),
        decoration: InputDecoration(
          labelText: l.yubiKeyPinLabel,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            iconSize: scaledSuffixIconSize(context),
            icon: Icon(
              _yubikeyPinObscured ? Icons.visibility : Icons.visibility_off,
              semanticLabel: _yubikeyPinObscured
                  ? l.tooltipShowPin
                  : l.tooltipHidePin,
            ),
            tooltip: _yubikeyPinObscured ? l.tooltipShowPin : l.tooltipHidePin,
            onPressed: () =>
                setState(() => _yubikeyPinObscured = !_yubikeyPinObscured),
          ),
        ),
      ),
      if (widget.isAndroid && nfcAvailable) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Text(l.transportLabel, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'usb', label: Text(l.transportUsb)),
                ButtonSegment(value: 'nfc', label: Text(l.transportNfc)),
              ],
              selected: {_gabbroTransport},
              onSelectionChanged: (s) =>
                  setState(() => _gabbroTransport = s.first),
            ),
          ],
        ),
      ],
    ],
  ];

  // The source is intact, just too old: same words and link as the unlock
  // screen, so one refusal is not two different experiences. Error-red is
  // right - the import did fail - but the text carries the meaning on its
  // own (ADR-003), and names no format version (meaningless to the user).
  // Same shape for a source from a newer build: explain "update Gabbro".
  List<Widget> _gabbroFormatNotes(AppLocalizations l) => [
    if (_gabbroFormatTooOld)
      ..._formatNote(l.vaultFormatTooOld, l.vaultFormatUpgradeLink),
    if (_gabbroFormatTooNew)
      ..._formatNote(l.vaultFormatTooNew, l.vaultFormatTooNewLink),
  ];

  List<Widget> _formatNote(String text, String link) => [
    const SizedBox(height: 4),
    Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
    ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        icon: const Icon(Icons.open_in_new, size: 16),
        label: Text(link),
        onPressed: () =>
            showUrlDialog(context, title: link, url: vaultUpgradePathUrl),
      ),
    ),
  ];
}
