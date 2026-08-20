import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The passkey consent screen (Android provider phase 2).
///
/// Shown after the vault is unlocked, before any key is minted or any
/// challenge is signed: the user sees WHICH site is asking and WHAT they are
/// approving. Cancel hands the OS a refusal; nothing leaves the vault.
class PasskeyConsentScreen extends StatelessWidget {
  final bool isCreate;
  final String rpId;
  final String userName;
  final VoidCallback onApprove;
  final VoidCallback onCancel;

  const PasskeyConsentScreen({
    super.key,
    required this.isCreate,
    required this.rpId,
    required this.userName,
    required this.onApprove,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final prompt = isCreate
        ? l.passkeyCreatePrompt(rpId)
        : l.passkeySignInPrompt(rpId);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.key, size: 48),
                const SizedBox(height: 16),
                Text(
                  prompt,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if (userName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    userName,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                // OverflowBar wraps to a column when large text or a narrow
                // screen would overflow a fixed row.
                OverflowBar(
                  alignment: MainAxisAlignment.center,
                  spacing: 16,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.center,
                  children: [
                    TextButton(
                      onPressed: onCancel,
                      child: Text(l.cancel),
                    ),
                    FilledButton(
                      onPressed: onApprove,
                      child: Text(l.confirm),
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
