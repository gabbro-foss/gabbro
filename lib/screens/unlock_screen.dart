import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';
import 'package:gabbro/widgets/segmented_row.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';

// ── Bridge defaults ───────────────────────────────────────────────────────────

Future<void> _defaultUnlock(List<int> passphrase, String path) =>
    unlockVault(passphrase: passphrase, path: path);

EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

const _biometricChannel = MethodChannel('app.gabbro.gabbro/biometric');

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

  /// Registry used to populate the vault dropdown when [showVaultList] is true.
  final VaultRegistry? registry;

  /// When true and [registry] has 2+ vaults, shows an inline dropdown above
  /// the passphrase field so the user can pick which vault to unlock.
  final bool showVaultList;

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

  const UnlockScreen({
    super.key,
    required this.vaultPath,
    this.onUnlock = _defaultUnlock,
    this.onEstimateEntropy = _defaultEstimateEntropy,
    this.blockPassphraseCopyPaste = true,
    this.yubikeyRecords,
    this.onUnlockWithYubikey = _defaultUnlockWithYubikey,
    this.onUnlockWithAnyYubikey = _defaultUnlockWithAnyYubikey,
    this.vaultAlias,
    this.registry,
    this.showVaultList = false,
    this.onVaultSwitch,
    this.biometricEnabled = false,
    this.onBiometricIsEnrolled = _defaultBiometricIsEnrolled,
    this.onBiometricAuthenticate = _defaultBiometricAuthenticate,
    this.onBiometricInvalidated,
  });

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passphraseController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscured = true;
  bool _pinObscured = true;
  bool _isUnlocking = false;
  String _transport = 'usb';
  String? _errorMessage;
  EntropyResult? _entropy;
  late final List<YubikeyRecordData> _yubikeyRecords;
  late String _selectedPath;
  bool _biometricEnrolled = false;

  bool get _isYubikeyMode => _yubikeyRecords.isNotEmpty;

  bool get _showDropdown =>
      widget.showVaultList &&
      widget.registry != null &&
      widget.registry!.records.length > 1;

  @override
  void initState() {
    super.initState();
    _yubikeyRecords = widget.yubikeyRecords ?? _detectYubikeyRecords();
    _selectedPath = widget.vaultPath;
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

  @override
  void dispose() {
    _passphraseController.dispose();
    _pinController.dispose();
    super.dispose();
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
      if (mounted) {
        GabbroApp.maybeOf(context)?.touchVaultLastUsed(widget.vaultPath);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VaultListScreen(
              vaultPath: widget.vaultPath,
              vaultAlias: widget.vaultAlias,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (e) {
          PlatformException(code: 'TRANSPORT_ERROR') =>
            e.message ?? l.transportError,
          PlatformException(code: 'NO_FIDO2_DEVICE') =>
            e.message ?? l.noFidoDeviceFound,
          _ => _isYubikeyMode
              ? l.unlockErrorPassphraseAndPin
              : l.unlockErrorPassphrase,
        };
      });
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
                    if (_biometricEnrolled) ...[
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
                            onPressed: () =>
                                setState(() => _pinObscured = !_pinObscured),
                          ),
                        ),
                      ),
                      if (!Platform.isLinux) ...[
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
