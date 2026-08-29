import 'dart:io';

import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'src/rust/api/simple.dart';

/// Inside a sandbox with no session bus the portal client throws a
/// `SocketException` that would crash the isolate; `runPicker` turns any such
/// failure into [FilePickerUnavailable] so the editable path fields remain as
/// the fallback.

/// Thrown when the native file dialog could not be reached (typically the XDG
/// portal / DBus session bus is unavailable in a sandbox). Carries the
/// underlying [cause] for logging.
class FilePickerUnavailable implements Exception {
  final Object cause;

  const FilePickerUnavailable(this.cause);

  @override
  String toString() => 'FilePickerUnavailable: $cause';
}

/// R-04 keeps the process non-dumpable, but then `xdg-desktop-portal` cannot
/// read `/proc/<pid>` to service a FileChooser, so the flag is raised only
/// while a dialog is open. See `hardening.rs`.
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
