import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gabbro/widgets/gabbro_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/autotype_listener.dart';
import 'package:gabbro/autotype_target.dart';
import 'package:gabbro/clipboard_clear.dart';
import 'package:gabbro/gabbro_contrast.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/nfc_capability.dart';
import 'package:gabbro/screens/adopt_vault_screen.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/save_confirm_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart'
    show
        confirmYubikey,
        confirmAnyYubikey,
        focusVaultSearch,
        vaultRegionTab,
        vaultRegionEscape,
        vaultRegionActive,
        openNewEntry,
        openVaultMenu,
        quitVault;
import 'package:gabbro/src/rust/api/autotype_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/frb_generated.dart';
import 'package:gabbro/text_scale.dart';
import 'package:gabbro/vault_registry.dart';

/// Maps a non-system [LanguageChoice] to the correct [Locale].
///
/// Most locales use a single BCP-47 language tag that matches the enum name.
/// The five complex locales (pt_PT, pt_BR, sr_Latn, zh_CN, zh_TW) need a
/// country or script subtag and are handled explicitly.
///
/// Public only as a test seam: `test/locale_resolution_test.dart` asserts every
/// mapping lands on a locale in [AppLocalizations.supportedLocales].
@visibleForTesting
Locale localeFor(LanguageChoice choice) {
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

/// Quit is offered only on Linux: a tiling WM (e.g. qtile) may have no
/// title-bar close, and there is no other way out of the locked/first-run
/// screens. Elsewhere this is null, so the Quit controls are absent.
VoidCallback? get _quitApp => Platform.isLinux ? () => exit(0) : null;

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

/// Maps the theme setting to a Flutter ThemeMode. Single source for both the
/// main app shell and the autofill unlock shell.
ThemeMode themeModeFor(ThemeChoice choice) => switch (choice) {
  ThemeChoice.system => ThemeMode.system,
  ThemeChoice.light => ThemeMode.light,
  ThemeChoice.dark => ThemeMode.dark,
};

@pragma('vm:entry-point')
Future<void> autofillUnlockMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await initNfcCapability();
  final registry = await VaultRegistry.load();
  final lastUsed = registry.lastUsed;
  final String initialVaultPath;
  if (lastUsed != null) {
    initialVaultPath = lastUsed.path;
  } else {
    final dataDir = await GabbroPaths.dataDir();
    initialVaultPath = '$dataDir/gabbro.gabbro';
  }
  final settings = await AppSettings.load();
  runApp(buildAutofillUnlockApp(
    settings: settings,
    registry: registry,
    initialVaultPath: initialVaultPath,
  ));
}

/// The autofill unlock app. Mirrors [main]'s MaterialApp shell (localization
/// delegates / locale / theme / text scale) and reuses [UnlockScreen] so the
/// autofill prompt offers the full unlock flow — vault picker, passphrase,
/// YubiKey, biometric. After the shared vault session unlocks, [onUnlocked]
/// signals the native side (the `unlock` method) to build the fill response.
Widget buildAutofillUnlockApp({
  required AppSettings settings,
  required VaultRegistry registry,
  required String initialVaultPath,
  MethodChannel channel = const MethodChannel('app.gabbro.gabbro/autofill'),
  // Test seam: defaults to the real bridge unlock; widget tests inject a fake.
  Future<void> Function(List<int>, String) onUnlock = defaultUnlock,
  // Test seam: real FFI cannot run under `flutter test`, so the lock is
  // injectable. Only the device pass proves the real wiring.
  void Function() onLock = lockVault,
}) =>
    _AutofillUnlockApp(
      settings: settings,
      registry: registry,
      initialVaultPath: initialVaultPath,
      channel: channel,
      onUnlock: onUnlock,
      onLock: onLock,
    );

class _AutofillUnlockApp extends StatefulWidget {
  final AppSettings settings;
  final VaultRegistry registry;
  final String initialVaultPath;
  final MethodChannel channel;
  final Future<void> Function(List<int>, String) onUnlock;
  final void Function() onLock;

  const _AutofillUnlockApp({
    required this.settings,
    required this.registry,
    required this.initialVaultPath,
    required this.channel,
    required this.onUnlock,
    required this.onLock,
  });

