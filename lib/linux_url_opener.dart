import 'dart:io';

/// Opens a link on Linux by handing it to the desktop's own handler,
/// `xdg-open` — the same thing `url_launcher` did, without the plugin.
///
/// The URL comes from vault data, so it is passed as a single argument to the
/// program: no shell is involved, and its punctuation can never be read as
/// commands.
class LinuxUrlOpener {
  LinuxUrlOpener({
    Future<ProcessResult> Function(String, List<String>)? runProcess,
  }) : _runProcess = runProcess ?? Process.run;

  final Future<ProcessResult> Function(String, List<String>) _runProcess;

  /// Asks the desktop to open [uri]. False when nothing could open it, which
  /// the caller turns into a message rather than a silent no-op.
  Future<bool> open(Uri uri) async {
    try {
      final result = await _runProcess('xdg-open', [uri.toString()]);
      return result.exitCode == 0;
    } on ProcessException {
      // No xdg-utils on the box (a minimal install): the caller says so,
      // rather than the tap killing the isolate.
      return false;
    }
  }
}
