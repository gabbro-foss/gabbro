import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  final vaultPath = '${dir.path}/gabbro.gabbro';
  final vaultExists = await File(vaultPath).exists();
  runApp(GabbroApp(vaultPath: vaultPath, vaultExists: vaultExists));
}

class GabbroApp extends StatelessWidget {
  final String vaultPath;
  final bool vaultExists;

  const GabbroApp({
    super.key,
    required this.vaultPath,
    required this.vaultExists,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gabbro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF534AB7),
        ),
        useMaterial3: true,
      ),
      home: vaultExists
          ? UnlockScreen(vaultPath: vaultPath)
          : const OnboardingScreen(),
    );
  }
}