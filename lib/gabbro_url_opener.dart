import 'dart:io';

import 'android_url_opener.dart';
import 'linux_url_opener.dart';

/// What came of asking to open a link.
///
/// [notAWebLink] is a deliberate refusal, not a malfunction, so callers say
/// something different about it than about [failed].
enum UrlOpenResult { opened, notAWebLink, failed }

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

  /// Opens [url] in the user's browser. Anything other than
  /// [UrlOpenResult.opened] must reach the user as a message: a button that
  /// silently does nothing is the same as a broken one.
  static Future<UrlOpenResult> open(String url) async {
    final uri = browserUri(url);
    if (uri == null) return UrlOpenResult.notAWebLink;
    if (!_webSchemes.contains(uri.scheme.toLowerCase())) {
      return UrlOpenResult.notAWebLink;
    }
    final opened =
        isLinux() ? await linuxOpener.open(uri) : await androidOpener.open(uri);
    return opened ? UrlOpenResult.opened : UrlOpenResult.failed;
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
