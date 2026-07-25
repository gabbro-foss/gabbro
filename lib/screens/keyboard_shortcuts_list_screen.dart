import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';

/// Read-only reference of the desktop keyboard shortcuts (Linux). Reached from
/// the vault-list overflow menu; not offered on Android, which has no physical
/// keyboard. The key combos are literal identifiers (not localised); only the
/// descriptions are. Keep in sync with the wiring in main.dart (Ctrl+L / Ctrl+N /
/// Ctrl+M) and vault_list_screen.dart (Ctrl+F / Ctrl+Shift+F). Ctrl+N / Ctrl+M
/// reuse the existing New-entry / Menu labels (DRY).
class KeyboardShortcutsListScreen extends StatelessWidget {
  const KeyboardShortcutsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.keyboardShortcutsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(l.kbSectionGeneral, const [
            ('Ctrl+L', null),
            ('Ctrl+N', null),
            ('Ctrl+M', null),
          ], descriptions: [l.kbLockVault, l.newEntryTitle, l.tooltipMenu]),
          _Section(l.kbSectionSearch, const [
            ('Ctrl+F', null),
            ('Ctrl+Shift+F', null),
          ], descriptions: [l.kbFocusSearch, l.kbSearchAllFields]),
          _Section(l.kbSectionNavigation, const [
            ('Tab / Shift+Tab', null),
            ('Enter / Space', null),
            ('Esc', null),
          ], descriptions: [
            l.kbMoveBetweenControls,
            l.kbActivateControl,
            l.kbCloseDialog,
          ]),
          const SizedBox(height: 20),
          Text(
            l.kbNoCopyNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  // Only the combo is used from each record; descriptions come in parallel so
  // the const combo list stays const.
  final List<(String, Object?)> combos;
  final List<String> descriptions;
  const _Section(this.title, this.combos, {required this.descriptions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        for (var i = 0; i < combos.length; i++)
          _Shortcut(combo: combos[i].$1, description: descriptions[i]),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  final String combo;
  final String description;
  const _Shortcut({required this.combo, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A combo can be an unbreakable token (e.g. Ctrl+Shift+F); at very
          // large text it would overflow, so let the badge scroll horizontally
          // rather than clip.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                combo,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
