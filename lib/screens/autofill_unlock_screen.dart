import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shown by UnlockActivity when the vault is locked and an autofill request
/// has arrived. The user enters their passphrase; on success a MethodChannel
/// message is sent back to Kotlin with the matched credential.
class AutofillUnlockScreen extends StatefulWidget {
  const AutofillUnlockScreen({super.key});

  @override
  State<AutofillUnlockScreen> createState() => _AutofillUnlockScreenState();
}

class _AutofillUnlockScreenState extends State<AutofillUnlockScreen> {
  static const _channel = MethodChannel('app.gabbro.gabbro/autofill');

  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _channel.invokeMethod('unlock', {'passphrase': _controller.text});
    } on PlatformException catch (e) {
      setState(() {
        _error = e.message ?? 'Unlock failed';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock Gabbro')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_controller.text.isNotEmpty && !_loading) _unlock();
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _controller.text.isNotEmpty && !_loading ? _unlock : null,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}