  @override
  State<_AutofillUnlockApp> createState() => _AutofillUnlockAppState();
}

class _AutofillUnlockAppState extends State<_AutofillUnlockApp> {
  late String _vaultPath = widget.initialVaultPath;
  final _navigatorKey = GlobalKey<NavigatorState>();

  String? _aliasFor(String path) {
    for (final r in widget.registry.records) {
      if (r.path == path) return r.alias;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.settings.highContrast;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: TextScaler.linear(
          clampToDevice(widget.settings.textScale, mq.size.shortestSide),
        ),
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: widget.settings.language == LanguageChoice.system
            ? null
            : localeFor(widget.settings.language),
        themeMode: themeModeFor(widget.settings.theme),
        theme: gabbroLightTheme(highContrast: hc),
        darkTheme: gabbroDarkTheme(highContrast: hc),
        navigatorKey: _navigatorKey,
        // ValueKey forces a fresh UnlockScreen on vault switch so it re-detects
        // the newly selected vault's YubiKey records.
        home: UnlockScreen(
          key: ValueKey(_vaultPath),
          vaultPath: _vaultPath,
          vaultAlias: _aliasFor(_vaultPath),
          registry: widget.registry,
          onVaultSwitch: (path, alias) => setState(() => _vaultPath = path),
          onUnlock: widget.onUnlock,
          onUnlocked: _onUnlocked,
          blockPassphraseCopyPaste: widget.settings.blockPassphraseCopyPaste,
          onQuit: _quitApp,
        ),
      ),
    );
  }

  /// After unlock, ask the native side to build the fill response. It returns
  /// whether a credential matched; on no match we show a localized dialog here
  /// (a native AlertDialog could not be localized against the Flutter ARBs) and
  /// then cancel.
  Future<void> _onUnlocked() async {
    final matched = await widget.channel.invokeMethod<bool>('unlock');
    if (matched == true) {
      // RT-5: this activity runs only because the vault was locked, so the
      // session is ours. It finishes here and its Dart isolate dies with it,
      // leaving nothing to close that session — so lock first, THEN finish.
      // `unlock` deliberately no longer finishes: locking after it would race
      // the engine teardown.
      widget.onLock();
      await widget.channel.invokeMethod('finish');
      return;
    }
    if (!mounted) return;
    // Show the dialog from a context UNDER the MaterialApp's Navigator/Overlay.
    // This State's own `context` sits above MaterialApp, where showDialog can find
    // neither an Overlay nor MaterialLocalizations and would throw.
    final navContext = _navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    await showAutofillNoMatchDialog(
      navContext,
      widget.channel,
      onLock: widget.onLock,
    );
  }
}

/// The autofill "no credentials found" dialog (localized). Shown by the unlock
/// flow when the vault unlocks but nothing matches the requesting app/site. On
/// dismiss it tells the native side to cancel (deliver nothing to the field).
Future<void> showAutofillNoMatchDialog(
  BuildContext context,
  MethodChannel channel, {
  // RT-5: the vault was opened for a fill that matched nothing. It is still
  // ours, so it closes before the activity ends. Defaults to no-op for the
  // standalone dialog test, which drives no session.
  void Function()? onLock,
}) async {
  final l = AppLocalizations.of(context);
  await showGabbroDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(l.autofillNoMatchTitle),
      content: Text(l.autofillNoMatchBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.dismiss),
        ),
      ],
    ),
  );
  onLock?.call();
  await channel.invokeMethod('cancel');
}

