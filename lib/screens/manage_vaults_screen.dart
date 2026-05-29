import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/widgets/segmented_row.dart';

class _RenameDialog extends StatefulWidget {
  final String initialAlias;
  final Set<String> takenAliases;
  const _RenameDialog({
    required this.initialAlias,
    required this.takenAliases,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAlias);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alias = _controller.text.trim();
    final isTaken = widget.takenAliases.contains(alias);

    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.renameVaultTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l.aliasLabel),
            onChanged: (_) => setState(() {}),
          ),
          if (isTaken && alias.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              l.vaultNameAlreadyExists(alias),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: (alias.isEmpty || isTaken)
              ? null
              : () => Navigator.of(context).pop(alias),
          child: Text(l.save),
        ),
      ],
    );
  }
}

List<YubikeyRecordData> _defaultListYubikeyRecords(String path) {
  try {
    return listVaultYubikeyRecords(path: path);
  } catch (_) {
    return [];
  }
}

class ManageVaultsScreen extends StatefulWidget {
  final VaultRegistry registry;
  final Future<void> Function(String path, String alias) onRename;
  final Future<void> Function(String path) onDelete;
  final VoidCallback onAddVault;
  final void Function(String path, String alias) onSwitchToVault;

  final Future<void> Function(List<int> credentialId, List<int> salt, String pin, String transport)
      onConfirmYubikey;
  final Future<void> Function(List<YubikeyRecordData> records, String pin, String transport)
      onConfirmAnyYubikey;

  /// Injected for testing; defaults to reading the vault file.
  final List<YubikeyRecordData> Function(String path) listYubikeyRecords;

  const ManageVaultsScreen({
    super.key,
    required this.registry,
    required this.onRename,
    required this.onDelete,
    required this.onAddVault,
    required this.onSwitchToVault,
    required this.onConfirmYubikey,
    required this.onConfirmAnyYubikey,
    this.listYubikeyRecords = _defaultListYubikeyRecords,
  });

  @override
  State<ManageVaultsScreen> createState() => _ManageVaultsScreenState();
}

class _ManageVaultsScreenState extends State<ManageVaultsScreen> {
  late VaultRegistry _registry;
  String _transport = 'usb';

  @override
  void initState() {
    super.initState();
    _registry = widget.registry;
  }

  Future<void> _showRenameDialog(VaultRecord record) async {
    final takenAliases = _registry.records
        .where((r) => r.path != record.path)
        .map((r) => r.alias)
        .toSet();
    final String? newAlias = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        initialAlias: record.alias,
        takenAliases: takenAliases,
      ),
    );
    if (newAlias != null) {
      setState(() => _registry = _registry.updateAlias(record.path, newAlias));
      await widget.onRename(record.path, newAlias);
    }
  }

  Future<void> _showDeleteDialog(VaultRecord record) async {
    final ykRecords = widget.listYubikeyRecords(record.path);
    final isYubikey = ykRecords.isNotEmpty;

    // Step 1 — warning
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.deleteVaultTitle),
          content: Text(
            isYubikey
                ? l.deleteVaultYubikeyContent(record.alias, record.path)
                : l.deleteVaultContent(record.alias, record.path),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l.continueAction),
            ),
          ],
        );
      },
    );
    if (step1 != true) return;
    if (!mounted) return;

    // Step 2 — type DELETE to confirm
    final confirmController = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.deleteVaultConfirmTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.typeDeleteToConfirm),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('delete_vault_confirm_field'),
                  controller: confirmController,
                  autofocus: true,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: confirmController.text == l.typeDeleteWord
                    ? () => Navigator.of(ctx).pop(true)
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: Text(l.confirm),
              ),
            ],
          );
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => confirmController.dispose());
    if (step2 != true) return;
    if (!mounted) return;

    // Step 3 — YubiKey tap authorization (YubiKey vaults only)
    if (isYubikey) {
      final pinController = TextEditingController();
      bool isAuthorizing = false;
      bool obscurePin = true;
      String? authError;
      String dialogTransport = _transport;

      final step3 = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final l = AppLocalizations.of(ctx);
            return AlertDialog(
              title: Text(l.touchYourYubiKey),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.yubiKeyAuthorizeDeletion),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('delete_vault_yubikey_pin_field'),
                    controller: pinController,
                    obscureText: obscurePin,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l.yubiKeyPinLabel,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePin ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setDialogState(() => obscurePin = !obscurePin),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (!Platform.isLinux) ...[
                    const SizedBox(height: 12),
                    SegmentedRow<String>(
                      values: const ['usb', 'nfc'],
                      selected: dialogTransport,
                      label: (v) => v.toUpperCase(),
                      onSelected: (v) => setDialogState(() => dialogTransport = v),
                    ),
                  ],
                  if (isAuthorizing) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.tapYubiKeyNow,
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (authError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      authError!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l.cancel),
                ),
                TextButton(
                  onPressed: (isAuthorizing || pinController.text.isEmpty)
                      ? null
                      : () async {
                          setDialogState(() {
                            isAuthorizing = true;
                            authError = null;
                          });
                          try {
                            if (ykRecords.length == 1) {
                              final r = ykRecords.first;
                              await widget.onConfirmYubikey(
                                r.credentialId,
                                r.salt,
                                pinController.text,
                                dialogTransport,
                              );
                            } else {
                              await widget.onConfirmAnyYubikey(
                                ykRecords,
                                pinController.text,
                                dialogTransport,
                              );
                            }
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } catch (e) {
                            if (ctx.mounted) {
                              setDialogState(() {
                                isAuthorizing = false;
                                authError = switch (e) {
                                  PlatformException(code: 'TRANSPORT_ERROR') =>
                                    e.message ?? l.transportError,
                                  PlatformException(code: 'NO_FIDO2_DEVICE') =>
                                    e.message ?? l.noFidoDeviceFound,
                                  _ => l.authorizationFailed,
                                };
                              });
                            }
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  child: isAuthorizing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.authorize),
                ),
              ],
            );
          },
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => pinController.dispose());
      if (mounted) setState(() => _transport = dialogTransport);
      if (step3 != true) return;
      if (!mounted) return;
    }

    setState(() => _registry = _registry.remove(record.path));
    await widget.onDelete(record.path);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.manageVaultsTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _registry.records.isEmpty
                  ? Center(child: Text(l.noVaultsRegisteredText))
                  : ListView.builder(
                      itemCount: _registry.records.length,
                      itemBuilder: (_, i) {
                        final record = _registry.records[i];
                        return ListTile(
                          leading: const Icon(Icons.lock_outlined),
                          title: Text(record.alias),
                          subtitle: Text(
                            record.path,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () =>
                              widget.onSwitchToVault(record.path, record.alias),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: l.rename,
                                onPressed: () => _showRenameDialog(record),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outlined,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                tooltip: l.deleteVaultTooltip,
                                onPressed: () => _showDeleteDialog(record),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: widget.onAddVault,
                icon: const Icon(Icons.add),
                label: Text(l.addVault),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
