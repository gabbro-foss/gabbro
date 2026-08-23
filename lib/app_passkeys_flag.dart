import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';

/// Test-only override for the Android gate; production resolves through
/// [Platform.isAndroid].
@visibleForTesting
bool? debugAppPasskeysIsAndroid;

const _channel = MethodChannel('app.gabbro.gabbro/app_passkeys');

/// Mirror the app-passkeys opt-in (F1) into Android SharedPreferences, where
/// the credential-provider service — which runs without Flutter — reads it.
/// Best-effort: a channel failure leaves the provider on its stored value
/// (absent = off), so a native app is refused rather than allowed.
Future<void> pushAppPasskeysFlag(bool enabled) async {
  final isAndroid = debugAppPasskeysIsAndroid ?? Platform.isAndroid;
  if (!isAndroid) return;
  try {
    await _channel.invokeMethod('setAppPasskeys', enabled);
  } catch (e) {
    debugPrint('app passkeys: flag push failed: $e');
  }
}
