import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:gabbro/l10n/app_localizations.dart';

/// Every dialog in the app goes through here instead of calling `showDialog`
/// directly.
///
/// Why: an `AlertDialog` gives its buttons a fixed strip at the bottom and lets
/// the message shrink to fit whatever is left. On a 360dp phone at the 2x
/// device ceiling that message is silently cut short and the buttons can be
/// pushed off the bottom of the screen. `scrollable: true`
/// does not help — it scrolls the title and content, never the actions.
///
/// So the whole dialog is put inside a scroll view instead: centred exactly as
/// before while it fits, scrollable once it does not.
Future<T?> showGabbroDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _ScrollWholeDialog(child: builder(ctx)),
  );
}

/// Shows a failure [message] in a dialog that scrolls as a whole, so the one
/// explanation the user gets is never clipped the way a SnackBar clips long
/// text at large scale (same fix as the URL refusal, ADR-016). Announced on
/// Linux, where a screen reader is not told a dialog appeared.
Future<void> showFailureMessage(BuildContext context, String message) {
  if (!Platform.isAndroid) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }
  return showGabbroDialog<void>(
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

class _ScrollWholeDialog extends StatelessWidget {
  const _ScrollWholeDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // The scroll view covers the whole screen. Left opaque it would eat
        // the tap beside the dialog that is meant to dismiss it, so hit tests
        // fall through wherever the dialog itself is not.
        hitTestBehavior: HitTestBehavior.deferToChild,
        // Fill the screen when the dialog is smaller than it, so Center still
        // centres; grow past it when the dialog is taller, so it scrolls.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
