import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/src/rust/api/fido_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final result = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(result);
}

class ManageYubiKeysScreen extends StatefulWidget {
  final String vaultPath;
  final String transport;

  const ManageYubiKeysScreen({
    super.key,
    required this.vaultPath,
    this.transport = 'usb',
  });

  @override
  State<ManageYubiKeysScreen> createState() => _ManageYubiKeysScreenState();
}

class _ManageYubiKeysScreenState extends State<ManageYubiKeysScreen> {
  List<YubikeyRecordData> _records = [];
  Map<String, String> _aliases = {};
  bool _loading = true;
  String? _error;

  // Tracks whether a cancellable progress dialog is currently shown (Android).
  bool _progressShown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = listVaultYubikeyRecords(path: widget.vaultPath);
      final aliases = listYubikeyAliases();
      final aliasMap = <String, String>{};
      for (final a in aliases) {
        aliasMap[a.credentialIdHex] = a.alias;
      }
      setState(() {
        _records = records;
        _aliases = aliasMap;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _credHint(List<int> credId) {
    final hex = _toHex(credId);
    return 'ID: ${hex.length > 16 ? '${hex.substring(0, 16)}…' : hex}';
  }

  Future<void> _editAlias(YubikeyRecordData record, int index) async {
    final hex = _toHex(record.credentialId);
    final controller = TextEditingController(text: _aliases[hex] ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit alias for key ${index + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Alias',
            hintText: 'e.g. Primary, Work key…',
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await setYubikeyAlias(
          credentialIdHex: hex,
          alias: controller.text.trim(),
        );
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed to save alias: $e')));
        }
      }
    }
    controller.dispose();
  }

  Future<void> _removeKey(YubikeyRecordData record, int index) async {
    final isSecondToLast = _records.length == 2;

    final Widget warningContent = isSecondToLast
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This will leave only one registered YubiKey.'),
              const SizedBox(height: 12),
              Text(
                'WARNING: if that remaining key is lost, damaged, or stolen, '
                'vault access will be permanently impossible. '
                'There is no recovery path.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Are you sure you want to remove this key?'),
            ],
          )
        : const Text('Remove this YubiKey from the vault?');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSecondToLast ? 'Security warning' : 'Remove YubiKey'),
        content: warningContent,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await removeYubikey(credId: record.credentialId);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('YubiKey removed')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed to remove key: $e')));
        }
      }
    }
  }

  Future<void> _addKey() async {
    final appState = GabbroApp.of(context);
    appState.suspendForegroundLock();
    try {
      if (Platform.isLinux) {
        await _addKeyLinux();
      } else {
        await _addKeyAndroid();
      }
    } finally {
      if (mounted) appState.resumeForegroundLock();
    }
  }

  Future<void> _addKeyLinux() async {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No FIDO2 device found. Insert your YubiKey and try again.')),
      );
      return;
    }
    final pin = await _promptPin();
    if (pin == null || !mounted) return;

    final devicePath = devices.first;
    _showLinuxProgress('Tap your new YubiKey to register…');
    try {
      final cred = await fidoRegister(devicePath: devicePath, pin: pin);
      if (!mounted) return;
      Navigator.of(context).pop();

      _showLinuxProgress('Tap your new YubiKey again to activate…');
      final hmac = await fidoGetHmacSecret(
        devicePath: devicePath,
        credentialId: cred.credentialId,
        salt: cred.salt,
        pin: pin,
      );
      if (!mounted) return;
      Navigator.of(context).pop();

      await addYubikey(
        newCredId: cred.credentialId,
        newHmacSecret: hmac,
        newSalt: cred.salt,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('YubiKey added')));
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add key: $e')));
      }
    }
  }

  Future<void> _addKeyAndroid() async {
    final options = await _promptPinAndTransport();
    if (options == null || !mounted) return;
    final (pin, transport) = options;

    final salt = Uint8List.fromList(
        List.generate(32, (_) => Random.secure().nextInt(256)));

    final isNfc = transport == 'nfc';
    // step: 0 = step 1 in progress, 1 = step 1 done / step 2 in progress
    final stepNotifier = ValueNotifier<int>(0);
    String? credIdHex;

    _progressShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: stepNotifier,
        builder: (ctx, step, _) => AlertDialog(
          title: const Text('Add YubiKey'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepRow(
                ctx,
                label: isNfc
                    ? 'Hold key to phone to register'
                    : 'Once connected, tap the key to register',
                done: step >= 1,
                active: step == 0,
              ),
              const SizedBox(height: 16),
              _stepRow(
                ctx,
                label: isNfc
                    ? 'Hold key to phone again to activate'
                    : 'Once connected, tap the key again to activate',
                done: false,
                active: step == 1,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _progressShown = false;
                Navigator.of(ctx).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ).then((_) => _progressShown = false);

    try {
      // Step 1: register — obtain credentialId.
      final cred = await _yubikeyChannel.invokeMethod<String>(
        'register',
        {'pin': pin, 'transport': transport},
      );
      if (!mounted) return;
      if (cred == null) throw Exception('No result from YubiKey');
      credIdHex = cred;
      stepNotifier.value = 1;

      if (!mounted) return;

      // Step 2: get_hmac_secret — obtain HMAC secret using the new credential.
      final hmacHex = await _yubikeyChannel.invokeMethod<String>(
        'get_hmac_secret',
        {
          'credentialId': credIdHex,
          'salt': _toHex(salt),
          'pin': pin,
          'transport': transport,
        },
      );
      if (!mounted) return;
      if (_progressShown) {
        Navigator.of(context).pop();
        _progressShown = false;
      }
      if (hmacHex == null) throw Exception('No HMAC secret from YubiKey');

      await addYubikey(
        newCredId: _fromHex(credIdHex),
        newHmacSecret: _fromHex(hmacHex),
        newSalt: salt,
      );
      await _silentRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('YubiKey added')));
      }
    } catch (e) {
      if (mounted) {
        if (_progressShown) {
          try {
            Navigator.of(context).pop();
          } catch (_) {}
          _progressShown = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(credIdHex == null
              ? 'Failed to register key: $e'
              : 'Failed to activate key: $e'),
        ));
      }
    } finally {
      stepNotifier.dispose();
    }
  }

  Widget _stepRow(
    BuildContext context, {
    required String label,
    required bool done,
    required bool active,
  }) {
    final theme = Theme.of(context);
    final Widget indicator;
    if (done) {
      indicator = Icon(Icons.check_circle_rounded,
          color: theme.colorScheme.primary, size: 24);
    } else if (active) {
      indicator = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: theme.colorScheme.primary),
      );
    } else {
      indicator = Icon(Icons.radio_button_unchecked,
          color: theme.disabledColor, size: 24);
    }
    return Row(
      children: [
        SizedBox(width: 24, height: 24, child: Center(child: indicator)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: active || done ? null : theme.disabledColor,
            ),
          ),
        ),
      ],
    );
  }

  // Refresh records without showing the full-screen loading spinner.
  Future<void> _silentRefresh() async {
    try {
      final records = listVaultYubikeyRecords(path: widget.vaultPath);
      final aliases = listYubikeyAliases();
      final aliasMap = <String, String>{};
      for (final a in aliases) {
        aliasMap[a.credentialIdHex] = a.alias;
      }
      if (mounted) {
        setState(() {
          _records = records;
          _aliases = aliasMap;
        });
      }
    } catch (_) {
      await _load();
    }
  }

  // Non-cancellable progress dialog used on Linux (operations are prompt).
  void _showLinuxProgress(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptPin() async {
    bool obscure = true;
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Enter YubiKey PIN'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'PIN',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setLocal(() => obscure = !obscure),
              ),
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return (pin == null || pin.isEmpty) ? null : pin;
  }

  Future<(String pin, String transport)?> _promptPinAndTransport() async {
    bool obscure = true;
    final controller = TextEditingController();
    String selectedTransport = widget.transport;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add YubiKey'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Transport:'),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('USB'),
                    selected: selectedTransport == 'usb',
                    onSelected: (_) =>
                        setLocal(() => selectedTransport = 'usb'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('NFC'),
                    selected: selectedTransport == 'nfc',
                    onSelected: (_) =>
                        setLocal(() => selectedTransport = 'nfc'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setLocal(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (_) => Navigator.of(ctx).pop({
                  'pin': controller.text,
                  'transport': selectedTransport,
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop({
                'pin': controller.text,
                'transport': selectedTransport,
              }),
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return null;
    return (result['pin'] ?? '', result['transport'] ?? 'usb');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage YubiKeys'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _records.isEmpty
                  ? const Center(child: Text('No YubiKeys registered'))
                  : Column(
                      children: [
                        if (_records.length == 1)
                          Container(
                            width: double.infinity,
                            color: Theme.of(context).colorScheme.errorContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Only one key registered. '
                                    'If this key is lost, vault access is permanently impossible.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _records.length,
                            itemBuilder: (context, i) {
                              final record = _records[i];
                              final hex = _toHex(record.credentialId);
                              final alias = _aliases[hex] ?? '';
                              final isOnly = _records.length == 1;
                              return ListTile(
                                leading: const Icon(Icons.security),
                                title: Text(
                                    alias.isEmpty ? 'Key ${i + 1}' : alias),
                                subtitle:
                                    Text(_credHint(record.credentialId)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon:
                                          const Icon(Icons.edit_outlined),
                                      tooltip: 'Edit alias',
                                      onPressed: () =>
                                          _editAlias(record, i),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: isOnly
                                            ? Theme.of(context).disabledColor
                                            : Theme.of(context)
                                                .colorScheme
                                                .error,
                                      ),
                                      tooltip: isOnly
                                          ? 'Cannot remove the last key'
                                          : 'Remove key',
                                      onPressed: isOnly
                                          ? null
                                          : () => _removeKey(record, i),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
      floatingActionButton: _records.length < 4
          ? FloatingActionButton.extended(
              onPressed: _addKey,
              icon: const Icon(Icons.add),
              label: const Text('Add YubiKey'),
            )
          : null,
    );
  }
}
