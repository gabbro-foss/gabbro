import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';

// ── Hex helpers ───────────────────────────────────────────────────────────────

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _fromHex(String hex) {
  final result = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return result;
}

// ── Bridge defaults ───────────────────────────────────────────────────────────

Future<void> _defaultUnlock(List<int> passphrase, String path) =>
    unlockVault(passphrase: passphrase, path: path);

EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

Future<void> _defaultUnlockWithYubikey(
  List<int> passphrase,
  List<int> credentialId,
  List<int> hkdfSalt,
  String pin,
  String path,
) async {
  final hmacHex = await _yubikeyChannel.invokeMethod<String>(
    'get_hmac_secret',
    {
      'credentialId': _toHex(credentialId),
      'salt': _toHex(hkdfSalt),
      'pin': pin,
    },
  );
  await unlockVaultWithYubikey(
    passphrase: passphrase,
    hmacSecret: _fromHex(hmacHex!),
    credentialId: credentialId,
    hkdfSalt: hkdfSalt,
    path: path,
  );
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
  ) onUnlockWithYubikey;

  const UnlockScreen({
    super.key,
    required this.vaultPath,
    this.onUnlock = _defaultUnlock,
    this.onEstimateEntropy = _defaultEstimateEntropy,
    this.blockPassphraseCopyPaste = true,
    this.yubikeyRecords,
    this.onUnlockWithYubikey = _defaultUnlockWithYubikey,
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
  String? _errorMessage;
  EntropyResult? _entropy;
  late final List<YubikeyRecordData> _yubikeyRecords;

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
    _passphraseController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });
    try {
      if (_isYubikeyMode) {
        final record = _yubikeyRecords.first;
        await widget.onUnlockWithYubikey(
          _passphraseController.text.codeUnits,
          record.credentialId,
          record.salt,
          _pinController.text,
          widget.vaultPath,
        );
      } else {
        await widget.onUnlock(
          _passphraseController.text.codeUnits,
          widget.vaultPath,
        );
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VaultListScreen(vaultPath: widget.vaultPath),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = _isYubikeyMode
            ? 'Could not unlock vault. Check your passphrase and YubiKey PIN.'
            : 'Could not unlock vault. Check your passphrase.';
      });
    } finally {
      setState(() => _isUnlocking = false);
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

  String _tierLabel(StrengthTier tier) => switch (tier) {
        StrengthTier.terrible => 'Terrible',
        StrengthTier.weak => 'Weak',
        StrengthTier.fair => 'Fair',
        StrengthTier.strong => 'Strong',
        StrengthTier.veryStrong => 'Very strong',
        StrengthTier.centuries => 'Excellent',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Gabbro',
                      style: Theme.of(context).textTheme.headlineLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isYubikeyMode
                          ? 'Enter your passphrase and YubiKey PIN to unlock'
                          : 'Enter your passphrase to unlock',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
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
                        labelText: 'Passphrase',
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
                        '${_tierLabel(_entropy!.tier)} · ${_entropy!.bits.toStringAsFixed(1)} bits of entropy',
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
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Insert your YubiKey and tap when prompted',
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
                          : const Text('Unlock'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
