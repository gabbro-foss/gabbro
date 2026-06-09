import 'dart:convert';
import 'dart:io';
import 'package:gabbro/app_paths.dart';

// Valid values shown in comments throughout this file.
// Lines beginning with // or # are stripped before parsing.

/// User-editable application settings.
/// On Linux: `~/.config/gabbro/settings.jsonc`
/// On Android: `<app support dir>/settings.jsonc`
class AppSettings {
  final ThemeChoice theme;
  final TextSizeChoice textSize;
  final bool highContrast; // placeholder — not yet implemented
  final ForegroundLockTimeout foregroundLockTimeout;
  final BackgroundLockTimeout backgroundLockTimeout;
  final ClipboardClearTimeout clipboardClearTimeout;
  final PasswordHistoryExpiry passwordHistoryExpiry;
  final AlphabetBarPosition alphabetBarPosition;
  final bool blockPassphraseCopyPaste;
  final bool showVaultList;
  final LanguageChoice language;
  final bool biometricUnlock;
  final double tabletListPaneWidth;

  const AppSettings({
    this.theme = ThemeChoice.system,
    this.textSize = TextSizeChoice.regular,
    this.highContrast = false,
    this.foregroundLockTimeout = ForegroundLockTimeout.thirtySeconds,
    this.backgroundLockTimeout = BackgroundLockTimeout.fiveMinutes,
    this.clipboardClearTimeout = ClipboardClearTimeout.sixtySeconds,
    this.passwordHistoryExpiry = PasswordHistoryExpiry.thirtyDays,
    this.alphabetBarPosition = AlphabetBarPosition.left,
    this.blockPassphraseCopyPaste = true,
    this.showVaultList = false,
    this.language = LanguageChoice.system,
    this.biometricUnlock = false,
    this.tabletListPaneWidth = 260.0,
  });

