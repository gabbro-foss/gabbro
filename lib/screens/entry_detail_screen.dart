import 'dart:async';
import 'dart:io';

import 'package:gabbro/gabbro_file_picker.dart';
import 'package:intl/intl.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gabbro/widgets/gabbro_dialog.dart';
import 'package:flutter/semantics.dart';
import 'package:gabbro/autotype_target.dart';
import 'package:gabbro/clipboard_clear.dart';
import 'package:gabbro/control_scale.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/widgets/url_link.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/recovery_history_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

String _localizeCardStatus(String status, AppLocalizations l) =>
    switch (status) {
      'active' => l.cardStatusActive,
      'lapsed' => l.cardStatusLapsed,
      'inactive' => l.cardStatusInactive,
      _ => status,
    };

/// Formats an ISO 8601 UTC timestamp string into a locale-aware human-readable form.
/// Returns [unknownLabel] for empty or unparseable input.
String formatTimestamp(
  String iso, {
  String unknownLabel = 'Unknown',
  String locale = 'en',
}) {
  if (iso.isEmpty) return unknownLabel;
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('d MMM yyyy, HH:mm', locale).format(dt);
  } catch (_) {
    return unknownLabel;
  }
}

Future<void> _defaultDelete(String id) => deleteEntry(id: id);
Future<Uint8List> _defaultExtractAttachment(String entryId, String uuid) =>
    extractAttachment(entryId: entryId, uuid: uuid);
VaultEntryData _defaultGetEntry(String id) => getEntry(id: id);
Future<UrlOpenResult> _defaultLaunchUrl(String url) =>
    GabbroUrlOpener.open(url);

/// Pick a destination for a decrypted file export. On Android the native
/// directory picker yields a folder, to which the filename is appended; on
/// desktop the save dialog yields a full path. Returns null if cancelled.
Future<String?> _defaultExportFilePicker(String filename,
    {required bool isAndroid}) async {
  if (isAndroid) {
    final dir = await GabbroFilePicker.androidPickDirectory();
    return dir == null ? null : '$dir/$filename';
  }
  return GabbroFilePicker.savePath(fileName: filename);
}

Future<List<HistoryRecordData>> _defaultFetchHistory(String id) =>
    getEntryHistory(id: id);
Future<void> _defaultRestoreHistory(String id, int index) =>
    restoreHistory(id: id, index: index);
Future<void> _defaultDeleteHistory(String id, int index) =>
    deleteHistory(id: id, index: index);

class EntryDetailScreen extends StatefulWidget {
  final VaultEntryData entry;
  final Future<void> Function(String id) onDeleteEntry;
  final ClipboardClearTimeout clipboardClearTimeout;

  /// Recovery history (values replaced during sync). Injectable for tests; the
  /// fetch is best-effort and failures simply hide the section.
  final Future<List<HistoryRecordData>> Function(String id) onFetchHistory;
  final Future<void> Function(String id, int index) onRestoreHistory;
  final Future<void> Function(String id, int index) onDeleteHistory;

  /// Optional callback invoked after a successful delete, in place of
  /// [Navigator.pop]. Used by the tablet layout to clear the detail pane
  /// without popping the route.
  final VoidCallback? onDeleted;

  /// Optional callback invoked after a successful edit. Used by the tablet
  /// layout to refresh the list pane without popping the route.
  final VoidCallback? onEdited;

  final Future<UrlOpenResult> Function(String url) onLaunchUrl;

  /// Test seam: pick the decrypted-file export destination. Null uses the
  /// native dialog, which may throw when the file portal is unavailable
  /// (sandbox).
  final Future<String?> Function(String filename)? exportFilePicker;

  /// Test seam: fetch an attachment's bytes for saving to disk. Bytes cross
  /// the bridge only on demand — the entry DTO carries metadata alone.
  final Future<Uint8List> Function(String entryId, String uuid)
  onExtractAttachment;

  /// Test seam: re-read the entry after the edit screen returns without a
  /// review-save. Edit-mode attachment adds/removes persist immediately, so
  /// the stale in-memory entry must be refreshed or they stay invisible.
  final VaultEntryData Function(String id)? onGetEntry;

  /// Extra bottom padding below the scrollable body, on top of the normal
  /// content padding. The tablet two-pane layout passes this so the detail
  /// pane's last item clears the Scaffold-level FAB that floats over its
  /// bottom-right corner; the phone full-screen route (no FAB) leaves it 0.
  final double bottomReserve;

