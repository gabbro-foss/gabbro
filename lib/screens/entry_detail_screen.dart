import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/password_history_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

String _localizeCardStatus(String status, AppLocalizations l) => switch (status) {
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
Future<void> _defaultCopy(String value) =>
    Clipboard.setData(ClipboardData(text: value));
Future<void> _defaultLaunchUrl(String url) async {
  var uri = Uri.tryParse(url);
  if (uri == null) return;
  if (uri.scheme.isEmpty) uri = Uri.tryParse('https://$url');
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Pick a destination for a decrypted file export. On Android the native
/// directory picker yields a folder, to which the filename is appended; on
/// desktop the save dialog yields a full path. Returns null if cancelled.
Future<String?> _defaultExportFilePicker(String filename) async {
  if (Platform.isAndroid) {
    final dir = await FilePicker.getDirectoryPath();
    return dir == null ? null : '$dir/$filename';
  }
  return FilePicker.saveFile(fileName: filename);
}

Future<void> _defaultClearHistory(String id) =>
    sessionClearPasswordHistory(id: id);
Future<void> _defaultRevertPassword(String id) =>
    sessionRevertPassword(id: id);

class EntryDetailScreen extends StatefulWidget {
  final VaultEntryData entry;
  final Future<void> Function(String id) onDeleteEntry;
  final Future<void> Function(String value) onCopyToClipboard;
  final ClipboardClearTimeout clipboardClearTimeout;
  final Future<void> Function(String id) onClearPasswordHistory;
  final Future<void> Function(String id) onRevertPassword;

  /// Optional callback invoked after a successful delete, in place of
  /// [Navigator.pop]. Used by the tablet layout to clear the detail pane
  /// without popping the route.
  final VoidCallback? onDeleted;

  /// Optional callback invoked after a successful edit. Used by the tablet
  /// layout to refresh the list pane without popping the route.
  final VoidCallback? onEdited;

  final Future<void> Function(String url) onLaunchUrl;

  /// Test seam: pick the decrypted-file export destination. Defaults to the
  /// native dialog; may throw when the file portal is unavailable (sandbox).
  final Future<String?> Function(String filename) exportFilePicker;

  const EntryDetailScreen({
    super.key,
    required this.entry,
    this.onDeleteEntry = _defaultDelete,
    this.onCopyToClipboard = _defaultCopy,
    this.clipboardClearTimeout = ClipboardClearTimeout.sixtySeconds,
    this.onClearPasswordHistory = _defaultClearHistory,
    this.onRevertPassword = _defaultRevertPassword,
    this.onLaunchUrl = _defaultLaunchUrl,
    this.onDeleted,
    this.onEdited,
    this.exportFilePicker = _defaultExportFilePicker,
  });

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late VaultEntryData _entry;
  Timer? _clipboardClearTimer;

  bool _passwordObscured = true;
  bool _cardNumberObscured = true;
  bool _cvvObscured = true;
  final Set<String> _revealedFields = {};

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    super.dispose();
  }

  String _entryId() => switch (_entry) {
    VaultEntryData_Login(:final field0) => field0.id,
    VaultEntryData_Note(:final field0) => field0.id,
    VaultEntryData_Identity(:final field0) => field0.id,
    VaultEntryData_Card(:final field0) => field0.id,
    VaultEntryData_File(:final field0) => field0.id,
    VaultEntryData_Custom(:final field0) => field0.id,
  };

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
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
    await widget.onDeleteEntry(_entryId());
    if (!context.mounted) return;
    if (widget.onDeleted != null) {
      widget.onDeleted!();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  /// Export a file entry's bytes to a user-specified path.
  Future<void> _exportFile(FileEntryData e) async {
    final pathController = TextEditingController(
      text: '${Platform.environment['HOME'] ?? '/tmp'}/${e.filename}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dl = AppLocalizations.of(ctx);
        return AlertDialog(
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
                          () => widget.exportFilePicker(e.filename),
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
      await file.writeAsBytes(e.data);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).exportedToPath(path))));
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).exportFailed(err.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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
              tooltip: l.tooltipExportFile,
              onPressed: () => _exportFile(field0),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l.tooltipEditEntry,
            onPressed: () async {
              final entryType = switch (_entry) {
                VaultEntryData_Login() => 'Login',
                VaultEntryData_Note() => 'Note',
                VaultEntryData_Identity() => 'Identity',
                VaultEntryData_Card() => 'Card',
                VaultEntryData_File() => 'File',
                VaultEntryData_Custom() => 'Custom',
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
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l.tooltipDeleteEntry,
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
  };

  Widget _buildBody(AppLocalizations l) => switch (_entry) {
    VaultEntryData_Login(:final field0) => _loginView(field0, l),
    VaultEntryData_Note(:final field0) => _noteView(field0, l),
    VaultEntryData_Identity(:final field0) => _identityView(field0, l),
    VaultEntryData_Card(:final field0) => _cardView(field0, l),
    VaultEntryData_File(:final field0) => _fileView(field0, l),
    VaultEntryData_Custom(:final field0) => _customView(field0, l),
  };

  // ── Entry type views ─────────────────────────────────────────────────────────

  Widget _loginView(LoginEntryData e, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(l.fieldTitle, e.title, l),
        _urlField(e.url, l),
        _field(l.fieldUsername, e.username, l),
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l.passwordHistoryTitle,
            style: const TextStyle(fontSize: 14),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PasswordHistoryScreen(
                entry: e,
                onDeleteHistory: () async {
                  final id = _entryId();
                  try {
                    await widget.onClearPasswordHistory(id);
                    final fresh = getEntry(id: id);
                    if (mounted) setState(() => _entry = fresh);
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (err) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context).failedToClearHistory(err.toString())),
                          backgroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                },
                onRevert: () async {
                  final id = _entryId();
                  try {
                    await widget.onRevertPassword(id);
                    final fresh = getEntry(id: id);
                    if (mounted) setState(() => _entry = fresh);
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (err) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context).failedToRevertPassword(err.toString())),
                          backgroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ),
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
        if (e.creditLimit != null) _field(l.reviewFieldCreditLimit, e.creditLimit!, l),
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
        _timestampsRow(e.createdAt, e.updatedAt, e.folder, l),
      ],
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || url.isEmpty) return;
    final confirmed = await showDialog<bool>(
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
    await widget.onLaunchUrl(url);
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
              Expanded(
                child: Text(url, style: const TextStyle(fontSize: 16)),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_browser_outlined, size: 18),
                tooltip: l.openInBrowser,
                onPressed: () => _launchUrl(context, url),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
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
    await widget.onCopyToClipboard(value);
    _clipboardClearTimer?.cancel();

    final timeout = widget.clipboardClearTimeout;
    final duration = switch (timeout) {
      ClipboardClearTimeout.never => null,
      ClipboardClearTimeout.thirtySeconds => const Duration(seconds: 30),
      ClipboardClearTimeout.sixtySeconds => const Duration(seconds: 60),
      ClipboardClearTimeout.twoMinutes => const Duration(minutes: 2),
    };

    if (duration != null) {
      _clipboardClearTimer = Timer(duration, () {
        Clipboard.setData(const ClipboardData(text: ''));
      });
    }

    if (mounted) {
      final l = AppLocalizations.of(context);
      final label = switch (timeout) {
        ClipboardClearTimeout.never => l.copiedNeverClears,
        ClipboardClearTimeout.thirtySeconds => l.copiedClears30s,
        ClipboardClearTimeout.sixtySeconds => l.copiedClears60s,
        ClipboardClearTimeout.twoMinutes => l.copiedClears2min,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          duration: const Duration(seconds: 3),
        ),
      );
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

  Widget _field(String label, String value, AppLocalizations l, {bool obscure = false}) {
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
                icon: const Icon(Icons.copy_outlined, size: 18),
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
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: l.tooltipCopy,
                onPressed: () => _copyToClipboard(value),
              ),
              IconButton(
                icon: Icon(
                  obscured ? Icons.visibility_off : Icons.visibility,
                  size: 18,
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

  Widget _timestampsRow(String createdAt, String updatedAt, String folder, AppLocalizations l) {
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
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      formatTimestamp(createdAt, unknownLabel: l.timestampUnknown, locale: l.localeName),
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
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      formatTimestamp(updatedAt, unknownLabel: l.timestampUnknown, locale: l.localeName),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
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
