import 'package:flutter/material.dart';

/// Every dialog in the app goes through here instead of calling `showDialog`
/// directly.
///
/// Why: an `AlertDialog` gives its buttons a fixed strip at the bottom and lets
/// the message shrink to fit whatever is left. On a 360dp phone that message is
/// silently cut short at 2x text and gone entirely at 4x, where the buttons
/// have themselves been pushed off the bottom of the screen. `scrollable: true`
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