  /// Whether this is running on Android. Drives the copy announcement (only
  /// Linux gets one: TalkBack reads the snackbar itself, and an announcement
  /// would make it drop its speech queue) and the file-export picker, which
  /// asks Android for a folder and desktop for a full path. Tests simulating
  /// Android can pass `isAndroid: true`.
  final bool isAndroid;

  EntryDetailScreen({
    super.key,
    required this.entry,
    bool? isAndroid,
    this.onDeleteEntry = _defaultDelete,
    this.clipboardClearTimeout = ClipboardClearTimeout.sixtySeconds,
    this.onFetchHistory = _defaultFetchHistory,
    this.onRestoreHistory = _defaultRestoreHistory,
    this.onDeleteHistory = _defaultDeleteHistory,
    this.onLaunchUrl = _defaultLaunchUrl,
    this.onDeleted,
    this.onEdited,
    this.exportFilePicker,
    this.onExtractAttachment = _defaultExtractAttachment,
    this.onGetEntry,
    this.bottomReserve = 0,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late VaultEntryData _entry;

  bool _passwordObscured = true;
  bool _cardNumberObscured = true;
  bool _cvvObscured = true;
  final Set<String> _revealedFields = {};

  List<HistoryRecordData> _history = const [];

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    // Designate this Login as the Linux auto-type target while it is open
    // (ADR-017). Harmless on other platforms — only the Linux listener reads it.
    if (_entry is VaultEntryData_Login) autotypeTarget.setLogin(_entryId());
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final h = await widget.onFetchHistory(_entryId());
      if (mounted) setState(() => _history = h);
    } catch (_) {
      // Best-effort: a fetch failure simply hides the recovery-history section.
    }
  }

  @override
  void dispose() {
    // Stop targeting this Login once its screen closes, unless a newer screen
    // has already claimed the target (clearIf guards that). A pending clipboard
    // wipe deliberately survives this screen (RT-4) — clipboardWiper owns it.
    if (_entry is VaultEntryData_Login) autotypeTarget.clearIf(_entryId());
    super.dispose();
  }

