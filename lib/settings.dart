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

  /// Absolute interface text scale (1.0 = normal). Drives both text and, in
  /// later phases, control/target sizing (ADR-016). Stored range [0.8, 8.0];
  /// clamped to the device's screen-derived max on load (see text_scale.dart).
  final double textScale;
  final bool highContrast; // placeholder — not yet implemented
  final ForegroundLockTimeout foregroundLockTimeout;
  final BackgroundLockTimeout backgroundLockTimeout;
  final ClipboardClearTimeout clipboardClearTimeout;
  final PasswordHistoryExpiry passwordHistoryExpiry;
  final AlphabetBarPosition alphabetBarPosition;
  final bool blockPassphraseCopyPaste;
  final LanguageChoice language;
  final bool biometricUnlock;
  final double tabletListPaneWidth;

  /// Persisted SAF tree URI of the Android `.gabbro` export destination folder
  /// (`content://…/tree/…`). Empty until the user picks a folder. Lets export
  /// remember the sync folder across runs instead of re-picking each time.
  /// Android-only; ignored on Linux.
  final String androidExportFolderUri;

  const AppSettings({
    this.theme = ThemeChoice.system,
    this.textScale = 1.0,
    this.highContrast = false,
    this.foregroundLockTimeout = ForegroundLockTimeout.thirtySeconds,
    this.backgroundLockTimeout = BackgroundLockTimeout.fiveMinutes,
    this.clipboardClearTimeout = ClipboardClearTimeout.sixtySeconds,
    this.passwordHistoryExpiry = PasswordHistoryExpiry.thirtyDays,
    this.alphabetBarPosition = AlphabetBarPosition.left,
    this.blockPassphraseCopyPaste = true,
    this.language = LanguageChoice.system,
    this.biometricUnlock = false,
    this.tabletListPaneWidth = 260.0,
    this.androidExportFolderUri = '',
  });

  static AppSettings get defaults => const AppSettings();

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'text_scale': textScale,
    'high_contrast': highContrast,
    'foreground_lock_timeout': foregroundLockTimeout.name,
    'background_lock_timeout': backgroundLockTimeout.name,
    'clipboard_clear_timeout': clipboardClearTimeout.name,
    'password_history_expiry': passwordHistoryExpiry.name,
    'alphabet_bar_position': alphabetBarPosition.name,
    'block_passphrase_copy_paste': blockPassphraseCopyPaste,
    'language': language.name,
    'biometric_unlock': biometricUnlock,
    'tablet_list_pane_width': tabletListPaneWidth,
    'android_export_folder_uri': androidExportFolderUri,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      theme: ThemeChoice.values.byName((json['theme'] as String? ?? 'system')),
      textScale: _parseTextScale(json),
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
      language: LanguageChoice.values.byName(
        json['language'] as String? ?? 'system',
      ),
      biometricUnlock: json['biometric_unlock'] as bool? ?? false,
      tabletListPaneWidth: (json['tablet_list_pane_width'] as num?)
              ?.toDouble()
              .clamp(180.0, 900.0) ??
          260.0,
      androidExportFolderUri: json['android_export_folder_uri'] as String? ?? '',
    );
  }

  // Hard bounds on the stored scale; the device-derived max is applied
  // separately at load/render time (text_scale.dart, ADR-016).
  static const double minTextScale = 0.8;
  static const double maxTextScale = 8.0;

  /// Resolves the interface text scale from persisted JSON. Prefers the new
  /// numeric `text_scale` key; falls back to migrating the legacy `text_size`
  /// word; defaults to 1.0. Result is clamped to [minTextScale, maxTextScale].
  static double _parseTextScale(Map<String, dynamic> json) {
    final numeric = json['text_scale'];
    if (numeric is num) {
      return numeric.toDouble().clamp(minTextScale, maxTextScale).toDouble();
    }
    final legacy = json['text_size'] as String?;
    if (legacy != null) return _legacyTextSizeScale(legacy);
    return 1.0;
  }

  /// Maps a pre-ADR-016 `text_size` word to its scale. Accepts both the
  /// camelCase (`extraLarge`) and underscore (`extra_large`) legacy forms.
  static double _legacyTextSizeScale(String word) {
    switch (word.replaceAll('extra_large', 'extraLarge')) {
      case 'small':
        return 0.85;
      case 'large':
        return 1.15;
      case 'extraLarge':
        return 1.3;
      case 'xxLarge':
        return 1.5;
      case 'regular':
      default:
        return 1.0;
    }
  }

  AppSettings copyWith({
    ThemeChoice? theme,
    double? textScale,
    bool? highContrast,
    ForegroundLockTimeout? foregroundLockTimeout,
    BackgroundLockTimeout? backgroundLockTimeout,
    ClipboardClearTimeout? clipboardClearTimeout,
    PasswordHistoryExpiry? passwordHistoryExpiry,
    AlphabetBarPosition? alphabetBarPosition,
    bool? blockPassphraseCopyPaste,
    LanguageChoice? language,
    bool? biometricUnlock,
    double? tabletListPaneWidth,
    String? androidExportFolderUri,
  }) => AppSettings(
    theme: theme ?? this.theme,
    textScale: textScale ?? this.textScale,
    highContrast: highContrast ?? this.highContrast,
    foregroundLockTimeout: foregroundLockTimeout ?? this.foregroundLockTimeout,
    backgroundLockTimeout: backgroundLockTimeout ?? this.backgroundLockTimeout,
    clipboardClearTimeout: clipboardClearTimeout ?? this.clipboardClearTimeout,
    passwordHistoryExpiry: passwordHistoryExpiry ?? this.passwordHistoryExpiry,
    alphabetBarPosition: alphabetBarPosition ?? this.alphabetBarPosition,
    blockPassphraseCopyPaste: blockPassphraseCopyPaste ?? this.blockPassphraseCopyPaste,
    language: language ?? this.language,
    biometricUnlock: biometricUnlock ?? this.biometricUnlock,
    tabletListPaneWidth: tabletListPaneWidth ?? this.tabletListPaneWidth,
    androidExportFolderUri:
        androidExportFolderUri ?? this.androidExportFolderUri,
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

  // Interface text scale (accessibility). 1.0 = normal; higher = larger text
  // and controls. Stored range 0.8 - 8.0; capped to your device's screen on load.
  "text_scale": $textScale,

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
  "tablet_list_pane_width": $tabletListPaneWidth,

  // Android export destination folder (SAF tree URI). Set automatically when you
  // pick an export folder; remembered so exports go straight there. Android only.
  "android_export_folder_uri": ${jsonEncode(androidExportFolderUri)}
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
  // Complex locales — enum name differs from BCP-47 tag; see localeFor() in main.dart
  ptBr, ptPt, srLatn, zhCn, zhTw,
}
