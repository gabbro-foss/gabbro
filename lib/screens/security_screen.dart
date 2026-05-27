import 'package:flutter/material.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Foreground lock ────────────────────────────────────────
              SectionHeader(label: 'Foreground lock'),
              const SizedBox(height: 4),
              const Text(
                'Lock after this much inactivity while the app is open.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<ForegroundLockTimeout>(
                values: ForegroundLockTimeout.values,
                selected: _settings.foregroundLockTimeout,
                label: (v) => switch (v) {
                  ForegroundLockTimeout.thirtySeconds => '30s',
                  ForegroundLockTimeout.oneMinute => '1 min',
                  ForegroundLockTimeout.fiveMinutes => '5 min',
                  ForegroundLockTimeout.never => 'Never',
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(foregroundLockTimeout: v)),
              ),
              const SizedBox(height: 32),

              // ── Background lock ────────────────────────────────────────
              SectionHeader(label: 'Background lock'),
              const SizedBox(height: 4),
              const Text(
                'Lock after the app has been in the background for this long.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<BackgroundLockTimeout>(
                values: BackgroundLockTimeout.values,
                selected: _settings.backgroundLockTimeout,
                label: (v) => switch (v) {
                  BackgroundLockTimeout.oneMinute => '1 min',
                  BackgroundLockTimeout.fiveMinutes => '5 min',
                  BackgroundLockTimeout.fifteenMinutes => '15 min',
                  BackgroundLockTimeout.never => 'Never',
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(backgroundLockTimeout: v)),
              ),
              const SizedBox(height: 32),

              // ── Password history ───────────────────────────────────────
              SectionHeader(label: 'Password history'),
              const SizedBox(height: 4),
              const Text(
                'How long to keep a previous password after it is changed. '
                '"Keep forever" means history is only deleted manually.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<PasswordHistoryExpiry>(
                values: PasswordHistoryExpiry.values,
                selected: _settings.passwordHistoryExpiry,
                label: (v) => switch (v) {
                  PasswordHistoryExpiry.sevenDays => '7 days',
                  PasswordHistoryExpiry.thirtyDays => '30 days',
                  PasswordHistoryExpiry.ninetyDays => '90 days',
                  PasswordHistoryExpiry.keepForever => 'Keep forever',
                },
                onSelected: (v) =>
                    _update(_settings.copyWith(passwordHistoryExpiry: v)),
              ),
              const SizedBox(height: 32),

              // ── Passphrase copy/paste ──────────────────────────────────
              SectionHeader(label: 'Passphrase copy/paste'),
              const SizedBox(height: 4),
              const Text(
                'Block copy and paste on master passphrase fields. '
                'Recommended: prevents passphrase leaking via clipboard.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Block copy/paste'),
                value: _settings.blockPassphraseCopyPaste,
                onChanged: (v) =>
                    _update(_settings.copyWith(blockPassphraseCopyPaste: v)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              const Text(
                'Note: this blocks the long-press context menu and text selection. '
                'Your keyboard\'s inline paste button may still work — '
                'this is a platform limitation that cannot be blocked.',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 32),

              // ── Vault list ─────────────────────────────────────────────
              SectionHeader(label: 'Vault list'),
              const SizedBox(height: 4),
              const Text(
                'Show a dropdown of all vaults on the login screen so you can '
                'pick which one to unlock without going to Manage vaults.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Show vault list on login'),
                value: _settings.showVaultList,
                onChanged: (v) =>
                    _update(_settings.copyWith(showVaultList: v)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              const Text(
                'High-security note: when this is OFF, the login screen shows '
                'only the last-used vault — no hint that other vaults exist. '
                'Trade-off: to switch vaults you must first unlock, then go to '
                'Menu → Manage vaults.',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 32),

              // ── Clipboard clear ────────────────────────────────────────
              SectionHeader(label: 'Clipboard clear'),
              const SizedBox(height: 4),
              const Text(
                'Clear the clipboard this long after copying a secret. '
                'Note: clipboard managers may retain a copy.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedRow<ClipboardClearTimeout>(
                values: ClipboardClearTimeout.values,
                selected: _settings.clipboardClearTimeout,
                label: (v) => switch (v) {
                  ClipboardClearTimeout.never => 'Never',
                  ClipboardClearTimeout.thirtySeconds => '30s',
                  ClipboardClearTimeout.sixtySeconds => '60s',
                  ClipboardClearTimeout.twoMinutes => '2 min',
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
