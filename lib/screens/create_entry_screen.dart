import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

class CreateEntryScreen extends StatefulWidget {
  final String entryType;
  final VaultEntryData? existing;

  const CreateEntryScreen({
    super.key,
    required this.entryType,
    this.existing,
  });

  @override
  State<CreateEntryScreen> createState() => _CreateEntryScreenState();
}

class _CreateEntryScreenState extends State<CreateEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _error;

  // ── Login fields ────────────────────────────────────────────────────────────
  late final TextEditingController _loginTitleController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _passwordObscured = true;

  // ── Note fields ─────────────────────────────────────────────────────────────
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  // ── Identity fields ─────────────────────────────────────────────────────────
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  // Dynamic custom fields for Identity
  final List<_CustomFieldState> _identityCustomFields = [];

  // ── Card fields ─────────────────────────────────────────────────────────────
  late final TextEditingController _cardNameController;
  late final TextEditingController _cardStatusController;
  late final TextEditingController _cardholderNameController;
  late final TextEditingController _cardNumberController;
  late final TextEditingController _expiryController;
  late final TextEditingController _cvvController;
  bool _cvvObscured = true;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _cardAccountNumberController;
  late final TextEditingController _paymentNetworkController;
  late final TextEditingController _cardNotesController;

  // ── File fields ─────────────────────────────────────────────────────────────
  String? _pickedFilename;
  Uint8List? _pickedFileBytes;
  late final TextEditingController _fileNotesController;

  // ── Custom entry fields ─────────────────────────────────────────────────────
  late final TextEditingController _customTitleController;
  final List<_CustomFieldState> _customFields = [];

  bool get _isEditing => widget.existing != null;

  // ── Card status options ─────────────────────────────────────────────────────
  static const _cardStatuses = ['active', 'lapsed', 'inactive'];

  // ── Payment network options ─────────────────────────────────────────────────
  static const _paymentNetworks = [
    'Visa',
    'Mastercard',
    'Amex',
    'Discover',
    'UnionPay',
    'Diners',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final e = widget.existing;

    // ── Login ──────────────────────────────────────────────────────────────
    if (e case VaultEntryData_Login(:final field0)) {
      _loginTitleController = TextEditingController(text: field0.title);
      _urlController = TextEditingController(text: field0.url);
      _usernameController = TextEditingController(text: field0.username);
      _passwordController = TextEditingController(text: field0.password);
    } else {
      _loginTitleController = TextEditingController();
      _urlController = TextEditingController();
      _usernameController = TextEditingController();
      _passwordController = TextEditingController();
    }

    // ── Note ───────────────────────────────────────────────────────────────
    if (e case VaultEntryData_Note(:final field0)) {
      _titleController = TextEditingController(text: field0.title);
      _contentController = TextEditingController(text: field0.content);
    } else {
      _titleController = TextEditingController();
      _contentController = TextEditingController();
    }

    // ── Identity ───────────────────────────────────────────────────────────
    if (e case VaultEntryData_Identity(:final field0)) {
      _firstNameController = TextEditingController(text: field0.firstName);
      _lastNameController = TextEditingController(text: field0.lastName);
      _emailController = TextEditingController(text: field0.email);
      _phoneController = TextEditingController(text: field0.phone ?? '');
      _addressController = TextEditingController(text: field0.address ?? '');
      for (final f in field0.customFields) {
        _identityCustomFields.add(_CustomFieldState(
          labelController: TextEditingController(text: f.label),
          valueController: TextEditingController(text: f.value),
          hidden: f.hidden,
        ));
      }
    } else {
      _firstNameController = TextEditingController();
      _lastNameController = TextEditingController();
      _emailController = TextEditingController();
      _phoneController = TextEditingController();
      _addressController = TextEditingController();
    }

    // ── Card ───────────────────────────────────────────────────────────────
    if (e case VaultEntryData_Card(:final field0)) {
      _cardNameController =
          TextEditingController(text: field0.cardName ?? '');
      _cardStatusController =
          TextEditingController(text: field0.status);
      _cardholderNameController =
          TextEditingController(text: field0.cardholderName);
      _cardNumberController =
          TextEditingController(text: field0.cardNumber);
      _expiryController = TextEditingController(text: field0.expiry);
      _cvvController = TextEditingController(text: field0.cvv);
      _creditLimitController =
          TextEditingController(text: field0.creditLimit ?? '');
      _cardAccountNumberController =
          TextEditingController(text: field0.cardAccountNumber ?? '');
      _paymentNetworkController =
          TextEditingController(text: field0.paymentNetwork ?? '');
      _cardNotesController =
          TextEditingController(text: field0.notes ?? '');
    } else {
      _cardNameController = TextEditingController();
      _cardStatusController = TextEditingController(text: 'active');
      _cardholderNameController = TextEditingController();
      _cardNumberController = TextEditingController();
      _expiryController = TextEditingController();
      _cvvController = TextEditingController();
      _creditLimitController = TextEditingController();
      _cardAccountNumberController = TextEditingController();
      _paymentNetworkController = TextEditingController();
      _cardNotesController = TextEditingController();
    }

    // ── File ───────────────────────────────────────────────────────────────
    if (e case VaultEntryData_File(:final field0)) {
      _pickedFilename = field0.filename;
      _pickedFileBytes = Uint8List.fromList(field0.data);
      _fileNotesController =
          TextEditingController(text: field0.notes ?? '');
    } else {
      _fileNotesController = TextEditingController();
    }

    // ── Custom ─────────────────────────────────────────────────────────────
    if (e case VaultEntryData_Custom(:final field0)) {
      _customTitleController =
          TextEditingController(text: field0.title);
      for (final f in field0.fields) {
        _customFields.add(_CustomFieldState(
          labelController: TextEditingController(text: f.label),
          valueController: TextEditingController(text: f.value),
          hidden: f.hidden,
        ));
      }
    } else {
      _customTitleController = TextEditingController();
    }
  }

  @override
  void dispose() {
    // Login
    _loginTitleController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    // Note
    _titleController.dispose();
    _contentController.dispose();
    // Identity
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    for (final f in _identityCustomFields) {
      f.dispose();
    }
    // Card
    _cardNameController.dispose();
    _cardStatusController.dispose();
    _cardholderNameController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _creditLimitController.dispose();
    _cardAccountNumberController.dispose();
    _paymentNetworkController.dispose();
    _cardNotesController.dispose();
    // File
    _fileNotesController.dispose();
    _filePathController.dispose();
    // Custom
    _customTitleController.dispose();
    for (final f in _customFields) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Save orchestration ───────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // File entry needs a file picked
    if (widget.entryType == 'File' && _pickedFileBytes == null) {
      setState(() => _error = 'Please pick a file.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (_isEditing) {
        await _saveUpdate();
        final id = switch (widget.existing!) {
          VaultEntryData_Login(:final field0) => field0.id,
          VaultEntryData_Note(:final field0) => field0.id,
          VaultEntryData_Identity(:final field0) => field0.id,
          VaultEntryData_Card(:final field0) => field0.id,
          VaultEntryData_File(:final field0) => field0.id,
          VaultEntryData_Custom(:final field0) => field0.id,
        };
        final updated = getEntry(id: id);
        if (mounted) Navigator.of(context).pop(updated);
      } else {
        await _saveCreate();
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveCreate() async {
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
            title: _loginTitleController.text,
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

      case 'Identity':
        await createEntry(
          entry: VaultEntryData.identity(IdentityEntryData(
            id: '',
            createdAt: '',
            updatedAt: '',
            folder: 'Personal',
            tags: [],
            favourite: false,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            email: _emailController.text,
            phone: _phoneController.text.isEmpty
                ? null
                : _phoneController.text,
            address: _addressController.text.isEmpty
                ? null
                : _addressController.text,
            customFields: _identityCustomFields
                .map((f) => CustomFieldData(
                      label: f.labelController.text,
                      value: f.valueController.text,
                      hidden: f.hidden,
                    ))
                .toList(),
          )),
        );

      case 'Card':
        await createEntry(
          entry: VaultEntryData.card(CardEntryData(
            id: '',
            createdAt: '',
            updatedAt: '',
            folder: 'Personal',
            tags: [],
            favourite: false,
            cardName: _cardNameController.text.isEmpty
                ? null
                : _cardNameController.text,
            status: _cardStatusController.text.isEmpty
                ? 'active'
                : _cardStatusController.text,
            cardholderName: _cardholderNameController.text,
            cardNumber: _cardNumberController.text,
            expiry: _expiryController.text,
            cvv: _cvvController.text,
            creditLimit: _creditLimitController.text.isEmpty
                ? null
                : _creditLimitController.text,
            cardAccountNumber: _cardAccountNumberController.text.isEmpty
                ? null
                : _cardAccountNumberController.text,
            paymentNetwork: _paymentNetworkController.text.isEmpty
                ? null
                : _paymentNetworkController.text,
            notes: _cardNotesController.text.isEmpty
                ? null
                : _cardNotesController.text,
            customFields: const [],
          )),
        );

      case 'File':
        await createEntry(
          entry: VaultEntryData.file(FileEntryData(
            id: '',
            createdAt: '',
            updatedAt: '',
            folder: 'Personal',
            tags: [],
            favourite: false,
            filename: _pickedFilename!,
            data: _pickedFileBytes!,
            notes: _fileNotesController.text.isEmpty
                ? null
                : _fileNotesController.text,
          )),
        );

      case 'Custom':
        await createEntry(
          entry: VaultEntryData.custom(CustomEntryData(
            id: '',
            createdAt: '',
            updatedAt: '',
            folder: 'Personal',
            tags: [],
            favourite: false,
            title: _customTitleController.text,
            fields: _customFields
                .map((f) => CustomFieldData(
                      label: f.labelController.text,
                      value: f.valueController.text,
                      hidden: f.hidden,
                    ))
                .toList(),
          )),
        );
    }
  }

  Future<void> _saveUpdate() async {
    switch (widget.existing) {
      case VaultEntryData_Login(:final field0):
        await updateEntry(
          entry: VaultEntryData.login(LoginEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            tags: field0.tags,
            favourite: field0.favourite,
            title: _loginTitleController.text,
            url: _urlController.text,
            username: _usernameController.text,
            password: _passwordController.text,
            customFields: field0.customFields,
          )),
        );

      case VaultEntryData_Note(:final field0):
        await updateEntry(
          entry: VaultEntryData.note(NoteEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            tags: field0.tags,
            favourite: field0.favourite,
            title: _titleController.text,
            content: _contentController.text,
          )),
        );

      case VaultEntryData_Identity(:final field0):
        await updateEntry(
          entry: VaultEntryData.identity(IdentityEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            tags: field0.tags,
            favourite: field0.favourite,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            email: _emailController.text,
            phone: _phoneController.text.isEmpty
                ? null
                : _phoneController.text,
            address: _addressController.text.isEmpty
                ? null
                : _addressController.text,
            customFields: _identityCustomFields
                .map((f) => CustomFieldData(
                      label: f.labelController.text,
                      value: f.valueController.text,
                      hidden: f.hidden,
                    ))
                .toList(),
          )),
        );

      case VaultEntryData_Card(:final field0):
        await updateEntry(
          entry: VaultEntryData.card(CardEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            tags: field0.tags,
            favourite: field0.favourite,
            cardName: _cardNameController.text.isEmpty
                ? null
                : _cardNameController.text,
            status: _cardStatusController.text.isEmpty
                ? 'active'
                : _cardStatusController.text,
            cardholderName: _cardholderNameController.text,
            cardNumber: _cardNumberController.text,
            expiry: _expiryController.text,
            cvv: _cvvController.text,
            creditLimit: _creditLimitController.text.isEmpty
                ? null
                : _creditLimitController.text,
            cardAccountNumber: _cardAccountNumberController.text.isEmpty
                ? null
                : _cardAccountNumberController.text,
            paymentNetwork: _paymentNetworkController.text.isEmpty
                ? null
                : _paymentNetworkController.text,
            notes: _cardNotesController.text.isEmpty
                ? null
                : _cardNotesController.text,
            customFields: field0.customFields,
          )),
        );

      case VaultEntryData_File(:final field0):
        await updateEntry(
          entry: VaultEntryData.file(FileEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            tags: field0.tags,
            favourite: field0.favourite,
            // Keep original file data if no new file was picked
            filename: _pickedFilename ?? field0.filename,
            data: _pickedFileBytes ?? Uint8List.fromList(field0.data),
            notes: _fileNotesController.text.isEmpty
                ? null
                : _fileNotesController.text,
          )),
        );

      case VaultEntryData_Custom(:final field0):
        await updateEntry(
          entry: VaultEntryData.custom(CustomEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            tags: field0.tags,
            favourite: field0.favourite,
            title: _customTitleController.text,
            fields: _customFields
                .map((f) => CustomFieldData(
                      label: f.labelController.text,
                      value: f.valueController.text,
                      hidden: f.hidden,
                    ))
                .toList(),
          )),
        );

      default:
        throw Exception('Edit not supported for this entry type.');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_screenTitle())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }

  String _screenTitle() {
    final action = _isEditing ? 'Edit' : 'New';
    final label = switch (widget.entryType) {
      'Login' => 'Password',
      'Note' => 'Note',
      'Identity' => 'Identity',
      'Card' => 'Card',
      'File' => 'File',
      'Custom' => 'Custom',
      _ => widget.entryType,
    };
    return '$action $label';
  }

  List<Widget> _buildFields() {
    return switch (widget.entryType) {
      'Login' => _loginFields(),
      'Note' => _noteFields(),
      'Identity' => _identityFields(),
      'Card' => _cardFields(),
      'File' => _fileFields(),
      'Custom' => _customEntryFields(),
      _ => [const Text('Entry type not yet supported.')],
    };
  }

  // ── Login fields ─────────────────────────────────────────────────────────────

  List<Widget> _loginFields() => [
        _textField(_loginTitleController, 'Title'),
        const SizedBox(height: 12),
        _textField(_urlController, 'URL'),
        const SizedBox(height: 12),
        _textField(_usernameController, 'Username'),
        const SizedBox(height: 12),
        _obscuredField(
          controller: _passwordController,
          label: 'Password',
          obscured: _passwordObscured,
          onToggle: () =>
              setState(() => _passwordObscured = !_passwordObscured),
          required: true,
        ),
      ];

  // ── Note fields ──────────────────────────────────────────────────────────────

  List<Widget> _noteFields() => [
        _textField(_titleController, 'Title'),
        const SizedBox(height: 12),
        _textField(_contentController, 'Content', maxLines: 6),
      ];

  // ── Identity fields ──────────────────────────────────────────────────────────

  List<Widget> _identityFields() => [
        _textField(_firstNameController, 'First name'),
        const SizedBox(height: 12),
        _textField(_lastNameController, 'Last name'),
        const SizedBox(height: 12),
        _textField(_emailController, 'Email',
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _optionalTextField(_phoneController, 'Phone',
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _optionalTextField(_addressController, 'Address', maxLines: 3),
        const SizedBox(height: 16),
        _customFieldsSection(
          fields: _identityCustomFields,
          onAdd: () => setState(() => _identityCustomFields
              .add(_CustomFieldState.empty())),
          onRemove: (i) => setState(() {
            _identityCustomFields[i].dispose();
            _identityCustomFields.removeAt(i);
          }),
          onToggleHidden: (i) => setState(
              () => _identityCustomFields[i].hidden =
                  !_identityCustomFields[i].hidden),
        ),
      ];

  // ── Card fields ──────────────────────────────────────────────────────────────

  List<Widget> _cardFields() => [
        _optionalTextField(_cardNameController, 'Card label (e.g. "Visa Platinum")'),
        const SizedBox(height: 12),
        _dropdownField(
          label: 'Status',
          value: _cardStatuses.contains(_cardStatusController.text)
              ? _cardStatusController.text
              : 'active',
          items: _cardStatuses,
          onChanged: (v) =>
              setState(() => _cardStatusController.text = v ?? 'active'),
        ),
        const SizedBox(height: 12),
        _textField(_cardholderNameController, 'Cardholder name'),
        const SizedBox(height: 12),
        _dropdownField(
          label: 'Payment network',
          value: _paymentNetworks.contains(_paymentNetworkController.text)
              ? _paymentNetworkController.text
              : null,
          items: _paymentNetworks,
          onChanged: (v) =>
              setState(() => _paymentNetworkController.text = v ?? ''),
          required: false,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cardNumberController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Card number',
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Card number is required';
            if (v.length < 12 || v.length > 19) {
              return 'Card number must be 12–19 digits';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _expiryController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                  _ExpiryInputFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: 'Expiry (MM/YY)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Expiry is required';
                  final pattern = RegExp(r'^\d{2}/\d{2}$');
                  if (!pattern.hasMatch(v)) return 'Use MM/YY format';
                  final month = int.tryParse(v.substring(0, 2));
                  if (month == null || month < 1 || month > 12) {
                    return 'Month must be 01–12';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _cvvController,
                obscureText: _cvvObscured,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: 'CVV',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_cvvObscured
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _cvvObscured = !_cvvObscured),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'CVV is required';
                  if (v.length < 3 || v.length > 4) {
                    return 'CVV must be 3 or 4 digits';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _optionalTextField(_creditLimitController, 'Credit limit',
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        _optionalTextField(
            _cardAccountNumberController, 'Account number'),
        const SizedBox(height: 12),
        _optionalTextField(_cardNotesController, 'Notes', maxLines: 3),
      ];

  // ── File fields ──────────────────────────────────────────────────────────────
  // Desktop approach: user types a file path and presses Load.
  // A native file picker will be added when Android support is built.

  final TextEditingController _filePathController = TextEditingController();
  String? _fileLoadError;

  List<Widget> _fileFields() => [
        if (_pickedFilename != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pickedFilename!,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_pickedFileBytes != null)
                  Text(
                    '${(_pickedFileBytes!.length / 1024).toStringAsFixed(1)} KB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _filePathController,
                decoration: InputDecoration(
                  labelText: 'File path',
                  border: const OutlineInputBorder(),
                  errorText: _fileLoadError,
                ),
                validator: (_) =>
                    _pickedFileBytes == null ? 'Please load a file' : null,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton(
                onPressed: _loadFileFromPath,
                child: const Text('Load'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _optionalTextField(_fileNotesController, 'Notes', maxLines: 3),
      ];

  Future<void> _loadFileFromPath() async {
    final path = _filePathController.text.trim();
    if (path.isEmpty) {
      setState(() => _fileLoadError = 'Enter a file path');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      setState(() => _fileLoadError = 'File not found');
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      setState(() {
        _pickedFilename = path.split(Platform.pathSeparator).last;
        _pickedFileBytes = bytes;
        _fileLoadError = null;
      });
    } catch (e) {
      setState(() => _fileLoadError = 'Could not read file: $e');
    }
  }

  // ── Custom entry fields ──────────────────────────────────────────────────────

  List<Widget> _customEntryFields() => [
        _textField(_customTitleController, 'Title'),
        const SizedBox(height: 16),
        _customFieldsSection(
          fields: _customFields,
          onAdd: () => setState(
              () => _customFields.add(_CustomFieldState.empty())),
          onRemove: (i) => setState(() {
            _customFields[i].dispose();
            _customFields.removeAt(i);
          }),
          onToggleHidden: (i) => setState(
              () => _customFields[i].hidden = !_customFields[i].hidden),
        ),
      ];

  // ── Shared custom fields section ─────────────────────────────────────────────

  Widget _customFieldsSection({
    required List<_CustomFieldState> fields,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
    required void Function(int) onToggleHidden,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fields.isNotEmpty)
          Text(
            'Custom fields',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        if (fields.isNotEmpty) const SizedBox(height: 8),
        ...List.generate(fields.length, (i) {
          final f = fields[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: f.labelController,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Label required'
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: f.valueController,
                    obscureText: f.hidden,
                    decoration: InputDecoration(
                      labelText: 'Value',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(f.hidden
                            ? Icons.visibility_off
                            : Icons.visibility),
                        tooltip: f.hidden ? 'Show value' : 'Hide value',
                        onPressed: () => onToggleHidden(i),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove field',
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add custom field'),
        ),
      ],
    );
  }

  // ── Field helpers ────────────────────────────────────────────────────────────

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? '$label is required' : null,
    );
  }

  /// Optional field — no validator, empty text is fine.
  Widget _optionalTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: '$label (optional)',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _obscuredField({
    required TextEditingController controller,
    required String label,
    required bool obscured,
    required VoidCallback onToggle,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscured,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(obscured ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
      validator: required
          ? (v) => (v == null || v.isEmpty) ? '$label is required' : null
          : null,
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    bool required = true,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: onChanged,
      validator: required
          ? (v) => (v == null || v.isEmpty) ? '$label is required' : null
          : null,
    );
  }
}

// ── Custom field state helper ────────────────────────────────────────────────

/// Holds the mutable state for a single user-defined key/value field.
class _CustomFieldState {
  final TextEditingController labelController;
  final TextEditingController valueController;
  bool hidden;

  _CustomFieldState({
    required this.labelController,
    required this.valueController,
    this.hidden = false,
  });

  factory _CustomFieldState.empty() => _CustomFieldState(
        labelController: TextEditingController(),
        valueController: TextEditingController(),
      );

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}

// ── Expiry input formatter ───────────────────────────────────────────────────

/// Auto-inserts '/' after the two month digits so the user only
/// needs to type 4 digits (MMYY) and gets MM/YY in the field.
class _ExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll('/', '');
    if (digits.length > 4) return oldValue;
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ── Custom field state helper ────────────────────────────────────────────────
