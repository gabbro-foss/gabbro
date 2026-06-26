import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/nfc_capability.dart';
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

// ── Default bridge implementations ───────────────────────────────────────────

List<YubikeyRecordData> _defaultListKeys(String path) =>
    listVaultYubikeyRecords(path: path);

Future<void> _defaultSetAlias(String hex, String alias) =>
    setYubikeyAlias(credentialIdHex: hex, alias: alias);

Future<void> _defaultRemoveKey(List<int> credId) =>
    removeYubikey(credId: credId);

Future<FidoCredentialData> _defaultFidoRegister({
  required String devicePath,
  required String pin,
}) =>
    fidoRegister(devicePath: devicePath, pin: pin);

Future<List<int>> _defaultFidoGetHmacSecret({
  required String devicePath,
  required List<int> credentialId,
  required List<int> salt,
  required String pin,
}) =>
    fidoGetHmacSecret(
      devicePath: devicePath,
      credentialId: credentialId,
      salt: salt,
      pin: pin,
    );

Future<void> _defaultAddYubikey({
  required List<int> newCredId,
  required List<int> newHmacSecret,
  required List<int> newSalt,
}) =>
    addYubikey(
      newCredId: newCredId,
      newHmacSecret: newHmacSecret,
      newSalt: newSalt,
    );

// ─────────────────────────────────────────────────────────────────────────────

class ManageYubiKeysScreen extends StatefulWidget {
  final String vaultPath;
  final String transport;

  // null = use Platform.isAndroid at runtime; set to true/false in tests.
  final bool? isAndroid;

  // ── Injected bridge callbacks (default to real bridge; swap in tests) ──────
  final List<YubikeyRecordData> Function(String path) onListKeys;
  final List<YubikeyAliasData> Function() onListAliases;
  final Future<void> Function(String hex, String alias) onSetAlias;
  final Future<void> Function(List<int> credId) onRemoveKey;
  final Future<void> Function({
    required List<int> newCredId,
    required List<int> newHmacSecret,
    required List<int> newSalt,
  }) onAddYubikey;

  // ── Linux FIDO callbacks ──────────────────────────────────────────────────
  final List<String> Function() onFidoListDevices;
  final Future<FidoCredentialData> Function({
    required String devicePath,
    required String pin,
  }) onFidoRegister;
  final Future<List<int>> Function({
    required String devicePath,
    required List<int> credentialId,
    required List<int> salt,
    required String pin,
  }) onFidoGetHmacSecret;

