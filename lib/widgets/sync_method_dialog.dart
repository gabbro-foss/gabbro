import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';

/// Asks how an incoming sync should be applied.
///
/// Pops `true` for the automatic merge (incoming wins, no prompts), `false` for
/// the one-by-one review, and `null` when the user backs out — which merges
/// nothing.
class SyncMethodDialog extends StatelessWidget {
  const SyncMethodDialog({super.key, this.showsPassphraseWarning = false});

  /// A passphrase-only save keeps nothing per-vault, so "it opened" proves
  /// only "same passphrase" — the dialog then warns before anything applies.
  /// A keyed file that is not the same vault fails to decrypt outright, so
  /// the keyed path leaves this off.
  final bool showsPassphraseWarning;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      // All three choices are long buttons, so they live in scrollable content.
      // An AlertDialog never scrolls its `actions`: a Cancel left there can be
      // pushed off the bottom of a 360dp phone at the 2x device ceiling and
      // cannot be tapped at all. Cancel therefore sits with the other two, and
      // replaces the barrier tap (ADR-016).
      scrollable: true,
      title: Text(l.syncMethodTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showsPassphraseWarning) ...[
            Text(l.syncSamePassphraseWarning),
            const SizedBox(height: 12),
          ],
          // "Merge automatically" named an action without saying what it did,
          // so it went unused. The paragraph is for sighted users; the
          // semanticsLabel below carries the same meaning to a screen reader,
          // which on Linux reads only a widget's NAME and never announces this
          // paragraph when the dialog opens. semanticsLabel (not a Semantics
          // wrapper) so the button keeps its own tap action and button role.
          Text(l.syncMethodExplainer),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l.syncMergeAutomatically,
              semanticsLabel: l.syncMergeAutomaticallySemantic,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              l.syncReviewAllChanges,
              semanticsLabel: l.syncReviewAllChangesSemantic,
            ),
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
