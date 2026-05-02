import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
  }
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

/// Public interface for descendant widgets to read settings and push updates.
abstract class GabbroAppState {
  AppSettings get settings;
  Future<void> updateSettings(AppSettings updated);
}

class GabbroApp extends StatefulWidget {
  final String vaultPath;
  final bool vaultExists;
  final AppSettings settings;

  final Widget? initialScreen;

  const GabbroApp({
    super.key,
    required this.vaultPath,
    required this.vaultExists,
    required this.settings,
    this.initialScreen,
  });

  @override
  State<GabbroApp> createState() => _GabbroAppState();

  /// Allow descendant widgets to update settings app-wide.
  static GabbroAppState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<_GabbroAppState>();
  }

  static GabbroAppState of(BuildContext context) {
    return context.findAncestorStateOfType<_GabbroAppState>()!;
  }
}

class _GabbroAppState extends State<GabbroApp>
    with WidgetsBindingObserver
    implements GabbroAppState {
  late AppSettings _settings;
  @override
  AppSettings get settings => _settings;

  final _navigatorKey = GlobalKey<NavigatorState>();

  Timer? _backgroundTimer;
  Timer? _foregroundTimer;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    WidgetsBinding.instance.addObserver(this);
    _resetForegroundTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundTimer?.cancel();
    _foregroundTimer?.cancel();
    super.dispose();
  }

  // ── Foreground inactivity timer ───────────────────────────────────────────

  Duration? get _foregroundDuration => switch (_settings.foregroundLockTimeout) {
    ForegroundLockTimeout.thirtySeconds => const Duration(seconds: 30),
    ForegroundLockTimeout.oneMinute    => const Duration(minutes: 1),
    ForegroundLockTimeout.fiveMinutes  => const Duration(minutes: 5),
    ForegroundLockTimeout.never        => null,
  };

  void _resetForegroundTimer() {
    _foregroundTimer?.cancel();
    final duration = _foregroundDuration;
    if (duration == null) return;
    _foregroundTimer = Timer(duration, _lock);
  }

  // ── Background timer ──────────────────────────────────────────────────────

  Duration? get _backgroundDuration => switch (_settings.backgroundLockTimeout) {
    BackgroundLockTimeout.oneMinute      => const Duration(minutes: 1),
    BackgroundLockTimeout.fiveMinutes    => const Duration(minutes: 5),
    BackgroundLockTimeout.fifteenMinutes => const Duration(minutes: 15),
    BackgroundLockTimeout.never          => null,
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _foregroundTimer?.cancel();
        final duration = _backgroundDuration;
        if (duration != null) {
          _backgroundTimer = Timer(duration, _lock);
        }
      case AppLifecycleState.detached:
        _lock();
      case AppLifecycleState.resumed:
        _backgroundTimer?.cancel();
        _resetForegroundTimer();
      default:
        break;
    }
  }

  // ── Lock ──────────────────────────────────────────────────────────────────

  void _lock() {
    _backgroundTimer?.cancel();
    _foregroundTimer?.cancel();
    try {
      lockVault();
    } catch (_) {}
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => UnlockScreen(vaultPath: widget.vaultPath),
      ),
      (_) => false,
    );
  }

  @override
  Future<void> updateSettings(AppSettings updated) async {
    await updated.save();
    setState(() => _settings = updated);
    _resetForegroundTimer();
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
    TextSizeChoice.extraLarge => 1.3,
    TextSizeChoice.xxLarge => 1.5,
  };

  static ThemeData _lightTheme({required bool highContrast}) {
    if (highContrast) {
      return ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF000000),
          onPrimary: Color(0xFFFFFFFF),
          secondary: Color(0xFF000000),
          onSecondary: Color(0xFFFFFFFF),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF000000),
          error: Color(0xFF990000),
          onError: Color(0xFFFFFFFF),
        ),
        useMaterial3: true,
      );
    }
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C7A3E)),
      useMaterial3: true,
    );
  }

  static ThemeData _darkTheme({required bool highContrast}) {
    if (highContrast) {
      return ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          onPrimary: Color(0xFF000000),
          secondary: Color(0xFFFFFFFF),
          onSecondary: Color(0xFF000000),
          surface: Color(0xFF000000),
          onSurface: Color(0xFFFFFFFF),
          error: Color(0xFFFF6666),
          onError: Color(0xFF000000),
        ),
        useMaterial3: true,
      );
    }
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5C7A3E),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = _settings.highContrast;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_textScale)),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _resetForegroundTimer,
        onPanDown: (_) => _resetForegroundTimer(),
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Gabbro',
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
          theme: _lightTheme(highContrast: hc),
          darkTheme: _darkTheme(highContrast: hc),
          home: widget.initialScreen ??
              (widget.vaultExists
                  ? UnlockScreen(vaultPath: widget.vaultPath)
                  : const OnboardingScreen()),
        ),
      ),
    );
  }
}