/// Autofill SAVE entrypoint (Android). The OS launches `SaveActivity` after the
/// user submits a login the vault lacks (or a changed password). Mirrors
/// [autofillUnlockMain]'s shell: reuses [UnlockScreen] when the vault is locked,
/// then shows [SaveConfirmScreen]. The captured login + suggested action come from
/// Kotlin via the `getSaveContext` channel call (matching is computed there).
@pragma('vm:entry-point')
Future<void> autofillSaveMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await initNfcCapability();
  final registry = await VaultRegistry.load();
  final lastUsed = registry.lastUsed;
  final String initialVaultPath;
  if (lastUsed != null) {
    initialVaultPath = lastUsed.path;
  } else {
    final dataDir = await GabbroPaths.dataDir();
    initialVaultPath = '$dataDir/gabbro.gabbro';
  }
  final settings = await AppSettings.load();
  const channel = MethodChannel('app.gabbro.gabbro/autofill_save');
  final alreadyUnlocked = await channel.invokeMethod<bool>('isUnlocked') ?? false;
  runApp(buildAutofillSaveApp(
    settings: settings,
    registry: registry,
    initialVaultPath: initialVaultPath,
    alreadyUnlocked: alreadyUnlocked,
  ));
}

/// The autofill save app. Reuses the unlock flow when the vault is locked, then
/// shows the confirm screen. [fetchSaveContextJson] defaults to the `getSaveContext`
/// channel call; widget tests inject it.
Widget buildAutofillSaveApp({
  required AppSettings settings,
  required VaultRegistry registry,
  required String initialVaultPath,
  required bool alreadyUnlocked,
  MethodChannel channel = const MethodChannel('app.gabbro.gabbro/autofill_save'),
  Future<String> Function()? fetchSaveContextJson,
  // Test seams: real FFI cannot run under `flutter test`. See the unlock shell.
  void Function() onLock = lockVault,
  Future<void> Function(List<int>, String) onUnlock = defaultUnlock,
}) =>
    _AutofillSaveApp(
      settings: settings,
      registry: registry,
      initialVaultPath: initialVaultPath,
      alreadyUnlocked: alreadyUnlocked,
      channel: channel,
      onLock: onLock,
      onUnlock: onUnlock,
      fetchSaveContextJson: fetchSaveContextJson ??
          () async => (await channel.invokeMethod<String>('getSaveContext')) ?? '{}',
    );

class _AutofillSaveApp extends StatefulWidget {
  final AppSettings settings;
  final VaultRegistry registry;
  final String initialVaultPath;
  final bool alreadyUnlocked;
  final MethodChannel channel;
  final Future<String> Function() fetchSaveContextJson;
  final void Function() onLock;
  final Future<void> Function(List<int>, String) onUnlock;

  const _AutofillSaveApp({
    required this.settings,
    required this.registry,
    required this.initialVaultPath,
    required this.alreadyUnlocked,
    required this.channel,
    required this.fetchSaveContextJson,
    required this.onLock,
    required this.onUnlock,
  });

  @override
  State<_AutofillSaveApp> createState() => _AutofillSaveAppState();
}

class _AutofillSaveAppState extends State<_AutofillSaveApp> {
  late String _vaultPath = widget.initialVaultPath;
  late bool _unlocked = widget.alreadyUnlocked;
  SaveContext? _context;

  @override
  void initState() {
    super.initState();
    if (_unlocked) _loadContext();
  }

  Future<void> _loadContext() async {
    final json = await widget.fetchSaveContextJson();
    if (!mounted) return;
    setState(() =>
        _context = SaveContext.fromJson(jsonDecode(json) as Map<String, dynamic>));
  }

