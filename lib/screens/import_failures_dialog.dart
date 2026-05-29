import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';

Future<int> showImportFailuresDialog(
  BuildContext context,
  List<ImportFailureData> failures,
) async {
  var savedViaEdit = 0;

  for (var i = 0; i < failures.length; i++) {
    if (!context.mounted) break;
    final failure = failures[i];

    final resolved = await showDialog<_FailureAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImportFailureDialog(
        failure: failure,
        index: i + 1,
        total: failures.length,
      ),
    );

    if (!context.mounted) break;

    if (resolved == _FailureAction.edit) {
      final entryType = _categoryToEntryType(failure.category);
      final prefill = Map<String, String>.fromEntries(
        failure.rawFields.map((pair) => MapEntry(pair.$1, pair.$2)),
      );
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CreateEntryScreen(
            entryType: entryType,
            prefill: prefill,
          ),
        ),
      );
      if (saved == true) savedViaEdit++;
    }
  }

  return savedViaEdit;
}

String _categoryToEntryType(String category) {
  return switch (category.toLowerCase()) {
    'creditcard' => 'Card',
    'login' || 'computer' || 'finance' => 'Login',
    'note' => 'Note',
    _ => 'Custom',
  };
}

enum _FailureAction { edit, skip }

class _ImportFailureDialog extends StatelessWidget {
  final ImportFailureData failure;
  final int index;
  final int total;

  const _ImportFailureDialog({
    required this.failure,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.importIssueTitle(index, total),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(failure.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            l.importIssueType(failure.category),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              failure.reason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.importIssueHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_FailureAction.skip),
          child: Text(l.skip),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_FailureAction.edit),
          icon: const Icon(Icons.edit_outlined),
          label: Text(l.edit),
        ),
      ],
    );
  }
}
