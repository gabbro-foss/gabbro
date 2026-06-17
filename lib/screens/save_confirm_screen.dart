import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

/// The autofill save-confirmation screen (Android). Shown by `SaveActivity` after
/// the vault is unlocked, when the OS asked Gabbro to save a submitted login.
///
/// Matching and the suggested action are computed in Kotlin (the single source of
/// truth) and handed over as a [SaveContext]; this screen resolves the user's
/// choice — never a silent overwrite — and performs the write through the existing
/// `create_entry`/`update_entry` bridge so the password-history retention follows
/// the in-app `passwordHistoryExpiry` setting.

/// Which action the Kotlin matcher suggests for a captured login.
enum SaveActionKind { create, update, noop }

/// An existing same-site/app login offered in the "choose another" picker.
class SaveCandidate {
  final String id;
  final String label;
  const SaveCandidate({required this.id, required this.label});
}

/// The `/autofill_save` payload: the captured login + web/app context, the
/// suggested action, and the same-site candidates for the picker.
class SaveContext {
  final String username;
  final String email;
  final String password;
  final String url;
  final String appId;
  final SaveActionKind action;
  final String? matchedId;
  final List<SaveCandidate> candidates;

  const SaveContext({
    required this.username,
    required this.email,
    required this.password,
    required this.url,
    required this.appId,
    required this.action,
    required this.matchedId,
    required this.candidates,
  });

  factory SaveContext.fromJson(Map<String, dynamic> json) {
    final captured = (json['captured'] as Map).cast<String, dynamic>();
    final decision = (json['decision'] as Map).cast<String, dynamic>();
    final action = switch (decision['action'] as String?) {
      'update' => SaveActionKind.update,
      'noop' => SaveActionKind.noop,
      _ => SaveActionKind.create,
    };
    final candidates = ((json['candidates'] as List?) ?? const [])
        .map((c) => (c as Map).cast<String, dynamic>())
        .map((c) => SaveCandidate(
              id: c['id'] as String? ?? '',
              label: c['label'] as String? ?? '',
            ))
        .toList();
    return SaveContext(
      username: captured['username'] as String? ?? '',
      email: captured['email'] as String? ?? '',
      password: captured['password'] as String? ?? '',
      url: captured['url'] as String? ?? '',
      appId: captured['appId'] as String? ?? '',
      action: action,
      matchedId: decision['matchedId'] as String?,
      candidates: candidates,
    );
  }
}

/// Maps the in-app history-retention setting to the `expiry_days` the bridge wants.
/// Same mapping as `create_entry_screen.dart`; `keepForever` -> null (no expiry).
int? expiryDaysFor(PasswordHistoryExpiry expiry) => switch (expiry) {
      PasswordHistoryExpiry.sevenDays => 7,
      PasswordHistoryExpiry.thirtyDays => 30,
      PasswordHistoryExpiry.ninetyDays => 90,
      PasswordHistoryExpiry.keepForever => null,
    };

Future<void> _defaultCreate(VaultEntryData entry) => createEntry(entry: entry);
VaultEntryData _defaultGetEntry(String id) => getEntry(id: id);
Future<void> _defaultUpdate(VaultEntryData entry, int? expiryDays) =>
    updateEntry(entry: entry, expiryDays: expiryDays);

class SaveConfirmScreen extends StatefulWidget {
  final SaveContext saveContext;

  /// Test seams: default to the real bridge calls; widget tests inject fakes.
  final Future<void> Function(VaultEntryData entry) onCreate;
  final VaultEntryData Function(String id) onGetEntry;
  final Future<void> Function(VaultEntryData entry, int? expiryDays) onUpdate;

  /// Signalled to the native side: write committed (finish OK) or dismissed.
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const SaveConfirmScreen({
    super.key,
    required this.saveContext,
    required this.onDone,
    required this.onCancel,
    this.onCreate = _defaultCreate,
    this.onGetEntry = _defaultGetEntry,
    this.onUpdate = _defaultUpdate,
  });

  @override
  State<SaveConfirmScreen> createState() => _SaveConfirmScreenState();
}

