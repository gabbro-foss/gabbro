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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildBody(),
      ),
    );
  }

  String _title() => switch (_entry) {
        VaultEntryData_Login(:final field0) =>
          field0.url.isNotEmpty ? field0.url : '(no URL)',
        VaultEntryData_Note(:final field0) => field0.title,
        VaultEntryData_Identity(:final field0) =>
          '${field0.firstName} ${field0.lastName}',
        VaultEntryData_Card(:final field0) => field0.cardholderName,
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

  Widget _loginView(LoginEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('URL', e.url),
        _field('Username', e.username),
        _field('Password', e.password, obscure: true),
        if (e.notes != null) _field('Notes', e.notes!),
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
      ],
    );
  }

  Widget _cardView(CardEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Cardholder', e.cardholderName),
        _field('Number', e.cardNumber, obscure: true),
        _field('Expiry', e.expiry),
        _field('CVV', e.cvv, obscure: true),
        if (e.notes != null) _field('Notes', e.notes!),
      ],
    );
  }

  Widget _fileView(FileEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Filename', e.filename),
        _field('Size', '${e.data.length} bytes'),
        if (e.notes != null) _field('Notes', e.notes!),
      ],
    );
  }

  Widget _customView(CustomEntryData e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Title', e.title),
        ...e.fields.map((f) => _field(f.label, f.value)),
      ],
    );
  }

  Widget _field(String label, String value, {bool obscure = false}) {
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
}