  static AppSettings get defaults => const AppSettings();

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'text_size': textSize.name,
    'high_contrast': highContrast,
    'foreground_lock_timeout': foregroundLockTimeout.name,
    'background_lock_timeout': backgroundLockTimeout.name,
    'clipboard_clear_timeout': clipboardClearTimeout.name,
    'password_history_expiry': passwordHistoryExpiry.name,
    'alphabet_bar_position': alphabetBarPosition.name,
    'block_passphrase_copy_paste': blockPassphraseCopyPaste,
    'show_vault_list': showVaultList,
    'language': language.name,
    'biometric_unlock': biometricUnlock,
    'tablet_list_pane_width': tabletListPaneWidth,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      theme: ThemeChoice.values.byName((json['theme'] as String? ?? 'system')),
      textSize: TextSizeChoice.values.byName(
        (json['text_size'] as String? ?? 'regular').replaceAll('extra_large', 'extraLarge'),
      ),
      highContrast: json['high_contrast'] as bool? ?? false,
      foregroundLockTimeout: ForegroundLockTimeout.values.byName(
        json['foreground_lock_timeout'] as String? ?? 'thirtySeconds',
      ),
      backgroundLockTimeout: BackgroundLockTimeout.values.byName(
        json['background_lock_timeout'] as String? ?? 'fiveMinutes',
      ),
      clipboardClearTimeout: ClipboardClearTimeout.values.byName(
        json['clipboard_clear_timeout'] as String? ?? 'sixtySeconds',
      ),
      passwordHistoryExpiry: PasswordHistoryExpiry.values.byName(
        json['password_history_expiry'] as String? ?? 'thirtyDays',
      ),
      alphabetBarPosition: AlphabetBarPosition.values.byName(
        json['alphabet_bar_position'] as String? ?? 'left',
      ),
      blockPassphraseCopyPaste: json['block_passphrase_copy_paste'] as bool? ?? true,
      showVaultList: json['show_vault_list'] as bool? ?? false,
      language: LanguageChoice.values.byName(
        json['language'] as String? ?? 'system',
      ),
      biometricUnlock: json['biometric_unlock'] as bool? ?? false,
      tabletListPaneWidth: (json['tablet_list_pane_width'] as num?)
              ?.toDouble()
              .clamp(180.0, 900.0) ??
          260.0,
    );
  }

  AppSettings copyWith({
    ThemeChoice? theme,
    TextSizeChoice? textSize,
    bool? highContrast,
    ForegroundLockTimeout? foregroundLockTimeout,
    BackgroundLockTimeout? backgroundLockTimeout,
    ClipboardClearTimeout? clipboardClearTimeout,
    PasswordHistoryExpiry? passwordHistoryExpiry,
    AlphabetBarPosition? alphabetBarPosition,
    bool? blockPassphraseCopyPaste,
    bool? showVaultList,
    LanguageChoice? language,
    bool? biometricUnlock,
    double? tabletListPaneWidth,
  }) => AppSettings(
    theme: theme ?? this.theme,
    textSize: textSize ?? this.textSize,
    highContrast: highContrast ?? this.highContrast,
    foregroundLockTimeout: foregroundLockTimeout ?? this.foregroundLockTimeout,
    backgroundLockTimeout: backgroundLockTimeout ?? this.backgroundLockTimeout,
    clipboardClearTimeout: clipboardClearTimeout ?? this.clipboardClearTimeout,
    passwordHistoryExpiry: passwordHistoryExpiry ?? this.passwordHistoryExpiry,
    alphabetBarPosition: alphabetBarPosition ?? this.alphabetBarPosition,
    blockPassphraseCopyPaste: blockPassphraseCopyPaste ?? this.blockPassphraseCopyPaste,
    showVaultList: showVaultList ?? this.showVaultList,
    language: language ?? this.language,
    biometricUnlock: biometricUnlock ?? this.biometricUnlock,
    tabletListPaneWidth: tabletListPaneWidth ?? this.tabletListPaneWidth,
  );

  // ── File I/O ───────────────────────────────────────────────────────────

  static Future<File> _settingsFile() async {
    final dirPath = await GabbroPaths.configDir();
    return File('$dirPath/settings.jsonc');
  }

  static Future<AppSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!file.existsSync()) return defaults;
      final raw = await file.readAsString();
      final stripped = _stripComments(raw);
      if (stripped.trim().isEmpty) return defaults;
      final json = jsonDecode(stripped) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    final file = await _settingsFile();
    await file.writeAsString(_toJsonc());
  }

  // ── JSONC generation ───────────────────────────────────────────────────

  String _toJsonc() =>
      '''// Gabbro settings
// Edit this file to customise Gabbro.
// Lines beginning with // or # are ignored.
// Invalid values fall back to the default.
{
  // Application theme.
  // Options: "system" | "light" | "dark"
  "theme": "${theme.name}",

  // Interface text size.
  // Options: "small" | "regular" | "large" | "extraLarge" | "xxLarge"
  "text_size": "${textSize.name}",

  // High-contrast mode (not yet implemented — reserved for future use).
  // Options: true | false
  "high_contrast": $highContrast,

  // How long before the vault locks due to foreground inactivity.
  // Options: "thirtySeconds" | "oneMinute" | "fiveMinutes" | "never"
  "foreground_lock_timeout": "${foregroundLockTimeout.name}",

  // How long the app can stay backgrounded before the vault locks.
  // Options: "oneMinute" | "fiveMinutes" | "fifteenMinutes" | "never"
  "background_lock_timeout": "${backgroundLockTimeout.name}",

  // How long before the clipboard is cleared after copying a secret.
  // Options: "never" | "thirtySeconds" | "sixtySeconds" | "twoMinutes"
  "clipboard_clear_timeout": "${clipboardClearTimeout.name}",

  // How long to keep a previous password before auto-purging.
  // Options: "sevenDays" | "thirtyDays" | "ninetyDays" | "keepForever"
  "password_history_expiry": "${passwordHistoryExpiry.name}",

  // Position of the alphabet index bar (phone layout only).
  // Options: "left" | "right"
  "alphabet_bar_position": "${alphabetBarPosition.name}",

  // Block copy/paste on master passphrase fields.
  // Options: true | false
  "block_passphrase_copy_paste": $blockPassphraseCopyPaste,

  // Show vault list on the login screen instead of the last-used vault only.
  // Options: true | false
  "show_vault_list": $showVaultList,

  // Override the system language for the app UI.
  // Options: "system" | "bg" | "cs" | "da" | "de" | "el" | "en" | "es" | "et" | "fi" | "fr"
  //        | "hr" | "hu" | "it" | "ja" | "kk" | "ko" | "lt" | "lv" | "nb" | "nn" | "pl"
  //        | "ptBr" | "ptPt" | "ru" | "sk" | "sl" | "srLatn" | "sv" | "uk" | "zhCn" | "zhTw"
  "language": "${language.name}",

  // Use biometrics (fingerprint/face) to unlock instead of typing the passphrase.
  // Android only. Stores the passphrase encrypted on-device. Default: false.
  // Options: true | false
  "biometric_unlock": $biometricUnlock,

  // Width of the list pane in the tablet / landscape two-pane layout (dp).
  // Drag the divider in the app to resize; this value is updated automatically.
  // Stored range: 180–900. Effective max is capped at 65% of screen width at runtime.
  "tablet_list_pane_width": $tabletListPaneWidth
}
''';

  // ── JSONC parser ───────────────────────────────────────────────────────

  /// Exposed for testing only.
  static String stripCommentsForTest(String input) => _stripComments(input);

  static String _stripComments(String input) {
    return input
        .split('\n')
        .where((line) {
          final trimmed = line.trimLeft();
          return !trimmed.startsWith('//') && !trimmed.startsWith('#');
        })
        .join('\n');
  }
}

// ── Enums ──────────────────────────────────────────────────────────────────

enum ThemeChoice { system, light, dark }

enum TextSizeChoice { small, regular, large, extraLarge, xxLarge }

enum ForegroundLockTimeout { thirtySeconds, oneMinute, fiveMinutes, never }

enum BackgroundLockTimeout { oneMinute, fiveMinutes, fifteenMinutes, never }

enum ClipboardClearTimeout { never, thirtySeconds, sixtySeconds, twoMinutes }

enum PasswordHistoryExpiry { sevenDays, thirtyDays, ninetyDays, keepForever }

enum AlphabetBarPosition { left, right }

enum LanguageChoice {
  system,
  // Simple locales — enum name equals BCP-47 language code
  bg, cs, da, de, el, en, es, et, eu, fi, fr,
  hr, hu, it, ja, kk, ko, lt, lv, nb, nn,
  nl, pl, ru, sk, sl, sv, uk, yo,
  // Complex locales — enum name differs from BCP-47 tag; see _localeFor() in main.dart
  ptBr, ptPt, srLatn, zhCn, zhTw,
}
