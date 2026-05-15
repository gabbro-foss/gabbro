import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

Future<void> _defaultChangePassphrase(
  List<int> oldPassphrase,
  List<int> newPassphrase,
) => changePassphrase(
  oldPassphrase: oldPassphrase,
  newPassphrase: newPassphrase,
);

EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

class ChangePassphraseScreen extends StatefulWidget {
  final Future<void> Function(List<int> oldPassphrase, List<int> newPassphrase)
  onChangePassphrase;
  final EntropyResult Function(String password) onEstimateEntropy;
  final bool blockPassphraseCopyPaste;

  const ChangePassphraseScreen({
    super.key,
    this.onChangePassphrase = _defaultChangePassphrase,
    this.onEstimateEntropy = _defaultEstimateEntropy,
    this.blockPassphraseCopyPaste = true,
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
  bool _isChanging = false;
  String? _error;
  EntropyResult? _entropy;
  bool? _confirmMatches;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
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
