import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// The delay after which the clipboard is wiped for a given [timeout], or
/// `null` for [ClipboardClearTimeout.never] (no wipe is scheduled). This is the
/// single home for the enum -> duration mapping that entry-detail, the
/// generator, and any future copy-a-secret site share.
Duration? clipboardClearDelay(ClipboardClearTimeout timeout) => switch (timeout) {
      ClipboardClearTimeout.never => null,
      ClipboardClearTimeout.thirtySeconds => const Duration(seconds: 30),
      ClipboardClearTimeout.sixtySeconds => const Duration(seconds: 60),
      ClipboardClearTimeout.twoMinutes => const Duration(minutes: 2),
    };

/// Shared "copy a secret, then wipe the clipboard" behaviour for any [State].
///
/// Owns the single pending clear timer: copying again cancels the prior wipe,
/// [dispose] cancels a pending wipe so it never fires after the widget is gone,
/// and a [ClipboardClearTimeout.never] timeout schedules no wipe at all. A site
/// adopts it with `with ClipboardClearMixin` and calls [copyThenClear]; its own
/// user feedback (snackbar, checkmark) stays its own concern.
mixin ClipboardClearMixin<T extends StatefulWidget> on State<T> {
  Timer? _clipboardClearTimer;

  /// Writes [value] to the clipboard, cancels any pending wipe, and schedules a
  /// fresh wipe per [timeout] (none for [ClipboardClearTimeout.never]).
  Future<void> copyThenClear(String value, ClipboardClearTimeout timeout) async {
    await Clipboard.setData(ClipboardData(text: value));
    _clipboardClearTimer?.cancel();
    final delay = clipboardClearDelay(timeout);
    if (delay != null) {
      _clipboardClearTimer = Timer(delay, () {
        Clipboard.setData(const ClipboardData(text: ''));
      });
    }
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    super.dispose();
  }
}
