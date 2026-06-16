import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

class ReviewChangesScreen extends StatefulWidget {
  final VaultEntryData original;
  final VaultEntryData updated;
  final int? expiryDays;
  final Future<void> Function(VaultEntryData, int?) onSave;

  const ReviewChangesScreen({
    super.key,
    required this.original,
    required this.updated,
    required this.expiryDays,
    required this.onSave,
  });

  @override
  State<ReviewChangesScreen> createState() => _ReviewChangesScreenState();
}

class _ReviewChangesScreenState extends State<ReviewChangesScreen> {
  bool _isSaving = false;
  String? _error;

  // Sensitive field visibility toggles
  bool _passwordObscured = true;
  bool _cvvObscured = true;
  bool _pinObscured = true;
  bool _transactionPasswordObscured = true;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.onSave(widget.updated, widget.expiryDays);
      final id = switch (widget.updated) {
        VaultEntryData_Login(:final field0) => field0.id,
        VaultEntryData_Note(:final field0) => field0.id,
        VaultEntryData_Identity(:final field0) => field0.id,
        VaultEntryData_Card(:final field0) => field0.id,
        VaultEntryData_File(:final field0) => field0.id,
        VaultEntryData_Custom(:final field0) => field0.id,
      };
      final refreshed = getEntry(id: id);
      if (mounted) Navigator.of(context).pop(refreshed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sensitiveChanges = _buildSensitiveChanges(l);
    final fieldDiffs = _buildFieldDiffs(l);

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        leadingWidth: 80,
        title: Text(l.reviewChangesTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sensitiveChanges.isNotEmpty) ...[
                _sectionHeader(l.reviewSensitiveFields),
                const SizedBox(height: 8),
                ...sensitiveChanges,
                const SizedBox(height: 16),
              ],
              if (fieldDiffs.isNotEmpty) ...[
                _sectionHeader(l.reviewOtherFields),
                const SizedBox(height: 8),
                ...fieldDiffs,
                const SizedBox(height: 16),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Diff builders ────────────────────────────────────────────────────────────

  List<Widget> _buildSensitiveChanges(AppLocalizations l) {
    final changes = <Widget>[];
    switch ((widget.original, widget.updated)) {
      case (VaultEntryData_Login(:final field0),
            VaultEntryData_Login(field0: final u)):
        if (field0.password != u.password) {
          changes.add(_sensitiveRow(
            label: l.reviewPasswordChanged,
            obscured: _passwordObscured,
            onToggle: () =>
                setState(() => _passwordObscured = !_passwordObscured),
            oldValue: field0.password,
            newValue: u.password,
          ));
        }
      case (VaultEntryData_Card(:final field0),
            VaultEntryData_Card(field0: final u)):
        if (field0.cvv != u.cvv) {
          changes.add(_sensitiveRow(
            label: l.reviewCvvChanged,
            obscured: _cvvObscured,
            onToggle: () => setState(() => _cvvObscured = !_cvvObscured),
            oldValue: field0.cvv,
            newValue: u.cvv,
          ));
        }
        if (field0.pin != u.pin) {
          changes.add(_sensitiveRow(
            label: l.reviewPinChanged,
            obscured: _pinObscured,
            onToggle: () => setState(() => _pinObscured = !_pinObscured),
            oldValue: field0.pin ?? '',
            newValue: u.pin ?? '',
          ));
        }
        if (field0.transactionPassword != u.transactionPassword) {
          changes.add(_sensitiveRow(
            label: l.reviewTransactionPasswordChanged,
            obscured: _transactionPasswordObscured,
            onToggle: () => setState(
              () => _transactionPasswordObscured = !_transactionPasswordObscured,
            ),
            oldValue: field0.transactionPassword ?? '',
            newValue: u.transactionPassword ?? '',
          ));
        }
      default:
        break;
    }
    return changes;
  }

  List<Widget> _buildFieldDiffs(AppLocalizations l) {
    final diffs = <Widget>[];
    switch ((widget.original, widget.updated)) {
      case (VaultEntryData_Login(:final field0),
            VaultEntryData_Login(field0: final u)):
        _addDiff(diffs, l.fieldTitle, field0.title, u.title);
        _addDiff(diffs, l.reviewFieldUrl, field0.url, u.url);
        _addDiff(diffs, l.fieldUsername, field0.username, u.username);
        _addDiff(diffs, l.reviewFieldNotes, field0.notes ?? '', u.notes ?? '');
        _addDiff(diffs, l.fieldAndroidAppId, field0.appId ?? '', u.appId ?? '');
        _addDiff(diffs, l.fieldFolder, field0.folder, u.folder);
        final loginLen = field0.customFields.length > u.customFields.length
            ? field0.customFields.length
            : u.customFields.length;
        for (var i = 0; i < loginLen; i++) {
          final label = i < u.customFields.length
              ? u.customFields[i].label
              : field0.customFields[i].label;
          final before = i < field0.customFields.length ? field0.customFields[i].value : '';
          final after = i < u.customFields.length ? u.customFields[i].value : '';
          _addDiff(diffs, label, before, after);
        }
      case (VaultEntryData_Note(:final field0),
            VaultEntryData_Note(field0: final u)):
        _addDiff(diffs, l.fieldTitle, field0.title, u.title);
        _addDiff(diffs, l.reviewFieldContent, field0.content, u.content);
        _addDiff(diffs, l.fieldFolder, field0.folder, u.folder);
        final noteLen = field0.customFields.length > u.customFields.length
            ? field0.customFields.length
            : u.customFields.length;
        for (var i = 0; i < noteLen; i++) {
          final label = i < u.customFields.length
              ? u.customFields[i].label
              : field0.customFields[i].label;
          final before = i < field0.customFields.length ? field0.customFields[i].value : '';
          final after = i < u.customFields.length ? u.customFields[i].value : '';
          _addDiff(diffs, label, before, after);
        }
      case (VaultEntryData_Card(:final field0),
            VaultEntryData_Card(field0: final u)):
        _addDiff(diffs, l.reviewFieldCardLabel, field0.cardName ?? '', u.cardName ?? '');
        _addDiff(diffs, l.reviewFieldStatus, field0.status, u.status);
        _addDiff(diffs, l.reviewFieldCardholder, field0.cardholderName, u.cardholderName);
        _addDiff(diffs, l.fieldCardNumber, field0.cardNumber, u.cardNumber);
        _addDiff(diffs, l.reviewFieldExpiry, field0.expiry, u.expiry);
        _addDiff(diffs, l.reviewFieldCreditLimit, field0.creditLimit ?? '', u.creditLimit ?? '');
        _addDiff(diffs, l.reviewFieldAccountNumber, field0.cardAccountNumber ?? '', u.cardAccountNumber ?? '');
        _addDiff(diffs, l.reviewFieldNetwork, field0.paymentNetwork ?? '', u.paymentNetwork ?? '');
        _addDiff(diffs, l.reviewFieldBank, field0.bankName ?? '', u.bankName ?? '');
        _addDiff(diffs, l.reviewFieldNotes, field0.notes ?? '', u.notes ?? '');
        _addDiff(diffs, l.fieldFolder, field0.folder, u.folder);
        final cardLen = field0.customFields.length > u.customFields.length
            ? field0.customFields.length
            : u.customFields.length;
        for (var i = 0; i < cardLen; i++) {
          final label = i < u.customFields.length
              ? u.customFields[i].label
              : field0.customFields[i].label;
          final before = i < field0.customFields.length ? field0.customFields[i].value : '';
          final after = i < u.customFields.length ? u.customFields[i].value : '';
          _addDiff(diffs, label, before, after);
        }
      case (VaultEntryData_Identity(:final field0),
            VaultEntryData_Identity(field0: final u)):
        _addDiff(diffs, l.fieldFirstName, field0.firstName, u.firstName);
        _addDiff(diffs, l.fieldLastName, field0.lastName, u.lastName);
        _addDiff(diffs, l.reviewFieldEmail, field0.email, u.email);
        _addDiff(diffs, l.reviewFieldPhone, field0.phone ?? '', u.phone ?? '');
        _addDiff(diffs, l.reviewFieldAddress, field0.address ?? '', u.address ?? '');
        _addDiff(diffs, l.fieldFolder, field0.folder, u.folder);
        final identityLen = field0.customFields.length > u.customFields.length
            ? field0.customFields.length
            : u.customFields.length;
        for (var i = 0; i < identityLen; i++) {
          final label = i < u.customFields.length
              ? u.customFields[i].label
              : field0.customFields[i].label;
          final before = i < field0.customFields.length ? field0.customFields[i].value : '';
          final after = i < u.customFields.length ? u.customFields[i].value : '';
          _addDiff(diffs, label, before, after);
        }
      case (VaultEntryData_Custom(:final field0),
            VaultEntryData_Custom(field0: final u)):
        _addDiff(diffs, l.fieldTitle, field0.title, u.title);
        _addDiff(diffs, l.fieldFolder, field0.folder, u.folder);
        final customLen = field0.fields.length > u.fields.length
            ? field0.fields.length
            : u.fields.length;
        for (var i = 0; i < customLen; i++) {
          final label = i < u.fields.length
              ? u.fields[i].label
              : field0.fields[i].label;
          final before = i < field0.fields.length ? field0.fields[i].value : '';
          final after = i < u.fields.length ? u.fields[i].value : '';
          _addDiff(diffs, label, before, after);
        }
      case (VaultEntryData_File(:final field0),
            VaultEntryData_File(field0: final u)):
        _addDiff(diffs, l.reviewFieldFilename, field0.filename, u.filename);
        if (field0.data.length != u.data.length) {
          _addDiff(diffs, l.reviewFieldSize, '${field0.data.length} bytes', '${u.data.length} bytes');
        }
        _addDiff(diffs, l.reviewFieldNotes, field0.notes ?? '', u.notes ?? '');
        _addDiff(diffs, l.fieldFolder, field0.folder, u.folder);
        final fileLen = field0.customFields.length > u.customFields.length
            ? field0.customFields.length
            : u.customFields.length;
        for (var i = 0; i < fileLen; i++) {
          final label = i < u.customFields.length
              ? u.customFields[i].label
              : field0.customFields[i].label;
          final before = i < field0.customFields.length ? field0.customFields[i].value : '';
          final after = i < u.customFields.length ? u.customFields[i].value : '';
          _addDiff(diffs, label, before, after);
        }
      default:
        break;
    }
    return diffs;
  }

  void _addDiff(
      List<Widget> diffs, String label, String before, String after) {
    if (before == after) return;
    diffs.add(_diffRow(label: label, before: before, after: after));
    diffs.add(const SizedBox(height: 8));
  }

  // ── Shared widgets ───────────────────────────────────────────────────────────

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );

  Widget _sensitiveRow({
    required String label,
    required bool obscured,
    required VoidCallback onToggle,
    required String oldValue,
    required String newValue,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined,
                  size: 18, color: colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 14, color: colorScheme.onErrorContainer),
                ),
              ),
              IconButton(
                icon: Icon(
                  obscured ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                tooltip: obscured
                    ? AppLocalizations.of(context).tooltipShowValues
                    : AppLocalizations.of(context).tooltipHide,
                onPressed: onToggle,
              ),
            ],
          ),
          if (!obscured) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).reviewOld,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        oldValue.isEmpty ? AppLocalizations.of(context).reviewEmpty : oldValue,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward,
                      size: 16, color: colorScheme.onErrorContainer),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).reviewNew,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        newValue.isEmpty ? AppLocalizations.of(context).reviewEmpty : newValue,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _diffRow({
    required String label,
    required String before,
    required String after,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  before.isEmpty ? AppLocalizations.of(context).reviewEmpty : before,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, size: 16),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  after.isEmpty ? AppLocalizations.of(context).reviewEmpty : after,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}