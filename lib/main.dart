import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart' show confirmYubikey, confirmAnyYubikey;
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/frb_generated.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:path_provider/path_provider.dart';

/// Maps a non-system [LanguageChoice] to the correct [Locale].
///
/// Most locales use a single BCP-47 language tag that matches the enum name.
/// The five complex locales (pt_PT, pt_BR, sr_Latn, zh_CN, zh_TW) need a
/// country or script subtag and are handled explicitly.
Locale _localeFor(LanguageChoice choice) {
  assert(choice != LanguageChoice.system);
  return switch (choice) {
    LanguageChoice.ptPt   => const Locale('pt', 'PT'),
    LanguageChoice.ptBr   => const Locale('pt', 'BR'),
    LanguageChoice.srLatn => Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'),
    LanguageChoice.zhCn   => const Locale('zh', 'CN'),
    LanguageChoice.zhTw   => const Locale('zh', 'TW'),
    _                     => Locale(choice.name),
  };
}

/// Material localizations delegate that falls back to English for locales not
/// covered by [GlobalMaterialLocalizations] (e.g. yo, nn).
class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    if (GlobalMaterialLocalizations.delegate.isSupported(locale)) {
      return GlobalMaterialLocalizations.delegate.load(locale);
    }
    return GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  }

  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}

/// Cupertino localizations delegate that falls back to English for locales not
/// covered by [GlobalCupertinoLocalizations] (e.g. yo, nn).
class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    if (GlobalCupertinoLocalizations.delegate.isSupported(locale)) {
      return GlobalCupertinoLocalizations.delegate.load(locale);
    }
    return GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
  }

  @override
  bool shouldReload(_FallbackCupertinoLocalizationsDelegate old) => false;
}

const List<LocalizationsDelegate<dynamic>> gabbroLocalizationsDelegates = [
  AppLocalizations.delegate,
  _FallbackMaterialLocalizationsDelegate(),
  _FallbackCupertinoLocalizationsDelegate(),
  GlobalWidgetsLocalizations.delegate,
];

@pragma('vm:entry-point')
Future<void> autofillUnlockMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final registry = await VaultRegistry.load();
  final lastUsed = registry.lastUsed;
  final String vaultPath;
  if (lastUsed != null) {
    vaultPath = lastUsed.path;
  } else {
    final dir = await getApplicationSupportDirectory();
    vaultPath = '${dir.path}/gabbro.gabbro';
  }
  const channel = MethodChannel('app.gabbro.gabbro/autofill');
  final settings = await AppSettings.load();
  final hc = settings.highContrast;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: gabbroLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: settings.language == LanguageChoice.system
          ? null
          : _localeFor(settings.language),
      themeMode: switch (settings.theme) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.light  => ThemeMode.light,
        ThemeChoice.dark   => ThemeMode.dark,
      },
      theme: gabbroLightTheme(highContrast: hc),
      darkTheme: gabbroDarkTheme(highContrast: hc),
      home: UnlockScreen(
        vaultPath: vaultPath,
        onUnlock: (passphrase, path) async {
          await unlockVault(passphrase: passphrase, path: path);
          await channel.invokeMethod('unlock');
        },
        blockPassphraseCopyPaste: settings.blockPassphraseCopyPaste,
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
  }
  await RustLib.init();
  final registry = await VaultRegistry.load();
  final lastUsed = registry.lastUsed;
  final settings = await AppSettings.load();
  runApp(
    GabbroApp(
      registry: registry,
      vaultPath: lastUsed?.path,
      settings: settings,
    ),
  );
}

/// Public interface for descendant widgets to read settings and push updates.
abstract class GabbroAppState {
  AppSettings get settings;
  VaultRegistry get registry;
  Future<void> updateSettings(AppSettings updated);
  /// Pause the foreground inactivity lock timer for the duration of a
  /// hardware operation (e.g. YubiKey tap).  Call [resumeForegroundLock]
  /// when the operation finishes (success or failure).
  void suspendForegroundLock();
  void resumeForegroundLock();
  /// Mark [path] as the most-recently-used vault so the auto-lock timer
  /// shows the correct unlock screen after a vault switch.
  Future<void> touchVaultLastUsed(String path);
  /// Navigate the root navigator to the unlock screen for [path]/[alias].
  void switchToVault(String path, String alias);
  /// Push the ManageVaultsScreen onto the root navigator.
  void navigateToManageVaults();
  /// Called after the active vault's file has been deleted (via VaultListScreen
  /// menu). Removes the vault from the registry and navigates to the next
  /// vault's unlock screen, or to OnboardingScreen if no vaults remain.
  Future<void> onActiveVaultDeleted(String path);
}

