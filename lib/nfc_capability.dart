import 'package:flutter/services.dart';

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

/// Detected once at startup so the transport selectors can read it
/// synchronously. Stays false on Linux (libfido2 is USB-only). Tests that set
/// it must reset it in tearDown.
bool nfcAvailable = false;

/// Query the platform for NFC hardware and cache the result in [nfcAvailable].
/// Any failure (no handler on Linux, platform error) is treated as no NFC.
Future<void> initNfcCapability() async {
  try {
    nfcAvailable =
        await _yubikeyChannel.invokeMethod<bool>('has_nfc') ?? false;
  } catch (_) {
    nfcAvailable = false;
  }
}
