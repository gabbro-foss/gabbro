import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/api/import.dart';

/// Informational dialog shown after an import when one or more entries were
/// skipped because their UUID already exists in the vault.
///
/// The user acknowledges the list and dismisses. No action is required —
/// the local version of each skipped entry is preserved as-is.
///
/// Usage:
/// ```dart
/// await showSkippedEntriesDialog(context, skipped);
/// ```
Future<void> showSkippedEntriesDialog(
  BuildContext context,
  List<SkippedEntryData> skipped,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _SkippedEntriesDialog(skipped: skipped),
  );
}

class _SkippedEntriesDialog extends StatelessWidget {
  final List<SkippedEntryData> skipped;

  const _SkippedEntriesDialog({required this.skipped});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${skipped.length} ${skipped.length == 1 ? 'entry' : 'entries'} skipped',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These entries already exist in your vault and were not overwritten:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: skipped.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        skipped[i].title,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        skipped[i].reason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
