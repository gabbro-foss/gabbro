import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/src/rust/api/vault.dart';

class EntryDetailScreen extends StatefulWidget {
  final VaultEntryData entry;

  const EntryDetailScreen({super.key, required this.entry});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late VaultEntryData _entry;

  bool _passwordObscured = true;
  bool _cardNumberObscured = true;
  bool _cvvObscured = true;
  final Set<String> _revealedFields = {};

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
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
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteEntry(id: _entryId());
    if (context.mounted) Navigator.of(context).pop(true);
  }

  /// Export a file entry's bytes to a user-specified path.
  Future<void> _exportFile(FileEntryData e) async {
    final pathController = TextEditingController(
      text: '${Platform.environment['HOME'] ?? '/tmp'}/${e.filename}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export file'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Save decrypted file to:'),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Export path',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final path = pathController.text.trim();
    if (path.isEmpty) return;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(e.data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to $path')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $err'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          // File export button — only shown for File entries
          if (_entry case VaultEntryData_File(:final field0))
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export file',
              onPressed: () => _exportFile(field0),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit entry',
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
                  builder: (context) => CreateEntryScreen(
                    entryType: entryType,
                    existing: _entry,
                  ),
                ),
              );
              if (updated != null && mounted) {
                setState(() => _entry = updated);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete entry',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildBody(),
        ),
      ),
    );
  }

  String _title() => switch (_entry) {
        VaultEntryData_Login(:final field0) =>
          field0.title.isNotEmpty ? field0.title : field0.url.isNotEmpty ? field0.url : '(no title)',
        VaultEntryData_Note(:final field0) => field0.title,
        VaultEntryData_Identity(:final field0) =>
          '${field0.firstName} ${field0.lastName}',
        VaultEntryData_Card(:final field0) =>
          field0.cardName ?? field0.cardholderName,
        VaultEntryData_File(:final field0) => field0.filename,
        VaultEntryData_Custom(:final field0) => field0.title,
      };

  Widget _buildBody() => switch (_entry) {
        VaultEntryData_Login(:final field0) => _loginView(field0),
        VaultEntryData_Note(:final field0) => _noteView(field0),
        VaultEntryData_Identity(:final field0) => _identityView(field0),
        VaultEntryData_Card(:final field0) => _cardView(field0),
        VaultEntryData_File(:final field0) => _fileView(field0),
        VaultEntryData_Custom(:final field0) => _customView(field0),
      };

  // ── Entry type views ─────────────────────────────────────────────────────────

  Widget _loginView(LoginEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Title', e.title),
        _field('URL', e.url),
        _field('Username', e.username),
        _toggleField(
          label: 'Password',
          value: e.password,
          obscured: _passwordObscured,
          onToggle: () => setState(() => _passwordObscured = !_passwordObscured),
        ),
        if (e.notes != null) _field('Notes', e.notes!),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader('Custom fields'),
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
                  )
                : _field(f.label, f.value),
          ),
        ],
      ],
    );
  }

  Widget _noteView(NoteEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Title', e.title),
        _field('Content', e.content),
      ],
    );
  }

  Widget _identityView(IdentityEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('First name', e.firstName),
        _field('Last name', e.lastName),
        if (e.email.isNotEmpty) _field('Email', e.email),
        if (e.phone != null) _field('Phone', e.phone!),
        if (e.address != null) _field('Address', e.address!),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader('Custom fields'),
          ...e.customFields.map(
            (f) => _field(f.label, f.value, obscure: f.hidden),
          ),
        ],
      ],
    );
  }

  Widget _cardView(CardEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (e.cardName != null) _field('Card label', e.cardName!),
        _field('Status', e.status),
        if (e.paymentNetwork != null)
          _field('Payment network', e.paymentNetwork!),
        _field('Cardholder', e.cardholderName),
        _toggleField(
          label: 'Number',
          value: e.cardNumber,
          obscured: _cardNumberObscured,
          onToggle: () =>
              setState(() => _cardNumberObscured = !_cardNumberObscured),
        ),
        _field('Expiry', e.expiry),
        _toggleField(
          label: 'CVV',
          value: e.cvv,
          obscured: _cvvObscured,
          onToggle: () => setState(() => _cvvObscured = !_cvvObscured),
        ),
        if (e.pin != null)
          _toggleField(
            label: 'PIN',
            value: e.pin!,
            obscured: !_revealedFields.contains('pin'),
            onToggle: () => setState(() {
              if (_revealedFields.contains('pin')) {
                _revealedFields.remove('pin');
              } else {
                _revealedFields.add('pin');
              }
            }),
          ),
        if (e.creditLimit != null) _field('Credit limit', e.creditLimit!),
        if (e.cardAccountNumber != null)
          _field('Account number', e.cardAccountNumber!),
        if (e.bankName != null) _field('Bank', e.bankName!),
        if (e.transactionPassword != null)
          _toggleField(
            label: 'Transaction password',
            value: e.transactionPassword!,
            obscured: !_revealedFields.contains('transaction_password'),
            onToggle: () => setState(() {
              if (_revealedFields.contains('transaction_password')) {
                _revealedFields.remove('transaction_password');
              } else {
                _revealedFields.add('transaction_password');
              }
            }),
          ),
        if (e.notes != null) _field('Notes', e.notes!),
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader('Custom fields'),
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
                  )
                : _field(f.label, f.value),
          ),
        ],
      ],
    );
  }

  Widget _fileView(FileEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Filename', e.filename),
        _field('Size', _formatBytes(e.data.length)),
        if (e.notes != null) _field('Notes', e.notes!),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _exportFile(e),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export file'),
        ),
      ],
    );
  }

  Widget _customView(CustomEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Title', e.title),
        if (e.fields.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader('Fields'),
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
                  )
                : _field(f.label, f.value),
          ),
        ],
      ],
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _field(String label, String value, {bool obscure = false}) {
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
          Text(
            obscure ? '••••••••' : value,
            style: const TextStyle(fontSize: 16),
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
                  obscured ? '••••••••' : value,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              IconButton(
                icon: Icon(
                  obscured ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                tooltip: obscured ? 'Show' : 'Hide',
                onPressed: onToggle,
              ),
            ],
          ),
          const Divider(),
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