  String? _aliasFor(String path) {
    for (final r in widget.registry.records) {
      if (r.path == path) return r.alias;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.settings.highContrast;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: TextScaler.linear(
          clampToDevice(widget.settings.textScale, mq.size.shortestSide),
        ),
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: gabbroLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: widget.settings.language == LanguageChoice.system
            ? null
            : localeFor(widget.settings.language),
        themeMode: themeModeFor(widget.settings.theme),
        theme: gabbroLightTheme(highContrast: hc),
        darkTheme: gabbroDarkTheme(highContrast: hc),
        home: _home(),
      ),
    );
  }

  Widget _home() {
    if (!_unlocked) {
      return UnlockScreen(
        key: ValueKey(_vaultPath),
        vaultPath: _vaultPath,
        vaultAlias: _aliasFor(_vaultPath),
        registry: widget.registry,
        onVaultSwitch: (path, alias) => setState(() => _vaultPath = path),
        onUnlock: widget.onUnlock,
        onUnlocked: () async {
          setState(() => _unlocked = true);
          await _loadContext();
        },
        blockPassphraseCopyPaste: widget.settings.blockPassphraseCopyPaste,
        onQuit: _quitApp,
      );
    }
    final ctx = _context;
    if (ctx == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return SaveConfirmScreen(
      saveContext: ctx,
      showSwitchVaultHint: widget.alreadyUnlocked,
      onDone: () => _finish('done'),
      onCancel: () => _finish('cancel'),
    );
  }

  /// RT-5: a vault THIS flow unlocked is ours to close, and the activity's Dart
  /// isolate dies when it finishes — so lock on the way out, before telling
  /// Kotlin to finish. A session the main app already had open is left alone:
  /// closing it would lock the user out of the app they are using.
  Future<void> _finish(String method) async {
    if (!widget.alreadyUnlocked) widget.onLock();
    await widget.channel.invokeMethod(method);
  }
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
  await initNfcCapability();
  final registry = await VaultRegistry.load();
  final lastUsed = registry.lastUsed;
  final settings = await AppSettings.load();
  if (Platform.isLinux) {
    await _startAutotypeListener();
  }
  runApp(
    GabbroApp(
      registry: registry,
      vaultPath: lastUsed?.path,
      settings: settings,
    ),
  );
}

/// Start the Linux auto-type trigger listener (ADR-017). The socket path and
/// token come from Rust so nothing is duplicated. Best-effort: a failure (or
/// another instance already owning the socket) just leaves auto-type inactive
/// in this instance — it never blocks launch.
Future<void> _startAutotypeListener() async {
  try {
    final listener = AutotypeListener(
      socketPath: await autotypeSocketPath(),
      token: await autotypeTriggerToken(),
      onTrigger: _onAutotypeTrigger,
    );
    if (!await listener.start()) {
      debugPrint('autotype: another instance owns the socket; listener not started');
    }
  } catch (e) {
    debugPrint('autotype: listener failed to start: $e');
  }
}

/// Per-entry direct-type (ADR-017): fill the Login the user has open in Gabbro
/// into the window that was focused when the trigger fired. No picker, so no
/// focus is stolen. Nothing open (or a locked vault, which cleared the target)
/// => nothing to type. The secret is read and injected in Rust.
Future<void> _onAutotypeTrigger() async {
  try {
    final id = autotypeTarget.loginId;
    if (id == null) return;
    final window = await autotypeCaptureActiveWindow();
    if (window == null) return;
    await autotypeFill(windowId: window.id, entryId: id);
  } catch (e) {
    debugPrint('autotype: fill failed: $e');
  }
}

/// Where to go after a vault is deleted from Manage Vaults (ADR-014).
enum PostDeleteRoute { stayOnManageVaults, onboarding, remainingVault }

/// Pure routing decision for [GabbroAppState.deleteVaultFromManager]. Active-vault
/// deletion leaves the screen — to the remaining last-used vault's unlock screen,
/// or onboarding when none remain; non-active deletion stays put. Kept pure (no
/// FFI/widgets) so it is unit-testable; the navigation itself stays in the State.
PostDeleteRoute postDeleteRoute({
  required bool wasActive,
  required bool hasRemaining,
}) {
  if (!wasActive) return PostDeleteRoute.stayOnManageVaults;
  return hasRemaining
      ? PostDeleteRoute.remainingVault
      : PostDeleteRoute.onboarding;
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
  /// Push the AdoptVaultScreen (register an existing `.gabbro` file).
  void openAdoptVault();
  /// R-03 P5: remove a vault whose file is unreadable, from the unlock screen.
  /// When [deleteFiles] is true the vault file and its `.bak` are deleted from
  /// disk; otherwise only the registry entry is removed (the bytes stay so the
  /// user can recover them). Routes to the next vault, or onboarding if none
  /// remain — so a single corrupt vault never strands the user.
  Future<void> removeVault(String path, {required bool deleteFiles});
  /// ADR-014: delete [path] from Manage Vaults (its file + `.bak` are removed).
  /// If it was the active vault, route to the remaining last-used vault's unlock
  /// screen (or onboarding when none remain); otherwise stay on Manage Vaults
  /// with the active session intact.
  Future<void> deleteVaultFromManager(String path);
}

