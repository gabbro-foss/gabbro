import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/fido_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/segmented_row.dart';

Future<void> _defaultChangePassphrase(
  List<int> oldPassphrase,
  List<int> newPassphrase,
) => changePassphrase(
  oldPassphrase: oldPassphrase,
  newPassphrase: newPassphrase,
);

EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> _defaultConfirmYubikey(
  List<int> credentialId,
  List<int> salt,
  String pin,
  String transport,
) async {
  if (Platform.isLinux) {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      throw PlatformException(
        code: 'NO_FIDO2_DEVICE',
        message: 'No FIDO2 device found. Insert your YubiKey and try again.',
      );
    }
    await fidoGetHmacSecret(
      devicePath: devices.first,
      credentialId: credentialId,
      salt: salt,
      pin: pin,
    );
    return;
  }
  await _yubikeyChannel.invokeMethod<String>(
    'get_hmac_secret',
    {'credentialId': _toHex(credentialId), 'salt': _toHex(salt), 'pin': pin, 'transport': transport},
  );
}

Future<void> _defaultConfirmAnyYubikey(
  List<YubikeyRecordData> records,
  String pin,
  String transport,
) async {
  if (Platform.isLinux) {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      throw PlatformException(
        code: 'NO_FIDO2_DEVICE',
        message: 'No FIDO2 device found. Insert your YubiKey and try again.',
      );
    }
    await fidoGetHmacSecretAny(
      devicePath: devices.first,
      records: records
          .map((r) => FidoRecordInput(credentialId: r.credentialId, salt: r.salt))
          .toList(),
      pin: pin,
    );
    return;
  }
  final recordsArg = records
      .map((r) => {'credentialId': _toHex(r.credentialId), 'salt': _toHex(r.salt)})
      .toList();
  await _yubikeyChannel.invokeMethod<Map<Object?, Object?>>(
    'get_hmac_secret_multi',
    {'records': recordsArg, 'pin': pin, 'transport': transport},
  );
}

class ChangePassphraseScreen extends StatefulWidget {
  final String vaultPath;
  final Future<void> Function(List<int> oldPassphrase, List<int> newPassphrase)
  onChangePassphrase;
  final EntropyResult Function(String password) onEstimateEntropy;
  final bool blockPassphraseCopyPaste;

  /// Pre-injected YubiKey records. `null` = auto-detect from vault file at
  /// construction time. Pass `[]` to force passphrase-only mode (tests).
  final List<YubikeyRecordData>? yubikeyRecords;

  /// Called in single-key YubiKey mode before changing the passphrase.
  final Future<void> Function(List<int> credentialId, List<int> salt, String pin, String transport)
      onConfirmYubikey;

  /// Called in multi-key YubiKey mode (2+ keys) before changing the passphrase.
  /// Sends all records in one FIDO2 assertion — one tap regardless of which key is inserted.
  final Future<void> Function(List<YubikeyRecordData> records, String pin, String transport)
      onConfirmAnyYubikey;

  const ChangePassphraseScreen({
    super.key,
    required this.vaultPath,
    this.onChangePassphrase = _defaultChangePassphrase,
    this.onEstimateEntropy = _defaultEstimateEntropy,
    this.blockPassphraseCopyPaste = true,
    this.yubikeyRecords,
    this.onConfirmYubikey = _defaultConfirmYubikey,
    this.onConfirmAnyYubikey = _defaultConfirmAnyYubikey,
  });

  @override
  State<ChangePassphraseScreen> createState() => _ChangePassphraseScreenState();
}

