import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/text_scale.dart';

void main() {
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

    // S5: the sync settings. Absent keys keep the old file loading, so an
    // upgraded install never loses its other settings.
    test('autoMergeSync defaults to false and round-trips', () {
      expect(AppSettings.fromJson({}).autoMergeSync, isFalse);
      expect(AppSettings.defaults.autoMergeSync, isFalse);
      const on = AppSettings(autoMergeSync: true);
      expect(on.toJson()['auto_merge_sync'], isTrue);
      expect(AppSettings.fromJson(on.toJson()).autoMergeSync, isTrue);
      expect(AppSettings.fromJson({'auto_merge_sync': true}).autoMergeSync, isTrue);
    });

    test('syncFolder defaults to empty and round-trips', () {
      expect(AppSettings.fromJson({}).syncFolder, '');
      const linux = AppSettings(syncFolder: '/home/user/GabbroSync');
      expect(AppSettings.fromJson(linux.toJson()).syncFolder, linux.syncFolder);
      const android = AppSettings(
        syncFolder:
            'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FGabbroSync',
      );
      expect(AppSettings.fromJson(android.toJson()).syncFolder, android.syncFolder);
      expect(android.toJson()['sync_folder'], android.syncFolder);
    });

    test('the sync settings survive the jsonc writer', () {
      const s = AppSettings(autoMergeSync: true, syncFolder: '/tmp/Gabbro "Sync"');
      final stripped = AppSettings.stripCommentsForTest(s.toJsoncForTest());
      final back = AppSettings.fromJson(jsonDecode(stripped) as Map<String, dynamic>);
      expect(back.autoMergeSync, isTrue);
      expect(back.syncFolder, '/tmp/Gabbro "Sync"');
    });

    test('copyWith overrides autoMergeSync and syncFolder only', () {
      const base = AppSettings(theme: ThemeChoice.dark);
      final a = base.copyWith(autoMergeSync: true);
      expect(a.autoMergeSync, isTrue);
      expect(a.syncFolder, '');
      expect(a.theme, ThemeChoice.dark);
      final b = base.copyWith(syncFolder: '/x');
      expect(b.syncFolder, '/x');
      expect(b.autoMergeSync, isFalse);
    });

    // R1: one remembered folder per screen, Linux path or Android tree URI.
    test('exportFolder and importFolder default to empty and round-trip', () {
      expect(AppSettings.fromJson({}).exportFolder, '');
      expect(AppSettings.fromJson({}).importFolder, '');
      const s = AppSettings(
        exportFolder: '/home/user/GabbroSync',
        importFolder: 'content://docs/document/primary%3ADownload%2Fx.json',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.exportFolder, s.exportFolder);
      expect(back.importFolder, s.importFolder);
      expect(s.toJson()['export_folder'], s.exportFolder);
      expect(s.toJson()['import_folder'], s.importFolder);
    });

    test('an old android_export_folder_uri is read into exportFolder', () {
      const old = 'content://docs/tree/primary%3ADownload%2FGabbroSync';
      expect(AppSettings.fromJson({'android_export_folder_uri': old}).exportFolder,
          old);
      // The new key wins when both are present.
      expect(
        AppSettings.fromJson(
            {'android_export_folder_uri': old, 'export_folder': '/new'}).exportFolder,
        '/new',
      );
      // Not written any more.
      expect(AppSettings.defaults.toJson().containsKey('android_export_folder_uri'),
          isFalse);
    });

    test('the folders survive the jsonc writer', () {
      const s = AppSettings(exportFolder: '/tmp/a "b"', importFolder: '/tmp/c');
      final stripped = AppSettings.stripCommentsForTest(s.toJsoncForTest());
      final back = AppSettings.fromJson(jsonDecode(stripped) as Map<String, dynamic>);
      expect(back.exportFolder, '/tmp/a "b"');
      expect(back.importFolder, '/tmp/c');
    });
  });

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

  test('defaults are system theme, normal text scale, no high contrast', () {
    final d = AppSettings.defaults;
    expect(d.theme, ThemeChoice.system);
    expect(d.textScale, 1.0);
    expect(d.highContrast, isFalse);
  });

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

  group('passkeyHintDismissed', () {
    // "Don't show again" on the passkey banner; without persistence a
    // tarball user who skipped the uhid setup is nagged on every launch.
    test('defaults to false', () {
      final s = AppSettings.fromJson({});
      expect(s.passkeyHintDismissed, isFalse);
    });

    test('round-trips true through fromJson', () {
      final s = AppSettings.fromJson({'passkey_hint_dismissed': true});
      expect(s.passkeyHintDismissed, isTrue);
    });

    test('serialises to toJson', () {
      const s = AppSettings(passkeyHintDismissed: true);
      expect(s.toJson()['passkey_hint_dismissed'], isTrue);
    });

    test('survives the generated jsonc', () {
      const s = AppSettings(passkeyHintDismissed: true);
      final stripped = AppSettings.stripCommentsForTest(s.toJsoncForTest());
      final reloaded = AppSettings.fromJson(
        jsonDecode(stripped) as Map<String, dynamic>,
      );
      expect(reloaded.passkeyHintDismissed, isTrue);
    });

    test('copyWith overrides passkeyHintDismissed only', () {
      const original = AppSettings();
      final updated = original.copyWith(passkeyHintDismissed: true);
      expect(updated.passkeyHintDismissed, isTrue);
      expect(updated.theme, original.theme);
      expect(updated.blockPassphraseCopyPaste, original.blockPassphraseCopyPaste);
    });
  });

  group('appPasskeys', () {
    // Informed opt-in for native-app passkeys (F1): Android grants INTERNET
    // silently, so this in-app toggle is the only ask the user ever gets.
    test('defaults to false', () {
      final s = AppSettings.fromJson({});
      expect(s.appPasskeys, isFalse);
    });

    test('round-trips true through fromJson', () {
      final s = AppSettings.fromJson({'app_passkeys': true});
      expect(s.appPasskeys, isTrue);
    });

    test('serialises to toJson', () {
      const s = AppSettings(appPasskeys: true);
      expect(s.toJson()['app_passkeys'], isTrue);
    });

    test('survives the generated jsonc', () {
      const s = AppSettings(appPasskeys: true);
      final stripped = AppSettings.stripCommentsForTest(s.toJsoncForTest());
      final reloaded = AppSettings.fromJson(
        jsonDecode(stripped) as Map<String, dynamic>,
      );
      expect(reloaded.appPasskeys, isTrue);
    });

    test('copyWith overrides appPasskeys only', () {
      const original = AppSettings();
      final updated = original.copyWith(appPasskeys: true);
      expect(updated.appPasskeys, isTrue);
      expect(updated.theme, original.theme);
      expect(updated.passkeyHintDismissed, original.passkeyHintDismissed);
    });
  });

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

  // Biometric is per-vault + device-local (AndroidKeyStore, not settings) - no
  // global settings flag. See BiometricStore / unlock_screen tests.

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

  group('textScale', () {
    test('A1 numeric text_scale round-trips through fromJson', () {
      final s = AppSettings.fromJson({'text_scale': 2.5});
      expect(s.textScale, 2.5);
    });

    test('A1 toJson round-trips textScale', () {
      const original = AppSettings(textScale: 2.25);
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.textScale, 2.25);
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

    test('A5 out-of-range clamps to [0.8, 3.0]', () {
      expect(AppSettings.fromJson({'text_scale': 99.0}).textScale, 3.0);
      expect(AppSettings.fromJson({'text_scale': 0.1}).textScale, 0.8);
    });

    test('A5 stored 8.0 from the old ceiling loads as 3.0', () {
      expect(AppSettings.fromJson({'text_scale': 8.0}).textScale, 3.0);
    });

    test('A5 in-range values survive', () {
      expect(AppSettings.fromJson({'text_scale': 3.0}).textScale, 3.0);
    });

    test('A5 storage ceiling equals the tablet render ceiling', () {
      expect(AppSettings.maxTextScale, kTabletMaxScale);
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
      final updated = original.copyWith(textScale: 2.5);
      expect(updated.textScale, 2.5);
      expect(updated.theme, original.theme);
      expect(updated.foregroundLockTimeout, original.foregroundLockTimeout);
    });
  });

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