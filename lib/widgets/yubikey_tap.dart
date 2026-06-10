import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gabbro/src/rust/api/fido_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

/// The hmac-secret output and the credential id of the YubiKey the user tapped.
typedef YubikeyHmacMatch = ({List<int> hmac, List<int> credentialId});

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _fromHex(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

/// Prompt the user to tap any of the vault's registered YubiKeys and return the
/// resulting hmac-secret output plus the matched credential id.
///
/// Mirrors the unlock screen's multi-key tap (`fidoGetHmacSecretAny` on Linux, the
/// `get_hmac_secret_multi` MethodChannel on Android) but returns the match instead
/// of unlocking — used by the import/sync flow to open a key-protected source
/// (ADR-013). Throws `PlatformException` if no device is present or the tap fails.
Future<YubikeyHmacMatch> getAnyYubikeyHmacSecret({
  required List<YubikeyRecordData> records,
  required String pin,
  required String transport,
}) async {
  if (Platform.isLinux) {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      throw PlatformException(
        code: 'NO_FIDO2_DEVICE',
        message: 'No FIDO2 device found. Insert your YubiKey and try again.',
      );
    }
    final match = await fidoGetHmacSecretAny(
      devicePath: devices.first,
      records: records
          .map((r) => FidoRecordInput(credentialId: r.credentialId, salt: r.salt))
          .toList(),
      pin: pin,
    );
    return (hmac: match.hmac, credentialId: match.credentialId);
  }

  // Android: a single MethodChannel call with all records; Kotlin runs one CTAP2
  // getAssertions over the allowList and returns the matched hmac + credential id.
  final recordsArg = records
      .map((r) => {'credentialId': _toHex(r.credentialId), 'salt': _toHex(r.salt)})
      .toList();
  final result = await _yubikeyChannel.invokeMethod<Map<Object?, Object?>>(
    'get_hmac_secret_multi',
    {'records': recordsArg, 'pin': pin, 'transport': transport},
  );
  return (
    hmac: _fromHex(result!['hmac'] as String),
    credentialId: _fromHex(result['credentialId'] as String),
  );
}
