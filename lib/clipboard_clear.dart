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

/// App-level, not per-widget (RT-4): a wipe owned by the copying State dies in
/// its dispose, so copying then pressing back left the secret on the clipboard
/// for good. One pending wipe app-wide; copying again cancels the prior one.
class ClipboardWiper {
  Timer? _timer;

  /// Whether a wipe is scheduled - i.e. Gabbro put a secret on the clipboard
  /// and has not wiped it yet. Never true for [ClipboardClearTimeout.never].
  bool get hasPendingWipe => _timer != null;

  /// Writes [value] to the clipboard, cancels any pending wipe, and schedules a
  /// fresh one per [timeout] (none for [ClipboardClearTimeout.never]).
  Future<void> copyThenClear(String value, ClipboardClearTimeout timeout) async {
    await Clipboard.setData(ClipboardData(text: value));
    _timer?.cancel();
    _timer = null;
    final delay = clipboardClearDelay(timeout);
    if (delay != null) _timer = Timer(delay, _wipe);
  }

  /// Wipe now instead of waiting out the delay - auto-lock only, meaning the
  /// user walked away. A no-op unless a wipe is actually pending, so it can
  /// never clear a clipboard Gabbro did not write, and never overrides
  /// [ClipboardClearTimeout.never].
  void wipeNow() {
    if (_timer == null) return;
    _timer!.cancel();
    _wipe();
  }

  /// Drop a pending wipe without touching the clipboard. For tests - production
  /// has no reason to forget a wipe it promised.
  @visibleForTesting
  void cancelPending() {
    _timer?.cancel();
    _timer = null;
  }

  void _wipe() {
    _timer = null;
    Clipboard.setData(const ClipboardData(text: ''));
  }
}

/// App-wide wiper shared by every copy-a-secret site and the auto-lock path.
final clipboardWiper = ClipboardWiper();
