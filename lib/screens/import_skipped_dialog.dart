import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/src/rust/api/import.dart';

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
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      // scrollable scrolls the note + list + actions together; the list below
      // is shrinkWrapped + non-scrolling so there is no fixed height to clip and
      // no nested scroll (ADR-016).
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.info_outline, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.entriesSkipped(skipped.length),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      // A plain Column (not a ListView) so it works inside scrollable:true's
      // intrinsic-width pass; the dialog's own scroll handles overflow (ADR-016).
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.skippedEntriesNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < skipped.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(skipped[i].title, style: theme.textTheme.bodyMedium),
                  Text(
                    skipped[i].reason,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.ok),
        ),
      ],
    );
  }
}
