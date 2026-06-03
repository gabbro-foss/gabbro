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
        textSize: TextSizeChoice.extraLarge,
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

    test('overrides highContrast only', () {
      const original = AppSettings();
      final updated = original.copyWith(highContrast: true);
      expect(updated.highContrast, isTrue);
      expect(updated.theme, original.theme);
      expect(updated.textSize, original.textSize);
    });

    test('round-trips highContrast true through fromJson', () {
      const original = AppSettings(
        theme: ThemeChoice.dark,
        textSize: TextSizeChoice.extraLarge,
        highContrast: true,
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.highContrast, isTrue);
      expect(restored.theme, original.theme);
      expect(restored.textSize, original.textSize);
    });
  });

  // ── defaults ─────────────────────────────────────────────────────────────

  test('defaults are system theme, regular text, no high contrast', () {
    final d = AppSettings.defaults;
    expect(d.theme, ThemeChoice.system);
    expect(d.textSize, TextSizeChoice.regular);
    expect(d.highContrast, isFalse);
  });

  // ── ForegroundLockTimeout ─────────────────────────────────────────────────

  group('ForegroundLockTimeout', () {
    test('all values round-trip through fromJson', () {
      for (final choice in ForegroundLockTimeout.values) {
        final s = AppSettings.fromJson({'foreground_lock_timeout': choice.name});
        expect(s.foregroundLockTimeout, choice);
      }
    });

    test('defaults to thirtySeconds', () {
      final s = AppSettings.fromJson({});
      expect(s.foregroundLockTimeout, ForegroundLockTimeout.thirtySeconds);
    });

    test('copyWith overrides foregroundLockTimeout only', () {
      const original = AppSettings();
      final updated = original.copyWith(
        foregroundLockTimeout: ForegroundLockTimeout.never,
      );
      expect(updated.foregroundLockTimeout, ForegroundLockTimeout.never);
      expect(updated.theme, original.theme);
      expect(updated.backgroundLockTimeout, original.backgroundLockTimeout);
    });

    test('serialises to toJson', () {
      const s = AppSettings(
        foregroundLockTimeout: ForegroundLockTimeout.oneMinute,
      );
      expect(s.toJson()['foreground_lock_timeout'], 'oneMinute');
    });
  });

  // ── ClipboardClearTimeout ─────────────────────────────────────────────────

  group('ClipboardClearTimeout', () {
    test('all values round-trip through fromJson', () {
      for (final choice in ClipboardClearTimeout.values) {
        final s = AppSettings.fromJson({'clipboard_clear_timeout': choice.name});
        expect(s.clipboardClearTimeout, choice);
      }
    });

    test('defaults to sixtySeconds', () {
      final s = AppSettings.fromJson({});
      expect(s.clipboardClearTimeout, ClipboardClearTimeout.sixtySeconds);
    });

    test('copyWith overrides clipboardClearTimeout only', () {
      const original = AppSettings();
      final updated = original.copyWith(
        clipboardClearTimeout: ClipboardClearTimeout.never,
      );
      expect(updated.clipboardClearTimeout, ClipboardClearTimeout.never);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });

    test('serialises to toJson', () {
      const s = AppSettings(
        clipboardClearTimeout: ClipboardClearTimeout.thirtySeconds,
      );
      expect(s.toJson()['clipboard_clear_timeout'], 'thirtySeconds');
    });
  });

  // ── AlphabetBarPosition ───────────────────────────────────────────────────

  group('AlphabetBarPosition', () {
    test('all values round-trip through fromJson', () {
      for (final choice in AlphabetBarPosition.values) {
        final s = AppSettings.fromJson({'alphabet_bar_position': choice.name});
        expect(s.alphabetBarPosition, choice);
      }
    });

    test('defaults to left', () {
      final s = AppSettings.fromJson({});
      expect(s.alphabetBarPosition, AlphabetBarPosition.left);
    });

    test('copyWith overrides alphabetBarPosition only', () {
      const original = AppSettings();
      final updated = original.copyWith(
        alphabetBarPosition: AlphabetBarPosition.right,
      );
      expect(updated.alphabetBarPosition, AlphabetBarPosition.right);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });

    test('serialises to toJson', () {
      const s = AppSettings(
        alphabetBarPosition: AlphabetBarPosition.right,
      );
      expect(s.toJson()['alphabet_bar_position'], 'right');
    });
  });

  // ── blockPassphraseCopyPaste ──────────────────────────────────────────────

  group('blockPassphraseCopyPaste', () {
    test('defaults to true', () {
      final s = AppSettings.fromJson({});
      expect(s.blockPassphraseCopyPaste, isTrue);
    });

    test('round-trips true through fromJson', () {
      final s = AppSettings.fromJson({'block_passphrase_copy_paste': true});
      expect(s.blockPassphraseCopyPaste, isTrue);
    });

    test('round-trips false through fromJson', () {
      final s = AppSettings.fromJson({'block_passphrase_copy_paste': false});
      expect(s.blockPassphraseCopyPaste, isFalse);
    });

    test('serialises to toJson', () {
      const s = AppSettings(blockPassphraseCopyPaste: false);
      expect(s.toJson()['block_passphrase_copy_paste'], isFalse);
    });

    test('copyWith overrides blockPassphraseCopyPaste only', () {
      const original = AppSettings();
      final updated = original.copyWith(blockPassphraseCopyPaste: false);
      expect(updated.blockPassphraseCopyPaste, isFalse);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });
  });

  // ── showVaultList ─────────────────────────────────────────────────────────

  group('showVaultList', () {
    test('defaults to false', () {
      final s = AppSettings.fromJson({});
      expect(s.showVaultList, isFalse);
    });

    test('round-trips true through fromJson', () {
      final s = AppSettings.fromJson({'show_vault_list': true});
      expect(s.showVaultList, isTrue);
    });

    test('round-trips false through fromJson', () {
      final s = AppSettings.fromJson({'show_vault_list': false});
      expect(s.showVaultList, isFalse);
    });

    test('serialises to toJson', () {
      const s = AppSettings(showVaultList: true);
      expect(s.toJson()['show_vault_list'], isTrue);
    });

    test('copyWith overrides showVaultList only', () {
      const original = AppSettings();
      final updated = original.copyWith(showVaultList: true);
      expect(updated.showVaultList, isTrue);
      expect(updated.theme, original.theme);
      expect(updated.blockPassphraseCopyPaste, original.blockPassphraseCopyPaste);
    });
  });

  // ── LanguageChoice ────────────────────────────────────────────────────────

  group('LanguageChoice', () {
    test('defaults to system', () {
      final s = AppSettings.fromJson({});
      expect(s.language, LanguageChoice.system);
    });

    test('all values round-trip through fromJson', () {
      for (final choice in LanguageChoice.values) {
        final s = AppSettings.fromJson({'language': choice.name});
        expect(s.language, choice);
      }
    });

    test('serialises to toJson', () {
      const s = AppSettings(language: LanguageChoice.de);
      expect(s.toJson()['language'], 'de');
    });

    test('copyWith overrides language only', () {
      const original = AppSettings();
      final updated = original.copyWith(language: LanguageChoice.fr);
      expect(updated.language, LanguageChoice.fr);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });

    test('missing key falls back to system', () {
      final s = AppSettings.fromJson({'theme': 'dark'});
      expect(s.language, LanguageChoice.system);
    });
  });

  // ── biometricUnlock ───────────────────────────────────────────────────────

  group('biometricUnlock', () {
    test('defaults to false', () {
      final s = AppSettings.fromJson({});
      expect(s.biometricUnlock, isFalse);
    });

    test('round-trips true through fromJson', () {
      final s = AppSettings.fromJson({'biometric_unlock': true});
      expect(s.biometricUnlock, isTrue);
    });

    test('round-trips false through fromJson', () {
      final s = AppSettings.fromJson({'biometric_unlock': false});
      expect(s.biometricUnlock, isFalse);
    });

    test('serialises to toJson', () {
      const s = AppSettings(biometricUnlock: true);
      expect(s.toJson()['biometric_unlock'], isTrue);
    });

    test('copyWith overrides biometricUnlock only', () {
      const original = AppSettings();
      final updated = original.copyWith(biometricUnlock: true);
      expect(updated.biometricUnlock, isTrue);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });

    test('missing key falls back to false', () {
      final s = AppSettings.fromJson({'theme': 'dark'});
      expect(s.biometricUnlock, isFalse);
    });
  });

  // ── BackgroundLockTimeout ─────────────────────────────────────────────────

  group('BackgroundLockTimeout', () {
    test('all values round-trip through fromJson', () {
      for (final choice in BackgroundLockTimeout.values) {
        final s = AppSettings.fromJson({'background_lock_timeout': choice.name});
        expect(s.backgroundLockTimeout, choice);
      }
    });

    test('defaults to fiveMinutes', () {
      final s = AppSettings.fromJson({});
      expect(s.backgroundLockTimeout, BackgroundLockTimeout.fiveMinutes);
    });

    test('copyWith overrides backgroundLockTimeout only', () {
      const original = AppSettings();
      final updated = original.copyWith(
        backgroundLockTimeout: BackgroundLockTimeout.never,
      );
      expect(updated.backgroundLockTimeout, BackgroundLockTimeout.never);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });

    test('serialises to toJson', () {
      const s = AppSettings(
        backgroundLockTimeout: BackgroundLockTimeout.fifteenMinutes,
      );
      expect(s.toJson()['background_lock_timeout'], 'fifteenMinutes');
    });
  });
}