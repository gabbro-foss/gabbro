import 'dart:io';

/// `xdg-open` with the URL as a single argument: it comes from vault data and
/// no shell must ever read its punctuation as commands.
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
