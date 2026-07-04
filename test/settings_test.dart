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
        'text_scale': 1.15,
        'high_contrast': true,
      });
      expect(s.theme, ThemeChoice.dark);
      expect(s.textScale, 1.15);
      expect(s.highContrast, isTrue);
    });

    test('falls back to defaults for missing keys', () {
      final s = AppSettings.fromJson({});
      expect(s.theme, ThemeChoice.system);
      expect(s.textScale, 1.0);
      expect(s.highContrast, isFalse);
    });

    test('all ThemeChoice values round-trip', () {
      for (final choice in ThemeChoice.values) {
        final s = AppSettings.fromJson({'theme': choice.name});
        expect(s.theme, choice);
      }
    });
  });

  // ── toJson ────────────────────────────────────────────────────────────────

  group('AppSettings.toJson', () {
    test('serialises all fields', () {
      const s = AppSettings(
        theme: ThemeChoice.light,
        textScale: 0.85,
        highContrast: false,
      );
      final json = s.toJson();
      expect(json['theme'], 'light');
      expect(json['text_scale'], 0.85);
      expect(json['high_contrast'], isFalse);
    });

    test('round-trips through fromJson', () {
      const original = AppSettings(
        theme: ThemeChoice.dark,
        textScale: 1.3,
        highContrast: false,
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.theme, original.theme);
      expect(restored.textScale, original.textScale);
      expect(restored.highContrast, original.highContrast);
    });

    test('androidExportFolderUri round-trips and defaults to empty', () {
      expect(AppSettings.fromJson({}).androidExportFolderUri, '');
      const original = AppSettings(
        androidExportFolderUri:
            'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FGabbroSync',
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.androidExportFolderUri, original.androidExportFolderUri);
    });
  });

  // ── copyWith ──────────────────────────────────────────────────────────────

  group('AppSettings.copyWith', () {
    test('overrides only the specified field', () {
      const original = AppSettings();
      final updated = original.copyWith(theme: ThemeChoice.dark);
      expect(updated.theme, ThemeChoice.dark);
      expect(updated.textScale, original.textScale);
      expect(updated.highContrast, original.highContrast);
    });

    test('leaving all params null returns equivalent settings', () {
      const original = AppSettings(
        theme: ThemeChoice.light,
        textScale: 1.15,
      );
      final copy = original.copyWith();
      expect(copy.theme, original.theme);
      expect(copy.textScale, original.textScale);
    });

    test('overrides highContrast only', () {
      const original = AppSettings();
      final updated = original.copyWith(highContrast: true);
      expect(updated.highContrast, isTrue);
      expect(updated.theme, original.theme);
      expect(updated.textScale, original.textScale);
    });

    test('round-trips highContrast true through fromJson', () {
      const original = AppSettings(
        theme: ThemeChoice.dark,
        textScale: 1.3,
        highContrast: true,
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.highContrast, isTrue);
      expect(restored.theme, original.theme);
      expect(restored.textScale, original.textScale);
    });
  });

  // ── defaults ─────────────────────────────────────────────────────────────

  test('defaults are system theme, normal text scale, no high contrast', () {
    final d = AppSettings.defaults;
    expect(d.theme, ThemeChoice.system);
    expect(d.textScale, 1.0);
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

  // ── show_vault_list removed (ADR-014) ─────────────────────────────────────

  group('show_vault_list removed (ADR-014)', () {
    test('toJson no longer emits show_vault_list', () {
      expect(
        const AppSettings().toJson().containsKey('show_vault_list'),
        isFalse,
      );
    });

    // Backward-compat: a settings.jsonc written by an older build carries
    // show_vault_list (ON or OFF). Loading it must not throw; the key is
    // ignored and never re-serialised.
    test('fromJson ignores a legacy show_vault_list = true', () {
      final s = AppSettings.fromJson({'show_vault_list': true});
      expect(s.toJson().containsKey('show_vault_list'), isFalse);
    });

    test('fromJson ignores a legacy show_vault_list = false', () {
      final s = AppSettings.fromJson({'show_vault_list': false});
      expect(s.toJson().containsKey('show_vault_list'), isFalse);
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

  // ── tabletListPaneWidth ───────────────────────────────────────────────────

  group('tabletListPaneWidth', () {
    test('defaults to 260.0', () {
      final s = AppSettings.fromJson({});
      expect(s.tabletListPaneWidth, 260.0);
    });

    test('round-trips 320.0 through fromJson', () {
      final s = AppSettings.fromJson({'tablet_list_pane_width': 320.0});
      expect(s.tabletListPaneWidth, 320.0);
    });

    test('accepts integer value from JSON', () {
      final s = AppSettings.fromJson({'tablet_list_pane_width': 350});
      expect(s.tabletListPaneWidth, 350.0);
    });

    test('clamps below 180 to 180', () {
      final s = AppSettings.fromJson({'tablet_list_pane_width': 50.0});
      expect(s.tabletListPaneWidth, 180.0);
    });

    test('clamps above 900 to 900', () {
      final s = AppSettings.fromJson({'tablet_list_pane_width': 1200.0});
      expect(s.tabletListPaneWidth, 900.0);
    });

    test('serialises to toJson', () {
      const s = AppSettings(tabletListPaneWidth: 380.0);
      expect(s.toJson()['tablet_list_pane_width'], 380.0);
    });

    test('copyWith overrides tabletListPaneWidth only', () {
      const original = AppSettings();
      final updated = original.copyWith(tabletListPaneWidth: 400.0);
      expect(updated.tabletListPaneWidth, 400.0);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });
  });

  // ── textScale (ADR-016) ───────────────────────────────────────────────────

  group('textScale', () {
    test('A1 numeric text_scale round-trips through fromJson', () {
      final s = AppSettings.fromJson({'text_scale': 2.5});
      expect(s.textScale, 2.5);
    });

    test('A1 toJson round-trips textScale', () {
      const original = AppSettings(textScale: 3.25);
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.textScale, 3.25);
    });

    test('A2 legacy text_size words migrate to numeric scale', () {
      const cases = {
        'small': 0.85,
        'regular': 1.0,
        'large': 1.15,
        'extraLarge': 1.3,
        'xxLarge': 1.5,
      };
      cases.forEach((word, scale) {
        final s = AppSettings.fromJson({'text_size': word});
        expect(s.textScale, scale, reason: 'text_size=$word');
      });
    });

    test('A2 legacy extra_large underscore form migrates', () {
      final s = AppSettings.fromJson({'text_size': 'extra_large'});
      expect(s.textScale, 1.3);
    });

    test('A3 when both keys present, numeric text_scale wins', () {
      final s = AppSettings.fromJson({'text_scale': 2.0, 'text_size': 'small'});
      expect(s.textScale, 2.0);
    });

    test('A4 neither key defaults to 1.0', () {
      final s = AppSettings.fromJson({'theme': 'dark'});
      expect(s.textScale, 1.0);
    });

    test('A5 out-of-range clamps to [0.8, 8.0]', () {
      expect(AppSettings.fromJson({'text_scale': 99.0}).textScale, 8.0);
      expect(AppSettings.fromJson({'text_scale': 0.1}).textScale, 0.8);
    });

    test('A5 integer JSON value accepted', () {
      final s = AppSettings.fromJson({'text_scale': 3});
      expect(s.textScale, 3.0);
    });

    test('A6 toJson emits numeric text_scale and no text_size key', () {
      final json = const AppSettings(textScale: 2.0).toJson();
      expect(json['text_scale'], 2.0);
      expect(json.containsKey('text_size'), isFalse);
    });

    test('copyWith overrides textScale only', () {
      const original = AppSettings();
      final updated = original.copyWith(textScale: 4.0);
      expect(updated.textScale, 4.0);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
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