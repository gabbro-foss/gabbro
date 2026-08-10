import 'package:flutter/services.dart';

/// Opens a link on Android by asking our own Kotlin handler
/// (`GabbroUnlockHostActivity`) to hand it to the system, instead of the
/// `url_launcher` plugin.
///
/// Returns false when nothing opened — no app installed that handles the link,
/// or the handler could not be reached — which the caller turns into a message
/// rather than a silent no-op.
class AndroidUrlOpener {
  static const channel = MethodChannel('app.gabbro.gabbro/url');

  Future<bool> open(Uri uri) async {
    try {
      final opened =
          await channel.invokeMethod<bool>('open_url', {'url': uri.toString()});
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
