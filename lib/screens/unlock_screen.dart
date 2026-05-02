import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';

Future<void> _defaultUnlock(List<int> passphrase, String path) =>
    unlockVault(passphrase: passphrase, path: path);
EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

class UnlockScreen extends StatefulWidget {
  final String vaultPath;
  final Future<void> Function(List<int> passphrase, String path) onUnlock;
  final EntropyResult Function(String password) onEstimateEntropy;

  const UnlockScreen({
    super.key,
    required this.vaultPath,
    this.onUnlock = _defaultUnlock,
    this.onEstimateEntropy = _defaultEstimateEntropy,
  });

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passphraseController = TextEditingController();
  bool _obscured = true;
  bool _isUnlocking = false;
  String? _errorMessage;
  EntropyResult? _entropy;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });
    try {
      await widget.onUnlock(
        _passphraseController.text.codeUnits,
        widget.vaultPath,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VaultListScreen(vaultPath: widget.vaultPath),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not unlock vault. Check your passphrase.';
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
          // ── Main content ───────────────────────────────────────────────
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
                      'Enter your passphrase to unlock',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    TextField(
                      controller: _passphraseController,
                      autofocus: true,
                      obscureText: _obscured,
                      onSubmitted: (_) => _isUnlocking ? null : _unlock(),
                      onChanged: (v) => setState(
                        () => _entropy = widget.onEstimateEntropy(v),
                      ),
                      decoration: InputDecoration(
                        labelText: 'Passphrase',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscured ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() => _obscured = !_obscured);
                          },
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
