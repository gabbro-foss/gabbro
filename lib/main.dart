import 'package:flutter/material.dart';
import 'package:gabbro/src/rust/frb_generated.dart';
import 'screens/unlock_screen.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const GabbroApp());
}

class GabbroApp extends StatelessWidget {
  const GabbroApp({super.key});

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
      home: const UnlockScreen(),
    );
  }
}