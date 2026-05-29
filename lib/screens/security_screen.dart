import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/widgets/segmented_row.dart';

class SecurityScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(AppSettings) onUpdate;

  const SecurityScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
  });

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(AppSettings updated) {
    widget.onUpdate(updated);
    setState(() => _settings = updated);
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
              Text(l.foregroundLockDescription, style: const TextStyle(fontSize: 12)),
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
              Text(l.backgroundLockDescription, style: const TextStyle(fontSize: 12)),
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
              Text(l.passwordHistoryDescription, style: const TextStyle(fontSize: 12)),
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
              Text(l.passphraseCopyPasteDescription, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l.blockCopyPasteTitle),
                value: _settings.blockPassphraseCopyPaste,
                onChanged: (v) =>
                    _update(_settings.copyWith(blockPassphraseCopyPaste: v)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              Text(l.passphraseCopyPasteNote, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 32),

              // ── Vault list ─────────────────────────────────────────────
              SectionHeader(label: l.sectionVaultList),
              const SizedBox(height: 4),
              Text(l.vaultListDescription, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l.showVaultListTitle),
                value: _settings.showVaultList,
                onChanged: (v) =>
                    _update(_settings.copyWith(showVaultList: v)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              Text(l.vaultListNote, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 32),

              // ── Clipboard clear ────────────────────────────────────────
              SectionHeader(label: l.sectionClipboardClear),
              const SizedBox(height: 4),
              Text(l.clipboardClearDescription, style: const TextStyle(fontSize: 12)),
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
