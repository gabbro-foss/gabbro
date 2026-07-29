import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';

/// Asks how an incoming sync should be applied.
///
/// Pops `true` for the automatic merge (incoming wins, no prompts), `false` for
/// the one-by-one review, and `null` when the user backs out — which merges
/// nothing.
class SyncMethodDialog extends StatelessWidget {
  const SyncMethodDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      // All three choices are long buttons, so they live in scrollable content.
      // An AlertDialog never scrolls its `actions`: a Cancel left there is
      // pushed off the bottom of a 360dp phone at the maximum supported text
      // scale (8x) and cannot be tapped at all, and the dialog overflows in 32
      // of the 37 languages. Cancel therefore sits with the other two, and
      // replaces the barrier tap (ADR-016).
      scrollable: true,
      title: Text(l.syncMethodTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.syncMergeAutomatically),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.syncReviewAllChanges),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.cancel),
          ),
        ],
      ),
    );
  }
}
