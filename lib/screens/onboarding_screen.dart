import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:path_provider/path_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  final _pathController = TextEditingController();

  bool _passphraseObscured = true;
  bool _confirmObscured = true;
  bool _isCreating = false;
  String? _error;
  EntropyResult? _entropy;
  bool? _confirmMatches;

  @override
  void initState() {
    super.initState();
    _initDefaultPath();
  }

  Future<void> _initDefaultPath() async {
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/gabbro.gabbro';
    setState(() => _pathController.text = path);
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _onPassphraseChanged(String value) {
    final result = estimateEntropy(password: value);
    setState(() => _entropy = result);
  }

  Future<void> _pickPath() async {
    final result = await FilePicker.saveFile(
      dialogTitle: 'Choose vault location',
      fileName: 'gabbro.gabbro',
    );
    if (result != null) {
      String path = result;
      if (!path.endsWith('.gabbro')) path = '$path.gabbro';
      setState(() => _pathController.text = path);
    }
  }

  Future<void> _createVault() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isCreating = true;
      _error = null;
    });
    try {
      // Ensure the directory exists
      final file = File(_pathController.text);
      await file.parent.create(recursive: true);

      await initVault(
        passphrase: _passphraseController.text.codeUnits,
        path: _pathController.text,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const VaultListScreen()),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
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
                  Text(
                    'Create your vault to get started.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Vault path
                  const Text(
                    'Vault location',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _pathController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Path to vault file',
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Path is required'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Choose location',
                        onPressed: _pickPath,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Passphrase
                  TextFormField(
                    controller: _passphraseController,
                    obscureText: _passphraseObscured,
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
                      if (v == null || v.isEmpty)
                        return 'Passphrase is required';
                      if (!_strongEnough) return 'Passphrase is too weak';
                      return null;
                    },
                  ),

                  // Entropy indicator
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

                  // Confirm passphrase
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _confirmObscured,
                    onChanged: (v) {
                      setState(
                        () => _confirmMatches = v.isEmpty ? null : v == _passphraseController.text,
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
                      if (v == null || v.isEmpty)
                        return 'Please confirm your passphrase';
                      if (v != _passphraseController.text)
                        return 'Passphrases do not match';
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
                    onPressed: (_isCreating || !_strongEnough)
                        ? null
                        : _createVault,
                    child: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create vault'),
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
