import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/review_changes_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/generator_widget.dart';

Future<void> _defaultCreate(VaultEntryData entry) => createEntry(entry: entry);
VaultEntryData _defaultGetEntry(String id) => getEntry(id: id);

class CreateEntryScreen extends StatefulWidget {
  final String entryType;
  final VaultEntryData? existing;
  /// Raw field values from a failed import, keyed by Gabbro canonical names
  /// (e.g. `"card_number"`, `"cardholder_name"`, `"expiry"`, `"cvv"`).
  /// Distinct from [existing] — carries unvalidated data that never made it
  /// into the vault. Used by the import failures review flow.
  final Map<String, String>? prefill;
  final Future<void> Function(VaultEntryData entry) onCreateEntry;
  final VaultEntryData Function(String id) onGetEntry;

  const CreateEntryScreen({
    super.key,
    required this.entryType,
    this.existing,
    this.prefill,
    this.onCreateEntry = _defaultCreate,
    this.onGetEntry = _defaultGetEntry,
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
  late final TextEditingController _loginNotesController;
  final FocusNode _loginTitleFocus = FocusNode();
  final FocusNode _urlFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _loginNotesFocus = FocusNode();

  // ── Note fields ─────────────────────────────────────────────────────────────
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final FocusNode _noteTitleFocus = FocusNode();
  final FocusNode _noteContentFocus = FocusNode();

  // ── Identity fields ─────────────────────────────────────────────────────────
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  final List<_CustomFieldState> _identityCustomFields = [];
  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  // ── Card fields ─────────────────────────────────────────────────────────────
  late final TextEditingController _cardNameController;
  late final TextEditingController _cardStatusController;
  late final TextEditingController _cardholderNameController;
  late final TextEditingController _cardNumberController;
  late final TextEditingController _expiryController;
  late final TextEditingController _cvvController;
  bool _cvvObscured = true;
  late final TextEditingController _pinController;
  bool _pinObscured = true;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _cardAccountNumberController;
  late final TextEditingController _paymentNetworkController;
  late final TextEditingController _cardNotesController;
  final FocusNode _cardNameFocus = FocusNode();
  final FocusNode _cardholderNameFocus = FocusNode();
  final FocusNode _cardNumberFocus = FocusNode();
  final FocusNode _expiryFocus = FocusNode();
  final FocusNode _cvvFocus = FocusNode();
  final FocusNode _pinFocus = FocusNode();
  final FocusNode _creditLimitFocus = FocusNode();
  final FocusNode _cardAccountNumberFocus = FocusNode();

  // ── File fields ─────────────────────────────────────────────────────────────
  String? _pickedFilename;
  Uint8List? _pickedFileBytes;
  late final TextEditingController _fileNotesController;

  // ── Custom entry fields ─────────────────────────────────────────────────────
  late final TextEditingController _customTitleController;
  final List<_CustomFieldState> _customFields = [];
  final FocusNode _customTitleFocus = FocusNode();

  bool get _isEditing => widget.existing != null;

  static const _cardStatuses = ['active', 'lapsed', 'inactive'];
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
      _loginNotesController = TextEditingController(text: field0.notes ?? '');
    } else {
      _loginTitleController = TextEditingController();
      _urlController = TextEditingController();
      _usernameController = TextEditingController();
      _passwordController = TextEditingController();
      _loginNotesController = TextEditingController();
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
        _identityCustomFields.add(
          _CustomFieldState(
            labelController: TextEditingController(text: f.label),
            valueController: TextEditingController(text: f.value),
            hidden: f.hidden,
          ),
        );
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
      _cardNameController = TextEditingController(text: field0.cardName ?? '');
      _cardStatusController = TextEditingController(text: field0.status);
      _cardholderNameController = TextEditingController(
        text: field0.cardholderName,
      );
      _cardNumberController = TextEditingController(text: field0.cardNumber);
      _expiryController = TextEditingController(text: field0.expiry);
      _cvvController = TextEditingController(text: field0.cvv);
      _pinController = TextEditingController(text: field0.pin ?? '');
      _creditLimitController = TextEditingController(
        text: field0.creditLimit ?? '',
      );
      _cardAccountNumberController = TextEditingController(
        text: field0.cardAccountNumber ?? '',
      );
      _paymentNetworkController = TextEditingController(
        text: field0.paymentNetwork ?? '',
      );
      _cardNotesController = TextEditingController(text: field0.notes ?? '');
    } else {
      final p = widget.prefill;
      _cardNameController = TextEditingController(text: p?['title'] ?? '');
      _cardStatusController = TextEditingController(text: 'active');
      _cardholderNameController = TextEditingController(
        text: p?['cardholder_name'] ?? '',
      );
      _cardNumberController = TextEditingController(
        text: p?['card_number'] ?? '',
      );
      _expiryController = TextEditingController(
        text: p?['expiry'] ?? '',
      );
      _cvvController = TextEditingController(
        text: p?['cvv'] ?? '',
      );
      _pinController = TextEditingController(
        text: p?['pin'] ?? '',
      );
      _creditLimitController = TextEditingController();
      _cardAccountNumberController = TextEditingController();
      _paymentNetworkController = TextEditingController(
        text: p?['payment_network'] ?? '',
      );
      _cardNotesController = TextEditingController();
    }

    // ── File ───────────────────────────────────────────────────────────────
    if (e case VaultEntryData_File(:final field0)) {
      _pickedFilename = field0.filename;
      _pickedFileBytes = Uint8List.fromList(field0.data);
      _fileNotesController = TextEditingController(text: field0.notes ?? '');
    } else {
      _fileNotesController = TextEditingController();
    }

    // ── Custom ─────────────────────────────────────────────────────────────
    if (e case VaultEntryData_Custom(:final field0)) {
      _customTitleController = TextEditingController(text: field0.title);
      for (final f in field0.fields) {
        _customFields.add(
          _CustomFieldState(
            labelController: TextEditingController(text: f.label),
            valueController: TextEditingController(text: f.value),
            hidden: f.hidden,
          ),
        );
      }
    } else {
      _customTitleController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _loginTitleController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _loginNotesController.dispose();
    _loginTitleFocus.dispose();
    _urlFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _loginNotesFocus.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _noteTitleFocus.dispose();
    _noteContentFocus.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    for (final f in _identityCustomFields) {
      f.dispose();
    }
    _cardNameController.dispose();
    _cardStatusController.dispose();
    _cardholderNameController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _pinController.dispose();
    _creditLimitController.dispose();
    _cardAccountNumberController.dispose();
    _paymentNetworkController.dispose();
    _cardNotesController.dispose();
    _cardNameFocus.dispose();
    _cardholderNameFocus.dispose();
    _cardNumberFocus.dispose();
    _expiryFocus.dispose();
    _cvvFocus.dispose();
    _pinFocus.dispose();
    _creditLimitFocus.dispose();
    _cardAccountNumberFocus.dispose();
    _fileNotesController.dispose();
    _customTitleController.dispose();
    _customTitleFocus.dispose();
    for (final f in _customFields) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Save orchestration ───────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.entryType == 'File' && _pickedFileBytes == null) {
      setState(() => _error = 'Please pick a file.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await _saveCreate();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Validates the form, builds the updated entry, checks for changes,
  /// and pushes ReviewChangesScreen. Called only in edit mode.
  Future<void> _review() async {
    if (!_formKey.currentState!.validate()) return;
    final updated = _buildUpdated();
    if (updated == null) return;
    if (!_hasChanges(widget.existing!, updated)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No changes to save.')));
      }
      return;
    }
    final expiry = _expiryDays();
    if (!mounted) return;
    final result = await Navigator.of(context).push<VaultEntryData>(
      MaterialPageRoute(
        builder: (context) => ReviewChangesScreen(
          original: widget.existing!,
          updated: updated,
          expiryDays: expiry,
          onSave: (entry, days) => updateEntry(entry: entry, expiryDays: days),
        ),
      ),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  /// Derives expiry days from AppSettings.passwordHistoryExpiry.
  int? _expiryDays() {
    final expiry = GabbroApp.of(context).settings.passwordHistoryExpiry;
    return switch (expiry) {
      PasswordHistoryExpiry.sevenDays => 7,
      PasswordHistoryExpiry.thirtyDays => 30,
      PasswordHistoryExpiry.ninetyDays => 90,
      PasswordHistoryExpiry.keepForever => null,
    };
  }

  /// Returns true if any field differs between [original] and [updated].
  bool _hasChanges(VaultEntryData original, VaultEntryData updated) {
    switch ((original, updated)) {
      case (
        VaultEntryData_Login(:final field0),
        VaultEntryData_Login(field0: final u),
      ):
        return field0.title != u.title ||
            field0.url != u.url ||
            field0.username != u.username ||
            field0.password != u.password ||
            field0.notes != u.notes;
      case (
        VaultEntryData_Note(:final field0),
        VaultEntryData_Note(field0: final u),
      ):
        return field0.title != u.title || field0.content != u.content;
      case (
        VaultEntryData_Identity(:final field0),
        VaultEntryData_Identity(field0: final u),
      ):
        return field0.firstName != u.firstName ||
            field0.lastName != u.lastName ||
            field0.email != u.email ||
            field0.phone != u.phone ||
            field0.address != u.address ||
            !listEquals(field0.customFields, u.customFields);
      case (
        VaultEntryData_Card(:final field0),
        VaultEntryData_Card(field0: final u),
      ):
        return field0.cardholderName != u.cardholderName ||
            field0.cardNumber != u.cardNumber ||
            field0.expiry != u.expiry ||
            field0.cvv != u.cvv ||
            field0.pin != u.pin ||
            field0.cardName != u.cardName ||
            field0.status != u.status;
      case (
        VaultEntryData_File(:final field0),
        VaultEntryData_File(field0: final u),
      ):
        return field0.filename != u.filename || field0.notes != u.notes;
      case (
        VaultEntryData_Custom(:final field0),
        VaultEntryData_Custom(field0: final u),
      ):
        return field0.title != u.title || field0.fields != u.fields;
      default:
        return true;
    }
  }

  /// Builds the updated VaultEntryData from current form state.
  /// Returns null if the entry type is not supported.
  VaultEntryData? _buildUpdated() {
    switch (widget.existing) {
      case VaultEntryData_Login(:final field0):
        return VaultEntryData.login(
          LoginEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            title: _loginTitleController.text,
            url: _urlController.text,
            username: _usernameController.text,
            password: _passwordController.text,
            notes: _loginNotesController.text.isEmpty
                ? null
                : _loginNotesController.text,
            customFields: field0.customFields,
            previousPassword: field0.previousPassword,
          ),
        );
      case VaultEntryData_Note(:final field0):
        return VaultEntryData.note(
          NoteEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            title: _titleController.text,
            content: _contentController.text,
          ),
        );
      case VaultEntryData_Identity(:final field0):
        return VaultEntryData.identity(
          IdentityEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            email: _emailController.text,
            phone: _phoneController.text.isEmpty ? null : _phoneController.text,
            address: _addressController.text.isEmpty
                ? null
                : _addressController.text,
            customFields: _identityCustomFields
                .map(
                  (f) => CustomFieldData(
                    label: f.labelController.text,
                    value: f.valueController.text,
                    hidden: f.hidden,
                  ),
                )
                .toList(),
          ),
        );
      case VaultEntryData_Card(:final field0):
        return VaultEntryData.card(
          CardEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
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
            pin: _pinController.text.isEmpty ? null : _pinController.text,
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
            previousCvv: field0.previousCvv,
            previousPin: field0.previousPin,
          ),
        );
      case VaultEntryData_File(:final field0):
        return VaultEntryData.file(
          FileEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            filename: _pickedFilename ?? field0.filename,
            data: _pickedFileBytes ?? Uint8List.fromList(field0.data),
            notes: _fileNotesController.text.isEmpty
                ? null
                : _fileNotesController.text,
          ),
        );
      case VaultEntryData_Custom(:final field0):
        return VaultEntryData.custom(
          CustomEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: field0.folder,
            title: _customTitleController.text,
            fields: _customFields
                .map(
                  (f) => CustomFieldData(
                    label: f.labelController.text,
                    value: f.valueController.text,
                    hidden: f.hidden,
                  ),
                )
                .toList(),
          ),
        );
      default:
        return null;
    }
  }

  Future<void> _saveCreate() async {
    switch (widget.entryType) {
      case 'Login':
        await widget.onCreateEntry(
          VaultEntryData.login(
            LoginEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
              title: _loginTitleController.text,
              url: _urlController.text,
              username: _usernameController.text,
              password: _passwordController.text,
              notes: _loginNotesController.text.isEmpty
                  ? null
                  : _loginNotesController.text,
              customFields: [],
            ),
          ),
        );

      case 'Note':
        await widget.onCreateEntry(
          VaultEntryData.note(
            NoteEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
              title: _titleController.text,
              content: _contentController.text,
            ),
          ),
        );

      case 'Identity':
        await widget.onCreateEntry(
          VaultEntryData.identity(
            IdentityEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
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
                  .map(
                    (f) => CustomFieldData(
                      label: f.labelController.text,
                      value: f.valueController.text,
                      hidden: f.hidden,
                    ),
                  )
                  .toList(),
            ),
          ),
        );

      case 'Card':
        await widget.onCreateEntry(
          VaultEntryData.card(
            CardEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
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
              pin: _pinController.text.isEmpty ? null : _pinController.text,
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
            ),
          ),
        );

      case 'File':
        await widget.onCreateEntry(
          VaultEntryData.file(
            FileEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
              filename: _pickedFilename!,
              data: _pickedFileBytes!,
              notes: _fileNotesController.text.isEmpty
                  ? null
                  : _fileNotesController.text,
            ),
          ),
        );

      case 'Custom':
        await widget.onCreateEntry(
          VaultEntryData.custom(
            CustomEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: 'Personal',
              title: _customTitleController.text,
              fields: _customFields
                  .map(
                    (f) => CustomFieldData(
                      label: f.labelController.text,
                      value: f.valueController.text,
                      hidden: f.hidden,
                    ),
                  )
                  .toList(),
            ),
          ),
        );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle()),
        actions: [
          if (_isEditing)
            TextButton(onPressed: _review, child: const Text('Review →')),
        ],
      ),
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
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (!_isEditing)
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
    TextFormField(
      controller: _loginTitleController,
      focusNode: _loginTitleFocus,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Title',
        border: OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Title is required' : null,
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_urlFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _urlController,
      focusNode: _urlFocus,
      decoration: const InputDecoration(
        labelText: 'URL',
        border: OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'URL is required' : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_usernameFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _usernameController,
      focusNode: _usernameFocus,
      decoration: const InputDecoration(
        labelText: 'Username',
        border: OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Username is required' : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_passwordFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      obscureText: _passwordObscured,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Password',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _passwordObscured ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () =>
              setState(() => _passwordObscured = !_passwordObscured),
        ),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Password is required' : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_loginNotesFocus),
    ),
    Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: const Key('open_generator_button'),
        icon: const Icon(Icons.auto_fix_high, size: 18),
        label: const Text('Generate'),
        onPressed: () async {
          final settings = GabbroApp.of(context).settings;
          final duration = switch (settings.clipboardClearTimeout) {
            ClipboardClearTimeout.never         => const Duration(hours: 24),
            ClipboardClearTimeout.thirtySeconds => const Duration(seconds: 30),
            ClipboardClearTimeout.sixtySeconds  => const Duration(seconds: 60),
            ClipboardClearTimeout.twoMinutes    => const Duration(minutes: 2),
          };
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Password generator')),
                body: GeneratorWidget(
                  clipboardClearDuration: duration,
                  onUsePassword: (value) {
                    setState(() => _passwordController.text = value);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
    const SizedBox(height: 12),
    _optionalTextField(
      _loginNotesController,
      'Notes',
      focusNode: _loginNotesFocus,
      maxLines: 3,
    ),
  ];

  // ── Note fields ──────────────────────────────────────────────────────────────

  List<Widget> _noteFields() => [
    TextFormField(
      controller: _titleController,
      focusNode: _noteTitleFocus,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Title',
        border: OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Title is required' : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_noteContentFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _contentController,
      focusNode: _noteContentFocus,
      maxLines: 6,
      decoration: const InputDecoration(
        labelText: 'Content',
        border: OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Content is required' : null,
    ),
  ];

  // ── Identity fields ──────────────────────────────────────────────────────────

  List<Widget> _identityFields() => [
    TextFormField(
      controller: _firstNameController,
      focusNode: _firstNameFocus,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'First name',
        border: OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'First name is required' : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_lastNameFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _lastNameController,
      focusNode: _lastNameFocus,
      decoration: const InputDecoration(
        labelText: 'Last name',
        border: OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Last name is required' : null,
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _emailController,
      focusNode: _emailFocus,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email (optional)',
        border: OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _phoneController,
      focusNode: _phoneFocus,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Phone (optional)',
        border: OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_addressFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _addressController,
      focusNode: _addressFocus,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Address (optional)',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),
    _customFieldsSection(
      fields: _identityCustomFields,
      onAdd: () =>
          setState(() => _identityCustomFields.add(_CustomFieldState.empty())),
      onRemove: (i) => setState(() {
        _identityCustomFields[i].dispose();
        _identityCustomFields.removeAt(i);
      }),
      onToggleHidden: (i) => setState(
        () =>
            _identityCustomFields[i].hidden = !_identityCustomFields[i].hidden,
      ),
    ),
  ];

  // ── Card fields ──────────────────────────────────────────────────────────────

  List<Widget> _cardFields() => [
    TextFormField(
      controller: _cardNameController,
      focusNode: _cardNameFocus,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Card label (e.g. "Visa Platinum")',
        border: OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Card label is required' : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_cardholderNameFocus),
    ),
    const SizedBox(height: 12),
    _dropdownField(
      label: 'Status',
      initialValue: _cardStatuses.contains(_cardStatusController.text)
          ? _cardStatusController.text
          : 'active',
      items: _cardStatuses,
      onChanged: (v) =>
          setState(() => _cardStatusController.text = v ?? 'active'),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _cardholderNameController,
      focusNode: _cardholderNameFocus,
      decoration: const InputDecoration(
        labelText: 'Cardholder name',
        border: OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Cardholder name is required' : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_cardNumberFocus),
    ),
    const SizedBox(height: 12),
    _dropdownField(
      label: 'Payment network',
      initialValue: _paymentNetworks.contains(_paymentNetworkController.text)
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
      focusNode: _cardNumberFocus,
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
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_expiryFocus),
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _expiryController,
            focusNode: _expiryFocus,
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
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_cvvFocus),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _cvvController,
            focusNode: _cvvFocus,
            obscureText: _cvvObscured,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: 'CVV',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _cvvObscured ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _cvvObscured = !_cvvObscured),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'CVV is required';
              if (v.length < 3 || v.length > 4) {
                return 'CVV must be 3 or 4 digits';
              }
              return null;
            },
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_pinFocus),
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _pinController,
      focusNode: _pinFocus,
      obscureText: _pinObscured,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(16),
      ],
      decoration: InputDecoration(
        labelText: 'PIN (optional)',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _pinObscured ? Icons.visibility_off : Icons.visibility,
          ),
          tooltip: _pinObscured ? 'Show PIN' : 'Hide PIN',
          onPressed: () => setState(() => _pinObscured = !_pinObscured),
        ),
      ),
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_creditLimitFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _creditLimitController,
      focusNode: _creditLimitFocus,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Credit limit (optional)',
        border: OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_cardAccountNumberFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _cardAccountNumberController,
      focusNode: _cardAccountNumberFocus,
      decoration: const InputDecoration(
        labelText: 'Account number (optional)',
        border: OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) => _save(),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _cardNotesController,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Notes (optional)',
        border: OutlineInputBorder(),
      ),
    ),
  ];

  // ── File fields ──────────────────────────────────────────────────────────────

  List<Widget> _fileFields() => [
    if (_pickedFilename != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_pickedFilename!, overflow: TextOverflow.ellipsis),
            ),
            if (_pickedFileBytes != null)
              Text(
                '${(_pickedFileBytes!.length / 1024).toStringAsFixed(1)} KB',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    if (_pickedFileBytes == null)
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'No file selected',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
    OutlinedButton.icon(
      onPressed: _pickFile,
      icon: const Icon(Icons.folder_open_outlined),
      label: const Text('Pick file'),
    ),
    const SizedBox(height: 12),
    _optionalTextField(_fileNotesController, 'Notes', maxLines: 3),
  ];

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    setState(() {
      _pickedFilename = f.name;
      _pickedFileBytes = f.bytes;
    });
  }

  // ── Custom entry fields ──────────────────────────────────────────────────────

  List<Widget> _customEntryFields() => [
    TextFormField(
      controller: _customTitleController,
      focusNode: _customTitleFocus,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Title',
        border: OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Title is required' : null,
      onFieldSubmitted: (_) => _save(),
    ),
    const SizedBox(height: 16),
    _customFieldsSection(
      fields: _customFields,
      onAdd: () => setState(() => _customFields.add(_CustomFieldState.empty())),
      onRemove: (i) => setState(() {
        _customFields[i].dispose();
        _customFields.removeAt(i);
      }),
      onToggleHidden: (i) =>
          setState(() => _customFields[i].hidden = !_customFields[i].hidden),
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
          Text('Custom fields', style: Theme.of(context).textTheme.titleSmall),
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
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Label required' : null,
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
                        icon: Icon(
                          f.hidden ? Icons.visibility_off : Icons.visibility,
                        ),
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

  Widget _optionalTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    FocusNode? focusNode,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: '$label (optional)',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? initialValue,
    required List<String> items,
    required void Function(String?) onChanged,
    bool required = true,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: initialValue,
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
