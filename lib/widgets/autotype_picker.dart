import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gabbro/control_scale.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/autotype_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

/// Keyboard-first picker for Linux auto-type (ADR-017 3.5): choose a login and
/// which part(s) to type into the window that was focused at trigger time.
///
/// Type to filter, Up/Down or Ctrl+J/K to move, Enter to fill (full), Ctrl+U /
/// Ctrl+P for username-/password-only, Esc to cancel. The two per-row buttons
/// mirror the variants for the mouse and carry tooltips/Semantics. Text and
/// targets scale with the app text size (ADR-016).
class AutotypePicker extends StatefulWidget {
  const AutotypePicker({
    super.key,
    required this.logins,
    required this.onSelect,
    required this.onCancel,
  });

  final List<EntrySummaryData> logins;
  final void Function(String entryId, AutotypeSequenceKind kind) onSelect;
  final VoidCallback onCancel;

  @override
  State<AutotypePicker> createState() => _AutotypePickerState();
}

class _AutotypePickerState extends State<AutotypePicker> {
  final _query = TextEditingController();
  int _highlight = 0;

  List<EntrySummaryData> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.logins;
    return widget.logins
        .where((e) => e.searchBlob.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged() => setState(() => _highlight = 0);

  void _move(int delta) {
    final n = _filtered.length;
    if (n == 0) return;
    setState(() => _highlight = (_highlight + delta).clamp(0, n - 1));
  }

  void _selectHighlighted(AutotypeSequenceKind kind) {
    final list = _filtered;
    if (list.isEmpty || _highlight >= list.length) return;
    widget.onSelect(list[_highlight].id, kind);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final filtered = _filtered;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
            _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _move(-1),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
            _selectHighlighted(AutotypeSequenceKind.usernameOnly),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            _selectHighlighted(AutotypeSequenceKind.passwordOnly),
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  onChanged: (_) => _onQueryChanged(),
                  onSubmitted: (_) =>
                      _selectHighlighted(AutotypeSequenceKind.full),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l.searchEntriesHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        key: const Key('autotype-empty'),
                        child: Text(l.noEntriesMatch),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final e = filtered[i];
                          return ListTile(
                            selected: i == _highlight,
                            title: Text(e.title),
                            onTap: () => widget.onSelect(
                              e.id,
                              AutotypeSequenceKind.full,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.person_outline),
                                  iconSize: scaledIconSize(context),
                                  tooltip: l.autotypeTypeUsername,
                                  onPressed: () => widget.onSelect(
                                    e.id,
                                    AutotypeSequenceKind.usernameOnly,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.password),
                                  iconSize: scaledIconSize(context),
                                  tooltip: l.autotypeTypePassword,
                                  onPressed: () => widget.onSelect(
                                    e.id,
                                    AutotypeSequenceKind.passwordOnly,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                key: const Key('autotype-hint-footer'),
                padding: const EdgeInsets.all(8),
                child: Text(
                  l.autotypeKeyHints,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
