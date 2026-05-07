import 'package:flutter/material.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/import.dart';

/// Blocking dialog shown after an import when one or more entries failed
/// domain validation.
///
/// Presents each failure in turn — title, source category, and rejection
/// reason — with two actions:
///
/// - **Edit**: opens [CreateEntryScreen] pre-populated with the raw field
///   values so the user can correct the offending field and save manually.
/// - **Skip**: discards the item.
///
/// The dialog does not close until every failure has been resolved (Edit or
/// Skip). This is intentional — failures should not be silently forgotten.
///
/// Usage:
/// ```dart
/// await showImportFailuresDialog(context, failures);
/// ```
/// Shows the import failures dialog and returns the number of entries
/// successfully saved via the Edit path.
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
      barrierDismissible: false, // must resolve each failure explicitly
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
    // Whether Edit or Skip (or backed out), this failure is resolved.
  }

  return savedViaEdit;
}

/// Maps a source category string to a Gabbro entry type string.
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Import issue ($index of $total)',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failure.title,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Type: ${failure.category}',
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
            'Edit to correct and save this entry, or skip to discard it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_FailureAction.skip),
          child: const Text('Skip'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_FailureAction.edit),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
      ],
    );
  }
}
