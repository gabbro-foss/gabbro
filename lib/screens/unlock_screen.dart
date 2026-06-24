import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';
import 'package:gabbro/widgets/segmented_row.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';

// ── Bridge defaults ───────────────────────────────────────────────────────────

// Public so the autofill unlock shell can reuse it as its injectable default.
Future<void> defaultUnlock(List<int> passphrase, String path) =>
    unlockVault(passphrase: passphrase, path: path);

// R-03: probe whether the vault file parses at all. Only a parse failure may
// surface the restore offer — authentication failures never do.
Future<bool> _defaultVaultIsReadable(String path) async {
  try {
    readVaultHeader(path: path);
    return true;
  } on StateError {
    // Bridge not initialized (widget-test context, or a startup race): we
    // cannot probe, and "cannot probe" must never masquerade as "corrupt" —
    // report healthy so the restore banner cannot appear by accident.
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _defaultBackupUsable(String path) async {
  try {
    return await vaultBackupUsable(path: path);
  } on StateError {
    return false;
  }
}

Future<void> _defaultRestoreBackup(String path) => restoreVaultBackup(path: path);

// R-03: let the user pick their own off-device backup `.gabbro` and restore it
// over the corrupt vault. Returns false if the user cancelled the picker.
// `file_picker` copies the chosen file to an app-readable path on Android too,
// so the same path-based restore works on every platform.
Future<bool> _defaultRestoreFromFile(String vaultPath) async {
  final result = await runPicker(
    () => FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gabbro'],
    ),
  );
  final source = result?.files.single.path;
  if (source == null) return false; // cancelled
  await restoreVaultFromFile(path: vaultPath, source: source);
  return true;
}

EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

const _biometricChannel = MethodChannel('app.gabbro.gabbro/biometric');

Future<void> _defaultCancelTap() => cancelYubikeyTap();

Future<bool> _defaultBiometricIsEnrolled(String vaultPath) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _biometricChannel.invokeMethod<bool>(
          'isEnrolled', {'vaultPath': vaultPath}) ??
        false;
  } catch (_) {
    return false;
  }
}