  String _entryId() => switch (_entry) {
    VaultEntryData_Login(:final field0) => field0.id,
    VaultEntryData_Note(:final field0) => field0.id,
    VaultEntryData_Identity(:final field0) => field0.id,
    VaultEntryData_Card(:final field0) => field0.id,
    VaultEntryData_File(:final field0) => field0.id,
    VaultEntryData_Custom(:final field0) => field0.id,
    VaultEntryData_Passkey(:final field0) => field0.id,
  };

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showGabbroDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.deleteEntryTitle),
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
    // Captured before the await: the two-pane layout drops this screen as soon
    // as the entry leaves the filtered list, and the parent must still be told
    // to reload — otherwise the deleted row sits in the list until something
    // else forces a refresh (round 19). Only the Navigator use below needs a
    // live context, so only it is guarded.
    final onDeleted = widget.onDeleted;
    await widget.onDeleteEntry(_entryId());
    if (onDeleted != null) {
      onDeleted();
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }

  /// The injected picker if the caller supplied one, else the native dialog
  /// for this platform.
  Future<String?> _pickExportPath(String filename) =>
      widget.exportFilePicker?.call(filename) ??
      _defaultExportFilePicker(filename, isAndroid: widget.isAndroid);

  /// Export a file entry's bytes to a user-specified path.
  Future<void> _exportFile(FileEntryData e) =>
      _exportBytes(e.filename, () async => e.data);

  /// Save an attachment to disk: bytes are fetched from the vault only after
  /// the user confirms a destination.
  Future<void> _exportAttachment(AttachmentMetaData a) =>
      _exportBytes(a.name, () => widget.onExtractAttachment(_entryId(), a.uuid));

  /// Shared save-to-disk flow (File entry payloads and attachments): path
  /// dialog with browse button, then the write, errors in a scrollable dialog.
  Future<void> _exportBytes(
    String filename,
    Future<List<int>> Function() loadBytes,
  ) async {
    final pathController = TextEditingController(
      text: '${Platform.environment['HOME'] ?? '/tmp'}/$filename',
    );
    final confirmed = await showGabbroDialog<bool>(
      context: context,
      builder: (ctx) {
        final dl = AppLocalizations.of(ctx);
        return AlertDialog(
          scrollable: true, // scrolls title+content only; showGabbroDialog scrolls the rest
          title: Text(dl.exportFileTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dl.saveDecryptedFileTo),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: dl.exportPathLabel,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: dl.tooltipBrowse,
                    onPressed: () async {
                      final String? picked;
                      try {
                        picked = await runPicker(
                          () => _pickExportPath(filename),
                        );
                      } on FilePickerUnavailable {
                        if (ctx.mounted) showPickerUnavailable(ctx);
                        return;
                      }
                      if (picked != null) {
                        pathController.text = picked;
                      }
                    },
                  ),
                ),
                onSubmitted: (_) => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(dl.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(dl.exportLabel),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final path = pathController.text.trim();
    if (path.isEmpty) return;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(await loadBytes());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).exportedToPath(path)),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        // A dialog, not a SnackBar: the error carries the full path, which
        // can outgrow the strip, and a SnackBar clips without scrolling
        // (ADR-016).
        await showFailureMessage(
          context,
          AppLocalizations.of(context).exportFailed(err.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(l)),
        actions: [
          // File export button — only shown for File entries
          if (_entry case VaultEntryData_File(:final field0))
            IconButton(
              icon: const Icon(Icons.download_outlined),
              iconSize: scaledIconSize(context),
              tooltip: l.tooltipExportFile,
              onPressed: () => _exportFile(field0),
            ),
          IconButton(
            icon: Icon(Icons.edit_outlined, semanticLabel: l.tooltipEditEntry),
            iconSize: scaledIconSize(context),
            tooltip: l.tooltipEditEntry,
            onPressed: () async {
              final entryType = switch (_entry) {
                VaultEntryData_Login() => 'Login',
                VaultEntryData_Note() => 'Note',
                VaultEntryData_Identity() => 'Identity',
                VaultEntryData_Card() => 'Card',
                VaultEntryData_File() => 'File',
                VaultEntryData_Custom() => 'Custom',
                VaultEntryData_Passkey() => 'Passkey',
              };
              final updated = await Navigator.of(context).push<VaultEntryData>(
                MaterialPageRoute(
                  builder: (context) =>
                      CreateEntryScreen(entryType: entryType, existing: _entry),
                ),
              );
              if (updated != null && mounted) {
                setState(() => _entry = updated);
                widget.onEdited?.call();
              } else if (mounted) {
                // No review-save, but edit-mode attachment adds/removes have
                // already persisted — re-read or they stay invisible here.
                try {
                  final fresh = (widget.onGetEntry ?? _defaultGetEntry)(
                    _entryId(),
                  );
                  setState(() => _entry = fresh);
                } catch (_) {
                  // Keep the current view if the re-read fails (e.g. locked).
                }
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, semanticLabel: l.tooltipDeleteEntry),
            iconSize: scaledIconSize(context),
            tooltip: l.tooltipDeleteEntry,
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + widget.bottomReserve),
          child: _buildBody(l),
        ),
      ),
    );
  }

  String _title(AppLocalizations l) => switch (_entry) {
    VaultEntryData_Login(:final field0) =>
      field0.title.isNotEmpty
          ? field0.title
          : field0.url.isNotEmpty
          ? field0.url
          : l.noTitleFallback,
    VaultEntryData_Note(:final field0) => field0.title,
    VaultEntryData_Identity(:final field0) =>
      '${field0.firstName} ${field0.lastName}',
    VaultEntryData_Card(:final field0) =>
      field0.cardName ?? field0.cardholderName,
    VaultEntryData_File(:final field0) => field0.filename,
    VaultEntryData_Custom(:final field0) => field0.title,
    VaultEntryData_Passkey(:final field0) =>
      field0.rpId.isNotEmpty ? field0.rpId : l.noTitleFallback,
  };

  Widget _buildBody(AppLocalizations l) => switch (_entry) {
    VaultEntryData_Login(:final field0) => _loginView(field0, l),
    VaultEntryData_Note(:final field0) => _noteView(field0, l),
    VaultEntryData_Identity(:final field0) => _identityView(field0, l),
    VaultEntryData_Card(:final field0) => _cardView(field0, l),
    VaultEntryData_File(:final field0) => _fileView(field0, l),
    VaultEntryData_Custom(:final field0) => _customView(field0, l),
    VaultEntryData_Passkey(:final field0) => _passkeyView(field0, l),
  };

  // ── Entry type views ─────────────────────────────────────────────────────────

  /// Attachment rows for the five attachment-bearing types (a File entry is
  /// its own payload and uses the export button in the app bar instead).
  List<Widget> _attachmentBlock(
    List<AttachmentMetaData> atts,
    AppLocalizations l,
  ) {
    if (atts.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      _sectionHeader(l.fieldAttachments),
      ...atts.map(
        (a) => Row(
          children: [
            const Icon(Icons.attach_file),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${a.name} (${(a.size.toInt() / 1024).toStringAsFixed(1)} KB)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              iconSize: scaledIconSize(context),
              tooltip: l.tooltipExportFile,
              onPressed: () => _exportAttachment(a),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _loginView(LoginEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(l.fieldTitle, e.title, l),
        _urlField(e.url, l),
        _field(l.fieldUsername, e.username, l),
        if (e.email != null && e.email!.isNotEmpty)
          _field(l.fieldEmail, e.email!, l),
        _toggleField(
          label: l.fieldPassword,
          value: e.password,
          obscured: _passwordObscured,
          onToggle: () =>
              setState(() => _passwordObscured = !_passwordObscured),
          onLongPress: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => PasswordBreakdownSheet(password: e.password),
          ),
          l: l,
        ),
        if (e.notes != null) _field(l.reviewFieldNotes, e.notes!, l),
        if (e.appId != null && e.appId!.isNotEmpty)
          _field(l.fieldAndroidAppId, e.appId!, l),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(l.fieldCustomFields),
          ...e.customFields.map(
            (f) => f.hidden
                ? _toggleField(
                    label: f.label,
                    value: f.value,
                    obscured: !_revealedFields.contains(f.label),
                    onToggle: () => setState(() {
                      if (_revealedFields.contains(f.label)) {
                        _revealedFields.remove(f.label);
                      } else {
                        _revealedFields.add(f.label);
                      }
                    }),
                    l: l,
                  )
                : _field(f.label, f.value, l),
          ),
        ],
        ..._attachmentBlock(e.attachments, l),
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  Widget _noteView(NoteEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(l.fieldTitle, e.title, l),
        _field(l.reviewFieldContent, e.content, l),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(l.fieldCustomFields),
          ...e.customFields.map(
            (f) => f.hidden
                ? _toggleField(
                    label: f.label,
                    value: f.value,
                    obscured: !_revealedFields.contains(f.label),
                    onToggle: () => setState(() {
                      if (_revealedFields.contains(f.label)) {
                        _revealedFields.remove(f.label);
                      } else {
                        _revealedFields.add(f.label);
                      }
                    }),
                    l: l,
                  )
                : _field(f.label, f.value, l),
          ),
        ],
        ..._attachmentBlock(e.attachments, l),
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  Widget _identityView(IdentityEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(l.fieldFirstName, e.firstName, l),
        _field(l.fieldLastName, e.lastName, l),
        if (e.email.isNotEmpty) _field(l.reviewFieldEmail, e.email, l),
        if (e.phone != null) _field(l.reviewFieldPhone, e.phone!, l),
        if (e.address != null) _field(l.reviewFieldAddress, e.address!, l),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(l.fieldCustomFields),
          ...e.customFields.map(
            (f) => f.hidden
                ? _toggleField(
                    label: f.label,
                    value: f.value,
                    obscured: !_revealedFields.contains(f.label),
                    onToggle: () => setState(() {
                      if (_revealedFields.contains(f.label)) {
                        _revealedFields.remove(f.label);
                      } else {
                        _revealedFields.add(f.label);
                      }
                    }),
                    l: l,
                  )
                : _field(f.label, f.value, l),
          ),
        ],
        ..._attachmentBlock(e.attachments, l),
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  Widget _cardView(CardEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (e.cardName != null) _field(l.reviewFieldCardLabel, e.cardName!, l),
        _field(l.reviewFieldStatus, _localizeCardStatus(e.status, l), l),
        if (e.paymentNetwork != null)
          _field(l.reviewFieldNetwork, e.paymentNetwork!, l),
        _field(l.reviewFieldCardholder, e.cardholderName, l),
        _toggleField(
          label: l.reviewFieldCardNumber,
          value: e.cardNumber,
          obscured: _cardNumberObscured,
          onToggle: () =>
              setState(() => _cardNumberObscured = !_cardNumberObscured),
          l: l,
        ),
        _field(l.reviewFieldExpiry, e.expiry, l),
        _toggleField(
          label: l.reviewFieldCVV,
          value: e.cvv,
          obscured: _cvvObscured,
          onToggle: () => setState(() => _cvvObscured = !_cvvObscured),
          l: l,
        ),
        if (e.pin != null)
          _toggleField(
            label: l.pinLabel,
            value: e.pin!,
            obscured: !_revealedFields.contains('pin'),
            onToggle: () => setState(() {
              if (_revealedFields.contains('pin')) {
                _revealedFields.remove('pin');
              } else {
                _revealedFields.add('pin');
              }
            }),
            l: l,
          ),
        if (e.creditLimit != null)
          _field(l.reviewFieldCreditLimit, e.creditLimit!, l),
        if (e.cardAccountNumber != null)
          _field(l.reviewFieldAccountNumber, e.cardAccountNumber!, l),
        if (e.bankName != null) _field(l.reviewFieldBank, e.bankName!, l),
        if (e.transactionPassword != null)
          _toggleField(
            label: l.reviewFieldTransactionPassword,
            value: e.transactionPassword!,
            obscured: !_revealedFields.contains('transaction_password'),
            onToggle: () => setState(() {
              if (_revealedFields.contains('transaction_password')) {
                _revealedFields.remove('transaction_password');
              } else {
                _revealedFields.add('transaction_password');
              }
            }),
            l: l,
          ),
        if (e.notes != null) _field(l.reviewFieldNotes, e.notes!, l),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(l.fieldCustomFields),
          ...e.customFields.map(
            (f) => f.hidden
                ? _toggleField(
                    label: f.label,
                    value: f.value,
                    obscured: !_revealedFields.contains(f.label),
                    onToggle: () => setState(() {
                      if (_revealedFields.contains(f.label)) {
                        _revealedFields.remove(f.label);
                      } else {
                        _revealedFields.add(f.label);
                      }
                    }),
                    l: l,
                  )
                : _field(f.label, f.value, l),
          ),
        ],
        ..._attachmentBlock(e.attachments, l),
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  Widget _fileView(FileEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(l.reviewFieldFilename, e.filename, l),
        _field(l.reviewFieldSize, _formatBytes(e.data.length), l),
        if (e.notes != null) _field(l.reviewFieldNotes, e.notes!, l),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(l.fieldCustomFields),
          ...e.customFields.map(
            (f) => f.hidden
                ? _toggleField(
                    label: f.label,
                    value: f.value,
                    obscured: !_revealedFields.contains(f.label),
                    onToggle: () => setState(() {
                      if (_revealedFields.contains(f.label)) {
                        _revealedFields.remove(f.label);
                      } else {
                        _revealedFields.add(f.label);
                      }
                    }),
                    l: l,
                  )
                : _field(f.label, f.value, l),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _exportFile(e),
          icon: const Icon(Icons.download_outlined),
          label: Text(l.exportFileTitle),
        ),
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  Widget _passkeyView(PasskeyEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _urlField(e.rpId, l),
        _field(l.fieldUsername, e.userName, l),
        if (e.notes != null && e.notes!.isNotEmpty)
          _field(l.reviewFieldNotes, e.notes!, l),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(l.fieldCustomFields),
          ...e.customFields.map(
            (f) => f.hidden
                ? _toggleField(
                    label: f.label,
                    value: f.value,
                    obscured: !_revealedFields.contains(f.label),
                    onToggle: () => setState(() {
                      if (_revealedFields.contains(f.label)) {
                        _revealedFields.remove(f.label);
                      } else {
                        _revealedFields.add(f.label);
                      }
                    }),
                    l: l,
                  )
                : _field(f.label, f.value, l),
          ),
        ],
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  Widget _customView(CustomEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(l.fieldTitle, e.title, l),
        if (e.fields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(l.customEntryFieldsHeader),
          ...e.fields.map(
            (f) => f.hidden
                ? _toggleField(
                    label: f.label,
                    value: f.value,
                    obscured: !_revealedFields.contains(f.label),
                    onToggle: () => setState(() {
                      if (_revealedFields.contains(f.label)) {
                        _revealedFields.remove(f.label);
                      } else {
                        _revealedFields.add(f.label);
                      }
                    }),
                    l: l,
                  )
                : _field(f.label, f.value, l),
          ),
        ],
        ..._attachmentBlock(e.attachments, l),
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || url.isEmpty) return;
    final confirmed = await showGabbroDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.openInBrowserTitle),
          content: Text(url),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.openInBrowser),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final result = await widget.onLaunchUrl(url);
    if (context.mounted) reportUrlOutcome(context, result, url);
  }

  Widget _urlField(String url, AppLocalizations l) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.reviewFieldUrl,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(url, style: const TextStyle(fontSize: 16))),
              IconButton(
                icon: Icon(Icons.open_in_browser_outlined, size: 18, semanticLabel: l.openInBrowser),
                tooltip: l.openInBrowser,
                onPressed: () => _launchUrl(context, url),
              ),
              IconButton(
                icon: Icon(Icons.copy_outlined, size: 18, semanticLabel: l.tooltipCopy),
                tooltip: l.tooltipCopy,
                onPressed: () => _copyToClipboard(url),
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String value) async {
    await clipboardWiper.copyThenClear(value, widget.clipboardClearTimeout);

    if (mounted) {
      final l = AppLocalizations.of(context);
      final label = switch (widget.clipboardClearTimeout) {
        ClipboardClearTimeout.never => l.copiedNeverClears,
        ClipboardClearTimeout.thirtySeconds => l.copiedClears30s,
        ClipboardClearTimeout.sixtySeconds => l.copiedClears60s,
        ClipboardClearTimeout.twoMinutes => l.copiedClears2min,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label), duration: const Duration(seconds: 3)),
      );
      // A Linux screen reader never sees the snackbar: it reads a node's name
      // and is not told one appeared, so copying was completely silent
      // (round 26). The copy moves no focus, so this has nothing competing
      // with it. Same text, so no new translations.
      if (!widget.isAndroid) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          label,
          Directionality.of(context),
        );
      }
    }
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _field(
    String label,
    String value,
    AppLocalizations l, {
    bool obscure = false,
  }) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  obscure ? '••••••••' : value,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_outlined, size: 18, semanticLabel: l.tooltipCopy),
                tooltip: l.tooltipCopy,
                onPressed: () => _copyToClipboard(value),
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _toggleField({
    required String label,
    required String value,
    required bool obscured,
    required VoidCallback onToggle,
    required AppLocalizations l,
    VoidCallback? onLongPress,
  }) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: obscured ? null : onLongPress,
                  child: Text(
                    obscured ? '••••••••' : value,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              // Breakdown — only for fields wired with a breakdown (the
              // password) and only while revealed. onLongPress carries the
              // same action, so a tap here mirrors the long-press.
              if (onLongPress != null && !obscured)
                IconButton(
                  key: const Key('breakdown_button'),
                  icon: Icon(
                    Icons.analytics_outlined,
                    size: 18,
                    semanticLabel: l.passwordBreakdownTitle,
                  ),
                  tooltip: l.passwordBreakdownTitle,
                  onPressed: onLongPress,
                ),
              IconButton(
                icon: Icon(Icons.copy_outlined, size: 18, semanticLabel: l.tooltipCopy),
                tooltip: l.tooltipCopy,
                onPressed: () => _copyToClipboard(value),
              ),
              IconButton(
                iconSize: scaledIconSize(context, 18),
                icon: Icon(
                  obscured ? Icons.visibility_off : Icons.visibility,
                  semanticLabel: obscured ? l.tooltipShow : l.tooltipHide,
                ),
                tooltip: obscured ? l.tooltipShow : l.tooltipHide,
                onPressed: onToggle,
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _timestampsRow(
    String createdAt,
    String updatedAt,
    String folder,
    AppLocalizations l,
  ) {
    final folderLabel = folder.isEmpty ? l.noFolder : folder;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.fieldFolder,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(folderLabel, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.timestampCreated,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      formatTimestamp(
                        createdAt,
                        unknownLabel: l.timestampUnknown,
                        locale: l.localeName,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.timestampUpdated,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      formatTimestamp(
                        updatedAt,
                        unknownLabel: l.timestampUnknown,
                        locale: l.localeName,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(
                  l.historyPrevious,
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  size: scaledIconSize(context, 18),
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecoveryHistoryScreen(
                        records: _history,
                        onRestore: (i) async {
                          await widget.onRestoreHistory(_entryId(), i);
                          final fresh = getEntry(id: _entryId());
                          if (mounted) setState(() => _entry = fresh);
                        },
                        onDelete: (i) => widget.onDeleteHistory(_entryId(), i),
                      ),
                    ),
                  );
                  await _loadHistory();
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
