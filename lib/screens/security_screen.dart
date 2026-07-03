import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/widgets/segmented_row.dart';

const _biometricChannel = MethodChannel('app.gabbro.gabbro/biometric');

Future<bool> _defaultBiometricIsEnrolled(String vaultPath) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _biometricChannel.invokeMethod<bool>('isEnrolled', {
          'vaultPath': vaultPath,
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

Future<bool> _defaultBiometricAvailable() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _biometricChannel.invokeMethod<bool>('isAvailable') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> _defaultBiometricEnroll(
  List<int> passphrase,
  String vaultPath,
) async {
  if (!Platform.isAndroid) return;
  await _biometricChannel.invokeMethod<void>('enroll', {
    'passphrase': passphrase
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    'vaultPath': vaultPath,
  });
}

Future<void> _defaultBiometricUnenroll() async {
  if (!Platform.isAndroid) return;
  try {
    await _biometricChannel.invokeMethod<void>('unenroll');
  } catch (_) {}
}

class SecurityScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(AppSettings) onUpdate;

  /// Injected for testing; production code uses [Platform.isAndroid].
  final bool isAndroid;

  final Future<bool> Function() onBiometricAvailable;

  /// Vault path the passphrase is being enrolled for (null only in tests that
  /// don't need vault-scoped biometrics).
  final String? vaultPath;
  final Future<bool> Function(String vaultPath) onBiometricIsEnrolled;
  final Future<void> Function(List<int> passphrase, String vaultPath)
  onBiometricEnroll;
  final Future<void> Function() onBiometricUnenroll;

  SecurityScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
    bool? isAndroid,
    this.vaultPath,
    this.onBiometricIsEnrolled = _defaultBiometricIsEnrolled,
    this.onBiometricAvailable = _defaultBiometricAvailable,
    this.onBiometricEnroll = _defaultBiometricEnroll,
    this.onBiometricUnenroll = _defaultBiometricUnenroll,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late AppSettings _settings;
  bool _biometricEnrolled = false;
  // Owned by the State (not the dialog) so it is never disposed mid-exit-
  // animation; cleared before and after each prompt to wipe the passphrase.
  final _enrollPassController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    if (widget.isAndroid && widget.vaultPath != null) {
      widget.onBiometricIsEnrolled(widget.vaultPath!).then((enrolled) {
        if (mounted) setState(() => _biometricEnrolled = enrolled);
      });
    }
  }

  @override
  void dispose() {
    _enrollPassController.dispose();
    super.dispose();
  }

  void _update(AppSettings updated) {
    widget.onUpdate(updated);
    setState(() => _settings = updated);
  }

  Future<void> _handleBiometricToggle(bool enable, AppLocalizations l) async {
    if (!enable) {
      await widget.onBiometricUnenroll();
      setState(() => _biometricEnrolled = false);
      _update(_settings.copyWith(biometricUnlock: false));
      return;
    }

    final available = await widget.onBiometricAvailable();
    if (!mounted) return;
    if (!available) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.biometricUnavailable)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // scrollable scrolls title + content + actions together, so nothing is
        // stranded off-screen at large text (ADR-016).
        scrollable: true,
        title: Text(l.biometricDialogTitle),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.biometricDialogBody),
            const SizedBox(height: 12),
            Text(
              l.biometricDialogAllBiometrics,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(l.biometricDialogInvalidation),
            const SizedBox(height: 8),
            Text(
              l.biometricDialogRecommendation,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.continueAction),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final passphrase = await _promptPassphrase(l);
    if (!mounted || passphrase == null) return;

    try {
      await widget.onBiometricEnroll(passphrase, widget.vaultPath ?? '');
      if (mounted) {
        setState(() => _biometricEnrolled = true);
        _update(_settings.copyWith(biometricUnlock: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<List<int>?> _promptPassphrase(AppLocalizations l) async {
    final controller = _enrollPassController..clear();
    // obscured lives outside the StatefulBuilder so it survives rebuilds.
    bool obscured = true;
    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(l.biometricEnrollTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.biometricEnrollDescription),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: obscured,
                autofocus: true,
                onSubmitted: (_) =>
                    Navigator.of(ctx2).pop(controller.text.codeUnits),
                decoration: InputDecoration(
                  labelText: l.passphraseLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscured ? Icons.visibility_off : Icons.visibility,
                    ),
                    tooltip: obscured ? l.tooltipShow : l.tooltipHide,
                    onPressed: () => setDialogState(() => obscured = !obscured),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx2).pop(null),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx2).pop(controller.text.codeUnits),
              child: Text(l.confirm),
            ),
          ],
        ),
      ),
    );
    controller
        .clear(); // wipe the passphrase; the controller lives on the State
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.securityTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Foreground lock ────────────────────────────────────────
              SectionHeader(label: l.sectionForegroundLock),
              const SizedBox(height: 4),
              Text(
                l.foregroundLockDescription,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<ForegroundLockTimeout>(
                values: ForegroundLockTimeout.values,
                selected: _settings.foregroundLockTimeout,
                label: (v) => switch (v) {
                  ForegroundLockTimeout.thirtySeconds => l.duration30s,
                  ForegroundLockTimeout.oneMinute => l.duration1min,
                  ForegroundLockTimeout.fiveMinutes => l.duration5min,
                  ForegroundLockTimeout.never => l.durationNever,
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(foregroundLockTimeout: v)),
              ),
              const SizedBox(height: 32),

              // ── Background lock ────────────────────────────────────────
              SectionHeader(label: l.sectionBackgroundLock),
              const SizedBox(height: 4),
              Text(
                l.backgroundLockDescription,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<BackgroundLockTimeout>(
                values: BackgroundLockTimeout.values,
                selected: _settings.backgroundLockTimeout,
                label: (v) => switch (v) {
                  BackgroundLockTimeout.oneMinute => l.duration1min,
                  BackgroundLockTimeout.fiveMinutes => l.duration5min,
                  BackgroundLockTimeout.fifteenMinutes => l.duration15min,
                  BackgroundLockTimeout.never => l.durationNever,
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(backgroundLockTimeout: v)),
              ),
              const SizedBox(height: 32),

              // ── Password history ───────────────────────────────────────
              SectionHeader(label: l.sectionPasswordHistory),
              const SizedBox(height: 4),
              Text(
                l.passwordHistoryDescription,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<PasswordHistoryExpiry>(
                values: PasswordHistoryExpiry.values,
                selected: _settings.passwordHistoryExpiry,
                label: (v) => switch (v) {
                  PasswordHistoryExpiry.sevenDays => l.duration7days,
                  PasswordHistoryExpiry.thirtyDays => l.duration30days,
                  PasswordHistoryExpiry.ninetyDays => l.duration90days,
                  PasswordHistoryExpiry.keepForever => l.durationKeepForever,
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(passwordHistoryExpiry: v)),
              ),
              const SizedBox(height: 32),

              // ── Passphrase copy/paste ──────────────────────────────────
              SectionHeader(label: l.sectionPassphraseCopyPaste),
              const SizedBox(height: 4),
              Text(
                l.passphraseCopyPasteDescription,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l.blockCopyPasteTitle),
                value: _settings.blockPassphraseCopyPaste,
                onChanged: (v) =>
                    _update(_settings.copyWith(blockPassphraseCopyPaste: v)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              Text(
                l.passphraseCopyPasteNote,
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 32),

              // ── Biometric unlock (Android only) ───────────────────────
              if (widget.isAndroid) ...[
                SectionHeader(label: l.sectionBiometricUnlock),
                const SizedBox(height: 4),
                Text(
                  l.biometricUnlockDescription,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: Text(l.biometricUnlockTitle),
                  value: _biometricEnrolled,
                  onChanged: (v) => _handleBiometricToggle(v, l),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                Text(
                  l.biometricUnlockNote,
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 32),
              ],

              // ── Clipboard clear ────────────────────────────────────────
              SectionHeader(label: l.sectionClipboardClear),
              const SizedBox(height: 4),
              Text(
                l.clipboardClearDescription,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<ClipboardClearTimeout>(
                values: ClipboardClearTimeout.values,
                selected: _settings.clipboardClearTimeout,
                label: (v) => switch (v) {
                  ClipboardClearTimeout.never => l.durationNever,
                  ClipboardClearTimeout.thirtySeconds => l.duration30s,
                  ClipboardClearTimeout.sixtySeconds => l.duration60s,
                  ClipboardClearTimeout.twoMinutes => l.duration2min,
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(clipboardClearTimeout: v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
