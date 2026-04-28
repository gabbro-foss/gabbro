import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  final vaultPath = '${dir.path}/gabbro.gabbro';
  final vaultExists = await File(vaultPath).exists();
  final settings = await AppSettings.load();
  runApp(
    GabbroApp(
      vaultPath: vaultPath,
      vaultExists: vaultExists,
      settings: settings,
    ),
  );
}

class GabbroApp extends StatefulWidget {
  final String vaultPath;
  final bool vaultExists;
  final AppSettings settings;

  const GabbroApp({
    super.key,
    required this.vaultPath,
    required this.vaultExists,
    required this.settings,
  });

  @override
  State<GabbroApp> createState() => _GabbroAppState();

  /// Allow descendant widgets to update settings app-wide.
  static _GabbroAppState of(BuildContext context) {
    return context.findAncestorStateOfType<_GabbroAppState>()!;
  }
}

class _GabbroAppState extends State<GabbroApp> {
  late AppSettings _settings;
  AppSettings get settings => _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  Future<void> updateSettings(AppSettings updated) async {
    await updated.save();
    setState(() => _settings = updated);
  }

  ThemeMode get _themeMode => switch (_settings.theme) {
    ThemeChoice.system => ThemeMode.system,
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
  };

  double get _textScale => switch (_settings.textSize) {
    TextSizeChoice.small => 0.85,
    TextSizeChoice.regular => 1.0,
    TextSizeChoice.large => 1.15,
    TextSizeChoice.extra_large => 1.3,
  };

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(_textScale)),
      child: MaterialApp(
        title: 'Gabbro',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF534AB7)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF534AB7),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: widget.vaultExists
            ? UnlockScreen(vaultPath: widget.vaultPath)
            : const OnboardingScreen(),
      ),
    );
  }
}
