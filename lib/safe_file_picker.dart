import 'dart:io';

import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'src/rust/api/simple.dart';

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

/// Raises (`true`) or lowers (`false`) the process `PR_SET_DUMPABLE` flag while
/// a native file dialog is open. R-04 keeps the process non-dumpable so a
/// same-uid peer cannot ptrace it or read `/proc/<pid>/mem`; but a non-dumpable
/// process also forbids `xdg-desktop-portal` (a same-uid peer) from reading
/// `/proc/<pid>/{root,cwd,exe}` to service a FileChooser request, so no file
/// dialog can open. We therefore raise the flag only for the picker window. The
/// `RLIMIT_CORE=0` no-core-dump guarantee is independent and stays in force.
typedef DumpableToggle = Future<void> Function(bool dumpable);

Future<void> _defaultSetDumpable(bool dumpable) async {
  if (!Platform.isLinux) return;
  try {
    await setProcessDumpable(dumpable: dumpable);
  } catch (_) {
    // Best-effort hardening: a toggle failure (e.g. the bridge not initialised
    // in a unit test, or an unexpected prctl error) must never block the file
    // dialog. init_app() treats the same class of failure as non-fatal.
  }
}

/// Overridable in tests; defaults to the real Rust bridge toggle.
DumpableToggle dumpableToggle = _defaultSetDumpable;

/// Restores [dumpableToggle] to the production implementation (test teardown).
void resetDumpableToggle() => dumpableToggle = _defaultSetDumpable;

int _pickerWindowDepth = 0;

/// Runs a native-picker operation, passing its result through unchanged
/// (including `null`, which means the user cancelled). Any thrown exception is
/// rethrown as [FilePickerUnavailable]. Brackets the call with [dumpableToggle]
/// so the XDG portal can reach the process while the dialog is open; nested
/// calls keep the flag raised until the outermost one completes.
Future<T?> runPicker<T>(Future<T?> Function() op) async {
  if (_pickerWindowDepth == 0) {
    await dumpableToggle(true);
  }
  _pickerWindowDepth++;
  try {
    return await op();
  } on Exception catch (e) {
    throw FilePickerUnavailable(e);
  } finally {
    _pickerWindowDepth--;
    if (_pickerWindowDepth == 0) {
      await dumpableToggle(false);
    }
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
