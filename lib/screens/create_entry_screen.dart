import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:gabbro/screens/review_changes_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/generator_widget.dart';

/// A file the user picked to attach: its name and (eagerly-loaded) bytes.
typedef PickedFile = ({String name, Uint8List? bytes});

Future<void> _defaultCreate(VaultEntryData entry) => createEntry(entry: entry);
VaultEntryData _defaultGetEntry(String id) => getEntry(id: id);

/// Native apps that asked Gabbro to autofill but matched no entry — surfaced as
/// tap-to-fill suggestions for the app-id field. Android only; empty elsewhere.
Future<List<String>> _defaultRecentApps() async {
  if (defaultTargetPlatform != TargetPlatform.android) return const [];
  try {
    const channel = MethodChannel('app.gabbro.gabbro/autofill');
    final list = await channel.invokeMethod<List<dynamic>>('getRecentApps');
    return list?.cast<String>() ?? const [];
  } catch (_) {
    return const [];
  }
}
List<String> _defaultListFolders() => listFolders();

Future<PickedFile?> _defaultPickFile() async {
  final result = await FilePicker.pickFiles(withData: true);
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.first;
  return (name: f.name, bytes: f.bytes);
}

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
  final List<String> Function()? listFolders;

  /// Test seam: pick a file to attach. Defaults to the native dialog; may throw
  /// when the file portal is unavailable (sandbox).
  final Future<PickedFile?> Function() pickFile;

  /// Test seam: fetch recently-seen native app ids for the suggestion chips.
  /// Defaults to the Android autofill MethodChannel; empty off-Android.
  final Future<List<String>> Function() recentAppsFetcher;

  const CreateEntryScreen({
    super.key,
    required this.entryType,
    this.existing,
    this.prefill,
    this.onCreateEntry = _defaultCreate,
    this.onGetEntry = _defaultGetEntry,
    this.listFolders,
    this.pickFile = _defaultPickFile,
    this.recentAppsFetcher = _defaultRecentApps,
  });

  @override
  State<CreateEntryScreen> createState() => _CreateEntryScreenState();
}

