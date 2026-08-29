import 'package:flutter/services.dart';

/// Returns false when nothing opened, so the caller can say so instead of a
/// silent no-op.
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
