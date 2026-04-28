import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/settings.dart';

void main() {
  // ── _stripComments ────────────────────────────────────────────────────────

  group('_stripComments', () {
    test('removes // lines', () {
      const input = '// a comment\n{"key": "value"}';
      final result = AppSettings.stripCommentsForTest(input);
      expect(result.contains('// a comment'), isFalse);
      expect(result.contains('"key"'), isTrue);
    });

    test('removes # lines', () {
      const input = '# a comment\n{"key": "value"}';
      final result = AppSettings.stripCommentsForTest(input);
      expect(result.contains('# a comment'), isFalse);
      expect(result.contains('"key"'), isTrue);
    });

    test('preserves non-comment lines', () {
      const input = '{\n  "theme": "dark"\n}';
      final result = AppSettings.stripCommentsForTest(input);
      expect(result.trim(), contains('"theme"'));
    });

    test('handles empty string', () {
      final result = AppSettings.stripCommentsForTest('');
      expect(result.trim(), isEmpty);
    });
  });

  // ── fromJson ──────────────────────────────────────────────────────────────

  group('AppSettings.fromJson', () {
    test('parses all fields correctly', () {
      final s = AppSettings.fromJson({
        'theme': 'dark',
        'text_size': 'large',
        'high_contrast': true,
      });
      expect(s.theme, ThemeChoice.dark);
      expect(s.textSize, TextSizeChoice.large);
      expect(s.highContrast, isTrue);
    });

    test('falls back to defaults for missing keys', () {
      final s = AppSettings.fromJson({});
      expect(s.theme, ThemeChoice.system);
      expect(s.textSize, TextSizeChoice.regular);
      expect(s.highContrast, isFalse);
    });

    test('all ThemeChoice values round-trip', () {
      for (final choice in ThemeChoice.values) {
        final s = AppSettings.fromJson({'theme': choice.name});
        expect(s.theme, choice);
      }
    });

    test('all TextSizeChoice values round-trip', () {
      for (final choice in TextSizeChoice.values) {
        final s = AppSettings.fromJson({'text_size': choice.name});
        expect(s.textSize, choice);
      }
    });
  });

  // ── toJson ────────────────────────────────────────────────────────────────

  group('AppSettings.toJson', () {
    test('serialises all fields', () {
      const s = AppSettings(
        theme: ThemeChoice.light,
        textSize: TextSizeChoice.small,
        highContrast: false,
      );
      final json = s.toJson();
      expect(json['theme'], 'light');
      expect(json['text_size'], 'small');
      expect(json['high_contrast'], isFalse);
    });

    test('round-trips through fromJson', () {
      const original = AppSettings(
        theme: ThemeChoice.dark,
        textSize: TextSizeChoice.extra_large,
        highContrast: false,
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.theme, original.theme);
      expect(restored.textSize, original.textSize);
      expect(restored.highContrast, original.highContrast);
    });
  });

  // ── copyWith ──────────────────────────────────────────────────────────────

  group('AppSettings.copyWith', () {
    test('overrides only the specified field', () {
      const original = AppSettings();
      final updated = original.copyWith(theme: ThemeChoice.dark);
      expect(updated.theme, ThemeChoice.dark);
      expect(updated.textSize, original.textSize);
      expect(updated.highContrast, original.highContrast);
    });

    test('leaving all params null returns equivalent settings', () {
      const original = AppSettings(
        theme: ThemeChoice.light,
        textSize: TextSizeChoice.large,
      );
      final copy = original.copyWith();
      expect(copy.theme, original.theme);
      expect(copy.textSize, original.textSize);
    });
  });

  // ── defaults ─────────────────────────────────────────────────────────────

  test('defaults are system theme, regular text, no high contrast', () {
    final d = AppSettings.defaults;
    expect(d.theme, ThemeChoice.system);
    expect(d.textSize, TextSizeChoice.regular);
    expect(d.highContrast, isFalse);
  });
}