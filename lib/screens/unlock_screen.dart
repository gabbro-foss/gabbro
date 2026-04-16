import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/screens/vault_list_screen.dart';

class UnlockScreen extends StatefulWidget {
  final String vaultPath;

  const UnlockScreen({super.key, required this.vaultPath});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passphraseController = TextEditingController();
  bool _obscured = true;
  bool _isUnlocking = false;
  String? _errorMessage;

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
      await unlockVault(
        passphrase: _passphraseController.text.codeUnits,
        path: widget.vaultPath,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const VaultListScreen(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
                  obscureText: _obscured,
                  onSubmitted: (_) => _isUnlocking ? null : _unlock(),
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
    );
  }
}