import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';

class PasswordHistoryScreen extends StatefulWidget {
  final LoginEntryData entry;
  final Future<void> Function() onDeleteHistory;
  final Future<void> Function() onRevert;

  const PasswordHistoryScreen({
    super.key,
    required this.entry,
    required this.onDeleteHistory,
    required this.onRevert,
  });

  @override
  State<PasswordHistoryScreen> createState() => _PasswordHistoryScreenState();
}

class _PasswordHistoryScreenState extends State<PasswordHistoryScreen> {
  bool _currentObscured = true;
  bool _previousObscured = true;

  String _prevMeta(AppLocalizations l, PreviousSecretData prev) {
    final saved = l.historySavedOn(formatTimestamp(prev.savedAt, locale: l.localeName));
    if (prev.expiresAt != null && prev.expiresAt!.isNotEmpty) {
      return l.historyExpiresAppend(
        saved,
        formatTimestamp(prev.expiresAt!, locale: l.localeName),
      );
    }
    return saved;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final prev = widget.entry.previousPassword;

    return Scaffold(
      appBar: AppBar(title: Text(l.passwordHistoryTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l.historyWarning,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),

              _sectionHeader(l.historyCurrent),
              const SizedBox(height: 8),
              _historyRow(
                l: l,
                meta: l.historySavedOn(formatTimestamp(widget.entry.updatedAt, locale: l.localeName)),
                value: widget.entry.password,
                obscured: _currentObscured,
                onToggle: () =>
                    setState(() => _currentObscured = !_currentObscured),
              ),

              if (prev != null) ...[
                const SizedBox(height: 16),
                _sectionHeader(l.historyPrevious),
                const SizedBox(height: 8),
                _historyRow(
                  l: l,
                  meta: _prevMeta(l, prev),
                  value: prev.value,
                  obscured: _previousObscured,
                  onToggle: () =>
                      setState(() => _previousObscured = !_previousObscured),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: widget.onDeleteHistory,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  child: Text(l.deleteEntryFromHistoryLabel),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: widget.onRevert,
                  child: Text(l.revert),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) => Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      );

  Widget _historyRow({
    required AppLocalizations l,
    required String meta,
    required String value,
    required bool obscured,
    required VoidCallback onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meta,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  obscured ? '••••••••' : value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  obscured ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                tooltip: obscured ? l.tooltipShow : l.tooltipHide,
                onPressed: onToggle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
