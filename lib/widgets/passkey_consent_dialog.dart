import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../passkey_daemon.dart';
import 'gabbro_dialog.dart';

/// Shows the in-app passkey consent pop-up for one request and returns the
/// chosen account index, or null if the user cancels. One account is a plain
/// approve/cancel; several are a tap-to-choose list (Android-parity, 16c). No
/// forced window raise — this appears over Gabbro when the user focuses it.
Future<int?> showPasskeyConsent(BuildContext context, PasskeyRequest request) {
  return showGabbroDialog<int>(
    context: context,
    builder: (ctx) => _PasskeyConsentDialog(request: request),
  );
}

class _PasskeyConsentDialog extends StatelessWidget {
  const _PasskeyConsentDialog({required this.request});

  final PasskeyRequest request;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final prompt = request.isCreate
        ? l.passkeyCreatePrompt(request.rpId)
        : l.passkeySignInPrompt(request.rpId);
    final several = request.accounts.length > 1;

    return AlertDialog(
      icon: const Icon(Icons.key),
      title: Text(prompt, textAlign: TextAlign.center),
      content: several
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < request.accounts.length; i++)
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(request.accounts[i]),
                    onTap: () => Navigator.of(context).pop(i),
                  ),
              ],
            )
          : (request.accounts.isNotEmpty
                ? Text(request.accounts.first, textAlign: TextAlign.center)
                : null),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l.cancel),
        ),
        // A single account confirms here; the chooser confirms by tapping a row.
        if (!several)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(0),
            child: Text(l.confirm),
          ),
      ],
    );
  }
}
