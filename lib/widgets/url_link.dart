import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:gabbro/gabbro_url_opener.dart';
import 'package:gabbro/widgets/gabbro_dialog.dart';

import '../l10n/app_localizations.dart';

/// A refused link (a rule) and a failed one (a malfunction) get different
/// messages, or the user hunts for a fault that is not there. A dialog, not a
/// SnackBar: a SnackBar clips, so at large text the one explanation runs off
/// the screen. Announced on Linux, where a reader never reads a transient
/// notice.
Future<void> openUrlAndReport(BuildContext context, String url) async {
  final result = await GabbroUrlOpener.open(url);
  if (!context.mounted) return;
  reportUrlOutcome(context, result, url);
}

/// Says what became of an attempt to open [url] - see [openUrlAndReport].
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

/// The URL is shown (and copyable) before anything opens, and it opens in the
/// system browser, never an in-app webview. Shared by every link so the
/// privacy property is identical everywhere.
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
