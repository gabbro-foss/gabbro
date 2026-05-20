import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/path_field.dart';
import 'package:path_provider/path_provider.dart';

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

Future<void> _defaultInitVault(List<int> passphrase, String path) =>
    initVault(passphrase: passphrase, path: path);

EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

Future<void> _defaultInitVaultWithYubikey(
  List<int> passphrase,
  String pin,
  String path,
) async {
  final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  final result = await _yubikeyChannel.invokeMapMethod<String, String>(
    'register_and_get_hmac',
    {
      'salt': _toHex(salt),
      'pin': pin,
    },
  );
  final credentialId = _fromHex(result!['credentialId']!);
  final hmacSecret = _fromHex(result['hmacSecret']!);
  await initVaultWithYubikey(
    passphrase: passphrase,
    hmacSecret: hmacSecret,
    credentialId: credentialId,
    hkdfSalt: salt,
    path: path,
  );
}

// ── Widget ────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  final String? initialPath;
  final String? postDeletionMessage;
  final Future<void> Function(List<int> passphrase, String path) onInitVault;
  final EntropyResult Function(String password) onEstimateEntropy;
  final bool blockPassphraseCopyPaste;

  /// Controls YubiKey opt-in section visibility. Defaults to `Platform.isAndroid`
  /// so tests on Linux can pass `isAndroid: true` to exercise the YubiKey UI.
  final bool isAndroid;

  final Future<void> Function(
    List<int> passphrase,
    String pin,
    String path,
  ) onInitVaultWithYubikey;

  OnboardingScreen({
    super.key,
    this.initialPath,
    this.postDeletionMessage,
    this.onInitVault = _defaultInitVault,
    this.onEstimateEntropy = _defaultEstimateEntropy,
    this.blockPassphraseCopyPaste = true,
    bool? isAndroid,
    this.onInitVaultWithYubikey = _defaultInitVaultWithYubikey,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  final _pinController = TextEditingController();
  String _vaultPath = '';

  bool _passphraseObscured = true;
  bool _confirmObscured = true;
  bool _pinObscured = true;
  bool _isCreating = false;
  String? _error;
  EntropyResult? _entropy;
  bool? _confirmMatches;
  bool _useYubikey = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      _vaultPath = widget.initialPath!;
    } else {
      _initDefaultPath();
    }
  }

  Future<void> _initDefaultPath() async {
    final dir = await getApplicationSupportDirectory();
    setState(() => _vaultPath = '${dir.path}/gabbro.gabbro');
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onPassphraseChanged(String value) {
    final result = widget.onEstimateEntropy(value);
    setState(() => _entropy = result);
  }

  Future<void> _createVault() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isCreating = true;
      _error = null;
    });
    try {
      final file = File(_vaultPath);
      await file.parent.create(recursive: true);
      if (_useYubikey) {
        await widget.onInitVaultWithYubikey(
          _passphraseController.text.codeUnits,
          _pinController.text,
          _vaultPath,
        );
      } else {
        await widget.onInitVault(
          _passphraseController.text.codeUnits,
          _vaultPath,
        );
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VaultListScreen(vaultPath: _vaultPath),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isCreating = false);
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

  bool get _strongEnough =>
      _entropy != null &&
      (_entropy!.tier == StrengthTier.strong ||
          _entropy!.tier == StrengthTier.veryStrong ||
          _entropy!.tier == StrengthTier.centuries);

  Future<void> _toggleAccessibility() async {
    final app = GabbroApp.maybeOf(context);
    if (app == null) return;
    final current = app.settings;
    final isOn =
        current.highContrast && current.textSize == TextSizeChoice.xxLarge;
    await app.updateSettings(
      current.copyWith(
        highContrast: !isOn,
        textSize: isOn ? TextSizeChoice.regular : TextSizeChoice.xxLarge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = GabbroApp.maybeOf(context);
    final isAccessibilityOn =
        app != null &&
        app.settings.highContrast &&
        app.settings.textSize == TextSizeChoice.xxLarge;

    return Scaffold(
      body: Stack(
        children: [
          // ── Main content ───────────────────────────────────────────────
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  32, 32, 32,
                  32 + MediaQuery.of(context).viewPadding.bottom,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome to Gabbro',
                        style: Theme.of(context).textTheme.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      if (widget.postDeletionMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.postDeletionMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Create your vault to get started.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 40),
                      Text(
                        widget.postDeletionMessage != null
                            ? 'New vault location (same as before)'
                            : 'Vault location',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (widget.isAndroid)
                        Text(
                          _vaultPath.isEmpty ? 'Loading…' : _vaultPath,
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        PathField(
                          mode: PathFieldMode.save,
                          hint: 'Path to vault file',
                          initialPath:
                              _vaultPath.isEmpty ? null : _vaultPath,
                          allowedExtensions: const ['gabbro'],
                          saveFileName: 'gabbro.gabbro',
                          onPathSelected: (path) =>
                              setState(() => _vaultPath = path),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Path is required'
                              : null,
                        ),
                      if (widget.postDeletionMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Choose a new master passphrase, or re-use your previous one if you prefer.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _passphraseController,
                        obscureText: _passphraseObscured,
                        enableInteractiveSelection:
                            !widget.blockPassphraseCopyPaste,
                        onChanged: _onPassphraseChanged,
                        decoration: InputDecoration(
                          labelText: 'Master passphrase',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passphraseObscured
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _passphraseObscured = !_passphraseObscured,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Passphrase is required';
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
                          '${_tierLabel(_entropy!.tier)} · ${_entropy!.bits.toStringAsFixed(1)} bits of entropy',
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
                        enableInteractiveSelection:
                            !widget.blockPassphraseCopyPaste,
                        onFieldSubmitted: (_) => _createVault(),
                        onChanged: (v) {
                          setState(
                            () => _confirmMatches = v.isEmpty
                                ? null
                                : v == _passphraseController.text,
                          );
                        },
                        decoration: InputDecoration(
                          labelText: 'Confirm passphrase',
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
                            return 'Please confirm your passphrase';
                          }
                          if (v != _passphraseController.text) {
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
                      // ── YubiKey opt-in (Android only) ──────────────────
                      if (widget.isAndroid) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Protect with YubiKey'),
                          subtitle: const Text('Hardware security key (recommended)'),
                          value: _useYubikey,
                          onChanged: (v) => setState(() => _useYubikey = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_useYubikey) ...[
                          const SizedBox(height: 12),
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
                                onPressed: () => setState(
                                  () => _pinObscured = !_pinObscured,
                                ),
                              ),
                            ),
                            validator: _useYubikey
                                ? (v) => (v == null || v.isEmpty)
                                    ? 'YubiKey PIN is required'
                                    : null
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Insert your YubiKey and tap when prompted',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
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
                        onPressed: (_isCreating || !_strongEnough)
                            ? null
                            : _createVault,
                        child: _isCreating
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create vault'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── Accessibility shortcut — top-right corner ──────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: SafeArea(
              child: AnimatedOpacity(
                opacity:
                    MediaQuery.of(context).viewInsets.bottom > 0 ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: OutlinedButton.icon(
                  icon: Icon(
                    Icons.accessibility_new,
                    color: isAccessibilityOn
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  label: const Text('Accessibility'),
                  onPressed: _toggleAccessibility,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