// A maximum-contrast scheme: every container / variant / outline role collapses
// to the surface / onSurface pair, so text is always onSurface on surface. Only
// `error` keeps its own high-contrast hue. Left at Material's defaults these
// roles are mid-tones that fail contrast in HC (review_changes rendered 1.74:1).
ColorScheme _highContrastScheme({
  required Brightness brightness,
  required Color surface,
  required Color onSurface,
  required Color error,
}) {
  final onError = brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
  final base = ColorScheme(
    brightness: brightness,
    primary: onSurface,
    onPrimary: surface,
    secondary: onSurface,
    onSecondary: surface,
    error: error,
    onError: onError,
    surface: surface,
    onSurface: onSurface,
  );
  return base.copyWith(
    tertiary: onSurface,
    onTertiary: surface,
    primaryContainer: surface,
    onPrimaryContainer: onSurface,
    secondaryContainer: surface,
    onSecondaryContainer: onSurface,
    tertiaryContainer: surface,
    onTertiaryContainer: onSurface,
    errorContainer: surface,
    onErrorContainer: onSurface,
    surfaceContainerLowest: surface,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surface,
    surfaceContainerHighest: surface,
    surfaceBright: surface,
    surfaceDim: surface,
    onSurfaceVariant: onSurface,
    outline: onSurface,
    outlineVariant: onSurface,
    inverseSurface: onSurface,
    onInverseSurface: surface,
    inversePrimary: surface,
    surfaceTint: surface,
  );
}

ThemeData gabbroLightTheme({required bool highContrast}) {
  if (highContrast) {
    return ThemeData(
      colorScheme: _highContrastScheme(
        brightness: Brightness.light,
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF000000),
        error: const Color(0xFF7A0000),
      ),
      extensions: const [GabbroContrast(highContrast: true)],
      useMaterial3: true,
    );
  }
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C7A3E)),
    extensions: const [GabbroContrast(highContrast: false)],
    useMaterial3: true,
  );
}

ThemeData gabbroDarkTheme({required bool highContrast}) {
  if (highContrast) {
    return ThemeData(
      colorScheme: _highContrastScheme(
        brightness: Brightness.dark,
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFFFFFFF),
        error: const Color(0xFFFF9999),
      ),
      extensions: const [GabbroContrast(highContrast: true)],
      useMaterial3: true,
    );
  }
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF5C7A3E),
      brightness: Brightness.dark,
    ),
    extensions: const [GabbroContrast(highContrast: false)],
    useMaterial3: true,
  );
}

/// True when [event] is a key-down of the physical [key] with Ctrl held. Matches
/// the PHYSICAL key (not the logical one) so Ctrl+L / Ctrl+F work on any keyboard
/// layout — on a Cyrillic/Greek layout the physical L/F position emits a non-Latin
/// letter, which a logical match would silently miss.
bool isCtrlShortcut(KeyEvent event, PhysicalKeyboardKey key) =>
    event is KeyDownEvent &&
    event.physicalKey == key &&
    HardwareKeyboard.instance.isControlPressed;

/// App-root fallback for the Escape key: peel one focus level (blur a field, or
/// close a dialog / pop a screen). Dispatched only when nothing deeper handled
/// Escape first, so a dialog's own Esc (e.g. the sync review's cancel-with-
/// rollback) always wins.
class _EscapeFallbackIntent extends Intent {
  const _EscapeFallbackIntent();
}

/// Owns Tab -> Next/PreviousFocusIntent traversal app-wide. While the vault list
/// owns Tab ([vaultRegionActive] true — desktop + vault list is the current
/// route) it ABSORBS the intent (the global HardwareKeyboard handler drives the
/// region cycle instead; that handler does NOT stop the focus/shortcuts path, so
/// without this the two fight and focus lands one control too far). Everywhere
/// else it performs the NORMAL traversal, so Tab is unchanged on other screens
/// and inside dialogs. It must stay ALWAYS-enabled: a disabled action still
/// shadows WidgetsApp's default in the Actions lookup, which would kill traversal
/// outright. Registered via MaterialApp.builder — below WidgetsApp's default
/// shortcuts, above every route's ModalScope — so it also covers the cold-start
/// case, where the key dispatches from the route scope with nothing focused.
class _RegionTraversalAction<T extends Intent> extends Action<T> {
  _RegionTraversalAction({required this.forward});
  final bool forward;

