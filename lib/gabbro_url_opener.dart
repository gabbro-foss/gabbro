import 'dart:io';

import 'android_url_opener.dart';
import 'linux_url_opener.dart';

/// The one way Gabbro opens a link.
///
/// Linux hands it to `xdg-open`; Android to our own channel. Both open the
/// user's own browser — never a webview inside Gabbro, where the vault is
/// open. All fields are test seams.
class GabbroUrlOpener {
  GabbroUrlOpener._();

  static bool Function() isLinux = () => Platform.isLinux;
  static LinuxUrlOpener linuxOpener = LinuxUrlOpener();
  static AndroidUrlOpener androidOpener = AndroidUrlOpener();

  /// Restores the platform clients (test teardown).
  static void reset() {
    isLinux = () => Platform.isLinux;
    linuxOpener = LinuxUrlOpener();
    androidOpener = AndroidUrlOpener();
  }

  /// The only schemes Gabbro hands to the system. A URL in a vault entry is
  /// user data and this action means "open a web page": anything else would
  /// let a saved entry reach a local file or another program. If a real need
  /// for others appears, widen it deliberately.
  static const _webSchemes = {'http', 'https'};

  /// Opens [url] in the user's browser. False when nothing opened — not a web
  /// address, an address that cannot be read, or no app to handle it — which
  /// callers turn into a message rather than a silent no-op.
  static Future<bool> open(String url) async {
    final uri = browserUri(url);
    if (uri == null) return false;
    if (!_webSchemes.contains(uri.scheme.toLowerCase())) return false;
    return isLinux() ? linuxOpener.open(uri) : androidOpener.open(uri);
  }

  /// The address to hand the system for [url], or null if it cannot be read.
  ///
  /// The system picks the browser from the scheme, so a URL saved without one
  /// (`example.com`) gets `https://`: Android would otherwise find no app to
  /// handle it, and Linux would take the text for a filename.
  static Uri? browserUri(String url) {
    var uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme.isEmpty) uri = Uri.tryParse('https://$url');
    return uri;
  }
}