class _ChangePassphraseScreenState extends State<ChangePassphraseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _oldObscured = true;
  bool _newObscured = true;
  bool _confirmObscured = true;
  bool _pinObscured = true;
  bool _isChanging = false;
  String _transport = 'usb';
  String? _error;
  EntropyResult? _entropy;
  bool? _confirmMatches;
  late final List<YubikeyRecordData> _yubikeyRecords;
  final _pinController = TextEditingController();

  bool get _isYubikeyMode => _yubikeyRecords.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _yubikeyRecords = widget.yubikeyRecords ?? _detectYubikeyRecords();
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
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onNewPassphraseChanged(String value) {
    final result = widget.onEstimateEntropy(value);
    setState(() => _entropy = result);
  }

  bool get _strongEnough =>
      _entropy != null &&
      (_entropy!.tier == StrengthTier.strong ||
          _entropy!.tier == StrengthTier.veryStrong ||
          _entropy!.tier == StrengthTier.centuries);

  Color _tierColor(StrengthTier tier) => switch (tier) {
    StrengthTier.terrible => Colors.red,
    StrengthTier.weak => Colors.orange,
    StrengthTier.fair => Colors.yellow.shade700,
    StrengthTier.strong => Colors.lightGreen,
    StrengthTier.veryStrong => Colors.green,
    StrengthTier.centuries => Colors.green.shade800,
  };

  String _tierLabel(StrengthTier tier) => switch (tier) {
    StrengthTier.terrible => 'Terrible',
    StrengthTier.weak => 'Weak',
    StrengthTier.fair => 'Fair',
    StrengthTier.strong => 'Strong',
    StrengthTier.veryStrong => 'Very strong',
    StrengthTier.centuries => 'Excellent',
  };

  Future<void> _changePassphrase() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isChanging = true;
      _error = null;
    });
    try {
      if (_isYubikeyMode) {
        try {
          if (_yubikeyRecords.length == 1) {
            final record = _yubikeyRecords.first;
            await widget.onConfirmYubikey(
              record.credentialId,
              record.salt,
              _pinController.text,
              _transport,
            );
          } else {
            await widget.onConfirmAnyYubikey(
              _yubikeyRecords,
              _pinController.text,
              _transport,
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _error = switch (e) {
                PlatformException(code: 'TRANSPORT_ERROR') =>
                  e.message ?? 'Transport error.',
                PlatformException(code: 'NO_FIDO2_DEVICE') =>
                  e.message ?? 'No FIDO2 device found. Insert your YubiKey and try again.',
                _ => 'Authorization failed — check your PIN and try again.',
              };
            });
          }
          return;
        }
      }
      await widget.onChangePassphrase(
        _oldController.text.codeUnits,
        _newController.text.codeUnits,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passphrase changed successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isChanging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change passphrase')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isYubikeyMode) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'YubiKey-protected vault — your YubiKey binding will be preserved.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pinController,
                      obscureText: _pinObscured,
                      decoration: InputDecoration(
                        labelText: 'YubiKey PIN',
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
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'YubiKey PIN is required'
                          : null,
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
                      _isChanging
                          ? 'Tap your YubiKey now…'
                          : 'Touch your YubiKey to authorize this change.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _oldController,
                    obscureText: _oldObscured,
                    enableInteractiveSelection: !widget.blockPassphraseCopyPaste,
                    decoration: InputDecoration(
                      labelText: 'Current passphrase',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _oldObscured
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _oldObscured = !_oldObscured),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Current passphrase is required'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _newController,
                    obscureText: _newObscured,
                    enableInteractiveSelection: !widget.blockPassphraseCopyPaste,
                    onChanged: _onNewPassphraseChanged,
                    decoration: InputDecoration(
                      labelText: 'New passphrase',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _newObscured
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _newObscured = !_newObscured),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'New passphrase is required';
                      }
                      if (!_strongEnough) return 'Passphrase is too weak';
                      return null;
                    },
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
                      '${_tierLabel(_entropy!.tier)} · ${_entropy!.bits.toStringAsFixed(1)} bits',
                      style: TextStyle(
                        fontSize: 12,
                        color: _tierColor(_entropy!.tier),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _confirmObscured,
                    enableInteractiveSelection: !widget.blockPassphraseCopyPaste,
                    onFieldSubmitted: (_) => _changePassphrase(),
                    onChanged: (v) {
                      setState(
                        () => _confirmMatches = v.isEmpty
                            ? null
                            : v == _newController.text,
                      );
                    },
                    decoration: InputDecoration(
                      labelText: 'Confirm new passphrase',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _confirmObscured
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _confirmObscured = !_confirmObscured,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please confirm your new passphrase';
                      }
                      if (v != _newController.text) {
                        return 'Passphrases do not match';
                      }
                      return null;
                    },
                  ),
                  if (_confirmMatches != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _confirmMatches!
                          ? '✓ Passphrases match'
                          : '✗ Passphrases do not match',
                      style: TextStyle(
                        fontSize: 12,
                        color: _confirmMatches!
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
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
                  FilledButton(
                    onPressed: (_isChanging || !_strongEnough)
                        ? null
                        : _changePassphrase,
                    child: _isChanging
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Change passphrase'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