Future<List<int>?> _defaultBiometricAuthenticate(String vaultPath) async {
  try {
    final bytes = await _biometricChannel.invokeMethod<Uint8List>(
      'authenticate', {'vaultPath': vaultPath},
    );
    return bytes?.toList();
  } on PlatformException catch (e) {
    if (e.code == 'BIOMETRIC_INVALIDATED') rethrow;
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> _defaultUnlockWithYubikey(
  List<int> passphrase,
  List<int> credentialId,
  List<int> hkdfSalt,
  String pin,
  String path,
  String transport,
) async {
  final hmacSecret = await getYubikeyHmacSecret(
    credentialId: credentialId,
    salt: hkdfSalt,
    pin: pin,
    transport: transport,
  );
  await unlockVaultWithYubikey(
    passphrase: passphrase,
    hmacSecret: hmacSecret,
    credentialId: credentialId,
    hkdfSalt: hkdfSalt,
    path: path,
  );
}

Future<void> _defaultUnlockWithAnyYubikey(
  List<int> passphrase,
  List<YubikeyRecordData> records,
  String pin,
  String path,
  String transport,
) async {
  final match = await getAnyYubikeyHmacSecret(
    records: records,
    pin: pin,
    transport: transport,
  );

  // Find the matching record to retrieve the correct hkdfSalt.
  final matchedRecord = records.firstWhere(
    (r) => _listEqual(r.credentialId, match.credentialId),
  );

  await unlockVaultWithYubikey(
    passphrase: passphrase,
    hmacSecret: match.hmac,
    credentialId: match.credentialId,
    hkdfSalt: matchedRecord.salt,
    path: path,
  );
}

bool _listEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── Widget ────────────────────────────────────────────────────────────────────

class UnlockScreen extends StatefulWidget {
  final String vaultPath;
  final Future<void> Function(List<int> passphrase, String path) onUnlock;

  /// Called after a successful unlock instead of navigating to VaultListScreen.
  /// The autofill activity sets this to signal the native side to build the
  /// fill response. Null (the default) keeps the in-app behaviour: navigate.
  final Future<void> Function()? onUnlocked;

  final EntropyResult Function(String password) onEstimateEntropy;
  final bool blockPassphraseCopyPaste;

  /// Pre-injected YubiKey records. `null` = auto-detect from vault file at
  /// construction time. Pass `[]` to force passphrase-only mode (tests).
  final List<YubikeyRecordData>? yubikeyRecords;

  final Future<void> Function(
    List<int> passphrase,
    List<int> credentialId,
    List<int> hkdfSalt,
    String pin,
    String path,
    String transport,
  ) onUnlockWithYubikey;

  /// Called when the vault has 2+ YubiKey records. Sends all records in one
  /// FIDO2 assertion call (one tap regardless of which key is inserted).
  final Future<void> Function(
    List<int> passphrase,
    List<YubikeyRecordData> records,
    String pin,
    String path,
    String transport,
  ) onUnlockWithAnyYubikey;

  /// Vault alias shown below the app title. Null = no alias displayed.
  final String? vaultAlias;

  /// Registry used to populate the vault dropdown. When it holds 2+ vaults the
  /// login screen shows an inline switcher above the passphrase field (ADR-014:
  /// the login screen always lists registered vaults).
  final VaultRegistry? registry;

  /// Called when the user selects a different vault from the dropdown.
  /// Null → falls back to GabbroApp.maybeOf(context)?.switchToVault(…).
  final void Function(String path, String alias)? onVaultSwitch;

  /// Whether biometric unlock is enabled in settings (from AppSettings.biometricUnlock).
  final bool biometricEnabled;

  /// Returns true if a biometric credential is stored for [vaultPath].
  final Future<bool> Function(String vaultPath) onBiometricIsEnrolled;

  /// Performs biometric authentication and returns the decrypted passphrase
  /// bytes for [vaultPath], or null if cancelled. Throws PlatformException
  /// with code 'BIOMETRIC_INVALIDATED' if the Keystore key was invalidated.
  final Future<List<int>?> Function(String vaultPath) onBiometricAuthenticate;

  /// Called when a BIOMETRIC_INVALIDATED error is received so the parent can
  /// save biometricUnlock: false to settings.
  final void Function()? onBiometricInvalidated;

  /// Aborts an in-flight YubiKey tap when the user presses Cancel.
  final Future<void> Function() onCancelTap;

  /// null = use Platform.isAndroid at runtime; set to true/false in tests.
  /// Gates the Cancel-during-tap button (a stalled tap can only be aborted on
  /// Android; the Linux FFI tap is not interruptible from here).
  final bool? isAndroid;

  /// R-03: returns false when the vault file cannot be parsed (corruption).
  /// Only this — never an authentication failure — can surface the restore
  /// offer.
  final Future<bool> Function(String path) onVaultIsReadable;

  /// R-03 P3: whether a *usable* (present and parseable) `.bak` safety copy
  /// exists next to the vault. A `.bak` that does not parse reports false, so
  /// the restore offer can never advertise a backup a restore would refuse.
  final Future<bool> Function(String path) onBackupUsable;

  /// R-03: replace the corrupt vault file with its `.bak` safety copy.
  /// Explicit user action; the restored vault still demands full credentials.
  final Future<void> Function(String path) onRestoreBackup;

  /// R-03: pick an external backup `.gabbro` and restore it over the corrupt
  /// vault. Returns true if a file was picked and restored, false if cancelled.
  /// Throws if the picked file is not a usable vault.
  final Future<bool> Function(String vaultPath) onRestoreFromFile;

  /// R-03 P5: remove an unrecoverable vault from the list, leaving the bytes on
  /// disk. Null → routes through GabbroApp.removeVault(deleteFiles: false).
  final Future<void> Function(String path)? onRemoveVaultFromList;

  /// R-03 P5: delete an unrecoverable vault's file and its `.bak` from disk.
  /// Null → routes through GabbroApp.removeVault(deleteFiles: true).
  final Future<void> Function(String path)? onDeleteVaultFile;

  const UnlockScreen({
    super.key,
    required this.vaultPath,
    this.onUnlock = defaultUnlock,
    this.onUnlocked,
    this.onEstimateEntropy = _defaultEstimateEntropy,
    this.blockPassphraseCopyPaste = true,
    this.yubikeyRecords,
    this.onUnlockWithYubikey = _defaultUnlockWithYubikey,
    this.onUnlockWithAnyYubikey = _defaultUnlockWithAnyYubikey,
    this.vaultAlias,
    this.registry,
    this.onVaultSwitch,
    this.biometricEnabled = false,
    this.onBiometricIsEnrolled = _defaultBiometricIsEnrolled,
    this.onBiometricAuthenticate = _defaultBiometricAuthenticate,
    this.onBiometricInvalidated,
    this.onCancelTap = _defaultCancelTap,
    this.isAndroid,
    this.onVaultIsReadable = _defaultVaultIsReadable,
    this.onBackupUsable = _defaultBackupUsable,
    this.onRestoreBackup = _defaultRestoreBackup,
    this.onRestoreFromFile = _defaultRestoreFromFile,
    this.onRemoveVaultFromList,
    this.onDeleteVaultFile,
  });

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with WidgetsBindingObserver {
  final _passphraseController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscured = true;
  bool _pinObscured = true;
  bool _isUnlocking = false;
  String _transport = 'usb';
  String? _errorMessage;
  EntropyResult? _entropy;
  late List<YubikeyRecordData> _yubikeyRecords;
  late String _selectedPath;
  bool _biometricEnrolled = false;
  // R-03 restore flow: set only by the parse probe, never by auth failures.
  bool _vaultCorrupt = false;
  bool _backupAvailable = false;
  bool _backupRestored = false;
  bool _vaultRestoredFromFile = false;

  bool get _isYubikeyMode => _yubikeyRecords.isNotEmpty;

  bool get _showDropdown =>
      widget.registry != null && widget.registry!.records.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _yubikeyRecords = widget.yubikeyRecords ?? _detectYubikeyRecords();
    _selectedPath = widget.vaultPath;
    _probeVault();
    if (widget.biometricEnabled) {
      widget.onBiometricIsEnrolled(widget.vaultPath).then((enrolled) {
        if (mounted) setState(() => _biometricEnrolled = enrolled);
      });
    }
  }

  List<YubikeyRecordData> _detectYubikeyRecords() {
    try {
      return listVaultYubikeyRecords(path: widget.vaultPath);
    } catch (_) {
      return [];
    }
  }

  // R-03: surface the restore offer only when the vault file itself cannot
  // be parsed. Wrong passphrase / wrong PIN / wrong or absent YubiKey all
  // leave this untouched.
  Future<void> _probeVault() async {
    final readable = await widget.onVaultIsReadable(widget.vaultPath);
    if (readable) return;
    final usable = await widget.onBackupUsable(widget.vaultPath);
    if (!mounted) return;
    setState(() {
      _vaultCorrupt = true;
      _backupAvailable = usable;
    });
  }

  Future<void> _confirmRestoreBackup() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.restoreBackupConfirmTitle),
        content: Text(l.restoreBackupConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.restoreBackupConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.onRestoreBackup(widget.vaultPath);
    } catch (e) {
      if (!mounted) return;
      // The .bak rotted between the usability probe and this restore (rare
      // race). It is no longer usable, so drop to the unrecoverable state
      // (remove-from-list / delete-file) rather than offering restore again.
      setState(() {
        _backupAvailable = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _vaultCorrupt = false;
      _backupRestored = true;
      _errorMessage = null;
      // The restored file may carry a different credential set than the
      // unreadable one suggested: re-detect YubiKey records.
      if (widget.yubikeyRecords == null) {
        _yubikeyRecords = _detectYubikeyRecords();
      }
    });
  }

  // R-03: restore the corrupt vault from an external backup file the user picks
  // (their off-device 3-2-1 copy). The bridge refuses a file that is not a
  // usable vault, so a corrupt vault is never replaced by another bad file.
  Future<void> _restoreFromFile() async {
    final l = AppLocalizations.of(context);
    final bool restored;
    try {
      restored = await widget.onRestoreFromFile(widget.vaultPath);
    } on FilePickerUnavailable {
      // The file dialog couldn't open (no portal) - not an invalid vault.
      if (!mounted) return;
      showPickerUnavailable(context, hasManualEntry: false);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l.restoreFromFileInvalidError);
      return;
    }
    if (!mounted || !restored) return; // user cancelled the picker
    setState(() {
      _vaultCorrupt = false;
      _backupAvailable = false;
      _vaultRestoredFromFile = true;
      _errorMessage = null;
      // The restored file may carry a different credential set: re-detect.
      if (widget.yubikeyRecords == null) {
        _yubikeyRecords = _detectYubikeyRecords();
      }
    });
  }

  // R-03 P5: remove an unrecoverable vault from the list, leaving its bytes on
  // disk (the user may yet recover them off-device).
  Future<void> _confirmRemoveFromList() async {
    final l = AppLocalizations.of(context);
    // Capture the app before the dialog await so no BuildContext is used across
    // the async gap.
    final app = GabbroApp.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeVaultFromListConfirmTitle),
        content: Text(l.removeVaultFromListConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.removeVaultFromListButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final cb = widget.onRemoveVaultFromList;
    if (cb != null) {
      await cb(widget.vaultPath);
    } else {
      await app?.removeVault(widget.vaultPath, deleteFiles: false);
    }
  }

  // R-03 P5: permanently delete an unrecoverable vault's file and its .bak.
  Future<void> _confirmDeleteVaultFile() async {
    final l = AppLocalizations.of(context);
    // Capture the app before the dialog await (no BuildContext across the gap).
    final app = GabbroApp.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteVaultFileConfirmTitle),
        content: Text(l.deleteVaultFileConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.deleteVaultFileButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final cb = widget.onDeleteVaultFile;
    if (cb != null) {
      await cb(widget.vaultPath);
    } else {
      await app?.removeVault(widget.vaultPath, deleteFiles: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passphraseController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // R-03: a vault can be corrupted while the app is backgrounded on its unlock
  // screen. Re-probe on resume so the corruption banner appears on return,
  // rather than only after an unlock attempt (P2) or a vault re-mount.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _probeVault();
    }
  }

  void _onDropdownChanged(String? path) {
    if (path == null || path == _selectedPath) return;
    final record =
        widget.registry!.records.firstWhere((r) => r.path == path);
    // Biometric is enrolled for the original vault's passphrase only.
    // Hide the button when the user switches to a different vault.
    setState(() {
      _selectedPath = path;
      _biometricEnrolled = false;
    });
    if (widget.onVaultSwitch != null) {
      widget.onVaultSwitch!(record.path, record.alias);
    } else {
      GabbroApp.maybeOf(context)?.switchToVault(record.path, record.alias);
    }
  }

  Future<void> _unlock() async {
    setState(() { _isUnlocking = true; _errorMessage = null; });
    try {
      await _doUnlock(_passphraseController.text.codeUnits);
    } finally {
      if (mounted) setState(() => _isUnlocking = false);
    }
  }

  Future<void> _unlockWithBiometrics() async {
    final l = AppLocalizations.of(context);
    setState(() { _isUnlocking = true; _errorMessage = null; });
    try {
      final passphrase = await widget.onBiometricAuthenticate(widget.vaultPath);
      if (!mounted) return;
      if (passphrase == null) {
        setState(() => _errorMessage = l.biometricCancelled);
        return;
      }
      await _doUnlock(passphrase);
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'BIOMETRIC_INVALIDATED') {
        setState(() {
          _biometricEnrolled = false;
          _errorMessage = l.biometricInvalidated;
        });
        widget.onBiometricInvalidated?.call();
      } else {
        setState(() => _errorMessage = l.biometricCancelled);
      }
    } finally {
      if (mounted) setState(() => _isUnlocking = false);
    }
  }

  Future<void> _doUnlock(List<int> passphrase) async {
    final l = AppLocalizations.of(context);
    try {
      if (_isYubikeyMode) {
        if (_yubikeyRecords.length == 1) {
          // Single-key path: one credential ID, one tap.
          final record = _yubikeyRecords.first;
          await widget.onUnlockWithYubikey(
            passphrase,
            record.credentialId,
            record.salt,
            _pinController.text,
            widget.vaultPath,
            _transport,
          );
        } else {
          // Multi-key path: all records in one FIDO2 assertion, one tap.
          await widget.onUnlockWithAnyYubikey(
            passphrase,
            _yubikeyRecords,
            _pinController.text,
            widget.vaultPath,
            _transport,
          );
        }
      } else {
        await widget.onUnlock(passphrase, widget.vaultPath);
      }
    } catch (e) {
      if (!mounted) return;
      // The user cancelled the tap: just drop back to the unlock form, no error.
      if (e is PlatformException && e.code == 'TAP_CANCELLED') return;
      // R-03 P2: re-probe before showing a generic auth error. If the vault
      // file itself became unreadable (e.g. corrupted while this screen was
      // mounted), surface the corruption banner instead of "check your
      // passphrase" — which would mislead and offer no way forward. A wrong
      // passphrase / PIN / key leaves the file readable, so the probe returns
      // readable and the generic error still shows (auth-failure invariant).
      final stillReadable = await widget.onVaultIsReadable(widget.vaultPath);
      if (!mounted) return;
      if (!stillReadable) {
        final usable = await widget.onBackupUsable(widget.vaultPath);
        if (!mounted) return;
        setState(() {
          _vaultCorrupt = true;
          _backupAvailable = usable;
          _errorMessage = null;
        });
        return;
      }
      setState(() {
        _errorMessage = switch (e) {
          PlatformException(code: 'TRANSPORT_ERROR') =>
            e.message ?? l.transportError,
          // A stalled tap that timed out means no key was presented; reuse the
          // no-device message (Kotlin supplies a precise message via e.message).
          PlatformException(code: 'TAP_TIMEOUT' || 'NO_FIDO2_DEVICE') =>
            e.message ?? l.noFidoDeviceFound,
          _ => _isYubikeyMode
              ? l.unlockErrorPassphraseAndPin
              : l.unlockErrorPassphrase,
        };
      });
      return;
    }
    // ── Unlock succeeded ── The post-success work below is NOT inside the auth
    // try/catch, so a failure here can never be reported as an authentication
    // error (e.g. the autofill onUnlocked signaling failing must not read as a
    // wrong passphrase).
    if (!mounted) return;
    GabbroApp.maybeOf(context)?.touchVaultLastUsed(widget.vaultPath);
    if (widget.onUnlocked != null) {
      // Autofill activity supplies onUnlocked to signal the native side (build
      // the fill response) instead of opening the vault list. Its failure is its
      // own concern, never an unlock error.
      try {
        await widget.onUnlocked!();
      } catch (_) {
        // Post-unlock signaling failed; nothing to surface as an auth error.
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => VaultListScreen(
            vaultPath: widget.vaultPath,
            vaultAlias: widget.vaultAlias,
          ),
        ),
      );
    }
  }

  Color _tierColor(StrengthTier tier) => switch (tier) {
        StrengthTier.terrible => Colors.red,
        StrengthTier.weak => Colors.orange,
        StrengthTier.fair => Colors.yellow.shade700,
        StrengthTier.strong => Colors.lightGreen,
        StrengthTier.veryStrong => Colors.green,
        StrengthTier.centuries => Colors.green.shade800,
      };

  String _tierLabel(StrengthTier tier, AppLocalizations l) => switch (tier) {
        StrengthTier.terrible => l.strengthTierTerrible,
        StrengthTier.weak => l.strengthTierWeak,
        StrengthTier.fair => l.strengthTierFair,
        StrengthTier.strong => l.strengthTierStrong,
        StrengthTier.veryStrong => l.strengthTierVeryStrong,
        StrengthTier.centuries => l.strengthTierExcellent,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final onAndroid = widget.isAndroid ?? Platform.isAndroid;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    Center(child: GabbroLogo(withText: true, width: 200)),
                    if (widget.vaultAlias != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.vaultAlias!,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _isYubikeyMode
                          ? l.unlockEnterPassphraseAndPin
                          : l.unlockEnterPassphrase,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    if (_biometricEnrolled && !_vaultCorrupt) ...[
                      if (_isYubikeyMode)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            AppLocalizations.of(context).biometricYubikeyHint,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _isUnlocking ? null : _unlockWithBiometrics,
                        icon: const Icon(Icons.fingerprint),
                        label: Text(AppLocalizations.of(context).useBiometrics),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // R-03: corruption banner + explicit recovery flow. Shown
                    // only when the parse probe failed, never on auth errors.
                    // State A: a usable .bak exists -> offer restore.
                    // State B: no usable .bak -> the vault is unrecoverable on
                    // this device; offer remove-from-list / delete-file so the
                    // user is never stranded (responsive buttons that stack on
                    // narrow Android screens rather than overflowing).
                    if (_vaultCorrupt) ...[
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _backupAvailable
                              ? Column(
                                  children: [
                                    Text(
                                      l.vaultCorruptBackupAvailable,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                      onPressed: _confirmRestoreBackup,
                                      icon: const Icon(
                                        Icons.settings_backup_restore,
                                      ),
                                      label: Text(l.restoreBackupButton),
                                    ),
                                    TextButton.icon(
                                      onPressed: _restoreFromFile,
                                      icon: const Icon(Icons.folder_open),
                                      label: Text(l.restoreFromFileButton),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Text(
                                      l.vaultUnrecoverableBody,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l.vaultUnrecoverableBackupHint,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      onAndroid
                                          ? l.vaultUnrecoverableNoteAndroid
                                          : l.vaultUnrecoverableNoteLinux,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    // Primary recovery: restore from the user's
                                    // own off-device backup file.
                                    FilledButton.icon(
                                      onPressed: _restoreFromFile,
                                      icon: const Icon(Icons.folder_open),
                                      label: Text(l.restoreFromFileButton),
                                    ),
                                    const SizedBox(height: 8),
                                    // Secondary "give up" actions. "Remove from
                                    // list" keeps the file on disk — only useful
                                    // where the user can reach it (desktop); on
                                    // Android app-private storage it would orphan
                                    // an unreachable file, so offer only "Delete
                                    // file" there.
                                    OverflowBar(
                                      alignment: MainAxisAlignment.center,
                                      overflowAlignment:
                                          OverflowBarAlignment.center,
                                      spacing: 8,
                                      overflowSpacing: 8,
                                      children: [
                                        if (!onAndroid)
                                          OutlinedButton.icon(
                                            onPressed: _confirmRemoveFromList,
                                            icon: const Icon(
                                              Icons.playlist_remove,
                                            ),
                                            label: Text(
                                              l.removeVaultFromListButton,
                                            ),
                                          ),
                                        OutlinedButton.icon(
                                          onPressed: _confirmDeleteVaultFile,
                                          icon: const Icon(Icons.delete_forever),
                                          label: Text(l.deleteVaultFileButton),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Restore failures (bad file / rotted .bak) surface here,
                      // since the normal error line lives in the hidden controls.
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                    if (_backupRestored) ...[
                      Text(
                        l.backupRestoredMessage,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_vaultRestoredFromFile) ...[
                      Text(
                        l.vaultRestoredMessage,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_showDropdown) ...[
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedPath,
                        items: widget.registry!.records
                            .map(
                              (r) => DropdownMenuItem(
                                value: r.path,
                                child: Text(r.alias),
                              ),
                            )
                            .toList(),
                        onChanged: _onDropdownChanged,
                      ),
                      const SizedBox(height: 16),
                    ],
                    // R-03: the vault cannot be opened — hide the unlock
                    // controls until it is restored. The vault dropdown above
                    // stays visible so the user can switch to another vault.
                    if (!_vaultCorrupt) ...[
                    TextField(
                      controller: _passphraseController,
                      autofocus: true,
                      obscureText: _obscured,
                      enableInteractiveSelection:
                          !widget.blockPassphraseCopyPaste,
                      onSubmitted: (_) => _isUnlocking ? null : _unlock(),
                      onChanged: (v) => setState(
                        () => _entropy = widget.onEstimateEntropy(v),
                      ),
                      decoration: InputDecoration(
                        labelText: l.passphraseLabel,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscured
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          tooltip: _obscured ? l.tooltipShow : l.tooltipHide,
                          onPressed: () =>
                              setState(() => _obscured = !_obscured),
                        ),
                      ),
                    ),
                    if (_entropy != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: switch (_entropy!.tier) {
                          StrengthTier.terrible => 0.1,
                          StrengthTier.weak => 0.25,
                          StrengthTier.fair => 0.5,
                          StrengthTier.strong => 0.75,
                          StrengthTier.veryStrong => 0.9,
                          StrengthTier.centuries => 1.0,
                        },
                        color: _tierColor(_entropy!.tier),
                        backgroundColor: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.unlockEntropyDisplay(
                          _tierLabel(_entropy!.tier, l),
                          _entropy!.bits.toStringAsFixed(1),
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: _tierColor(_entropy!.tier),
                        ),
                      ),
                    ],
                    if (_isYubikeyMode) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinController,
                        obscureText: _pinObscured,
                        enableInteractiveSelection:
                            !widget.blockPassphraseCopyPaste,
                        decoration: InputDecoration(
                          labelText: l.yubiKeyPinLabel,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _pinObscured
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            tooltip: _pinObscured
                                ? l.tooltipShowPin
                                : l.tooltipHidePin,
                            onPressed: () =>
                                setState(() => _pinObscured = !_pinObscured),
                          ),
                        ),
                      ),
                      // USB vs NFC is an Android-only choice: desktop (Linux)
                      // uses libfido2 over USB only, no NFC path. Gated on the
                      // injectable `onAndroid` seam so the selector is testable.
                      if (onAndroid) ...[
                        const SizedBox(height: 12),
                        SegmentedRow<String>(
                          values: const ['usb', 'nfc'],
                          selected: _transport,
                          label: (v) => v.toUpperCase(),
                          onSelected: (v) => setState(() => _transport = v),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        l.insertYubiKeyAndTap,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isUnlocking ? null : _unlock,
                      child: _isUnlocking
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l.unlock),
                    ),
                    // While a YubiKey tap is in flight on Android, offer an
                    // explicit Cancel so a stalled tap (no key presented) does
                    // not strand the user on an endless spinner.
                    if (_isUnlocking && _isYubikeyMode && onAndroid) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: widget.onCancelTap,
                        child: Text(l.cancel),
                      ),
                    ],
                    ], // end: unlock controls hidden while _vaultCorrupt
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