ThemeData gabbroLightTheme({required bool highContrast}) {
  if (highContrast) {
    return ThemeData(
      colorScheme: const ColorScheme.light(
        brightness: Brightness.light,
        primary: Color(0xFF000000),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF000000),
        onSecondary: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF000000),
        error: Color(0xFF7A0000),
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

ThemeData gabbroDarkTheme({required bool highContrast}) {
  if (highContrast) {
    return ThemeData(
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: Color(0xFFFFFFFF),
        onPrimary: Color(0xFF000000),
        secondary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFF000000),
        surface: Color(0xFF000000),
        onSurface: Color(0xFFFFFFFF),
        error: Color(0xFFFF9999),
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

class GabbroApp extends StatefulWidget {
  final VaultRegistry registry;

  /// Last-used vault path from the registry. Null when registry is empty
  /// (first-time user — routes to OnboardingScreen).
  final String? vaultPath;

  final AppSettings settings;

  final Widget? initialScreen;

  /// Overridable clock; defaults to [DateTime.now]. Pass a fake clock in tests.
  final DateTime Function() clock;

  const GabbroApp({
    super.key,
    required this.registry,
    required this.vaultPath,
    required this.settings,
    this.initialScreen,
    this.clock = DateTime.now,
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
  late VaultRegistry _registry;

  @override
  AppSettings get settings => _settings;

  @override
  VaultRegistry get registry => _registry;

  final _navigatorKey = GlobalKey<NavigatorState>();

  Timer? _foregroundTimer;
  Timer? _backgroundTimer;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _registry = widget.registry;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _resetForegroundTimer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _foregroundTimer?.cancel();
    _backgroundTimer?.cancel();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) _resetForegroundTimer();
    return false;
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
    if (_foregroundSuspended) return;
    final duration = _foregroundDuration;
    if (duration == null) return;
    _foregroundTimer = Timer(duration, _lock);
  }

  bool _foregroundSuspended = false;

  @override
  void suspendForegroundLock() {
    _foregroundSuspended = true;
    _foregroundTimer?.cancel();
  }

  @override
  void resumeForegroundLock() {
    _foregroundSuspended = false;
    _resetForegroundTimer();
  }

  // ── Background lock ───────────────────────────────────────────────────────
  //
  // Rather than a timer that must fire while the OS may have suspended the
  // Dart isolate, we record a timestamp when the app backgrounds and compare
  // elapsed time on resume. This is reliable across Android Doze, Linux WM
  // workspace switches, and any other scenario where background timers are
  // throttled or never fire.

  Duration? get _backgroundDuration => switch (_settings.backgroundLockTimeout) {
    BackgroundLockTimeout.oneMinute      => const Duration(minutes: 1),
    BackgroundLockTimeout.fiveMinutes    => const Duration(minutes: 5),
    BackgroundLockTimeout.fifteenMinutes => const Duration(minutes: 15),
    BackgroundLockTimeout.never          => null,
  };

  // Used on desktop only: fires _lock() if the app stays visible but unfocused
  // (tiling WM focus-switch). The process is still running, so timers are reliable.
  void _startBackgroundTimer() {
    _backgroundTimer?.cancel();
    final duration = _backgroundDuration;
    if (duration == null) return;
    _backgroundTimer = Timer(duration, _lock);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // On Linux/macOS/Windows, switching workspaces or losing window focus
        // fires inactive — hidden/paused are not sent. Record the backgrounding
        // timestamp so the elapsed check on resumed works.
        // On Android/iOS, inactive is a brief transition state (task switcher,
        // incoming call) that must NOT trigger background-lock timing.
        if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
          _foregroundTimer?.cancel();
          _backgroundedAt ??= widget.clock();
          // Start a real timer: app is still visible/running, so it will fire.
          // Covers the tiling-WM focus-switch case where resumed may come late.
          _startBackgroundTimer();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _foregroundTimer?.cancel();
        // ??= keeps the earliest timestamp (hidden fires before paused on Android).
        _backgroundedAt ??= widget.clock();
      case AppLifecycleState.detached:
        _lock();
      case AppLifecycleState.resumed:
        _backgroundTimer?.cancel();
        if (!_checkBackgroundTimeout()) _resetForegroundTimer();
    }
  }

  /// Returns true (and calls [_lock]) if the app was backgrounded for longer
  /// than the configured timeout. Clears [_backgroundedAt] in all cases.
  bool _checkBackgroundTimeout() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return false;
    final duration = _backgroundDuration;
    if (duration == null) return false;
    if (widget.clock().difference(backgroundedAt) >= duration) {
      _lock();
      return true;
    }
    return false;
  }

  // ── Lock ──────────────────────────────────────────────────────────────────

  void _lock() {
    _foregroundTimer?.cancel();
    _backgroundTimer?.cancel();
    _backgroundedAt = null;
    try {
      lockVault();
    } catch (_) {}
    final lastUsed = _registry.lastUsed;
    if (lastUsed == null || !File(lastUsed.path).existsSync()) return;
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _buildUnlockScreen(lastUsed.path, lastUsed.alias),
      ),
      (_) => false,
    );
  }

  // ── Registry helpers ───────────────────────────────────────────────────────

  Future<void> _onVaultCreated(String path, String alias) async {
    List<YubikeyRecordData> ykRecords = [];
    try { ykRecords = listVaultYubikeyRecords(path: path); } catch (_) {}
    final updated = _registry.add(VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.now(),
      type: ykRecords.isEmpty ? VaultType.passphrase : VaultType.yubikey,
    ));
    await updated.save();
    setState(() => _registry = updated);
  }

  UnlockScreen _buildUnlockScreen(String path, String alias) => UnlockScreen(
    vaultPath: path,
    vaultAlias: alias,
    blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
    registry: _settings.showVaultList ? _registry : null,
    showVaultList: _settings.showVaultList,
    biometricEnabled: _settings.biometricUnlock,
    onBiometricInvalidated: () => updateSettings(
      _settings.copyWith(biometricUnlock: false),
    ),
  );

  Widget _buildHome() {
    final lastUsed = _registry.lastUsed;
    if (lastUsed == null) {
      return OnboardingScreen(
        blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
        onVaultCreated: _onVaultCreated,
      );
    }
    return _buildUnlockScreen(lastUsed.path, lastUsed.alias);
  }

  @override
  Future<void> updateSettings(AppSettings updated) async {
    await updated.save();
    setState(() => _settings = updated);
    _resetForegroundTimer();
  }

  @override
  Future<void> touchVaultLastUsed(String path) async {
    final updated = _registry.touchLastUsed(path);
    await updated.save();
    setState(() => _registry = updated);
  }

  @override
  void switchToVault(String path, String alias) {
    _navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(builder: (_) => _buildUnlockScreen(path, alias)),
    );
  }

  @override
  void navigateToManageVaults() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => _buildManageVaultsScreen()),
    );
  }

  @override
  Future<void> onActiveVaultDeleted(String path) async {
    final updated = _registry.remove(path);
    await updated.save();
    // Direct field mutation — no setState, so _buildHome() is not called before
    // the pushAndRemoveUntil navigation completes. _onVaultCreated / touchVaultLastUsed
    // will call setState the next time the registry legitimately changes.
    _registry = updated;
    final lastUsed = updated.lastUsed;
    if (lastUsed == null) {
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => OnboardingScreen(
            initialPath: path,
            postDeletionMessage:
                'Your vault has been deleted. Create a new one to continue.',
            blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
            onVaultCreated: _onVaultCreated,
          ),
        ),
        (_) => false,
      );
    } else {
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => _buildUnlockScreen(lastUsed.path, lastUsed.alias),
        ),
        (_) => false,
      );
    }
  }

  ManageVaultsScreen _buildManageVaultsScreen() => ManageVaultsScreen(
    registry: _registry,
    onConfirmYubikey: confirmYubikey,
    onConfirmAnyYubikey: confirmAnyYubikey,
    onRename: (path, alias) async {
      // Update the file header alias only for the currently unlocked vault so
      // the body can be re-sealed with the new alias as AES-GCM AAD (Phase 3).
      if (path == _registry.lastUsed?.path) {
        await setVaultAlias(alias: alias);
      }
      final updated = _registry.updateAlias(path, alias);
      await updated.save();
      setState(() => _registry = updated);
    },
    onDelete: (path) async {
      final isActive = path == _registry.lastUsed?.path;
      final file = File(path);
      if (file.existsSync()) await file.delete();
      final updated = _registry.remove(path);
      await updated.save();
      if (isActive) {
        // Direct field mutation — same reason as onActiveVaultDeleted: avoid
        // setState racing with pushAndRemoveUntil navigation.
        _registry = updated;
        try { lockVault(); } catch (_) {}
        final lastUsed = updated.lastUsed;
        if (lastUsed == null) {
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => OnboardingScreen(
                postDeletionMessage:
                    'Your vault has been deleted. Create a new one to continue.',
                blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
                onVaultCreated: _onVaultCreated,
              ),
            ),
            (_) => false,
          );
        } else {
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => _buildUnlockScreen(lastUsed.path, lastUsed.alias),
            ),
            (_) => false,
          );
        }
      } else {
        setState(() => _registry = updated);
      }
    },
    onAddVault: () {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => OnboardingScreen(
            blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
            onVaultCreated: _onVaultCreated,
            existingAliases: _registry.records.map((r) => r.alias).toSet(),
          ),
        ),
      );
    },
    onSwitchToVault: (path, alias) {
      _navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (_) => _buildUnlockScreen(path, alias)),
      );
    },
  );

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

  @override
  Widget build(BuildContext context) {
    final hc = _settings.highContrast;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_textScale)),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetForegroundTimer(),
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Gabbro',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: gabbroLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: _settings.language == LanguageChoice.system
              ? null
              : _localeFor(_settings.language),
          themeMode: _themeMode,
          theme: gabbroLightTheme(highContrast: hc),
          darkTheme: gabbroDarkTheme(highContrast: hc),
          home: widget.initialScreen ?? _buildHome(),
        ),
      ),
    );
  }
}
