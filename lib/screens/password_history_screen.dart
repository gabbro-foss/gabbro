import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final prev = widget.entry.previousPassword;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Password history'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Warning banner ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Only 1 previous value is kept. '
                  'History auto-purges based on your security settings.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),

              // ── Current ────────────────────────────────────────────────
              _sectionHeader('Current'),
              const SizedBox(height: 8),
              _historyRow(
                meta: 'Saved ${formatTimestamp(widget.entry.updatedAt)}',
                value: widget.entry.password,
                obscured: _currentObscured,
                onToggle: () =>
                    setState(() => _currentObscured = !_currentObscured),
                trailing: Text(
                  'current',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),

              // ── Previous ───────────────────────────────────────────────
              if (prev != null) ...[
                const SizedBox(height: 16),
                _sectionHeader('Previous'),
                const SizedBox(height: 8),
                _historyRow(
                  meta: _prevMeta(prev),
                  value: prev.value,
                  obscured: _previousObscured,
                  onToggle: () =>
                      setState(() => _previousObscured = !_previousObscured),
                  trailing: TextButton(
                    onPressed: widget.onRevert,
                    child: const Text('Revert'),
                  ),
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
                  child: const Text('Delete previous entry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _prevMeta(PreviousSecretData prev) {
    final saved = 'Saved ${formatTimestamp(prev.savedAt)}';
    if (prev.expiresAt != null && prev.expiresAt!.isNotEmpty) {
      return '$saved · expires ${formatTimestamp(prev.expiresAt!)}';
    }
    return saved;
  }

  Widget _sectionHeader(String label) => Text(
        label,
        style:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      );

  Widget _historyRow({
    required String meta,
    required String value,
    required bool obscured,
    required VoidCallback onToggle,
    required Widget trailing,
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
                tooltip: obscured ? 'Show' : 'Hide',
                onPressed: onToggle,
              ),
              trailing,
            ],
          ),
        ],
      ),
    );
  }
}