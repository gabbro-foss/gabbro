import 'package:flutter/material.dart';
import 'package:gabbro/screens/autofill_unlock_screen.dart';
import 'package:gabbro/src/rust/frb_generated.dart';

/// Entry point used exclusively by UnlockActivity.
/// Completely separate from main() — no GabbroApp, no vault path resolution,
/// no auto-lock timer. Just the passphrase screen and its MethodChannel.
@pragma('vm:entry-point')
Future<void> autofillUnlockMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AutofillUnlockScreen(),
    ),
  );
}