  @override
  Object? invoke(T intent) {
    if (vaultRegionActive?.call() ?? false) return null; // vault list drives Tab
    final focus = FocusManager.instance.primaryFocus;
    if (forward) {
      focus?.nextFocus();
    } else {
      focus?.previousFocus();
    }
    return null;
  }
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

  /// Localization delegates; defaults to [gabbroLocalizationsDelegates].
  /// Override in tests to inject padded strings (see overflow_probe_test.dart).
  final Iterable<LocalizationsDelegate<dynamic>> localizationsDelegates;

  const GabbroApp({
    super.key,
    required this.registry,
    required this.vaultPath,
    required this.settings,
    this.initialScreen,
    this.clock = DateTime.now,
    this.localizationsDelegates = gabbroLocalizationsDelegates,
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
    if (event is KeyDownEvent) {
      _resetForegroundTimer();
      // Ctrl+L locks the vault from anywhere. (No Ctrl+C binding: copying a
      // secret stays a deliberate, auto-clearing action — see
      // keyboard_shortcuts_list_screen.)
      if (isCtrlShortcut(event, PhysicalKeyboardKey.keyL)) {
        _lock();
        return true;
      }
      // Ctrl+F focuses the vault-list search (Ctrl+Shift+F: all-fields mode).
      // Global like Ctrl+L so it keeps working wherever focus is; a no-op on
      // screens that haven't registered a handler.
      if (isCtrlShortcut(event, PhysicalKeyboardKey.keyF) &&
          focusVaultSearch != null) {
        focusVaultSearch!(allFields: HardwareKeyboard.instance.isShiftPressed);
        return true;
      }
      // Ctrl+N opens the new-entry type picker; Ctrl+M opens the overflow menu.
      // Both reach controls the region Tab-cycle excludes, so keyboard-only users
      // can still create entries and open the menu. Global like Ctrl+L; the
      // vault-list hooks self-gate (current route, not selection mode).
      if (isCtrlShortcut(event, PhysicalKeyboardKey.keyN) &&
          openNewEntry != null) {
        openNewEntry!();
        return true;
      }
      if (isCtrlShortcut(event, PhysicalKeyboardKey.keyM) &&
          openVaultMenu != null) {
        openVaultMenu!();
        return true;
      }
      // Ctrl+Q asks to lock and quit — it raises the menu item's own confirm
      // dialog rather than exiting, so a mistyped key costs a live session
      // nothing. Same gating as Ctrl+N / Ctrl+M.
      if (isCtrlShortcut(event, PhysicalKeyboardKey.keyQ) && quitVault != null) {
        quitVault!();
        return true;
      }
      // Tab / Shift+Tab drives the vault-list region cycle when a vault list has
      // registered a handler. Global like Ctrl+L/F so it fires wherever focus is
      // — a body-scoped Actions override silently failed on real hardware (round
      // 10). The handler self-gates (Linux desktop only, current route only) and
      // returns false to let Tab fall through to default traversal.
      if (event.logicalKey == LogicalKeyboardKey.tab &&
          vaultRegionTab != null) {
        final forward = !HardwareKeyboard.instance.isShiftPressed;
        if (vaultRegionTab!(forward: forward)) return true;
      }
      // Esc blurs a focused text field on a SCREEN before anything else (D4:
      // unfocus first, then a 2nd Esc goes back via the app-root fallback).
      // Handled here — ahead of focus dispatch — because a focused text field
      // otherwise swallows Escape. A field inside a dialog is left alone so the
      // app-root fallback closes the whole dialog instead of just blurring.
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        // The vault-list region cycle owns Esc while focus is inside it: Esc is
        // the only exit back to Unfocused, from ANY region — not only the
        // search field, which was the one region the blur below could reach.
        // The hook self-gates (desktop, current route, focus inside a region),
        // so Esc still pops screens and closes dialogs everywhere else.
        if (vaultRegionEscape?.call() ?? false) return true;
        final focus = FocusManager.instance.primaryFocus;
        final ctx = focus?.context;
        final inField =
            ctx != null && ctx.findAncestorStateOfType<EditableTextState>() != null;
        final inDialog = ctx != null && ModalRoute.of(ctx) is PopupRoute;
        if (inField && !inDialog) {
          focus!.unfocus();
          return true;
        }
      }
    }
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
    _foregroundTimer = Timer(duration, () => _lock(automatic: true));
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
    _backgroundTimer = Timer(duration, () => _lock(automatic: true));
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

  /// [automatic] marks a lock the user did not ask for — a timeout expiring,
  /// meaning they walked away. Those take the clipboard with them (RT-4). A
  /// deliberate lock (Ctrl+L, the menu item) leaves a pending wipe to run out
  /// its configured delay: the user is right there and may be about to paste.
  /// `detached` is the process dying, so it counts as deliberate — nothing is
  /// left running to honour a wipe either way.
  void _lock({bool automatic = false}) {
    _foregroundTimer?.cancel();
    _backgroundTimer?.cancel();
    _backgroundedAt = null;
    autotypeTarget.clear(); // a locked vault has no auto-type target
    if (automatic) clipboardWiper.wipeNow();
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
    final updated = _registry.add(VaultRecord(
      path: path,
      alias: alias,
      lastUsedAt: DateTime.now(),
    ));
    await updated.save();
    setState(() => _registry = updated);
  }

  UnlockScreen _buildUnlockScreen(String path, String alias) => UnlockScreen(
    vaultPath: path,
    vaultAlias: alias,
    blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
    registry: _registry,
    onQuit: _quitApp,
  );

  Widget _buildHome() {
    final lastUsed = _registry.lastUsed;
    if (lastUsed == null) {
      return OnboardingScreen(
        blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
        onVaultCreated: _onVaultCreated,
        onQuit: _quitApp,
        onAdoptRequested: openAdoptVault,
      );
    }
    return _buildUnlockScreen(lastUsed.path, lastUsed.alias);
  }

  @override
  Future<void> updateSettings(AppSettings updated) async {
    // Optimistic: reflect the change in the UI immediately, then persist.
    // Settings are best-effort on disk; the live app state is the source of
    // truth for the session.
    setState(() => _settings = updated);
    _resetForegroundTimer();
    await updated.save();
  }

  @override
  Future<void> touchVaultLastUsed(String path) async {
    final updated = _registry.touchLastUsed(path);
    await updated.save();
    setState(() => _registry = updated);
  }

  @override
  void switchToVault(String path, String alias) {
    // pushAndRemoveUntil (not pushReplacement) so the whole back stack is
    // cleared — a back-press after switching vaults must never reveal a prior
    // (possibly still-unlocked) vault's screen. Mirrors auto-lock (_lock).
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _buildUnlockScreen(path, alias)),
      (_) => false,
    );
  }

  @override
  void navigateToManageVaults() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => _buildManageVaultsScreen()),
    );
  }

  @override
  void openAdoptVault() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AdoptVaultScreen(
          registry: _registry,
          onRegistered: (path, alias) async {
            // Same registration the create flow uses (type auto-detect), then
            // the unlock screen with a cleared back stack — adopting grants
            // no access.
            await _onVaultCreated(path, alias);
            switchToVault(path, alias);
          },
        ),
      ),
    );
  }

  @override
  Future<void> removeVault(String path, {required bool deleteFiles}) async {
    if (deleteFiles) {
      // R-03: removes the vault AND its .bak safety copy.
      try {
        await deleteVaultFiles(path);
      } catch (_) {}
    }
    final updated = _registry.remove(path);
    await updated.save();
    // Direct field mutation (no setState) to avoid racing pushAndRemoveUntil —
    // mirrors onDelete for the active vault.
    _registry = updated;
    try {
      lockVault();
    } catch (_) {}
    final remaining = updated.lastUsed;
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => remaining == null
            ? OnboardingScreen(
                postDeletionMessage:
                    'The unreadable vault was removed. Create or add a vault to continue.',
                blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
                onVaultCreated: _onVaultCreated,
                onQuit: _quitApp,
                onAdoptRequested: openAdoptVault,
              )
            : _buildUnlockScreen(remaining.path, remaining.alias),
      ),
      (_) => false,
    );
  }

  @override
  Future<void> deleteVaultFromManager(String path) async {
    final wasActive = path == _registry.lastUsed?.path;
    // R-03: removes the vault AND its .bak safety copy. Tolerant like
    // removeVault so a missing/failed file delete still updates the registry.
    try {
      await deleteVaultFiles(path);
    } catch (_) {}
    final updated = _registry.remove(path);
    await updated.save();
    final remaining = updated.lastUsed;
    switch (postDeleteRoute(
      wasActive: wasActive,
      hasRemaining: remaining != null,
    )) {
      case PostDeleteRoute.stayOnManageVaults:
        // Non-active delete: the current unlocked session is unaffected.
        setState(() => _registry = updated);
      case PostDeleteRoute.onboarding:
        // Direct field mutation (no setState) to avoid racing pushAndRemoveUntil.
        _registry = updated;
        try {
          lockVault();
        } catch (_) {}
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => OnboardingScreen(
              postDeletionMessage:
                  'Your vault has been deleted. Create a new one to continue.',
              blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
              onVaultCreated: _onVaultCreated,
              onQuit: _quitApp,
              onAdoptRequested: openAdoptVault,
            ),
          ),
          (_) => false,
        );
      case PostDeleteRoute.remainingVault:
        _registry = updated;
        try {
          lockVault();
        } catch (_) {}
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => _buildUnlockScreen(remaining!.path, remaining.alias),
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
    onDelete: deleteVaultFromManager,
    onAddVault: () {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => OnboardingScreen(
            blockPassphraseCopyPaste: _settings.blockPassphraseCopyPaste,
            onVaultCreated: _onVaultCreated,
            existingAliases: _registry.records.map((r) => r.alias).toSet(),
            onQuit: _quitApp,
            onAdoptRequested: openAdoptVault,
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

  @override
  Widget build(BuildContext context) {
    final hc = _settings.highContrast;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: TextScaler.linear(
          clampToDevice(_settings.textScale, mq.size.shortestSide),
        ),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetForegroundTimer(),
        // App-root Escape fallback. Ancestor of the navigator, so any dialog's
        // own Esc handler wins; this only fires when nothing deeper did.
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): _EscapeFallbackIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _EscapeFallbackIntent: CallbackAction<_EscapeFallbackIntent>(
                onInvoke: (_) {
                  _handleEscape();
                  return null;
                },
              ),
            },
            child: MaterialApp(
              navigatorKey: _navigatorKey,
          title: 'Gabbro',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: widget.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: _settings.language == LanguageChoice.system
              ? null
              : localeFor(_settings.language),
          themeMode: _themeMode,
          theme: gabbroLightTheme(highContrast: hc),
          darkTheme: gabbroDarkTheme(highContrast: hc),
          // Below WidgetsApp's default shortcuts, above the Navigator: the only
          // place a Tab-traversal absorber overrides the default in every focus
          // state (including cold-start, dispatched from the route scope).
          builder: (context, child) => Actions(
            actions: <Type, Action<Intent>>{
              NextFocusIntent:
                  _RegionTraversalAction<NextFocusIntent>(forward: true),
              PreviousFocusIntent:
                  _RegionTraversalAction<PreviousFocusIntent>(forward: false),
            },
            child: child!,
          ),
          home: widget.initialScreen ?? _buildHome(),
            ),
          ),
        ),
      ),
    );
  }

  /// Escape fallback: close the top dialog, or pop the current screen (its back
  /// arrow). Fires only when nothing deeper handled Escape — a focused search
  /// field blurs itself (vault_list), and a dialog with its own Esc (sync review)
  /// cancels with rollback, both winning over this.
  void _handleEscape() => _navigatorKey.currentState?.maybePop();
}
