import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

class CreateEntryScreen extends StatefulWidget {
  final String entryType;

  const CreateEntryScreen({super.key, required this.entryType});

  @override
  State<CreateEntryScreen> createState() => _CreateEntryScreenState();
}

class _CreateEntryScreenState extends State<CreateEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _error;

  // Login fields
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordObscured = true;

  // Note fields
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      switch (widget.entryType) {
        case 'Login':
          await createEntry(
            entry: VaultEntryData.login(LoginEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
              tags: [],
              favourite: false,
              url: _urlController.text,
              username: _usernameController.text,
              password: _passwordController.text,
              customFields: [],
            )),
          );
        case 'Note':
          await createEntry(
            entry: VaultEntryData.note(NoteEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
              tags: [],
              favourite: false,
              title: _titleController.text,
              content: _contentController.text,
            )),
          );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.entryType == 'Login' ? 'New Password' : 'New Note';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._buildFields(),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error),
                  ),
                ),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFields() {
    switch (widget.entryType) {
      case 'Login':
        return [
          _textField(_urlController, 'URL'),
          const SizedBox(height: 12),
          _textField(_usernameController, 'Username'),
          const SizedBox(height: 12),
          _passwordField(),
        ];
      case 'Note':
        return [
          _textField(_titleController, 'Title'),
          const SizedBox(height: 12),
          _textField(_contentController, 'Content', maxLines: 6),
        ];
      default:
        return [const Text('Entry type not yet supported.')];
    }
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? '$label is required' : null,
    );
  }

  Widget _passwordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _passwordObscured,
      decoration: InputDecoration(
        labelText: 'Password',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
              _passwordObscured ? Icons.visibility_off : Icons.visibility),
          onPressed: () =>
              setState(() => _passwordObscured = !_passwordObscured),
        ),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Password is required' : null,
    );
  }
}