class _CreateEntryScreenState extends State<CreateEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _error;
  late String _selectedFolder;
  List<String> _folders = [];
  List<String> _recentApps = const [];

  // ── Login fields ────────────────────────────────────────────────────────────
  late final TextEditingController _loginTitleController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _loginEmailController;
  late final TextEditingController _passwordController;
  bool _passwordObscured = true;
  late final TextEditingController _loginNotesController;
  late final TextEditingController _appIdController;
  final List<_CustomFieldState> _loginCustomFields = [];
  final FocusNode _loginTitleFocus = FocusNode();
  final FocusNode _urlFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _loginNotesFocus = FocusNode();

  // ── Note fields ─────────────────────────────────────────────────────────────
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final List<_CustomFieldState> _noteCustomFields = [];
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
  final List<_CustomFieldState> _cardCustomFields = [];
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
  final List<_CustomFieldState> _fileCustomFields = [];

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
    _selectedFolder = _existingFolder();
    try {
      _folders = (widget.listFolders ?? _defaultListFolders)();
    } catch (_) {
      _folders = [];
    }
    // Suggestion chips for the app-id field (login form only).
    widget.recentAppsFetcher().then((apps) {
      if (mounted) setState(() => _recentApps = apps);
    });
  }

  String _existingFolder() {
    final e = widget.existing;
    if (e == null) return '';
    return switch (e) {
      VaultEntryData_Login(:final field0) => field0.folder,
      VaultEntryData_Note(:final field0) => field0.folder,
      VaultEntryData_Identity(:final field0) => field0.folder,
      VaultEntryData_Card(:final field0) => field0.folder,
      VaultEntryData_File(:final field0) => field0.folder,
      VaultEntryData_Custom(:final field0) => field0.folder,
    };
  }

  void _initControllers() {
    final e = widget.existing;

    // ── Login ──────────────────────────────────────────────────────────────
    if (e case VaultEntryData_Login(:final field0)) {
      _loginTitleController = TextEditingController(text: field0.title);
      _urlController = TextEditingController(text: field0.url);
      _usernameController = TextEditingController(text: field0.username);
      _loginEmailController = TextEditingController(text: field0.email ?? '');
      _passwordController = TextEditingController(text: field0.password);
      _loginNotesController = TextEditingController(text: field0.notes ?? '');
      _appIdController = TextEditingController(text: field0.appId ?? '');
      for (final f in field0.customFields) {
        _loginCustomFields.add(
          _CustomFieldState(
            labelController: TextEditingController(text: f.label),
            valueController: TextEditingController(text: f.value),
            hidden: f.hidden,
          ),
        );
      }
    } else {
      _loginTitleController = TextEditingController();
      _urlController = TextEditingController();
      _usernameController = TextEditingController();
      _loginEmailController = TextEditingController();
      _passwordController = TextEditingController();
      _loginNotesController = TextEditingController();
      _appIdController = TextEditingController();
    }

    // ── Note ───────────────────────────────────────────────────────────────
    if (e case VaultEntryData_Note(:final field0)) {
      _titleController = TextEditingController(text: field0.title);
      _contentController = TextEditingController(text: field0.content);
      for (final f in field0.customFields) {
        _noteCustomFields.add(
          _CustomFieldState(
            labelController: TextEditingController(text: f.label),
            valueController: TextEditingController(text: f.value),
            hidden: f.hidden,
          ),
        );
      }
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
      for (final f in field0.customFields) {
        _cardCustomFields.add(
          _CustomFieldState(
            labelController: TextEditingController(text: f.label),
            valueController: TextEditingController(text: f.value),
            hidden: f.hidden,
          ),
        );
      }
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
      for (final f in field0.customFields) {
        _fileCustomFields.add(
          _CustomFieldState(
            labelController: TextEditingController(text: f.label),
            valueController: TextEditingController(text: f.value),
            hidden: f.hidden,
          ),
        );
      }
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
    _loginEmailController.dispose();
    _passwordController.dispose();
    _loginNotesController.dispose();
    _appIdController.dispose();
    for (final f in _loginCustomFields) {
      f.dispose();
    }
    _loginTitleFocus.dispose();
    _urlFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _loginNotesFocus.dispose();
    _titleController.dispose();
    _contentController.dispose();
    for (final f in _noteCustomFields) {
      f.dispose();
    }
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
    for (final f in _cardCustomFields) {
      f.dispose();
    }
    _cardNameFocus.dispose();
    _cardholderNameFocus.dispose();
    _cardNumberFocus.dispose();
    _expiryFocus.dispose();
    _cvvFocus.dispose();
    _pinFocus.dispose();
    _creditLimitFocus.dispose();
    _cardAccountNumberFocus.dispose();
    _fileNotesController.dispose();
    for (final f in _fileCustomFields) {
      f.dispose();
    }
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
      setState(() => _error = AppLocalizations.of(context).pickAFile);
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
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).noChangesToSave)));
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
    // maybeOf for test-safety (no GabbroApp ancestor under bare testApp);
    // production always has the ancestor, so behaviour is unchanged.
    final app = GabbroApp.maybeOf(context);
    if (app == null) return null;
    final expiry = app.settings.passwordHistoryExpiry;
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
            field0.notes != u.notes ||
            field0.appId != u.appId ||
            field0.email != u.email ||
            !listEquals(field0.customFields, u.customFields) ||
            field0.folder != u.folder;
      case (
        VaultEntryData_Note(:final field0),
        VaultEntryData_Note(field0: final u),
      ):
        return field0.title != u.title ||
            field0.content != u.content ||
            !listEquals(field0.customFields, u.customFields) ||
            field0.folder != u.folder;
      case (
        VaultEntryData_Identity(:final field0),
        VaultEntryData_Identity(field0: final u),
      ):
        return field0.firstName != u.firstName ||
            field0.lastName != u.lastName ||
            field0.email != u.email ||
            field0.phone != u.phone ||
            field0.address != u.address ||
            !listEquals(field0.customFields, u.customFields) ||
            field0.folder != u.folder;
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
            field0.status != u.status ||
            field0.folder != u.folder ||
            field0.creditLimit != u.creditLimit ||
            field0.cardAccountNumber != u.cardAccountNumber ||
            field0.paymentNetwork != u.paymentNetwork ||
            field0.bankName != u.bankName ||
            field0.transactionPassword != u.transactionPassword ||
            field0.notes != u.notes ||
            !listEquals(field0.customFields, u.customFields);
      case (
        VaultEntryData_File(:final field0),
        VaultEntryData_File(field0: final u),
      ):
        return field0.filename != u.filename ||
            field0.notes != u.notes ||
            !listEquals(field0.customFields, u.customFields) ||
            field0.folder != u.folder;
      case (
        VaultEntryData_Custom(:final field0),
        VaultEntryData_Custom(field0: final u),
      ):
        return field0.title != u.title ||
            field0.fields != u.fields ||
            field0.folder != u.folder;
      default:
        return true;
    }
  }

  /// The trimmed app-id field value, or null when blank — an unset app id
  /// matches no native app (zero false positives).
  String? _appIdOrNull() {
    final v = _appIdController.text.trim();
    return v.isEmpty ? null : v;
  }

  /// The trimmed login email, or null when blank (the field is optional).
  String? _loginEmailOrNull() {
    final v = _loginEmailController.text.trim();
    return v.isEmpty ? null : v;
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
            folder: _selectedFolder,
            title: _loginTitleController.text,
            url: _urlController.text,
            username: _usernameController.text,
            password: _passwordController.text,
            notes: _loginNotesController.text.isEmpty
                ? null
                : _loginNotesController.text,
            customFields: _loginCustomFields
                .map(
                  (f) => CustomFieldData(
                    label: f.labelController.text,
                    value: f.valueController.text,
                    hidden: f.hidden,
                  ),
                )
                .toList(),
            appId: _appIdOrNull(),
            email: _loginEmailOrNull(),
          ),
        );
      case VaultEntryData_Note(:final field0):
        return VaultEntryData.note(
          NoteEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: _selectedFolder,
            title: _titleController.text,
            content: _contentController.text,
            customFields: _noteCustomFields
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
      case VaultEntryData_Identity(:final field0):
        return VaultEntryData.identity(
          IdentityEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: _selectedFolder,
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
            folder: _selectedFolder,
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
            bankName: field0.bankName,
            transactionPassword: field0.transactionPassword,
            notes: _cardNotesController.text.isEmpty
                ? null
                : _cardNotesController.text,
            customFields: _cardCustomFields
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
      case VaultEntryData_File(:final field0):
        return VaultEntryData.file(
          FileEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: _selectedFolder,
            filename: _pickedFilename ?? field0.filename,
            data: _pickedFileBytes ?? Uint8List.fromList(field0.data),
            notes: _fileNotesController.text.isEmpty
                ? null
                : _fileNotesController.text,
            customFields: _fileCustomFields
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
      case VaultEntryData_Custom(:final field0):
        return VaultEntryData.custom(
          CustomEntryData(
            id: field0.id,
            createdAt: field0.createdAt,
            updatedAt: '',
            folder: _selectedFolder,
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
              folder: _selectedFolder,
              title: _loginTitleController.text,
              url: _urlController.text,
              username: _usernameController.text,
              password: _passwordController.text,
              notes: _loginNotesController.text.isEmpty
                  ? null
                  : _loginNotesController.text,
              customFields: _loginCustomFields
                  .map(
                    (f) => CustomFieldData(
                      label: f.labelController.text,
                      value: f.valueController.text,
                      hidden: f.hidden,
                    ),
                  )
                  .toList(),
              appId: _appIdOrNull(),
              email: _loginEmailOrNull(),
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
              folder: _selectedFolder,
              title: _titleController.text,
              content: _contentController.text,
              customFields: _noteCustomFields
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

      case 'Identity':
        await widget.onCreateEntry(
          VaultEntryData.identity(
            IdentityEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: _selectedFolder,
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
              folder: _selectedFolder,
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
              customFields: _cardCustomFields
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

      case 'File':
        await widget.onCreateEntry(
          VaultEntryData.file(
            FileEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: _selectedFolder,
              filename: _pickedFilename!,
              data: _pickedFileBytes!,
              notes: _fileNotesController.text.isEmpty
                  ? null
                  : _fileNotesController.text,
              customFields: _fileCustomFields
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

      case 'Custom':
        await widget.onCreateEntry(
          VaultEntryData.custom(
            CustomEntryData(
              id: '',
              createdAt: '',
              updatedAt: '',
              folder: _selectedFolder,
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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle(l)),
        actions: [
          if (_isEditing)
            TextButton(onPressed: _review, child: Text(l.reviewArrow)),
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
                ..._buildFields(l),
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
                        : Text(l.save),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _screenTitle(AppLocalizations l) {
    final type = switch (widget.entryType) {
      'Login' => l.entryTypePassword,
      'Note' => l.entryTypeNote,
      'Identity' => l.entryTypeIdentity,
      'Card' => l.entryTypeCard,
      'File' => l.entryTypeFile,
      'Custom' => l.entryTypeCustom,
      _ => widget.entryType,
    };
    return _isEditing ? l.editEntryTitle(type) : l.createEntryTitle(type);
  }

  List<Widget> _buildFields(AppLocalizations l) {
    return switch (widget.entryType) {
      'Login' => _loginFields(l),
      'Note' => _noteFields(l),
      'Identity' => _identityFields(l),
      'Card' => _cardFields(l),
      'File' => _fileFields(l),
      'Custom' => _customEntryFields(l),
      _ => [Text(l.entryTypeNotSupported)],
    };
  }

  // ── Login fields ─────────────────────────────────────────────────────────────

  List<Widget> _loginFields(AppLocalizations l) => [
    _folderPicker(),
    const SizedBox(height: 12),
    TextFormField(
      controller: _loginTitleController,
      focusNode: _loginTitleFocus,
      autofocus: true,
      decoration: InputDecoration(
        labelText: l.fieldTitle,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? l.validatorTitleRequired : null,
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_urlFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _urlController,
      focusNode: _urlFocus,
      decoration: InputDecoration(
        labelText: l.fieldUrl,
        border: const OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_usernameFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _usernameController,
      focusNode: _usernameFocus,
      decoration: InputDecoration(
        labelText: l.fieldUsername,
        border: const OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _loginEmailController,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: l.fieldEmail,
        border: const OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      obscureText: _passwordObscured,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: l.fieldPassword,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _passwordObscured ? Icons.visibility_off : Icons.visibility,
          ),
          tooltip: _passwordObscured ? l.tooltipShow : l.tooltipHide,
          onPressed: () =>
              setState(() => _passwordObscured = !_passwordObscured),
        ),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? l.validatorPasswordRequired : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_loginNotesFocus),
    ),
    Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: const Key('open_generator_button'),
        icon: const Icon(Icons.auto_fix_high, size: 18),
        label: Text(l.generate),
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
              builder: (ctx) => Scaffold(
                appBar: AppBar(title: Text(AppLocalizations.of(ctx).generatorTitle)),
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
      l.fieldNotes,
      focusNode: _loginNotesFocus,
      maxLines: 3,
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _appIdController,
      decoration: InputDecoration(
        labelText: l.fieldAndroidAppId,
        helperText: l.fieldAndroidAppIdHelper,
        helperMaxLines: 4,
        border: const OutlineInputBorder(),
      ),
    ),
    if (_recentApps.isNotEmpty) ...[
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          l.recentlyUsedApps,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final pkg in _recentApps)
            ActionChip(
              label: Text(pkg),
              onPressed: () => setState(() => _appIdController.text = pkg),
            ),
        ],
      ),
    ],
    const SizedBox(height: 16),
    _customFieldsSection(
      fields: _loginCustomFields,
      onAdd: () =>
          setState(() => _loginCustomFields.add(_CustomFieldState.empty())),
      onRemove: (i) => setState(() {
        _loginCustomFields[i].dispose();
        _loginCustomFields.removeAt(i);
      }),
      onToggleHidden: (i) => setState(
        () => _loginCustomFields[i].hidden = !_loginCustomFields[i].hidden,
      ),
    ),
  ];

  // ── Note fields ──────────────────────────────────────────────────────────────

  List<Widget> _noteFields(AppLocalizations l) => [
    _folderPicker(),
    const SizedBox(height: 12),
    TextFormField(
      controller: _titleController,
      focusNode: _noteTitleFocus,
      autofocus: true,
      decoration: InputDecoration(
        labelText: l.fieldTitle,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? l.validatorTitleRequired : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_noteContentFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _contentController,
      focusNode: _noteContentFocus,
      maxLines: 6,
      decoration: InputDecoration(
        labelText: l.fieldContent,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? l.validatorContentRequired : null,
    ),
    const SizedBox(height: 16),
    _customFieldsSection(
      fields: _noteCustomFields,
      onAdd: () =>
          setState(() => _noteCustomFields.add(_CustomFieldState.empty())),
      onRemove: (i) => setState(() {
        _noteCustomFields[i].dispose();
        _noteCustomFields.removeAt(i);
      }),
      onToggleHidden: (i) => setState(
        () => _noteCustomFields[i].hidden = !_noteCustomFields[i].hidden,
      ),
    ),
  ];

  // ── Identity fields ──────────────────────────────────────────────────────────

  List<Widget> _identityFields(AppLocalizations l) => [
    _folderPicker(),
    const SizedBox(height: 12),
    TextFormField(
      controller: _firstNameController,
      focusNode: _firstNameFocus,
      autofocus: true,
      decoration: InputDecoration(
        labelText: l.fieldFirstName,
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? l.validatorFirstNameRequired : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_lastNameFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _lastNameController,
      focusNode: _lastNameFocus,
      decoration: InputDecoration(
        labelText: l.fieldLastName,
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? l.validatorLastNameRequired : null,
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _emailController,
      focusNode: _emailFocus,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: l.fieldEmail,
        border: const OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _phoneController,
      focusNode: _phoneFocus,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: l.fieldPhone,
        border: const OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_addressFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _addressController,
      focusNode: _addressFocus,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: l.fieldAddress,
        border: const OutlineInputBorder(),
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

  List<Widget> _cardFields(AppLocalizations l) => [
    _folderPicker(),
    const SizedBox(height: 12),
    TextFormField(
      controller: _cardNameController,
      focusNode: _cardNameFocus,
      autofocus: true,
      decoration: InputDecoration(
        labelText: l.fieldCardLabel,
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? l.validatorCardLabelRequired : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_cardholderNameFocus),
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(
      initialValue: _cardStatuses.contains(_cardStatusController.text)
          ? _cardStatusController.text
          : 'active',
      decoration: InputDecoration(
        labelText: l.fieldCardStatus,
        border: const OutlineInputBorder(),
      ),
      items: _cardStatuses.map((s) => DropdownMenuItem<String>(
        value: s,
        child: Text(_localizeCardStatus(s, l)),
      )).toList(),
      onChanged: (v) =>
          setState(() => _cardStatusController.text = v ?? 'active'),
      validator: (v) =>
          (v == null || v.isEmpty) ? l.validatorStatusRequired : null,
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _cardholderNameController,
      focusNode: _cardholderNameFocus,
      decoration: InputDecoration(
        labelText: l.fieldCardholderName,
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? l.validatorCardholderRequired : null,
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_cardNumberFocus),
    ),
    const SizedBox(height: 12),
    _dropdownField(
      label: l.fieldPaymentNetwork,
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
      decoration: InputDecoration(
        labelText: l.fieldCardNumber,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return l.validatorCardNumberRequired;
        if (v.length < 6 || v.length > 19) {
          return l.validatorCardNumberLength;
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
            decoration: InputDecoration(
              labelText: l.fieldExpiry,
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return l.validatorExpiryRequired;
              final pattern = RegExp(r'^\d{2}/\d{2}$');
              if (!pattern.hasMatch(v)) return l.validatorExpiryFormat;
              final month = int.tryParse(v.substring(0, 2));
              if (month == null || month < 1 || month > 12) {
                return l.validatorExpiryMonth;
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
              labelText: l.fieldCvv,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _cvvObscured ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: _cvvObscured ? l.tooltipShow : l.tooltipHide,
                onPressed: () => setState(() => _cvvObscured = !_cvvObscured),
              ),
            ),
            validator: (v) {
              if (v != null && v.isNotEmpty && (v.length < 3 || v.length > 4)) {
                return l.validatorCvvLength;
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
        labelText: l.fieldCardPin,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _pinObscured ? Icons.visibility_off : Icons.visibility,
          ),
          tooltip: _pinObscured ? l.tooltipShowPin : l.tooltipHidePin,
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
      decoration: InputDecoration(
        labelText: l.fieldCreditLimit,
        border: const OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) =>
          FocusScope.of(context).requestFocus(_cardAccountNumberFocus),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _cardAccountNumberController,
      focusNode: _cardAccountNumberFocus,
      decoration: InputDecoration(
        labelText: l.fieldAccountNumber,
        border: const OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) => _save(),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _cardNotesController,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: l.fieldNotes,
        border: const OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),
    _customFieldsSection(
      fields: _cardCustomFields,
      onAdd: () =>
          setState(() => _cardCustomFields.add(_CustomFieldState.empty())),
      onRemove: (i) => setState(() {
        _cardCustomFields[i].dispose();
        _cardCustomFields.removeAt(i);
      }),
      onToggleHidden: (i) => setState(
        () => _cardCustomFields[i].hidden = !_cardCustomFields[i].hidden,
      ),
    ),
  ];

  // ── File fields ──────────────────────────────────────────────────────────────

  List<Widget> _fileFields(AppLocalizations l) => [
    _folderPicker(),
    const SizedBox(height: 12),
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
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          l.noFileSelected,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
    OutlinedButton.icon(
      onPressed: _pickFile,
      icon: const Icon(Icons.folder_open_outlined),
      label: Text(l.pickFile),
    ),
    const SizedBox(height: 12),
    _optionalTextField(_fileNotesController, l.fieldNotes, maxLines: 3),
    const SizedBox(height: 16),
    _customFieldsSection(
      fields: _fileCustomFields,
      onAdd: () =>
          setState(() => _fileCustomFields.add(_CustomFieldState.empty())),
      onRemove: (i) => setState(() {
        _fileCustomFields[i].dispose();
        _fileCustomFields.removeAt(i);
      }),
      onToggleHidden: (i) => setState(
        () => _fileCustomFields[i].hidden = !_fileCustomFields[i].hidden,
      ),
    ),
  ];

  Future<void> _pickFile() async {
    final PickedFile? f;
    try {
      f = await runPicker(widget.pickFile);
    } on FilePickerUnavailable {
      if (mounted) showPickerUnavailable(context, hasManualEntry: false);
      return;
    }
    if (f == null || f.bytes == null) return;
    setState(() {
      _pickedFilename = f!.name;
      _pickedFileBytes = f.bytes;
    });
  }

  // ── Custom entry fields ──────────────────────────────────────────────────────

  List<Widget> _customEntryFields(AppLocalizations l) => [
    _folderPicker(),
    const SizedBox(height: 12),
    TextFormField(
      controller: _customTitleController,
      focusNode: _customTitleFocus,
      autofocus: true,
      decoration: InputDecoration(
        labelText: l.fieldTitle,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.isEmpty) ? l.validatorTitleRequired : null,
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
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fields.isNotEmpty)
          Text(l.fieldCustomFields, style: Theme.of(context).textTheme.titleSmall),
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
                    decoration: InputDecoration(
                      labelText: l.fieldLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? l.validatorLabelRequired : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: f.valueController,
                    obscureText: f.hidden,
                    decoration: InputDecoration(
                      labelText: l.fieldValue,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          f.hidden ? Icons.visibility_off : Icons.visibility,
                        ),
                        tooltip: f.hidden ? l.tooltipShowValue : l.tooltipHideValue,
                        onPressed: () => onToggleHidden(i),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: l.tooltipRemoveField,
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(l.addCustomField),
        ),
      ],
    );
  }

  // ── Field helpers ────────────────────────────────────────────────────────────

  Widget _folderPicker() {
    final l = AppLocalizations.of(context);
    // Build a deduplicated items list that always contains the current value.
    final folderSet = <String>{..._folders};
    if (_selectedFolder.isNotEmpty) folderSet.add(_selectedFolder);
    final folderItems = folderSet.toList()..sort();
    return DropdownButtonFormField<String>(
      initialValue: _selectedFolder,
      decoration: InputDecoration(
        labelText: l.fieldFolder,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(value: '', child: Text(l.noFolder)),
        ...folderItems.map((f) => DropdownMenuItem(value: f, child: Text(f))),
      ],
      onChanged: (v) => setState(() => _selectedFolder = v ?? ''),
    );
  }

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
        labelText: label,
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

// ── Card status localization ─────────────────────────────────────────────────

String _localizeCardStatus(String status, AppLocalizations l) => switch (status) {
  'active' => l.cardStatusActive,
  'lapsed' => l.cardStatusLapsed,
  'inactive' => l.cardStatusInactive,
  _ => status,
};

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
