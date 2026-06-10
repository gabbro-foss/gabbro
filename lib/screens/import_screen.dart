import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/csv_mapping_screen.dart';
import 'package:gabbro/screens/import_failures_dialog.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/path_field.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';

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
        String path, List<int> passphrase) =>
    importFromGabbro(path: path, passphrase: passphrase);

/// Sync from a key-protected source: passphrase + a tapped registered YubiKey
/// (ADR-013).
Future<GabbroImportResult> _defaultImportGabbroWithKey(
        String path, List<int> passphrase, List<int> hmac, List<int> credentialId) =>
    importFromGabbroWithKey(
        path: path,
        passphrase: passphrase,
        hmacSecret: hmac,
        credentialId: credentialId);

/// Reads the source vault's YubiKey records to decide whether a key is required.
/// Non-empty ⇒ key-protected. Sync — header read only.
List<YubikeyRecordData> _defaultDetectSourceRecords(String path) =>
    listVaultYubikeyRecords(path: path);

Future<YubikeyHmacMatch> _defaultGetYubikeyHmac(
        List<YubikeyRecordData> records, String pin, String transport) =>
    getAnyYubikeyHmacSecret(records: records, pin: pin, transport: transport);

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
      String path, List<int> passphrase, List<int> hmac, List<int> credentialId)
  onImportGabbroWithKey;

  /// Detects whether the chosen `.gabbro` source is key-protected.
  final List<YubikeyRecordData> Function(String path) onDetectSourceRecords;

  /// Prompts for a YubiKey tap and returns the hmac + matched credential.
  final Future<YubikeyHmacMatch> Function(
      List<YubikeyRecordData> records, String pin, String transport)
  onGetYubikeyHmac;

  final bool isAndroid;

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
    this.initialGabbroPath,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _enpassPath;
  String? _bitwardenPath;
  String? _googlePmPath;
  String? _dashlanePath;
  String? _csvPath;
  String? _gabbroPath;

  bool _isImportingEnpass = false;
  bool _isImportingBitwarden = false;
  bool _isImportingGooglePm = false;
  bool _isImportingDashlane = false;
  bool _isSniffingCsv = false;
  bool _isImportingGabbro = false;

  String? _enpassError;
  String? _bitwardenError;
  String? _googlePmError;
  String? _dashlaneError;
  String? _csvError;
  String? _gabbroError;

  final _passphraseController = TextEditingController();
  bool _showPassphrase = false;

  // ADR-013: when the chosen Gabbro source is key-protected, the user must tap a
  // registered YubiKey (plus a PIN, and a transport choice on Android) to sync.
  List<YubikeyRecordData> _gabbroSourceRecords = [];
  final _yubikeyPinController = TextEditingController();
  bool _yubikeyPinObscured = true;
  String _gabbroTransport = 'usb';

  bool get _gabbroSourceIsKeyProtected => _gabbroSourceRecords.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialGabbroPath;
    if (initial != null && initial.isNotEmpty) {
      _gabbroPath = initial;
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
    super.dispose();
  }

  // ── Enpass ───────────────────────────────────────────────────────────────

  Future<void> _importEnpass() async {
    final path = _enpassPath;
    if (path == null || path.isEmpty) {
      setState(() => _enpassError = AppLocalizations.of(context).importSelectFile);
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _enpassError = AppLocalizations.of(context).importFileNotFound);
      return;
    }
    setState(() {
      _isImportingEnpass = true;
      _enpassError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final result = await widget.onImportEnpass(bytes);
      var editedCount = 0;
      if (result.failures.isNotEmpty && mounted) {
        editedCount = await showImportFailuresDialog(context, result.failures);
      }
      if (result.skipped.isNotEmpty && mounted) {
        await showSkippedEntriesDialog(context, result.skipped);
      }
      if (mounted) Navigator.of(context).pop(result.imported.toInt() + editedCount);
    } catch (e) {
      if (mounted) setState(() => _enpassError = e.toString());
    } finally {
      if (mounted) setState(() => _isImportingEnpass = false);
    }
  }

  // ── Bitwarden ────────────────────────────────────────────────────────────

  Future<void> _importBitwarden() async {
    final path = _bitwardenPath;
    if (path == null || path.isEmpty) {
      setState(() => _bitwardenError = AppLocalizations.of(context).importSelectFile);
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _bitwardenError = AppLocalizations.of(context).importFileNotFound);
      return;
    }
    setState(() {
      _isImportingBitwarden = true;
      _bitwardenError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final result = await widget.onImportBitwarden(bytes);
      var editedCount = 0;
      if (result.failures.isNotEmpty && mounted) {
        editedCount = await showImportFailuresDialog(context, result.failures);
      }
      if (result.skipped.isNotEmpty && mounted) {
        await showSkippedEntriesDialog(context, result.skipped);
      }
      if (mounted) Navigator.of(context).pop(result.imported.toInt() + editedCount);
    } catch (e) {
      if (mounted) setState(() => _bitwardenError = e.toString());
    } finally {
      if (mounted) setState(() => _isImportingBitwarden = false);
    }
  }

  // ── Google Password Manager ──────────────────────────────────────────────

  Future<void> _importGooglePm() async {
    final path = _googlePmPath;
    if (path == null || path.isEmpty) {
      setState(() => _googlePmError = AppLocalizations.of(context).importSelectFile);
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _googlePmError = AppLocalizations.of(context).importFileNotFound);
      return;
    }
    setState(() {
      _isImportingGooglePm = true;
      _googlePmError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final result = await widget.onImportGooglePm(bytes);
      var editedCount = 0;
      if (result.failures.isNotEmpty && mounted) {
        editedCount = await showImportFailuresDialog(context, result.failures);
      }
      if (result.skipped.isNotEmpty && mounted) {
        await showSkippedEntriesDialog(context, result.skipped);
      }
      if (mounted) Navigator.of(context).pop(result.imported.toInt() + editedCount);
    } catch (e) {
      if (mounted) setState(() => _googlePmError = e.toString());
    } finally {
      if (mounted) setState(() => _isImportingGooglePm = false);
    }
  }

  // ── Dashlane ─────────────────────────────────────────────────────────────

  Future<void> _importDashlane() async {
    final path = _dashlanePath;
    if (path == null || path.isEmpty) {
      setState(() => _dashlaneError = AppLocalizations.of(context).importSelectFile);
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _dashlaneError = AppLocalizations.of(context).importFileNotFound);
      return;
    }
    setState(() {
      _isImportingDashlane = true;
      _dashlaneError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final result = await widget.onImportDashlane(bytes);
      var editedCount = 0;
      if (result.failures.isNotEmpty && mounted) {
        editedCount = await showImportFailuresDialog(context, result.failures);
      }
      if (result.skipped.isNotEmpty && mounted) {
        await showSkippedEntriesDialog(context, result.skipped);
      }
      if (mounted) Navigator.of(context).pop(result.imported.toInt() + editedCount);
    } catch (e) {
      if (mounted) setState(() => _dashlaneError = e.toString());
    } finally {
      if (mounted) setState(() => _isImportingDashlane = false);
    }
  }

  // ── Gabbro ───────────────────────────────────────────────────────────────

  Future<void> _importGabbro() async {
    final l = AppLocalizations.of(context);
    final path = _gabbroPath;
    if (path == null || path.isEmpty) {
      setState(() => _gabbroError = l.importSelectFile);
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _gabbroError = l.importFileNotFound);
      return;
    }
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) {
      setState(() => _gabbroError = l.importEnterPassphrase);
      return;
    }
    // A key-protected source also needs a YubiKey PIN (ADR-013).
    if (_gabbroSourceIsKeyProtected && _yubikeyPinController.text.isEmpty) {
      setState(() => _gabbroError = l.yubiKeyPinRequired);
      return;
    }
    setState(() {
      _isImportingGabbro = true;
      _gabbroError = null;
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
      if (result.skipped.isNotEmpty && mounted) {
        await showSkippedEntriesDialog(context, result.skipped);
      }
      if (mounted) Navigator.of(context).pop(result.imported.toInt());
    } catch (e) {
      if (mounted) setState(() => _gabbroError = e.toString());
    } finally {
      if (mounted) setState(() => _isImportingGabbro = false);
    }
  }

  // ── CSV ──────────────────────────────────────────────────────────────────

  Future<void> _sniffAndPushCsvMapping() async {
    final l = AppLocalizations.of(context);
    final path = _csvPath;
    if (path == null || path.isEmpty) {
      setState(() => _csvError = l.importSelectFile);
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _csvError = l.importFileNotFound);
      return;
    }
    setState(() {
      _isSniffingCsv = true;
      _csvError = null;
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
      if (mounted) setState(() => _csvError = e.toString());
    } finally {
      if (mounted) setState(() => _isSniffingCsv = false);
    }
  }

  // ── Warning banner ───────────────────────────────────────────────────────

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

  // ── Build ────────────────────────────────────────────────────────────────

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
              const SizedBox(height: 20),
              _gabbroSection(l),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _csvSection(l),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _importSection(
                title: 'Google Password Manager',
                subtitle: l.importGooglePmSubtitle,
                hint: '/home/user/Google Passwords.csv',
                allowedExtensions: ['csv'],
                onPathSelected: (p) => setState(() => _googlePmPath = p),
                isLoading: _isImportingGooglePm,
                error: _googlePmError,
                onImport: _importGooglePm,
                importLabel: l.import,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _importSection(
                title: 'Dashlane',
                subtitle: l.importDashlaneSubtitle,
                hint: '/home/user/dashlane_credentials.csv',
                allowedExtensions: ['csv'],
                onPathSelected: (p) => setState(() => _dashlanePath = p),
                isLoading: _isImportingDashlane,
                error: _dashlaneError,
                onImport: _importDashlane,
                importLabel: l.import,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _importSection(
                title: 'Enpass',
                subtitle: l.importEnpassSubtitle,
                hint: '/home/user/enpass_export.json',
                allowedExtensions: ['json'],
                onPathSelected: (p) => setState(() => _enpassPath = p),
                isLoading: _isImportingEnpass,
                error: _enpassError,
                onImport: _importEnpass,
                importLabel: l.import,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _importSection(
                title: 'Bitwarden',
                subtitle: l.importBitwardenSubtitle,
                hint: '/home/user/bitwarden_export.json',
                allowedExtensions: ['json'],
                onPathSelected: (p) => setState(() => _bitwardenPath = p),
                isLoading: _isImportingBitwarden,
                error: _bitwardenError,
                onImport: _importBitwarden,
                importLabel: l.import,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gabbroSection(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.gabbroVaultSection, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          l.importGabbroSubtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        PathField(
          mode: PathFieldMode.open,
          hint: '/home/user/vault.gabbro',
          allowedExtensions: ['gabbro'],
          onPathSelected: (p) => setState(() {
            _gabbroPath = p;
            _gabbroError = null;
            try {
              _gabbroSourceRecords = widget.onDetectSourceRecords(p);
            } catch (_) {
              _gabbroSourceRecords = [];
            }
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passphraseController,
          obscureText: !_showPassphrase,
          decoration: InputDecoration(
            labelText: l.vaultPassphraseLabel,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassphrase ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _showPassphrase = !_showPassphrase),
            ),
          ),
        ),
        if (_gabbroSourceIsKeyProtected) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.usb, size: 20,
                  color: Theme.of(context).colorScheme.primary),
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
            obscureText: _yubikeyPinObscured,
            decoration: InputDecoration(
              labelText: l.yubiKeyPinLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _yubikeyPinObscured ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(
                    () => _yubikeyPinObscured = !_yubikeyPinObscured),
              ),
            ),
          ),
          if (widget.isAndroid) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(l.transportLabel,
                    style: Theme.of(context).textTheme.bodyMedium),
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
        if (_gabbroError != null) ...[
          const SizedBox(height: 4),
          Text(
            _gabbroError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        // While syncing a key-protected source we are blocked on a hardware tap.
        // Surface the "tap now" prompt (matching the change-passphrase / manage-
        // vaults screens) so the spinner is never silent — on Android the tap call
        // blocks until a key is presented; the user can also back out to cancel.
        if (_isImportingGabbro && _gabbroSourceIsKeyProtected) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.touch_app, size: 20,
                  color: Theme.of(context).colorScheme.primary),
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
          onPressed: _isImportingGabbro ? null : _importGabbro,
          child: _isImportingGabbro
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.syncFromVault),
        ),
      ],
    );
  }

  Widget _importSection({
    required String title,
    required String subtitle,
    required String hint,
    required List<String> allowedExtensions,
    required void Function(String) onPathSelected,
    required bool isLoading,
    required String? error,
    required VoidCallback onImport,
    required String importLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        PathField(
          mode: PathFieldMode.open,
          hint: hint,
          allowedExtensions: allowedExtensions,
          onPathSelected: onPathSelected,
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: isLoading ? null : onImport,
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(importLabel),
        ),
      ],
    );
  }

  Widget _csvSection(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.genericCsvSection, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          l.importCsvSubtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        PathField(
          mode: PathFieldMode.open,
          hint: '/home/user/passwords.csv',
          allowedExtensions: ['csv'],
          onPathSelected: (p) => setState(() => _csvPath = p),
        ),
        if (_csvError != null) ...[
          const SizedBox(height: 4),
          Text(
            _csvError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isSniffingCsv ? null : _sniffAndPushCsvMapping,
          child: _isSniffingCsv
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.next),
        ),
      ],
    );
  }
}
