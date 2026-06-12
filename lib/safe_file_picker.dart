import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

/// A thin, tested seam around `file_picker`'s native dialogs.
///
/// On Linux `file_picker` reaches the system file dialog *only* through the XDG
/// Desktop Portal over the DBus session bus. Inside a sandbox (e.g. a Wayland
/// bubblewrap launch) where that bus socket isn't bound in, the underlying
/// `DBusClient` throws a `SocketException` that otherwise propagates unhandled
/// and crashes the isolate. `runPicker` converts any such failure into a typed
/// [FilePickerUnavailable] so callers can degrade gracefully — the editable
/// path fields are the manual fallback.

/// Thrown when the native file dialog could not be reached (typically the XDG
/// portal / DBus session bus is unavailable in a sandbox). Carries the
/// underlying [cause] for logging.
class FilePickerUnavailable implements Exception {
  final Object cause;

  const FilePickerUnavailable(this.cause);

  @override
  String toString() => 'FilePickerUnavailable: $cause';
}

/// Runs a native-picker operation, passing its result through unchanged
/// (including `null`, which means the user cancelled). Any thrown exception is
/// rethrown as [FilePickerUnavailable].
Future<T?> runPicker<T>(Future<T?> Function() op) async {
  try {
    return await op();
  } on Exception catch (e) {
    throw FilePickerUnavailable(e);
  }
}

/// Shows the consistent "native dialog unavailable" SnackBar. Call from a
/// [FilePickerUnavailable] catch block. When [hasManualEntry] is true (the
/// caller has an editable path field), the copy points the user at it;
/// otherwise it just states the portal is unreachable.
void showPickerUnavailable(BuildContext context, {bool hasManualEntry = true}) {
  final l = AppLocalizations.of(context);
  final message =
      hasManualEntry ? l.filePickerUnavailable : l.filePickerNoPortal;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