  const ManageYubiKeysScreen({
    super.key,
    required this.vaultPath,
    this.transport = 'usb',
    this.isAndroid,
    this.onListKeys = _defaultListKeys,
    this.onListAliases = listYubikeyAliases,
    this.onSetAlias = _defaultSetAlias,
    this.onRemoveKey = _defaultRemoveKey,
    this.onAddYubikey = _defaultAddYubikey,
    this.onFidoListDevices = fidoListDevices,
    this.onFidoRegister = _defaultFidoRegister,
    this.onFidoGetHmacSecret = _defaultFidoGetHmacSecret,
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
      final records = widget.onListKeys(widget.vaultPath);
      final aliases = widget.onListAliases();
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
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editAliasForKey(index + 1)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l.aliasLabel,
            hintText: l.aliasHint,
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await widget.onSetAlias(hex, controller.text.trim());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)
                  .failedToSaveAlias(e.toString()))));
        }
      }
    }
    // Defer disposal so the dialog's exit animation can finish before the
    // controller is released (avoids a post-dismiss rebuild touching a
    // disposed ChangeNotifier in debug mode).
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  Future<void> _removeKey(YubikeyRecordData record, int index) async {
    final l = AppLocalizations.of(context);
    final isSecondToLast = _records.length == 2;

    final Widget warningContent = isSecondToLast
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.lastKeyWarning),
              const SizedBox(height: 12),
              Text(
                l.yubiKeyLastKeyRiskWarning,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(l.removeKeyConfirm),
            ],
          )
        : Text(l.removeKeyVaultConfirm);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSecondToLast
            ? l.yubiKeySecurityWarning
            : l.removeYubiKeyTitle),
        content: warningContent,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.remove),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.onRemoveKey(record.credentialId);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context).yubiKeyRemoved)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)
                  .failedToRemoveKey(e.toString()))));
        }
      }
    }
  }

  Future<void> _addKey() async {
    final appState = GabbroApp.maybeOf(context);
    appState?.suspendForegroundLock();
    try {
      if (widget.isAndroid ?? Platform.isAndroid) {
        await _addKeyAndroid();
      } else {
        await _addKeyLinux();
      }
    } finally {
      if (mounted) appState?.resumeForegroundLock();
    }
  }

  Future<void> _addKeyLinux() async {
    final l = AppLocalizations.of(context);
    final devices = widget.onFidoListDevices();
    if (devices.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noFidoDeviceFound)),
      );
      return;
    }
    final pin = await _promptPin();
    if (pin == null || !mounted) return;

    final devicePath = devices.first;
    _showLinuxProgress(l.tapYubiKeyToRegister);
    try {
      final cred = await widget.onFidoRegister(
          devicePath: devicePath, pin: pin);
      if (!mounted) return;
      Navigator.of(context).pop();

      _showLinuxProgress(
          AppLocalizations.of(context).tapYubiKeyToActivate);
      final hmac = await widget.onFidoGetHmacSecret(
        devicePath: devicePath,
        credentialId: cred.credentialId,
        salt: cred.salt,
        pin: pin,
      );
      if (!mounted) return;
      Navigator.of(context).pop();

      await widget.onAddYubikey(
        newCredId: cred.credentialId,
        newHmacSecret: hmac,
        newSalt: cred.salt,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context).yubiKeyAdded)));
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)
                .failedToAddKey(e.toString()))));
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
        builder: (ctx, step, _) {
          final dl = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(dl.addYubiKeyTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stepRow(
                  ctx,
                  label: isNfc ? dl.tapRegisterNfc : dl.tapRegisterUsb,
                  done: step >= 1,
                  active: step == 0,
                ),
                const SizedBox(height: 16),
                _stepRow(
                  ctx,
                  label:
                      isNfc ? dl.tapActivateNfc : dl.tapActivateUsb,
                  done: false,
                  active: step == 1,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _progressShown = false;
                  // Abort the native tap so discovery stops and NFC reader mode
                  // is disarmed; the pending register/hmac call then rejects with
                  // TAP_CANCELLED (swallowed below).
                  _yubikeyChannel.invokeMethod('cancel_tap');
                  Navigator.of(ctx).pop();
                },
                child: Text(dl.cancel),
              ),
            ],
          );
        },
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

      await widget.onAddYubikey(
        newCredId: _fromHex(credIdHex),
        newHmacSecret: _fromHex(hmacHex),
        newSalt: salt,
      );
      await _silentRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context).yubiKeyAdded)));
      }
    } catch (e) {
      if (mounted) {
        if (_progressShown) {
          try {
            Navigator.of(context).pop();
          } catch (_) {}
          _progressShown = false;
        }
        // The user cancelled the tap: no error to report.
        if (e is PlatformException && e.code == 'TAP_CANCELLED') return;
        final al = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(credIdHex == null
              ? al.failedToRegisterKey(e.toString())
              : al.failedToActivateKey(e.toString())),
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
      final records = widget.onListKeys(widget.vaultPath);
      final aliases = widget.onListAliases();
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
        builder: (ctx, setLocal) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.enterYubiKeyPinTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: l.pinLabel,
                suffixIcon: IconButton(
                  icon:
                      Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  tooltip: obscure ? l.tooltipShowPin : l.tooltipHidePin,
                  onPressed: () => setLocal(() => obscure = !obscure),
                ),
              ),
              onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: Text(l.ok),
              ),
            ],
          );
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return (pin == null || pin.isEmpty) ? null : pin;
  }

  Future<(String pin, String transport)?> _promptPinAndTransport() async {
    bool obscure = true;
    final controller = TextEditingController();
    String selectedTransport = widget.transport;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.addYubiKeyTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Transport choice only when the device has NFC; otherwise the
                // single USB option is implicit (selectedTransport stays 'usb').
                if (nfcAvailable) ...[
                  Text(l.transportLabel),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ChoiceChip(
                        label: Text(l.transportUsb),
                        selected: selectedTransport == 'usb',
                        onSelected: (_) =>
                            setLocal(() => selectedTransport = 'usb'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(l.transportNfc),
                        selected: selectedTransport == 'nfc',
                        onSelected: (_) =>
                            setLocal(() => selectedTransport = 'nfc'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: l.pinLabel,
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility),
                      tooltip: obscure ? l.tooltipShowPin : l.tooltipHidePin,
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
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop({
                  'pin': controller.text,
                  'transport': selectedTransport,
                }),
                child: Text(l.register),
              ),
            ],
          );
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null) return null;
    return (result['pin'] ?? '', result['transport'] ?? 'usb');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageYubiKeysTitle),
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
              ? Center(child: Text(l.manageYubiKeysError(_error!)))
              : _records.isEmpty
                  ? Center(child: Text(l.noYubiKeysRegistered))
                  : Column(
                      children: [
                        if (_records.length == 1)
                          Container(
                            width: double.infinity,
                            color: Theme.of(context)
                                .colorScheme
                                .errorContainer,
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
                                    l.onlyOneKeyRegisteredWarning,
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
                              final bl = AppLocalizations.of(context);
                              return ListTile(
                                leading: const Icon(Icons.security),
                                title: Text(alias.isEmpty
                                    ? bl.keyDefaultTitle(i + 1)
                                    : alias),
                                subtitle:
                                    Text(_credHint(record.credentialId)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: bl.editAliasTooltip,
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
                                          ? bl.cannotRemoveLastKey
                                          : bl.removeKeyTooltip,
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
              label: Text(l.addYubiKey),
            )
          : null,
    );
  }
}
