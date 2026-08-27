import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/widgets/gabbro_dialog.dart';

import '../l10n/app_localizations.dart';

/// Opens [url] and tells the user when it did not work.
///
/// Two different outcomes need two different messages: a refused link is a
/// deliberate rule ("only web links"), while a failure is a malfunction
/// ("could not open"). Saying the wrong one sends the user looking for a fault
/// that is not there. Either way something is said — a button that silently
/// does nothing reads as broken.
///
/// It is a dialog, not a SnackBar: a SnackBar clips instead of scrolling, so at
/// the largest text sizes its message runs off the bottom of a phone screen and
/// the one explanation available cannot be read. Dialogs scroll as a whole.
///
/// The message is also announced on Linux, where a screen reader never reads a
/// transient notice; on Android TalkBack reads it already.
Future<void> openUrlAndReport(BuildContext context, String url) async {
  final result = await GabbroUrlOpener.open(url);
  if (!context.mounted) return;
  reportUrlOutcome(context, result, url);
}

/// Says what became of an attempt to open [url] — see [openUrlAndReport].
/// Separate so a caller that opens through its own seam still reports it the
/// same way.
void reportUrlOutcome(BuildContext context, UrlOpenResult result, String url) {
  if (result == UrlOpenResult.opened || !context.mounted) return;

  final l = AppLocalizations.of(context);
  final message = result == UrlOpenResult.notAWebLink
      ? l.onlyWebLinks
      : l.couldNotOpen(url);
  if (!Platform.isAndroid) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }
  showGabbroDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(AppLocalizations.of(ctx).close),
        ),
      ],
    ),
  );
}

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
    builder: (dialogContext) {
      final l = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.close),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l.openInBrowser),
            // Close this dialog first, and report through the screen behind it:
            // reporting first would put a second dialog on top, and the pop
            // would then close that instead of this one.
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await openUrlAndReport(context, url);
            },
          ),
        ],
      );
    },
  );
}
