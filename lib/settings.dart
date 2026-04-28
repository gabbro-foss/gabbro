import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// Valid values shown in comments throughout this file.
// Lines beginning with // or # are stripped before parsing.

/// User-editable application settings.
/// On Linux: ~/.config/gabbro/settings.jsonc
/// On Android: <app support dir>/settings.jsonc
class AppSettings {
  final ThemeChoice theme;
  final TextSizeChoice textSize;
  final bool highContrast; // placeholder — not yet implemented

  const AppSettings({
    this.theme = ThemeChoice.system,
    this.textSize = TextSizeChoice.regular,
    this.highContrast = false,
  });

  static AppSettings get defaults => const AppSettings();

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'text_size': textSize.name,
    'high_contrast': highContrast,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      theme: ThemeChoice.values.byName((json['theme'] as String? ?? 'system')),
      textSize: TextSizeChoice.values.byName(
        (json['text_size'] as String? ?? 'regular'),
      ),
      highContrast: json['high_contrast'] as bool? ?? false,
    );
  }

  AppSettings copyWith({
    ThemeChoice? theme,
    TextSizeChoice? textSize,
    bool? highContrast,
  }) => AppSettings(
    theme: theme ?? this.theme,
    textSize: textSize ?? this.textSize,
    highContrast: highContrast ?? this.highContrast,
  );

  // ── File I/O ───────────────────────────────────────────────────────────

  static Future<File> _settingsFile() async {
    final String dirPath;
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      dirPath = Platform.isLinux
          ? '$home/.config/gabbro'
          : '$home/Library/Application Support/gabbro';
    } else {
      // Android (and future platforms): use app support directory.
      final dir = await getApplicationSupportDirectory();
      dirPath = dir.path;
    }
    final dir = Directory(dirPath);
    if (!dir.existsSync()) await dir.create(recursive: true);
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
  // Options: "small" | "regular" | "large" | "extra_large"
  "text_size": "${textSize.name}",

  // High-contrast mode (not yet implemented — reserved for future use).
  // Options: true | false
  "high_contrast": $highContrast
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

enum TextSizeChoice { small, regular, large, extra_large }