class _SaveConfirmScreenState extends State<SaveConfirmScreen> {
  // Guards against a double write: once an action starts, the buttons disable so a
  // second tap (e.g. if the screen is slow to dismiss) cannot save again.
  bool _submitting = false;

  int? _expiryDays() {
    final app = GabbroApp.maybeOf(context);
    return app == null ? null : expiryDaysFor(app.settings.passwordHistoryExpiry);
  }

  Future<void> _create() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final c = widget.saveContext;
    final entry = VaultEntryData.login(
      LoginEntryData(
        id: '',
        createdAt: '',
        updatedAt: '',
        folder: '',
        title: c.url.isNotEmpty ? c.url : c.appId,
        url: c.url,
        username: c.username,
        password: c.password,
        notes: null,
        customFields: const [],
        previousPassword: null,
        appId: c.appId.isEmpty ? null : c.appId,
        email: c.email.isEmpty ? null : c.email,
      ),
    );
    try {
      await widget.onCreate(entry);
      widget.onDone();
    } catch (_) {
      // Write failed — re-enable the buttons so the user can retry or cancel
      // rather than being stranded on a frozen screen.
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _update(String id) async {
    if (_submitting) return;
    final existing = widget.onGetEntry(id);
    if (existing is! VaultEntryData_Login) {
      widget.onCancel();
      return;
    }
    setState(() => _submitting = true);
    final f = existing.field0;
    final updated = VaultEntryData.login(
      LoginEntryData(
        id: f.id,
        createdAt: f.createdAt,
        updatedAt: '',
        folder: f.folder,
        title: f.title,
        url: f.url,
        username: f.username,
        password: widget.saveContext.password,
        notes: f.notes,
        customFields: f.customFields,
        previousPassword: f.previousPassword,
        appId: f.appId,
        email: f.email,
      ),
    );
    try {
      await widget.onUpdate(updated, _expiryDays());
      widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickAnother() async {
    if (_submitting) return;
    final l = AppLocalizations.of(context);
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.saveConfirmChooseAnother),
        children: widget.saveContext.candidates
            .map(
              (cand) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(cand.id),
                child: Text(cand.label),
              ),
            )
            .toList(),
      ),
    );
    if (chosen == null || !mounted) return;
    await _update(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.saveContext;
    final site = c.url.isNotEmpty ? c.url : c.appId;
    final identifier = c.username.isNotEmpty ? c.username : c.email;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.saveConfirmTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (site.isNotEmpty)
                Text(site, style: theme.textTheme.titleMedium),
              if (identifier.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(identifier, style: theme.textTheme.bodyLarge),
                ),
              const SizedBox(height: 28),
              ..._actions(l, c),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(AppLocalizations l, SaveContext c) {
    final busy = _submitting;
    final cancel = TextButton(
      onPressed: busy ? null : widget.onCancel,
      child: Text(l.cancel),
    );
    final saveAsNew = OutlinedButton(
      onPressed: busy ? null : _create,
      child: Text(l.saveConfirmAsNew),
    );
    final chooseAnother = TextButton(
      onPressed: busy ? null : _pickAnother,
      child: Text(l.saveConfirmChooseAnother),
    );
    final hasCandidates = c.candidates.isNotEmpty;

    switch (c.action) {
      case SaveActionKind.update:
        return [
          ElevatedButton(
            onPressed: busy ? null : () => _update(c.matchedId!),
            child: Text(l.saveConfirmUpdate),
          ),
          const SizedBox(height: 8),
          saveAsNew,
          if (hasCandidates) chooseAnother,
          cancel,
        ];
      case SaveActionKind.create:
        return [
          ElevatedButton(
            onPressed: busy ? null : _create,
            child: Text(l.saveConfirmAsNew),
          ),
          if (hasCandidates) chooseAnother,
          cancel,
        ];
      case SaveActionKind.noop:
        return [
          Text(l.saveConfirmAlreadySaved),
          const SizedBox(height: 16),
          saveAsNew,
          cancel,
        ];
    }
  }
}
