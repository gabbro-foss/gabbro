import 'package:flutter/services.dart';

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

/// Whether this device has NFC hardware. Detected once at startup by
/// [initNfcCapability] and read synchronously by the USB/NFC transport selectors
/// so they only offer NFC where the device supports it. Defaults to false
/// (USB-only) until detected, and stays false on Linux (libfido2 is USB-only,
/// so the `has_nfc` channel has no handler). Tests set this directly and must
/// reset it in tearDown.
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
