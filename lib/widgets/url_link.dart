import 'package:flutter/material.dart';
import 'package:gabbro/widgets/gabbro_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Hands a URL to the system browser. Returns false when nothing could open it,
/// which the caller turns into a message rather than a silent no-op.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultOpenUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Overridable in tests; defaults to the real launcher.
UrlOpener openUrl = _defaultOpenUrl;

/// Restores [openUrl] to the production implementation (test teardown).
void resetUrlOpener() => openUrl = _defaultOpenUrl;

/// Show a URL to the user, then let them open it in the system browser.
///
/// Gabbro never opens a browser straight from a tap: the URL is shown first
/// (selectable, so it can be copied instead) and the user chooses. `externalApplication`
/// mode means the system browser, never an in-app webview.
///
/// Shared by the About screen's link/component tiles and the unlock screen's
/// vault-upgrade link so the behaviour — and the privacy property — is identical
/// wherever a link appears.
Future<void> showUrlDialog(
  BuildContext context, {
  required String title,
  required String url,
}) {
  return showGabbroDialog<void>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(title),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.close),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l.openInBrowser),
            onPressed: () async {
              final launched = await openUrl(Uri.parse(url));
              if (!launched && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context).couldNotOpen(url)),
                  ),
                );
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
