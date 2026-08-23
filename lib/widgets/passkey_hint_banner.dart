import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../passkey_daemon.dart';

/// Vault-list notice that the passkey provider is inactive (Linux): names the
/// cause and points at the README fix, because the failure is otherwise
/// silent — passkeys just never appear in the browser. X hides it for this
/// session; "Don't show again" hides it forever (the caller persists it).
class PasskeyHintBanner extends StatelessWidget {
  const PasskeyHintBanner({
    super.key,
    required this.reason,
    required this.onDismiss,
    required this.onDismissForever,
  });

  final PasskeyFailureReason reason;
  final VoidCallback onDismiss;
  final VoidCallback onDismissForever;

  /// The reason-specific message; also what the vault list announces to a
  /// screen reader when the banner appears (Linux reads only names).
  static String message(AppLocalizations l10n, PasskeyFailureReason reason) =>
      switch (reason) {
        PasskeyFailureReason.moduleMissing => l10n.passkeyHintModuleMissing,
        PasskeyFailureReason.noAccess => l10n.passkeyHintNoAccess,
        PasskeyFailureReason.other => l10n.passkeyHintOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        // The banner is the vault list's bottomNavigationBar: cap it so a
        // verbose locale at max text scale scrolls here instead of pushing
        // the list off screen.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(message(l10n, reason)),
                  ),
                ),
                // OverflowBar: at large text scales the buttons drop onto
                // their own lines instead of overflowing a fixed row.
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onDismissForever,
                      child: Text(l10n.passkeyHintDontShowAgain),
                    ),
                    IconButton(
                      tooltip: l10n.dismiss,
                      icon: Icon(Icons.close, semanticLabel: l10n.dismiss),
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
