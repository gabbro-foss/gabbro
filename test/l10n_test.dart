import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

Widget _buildWithLocale(LanguageChoice lang, Widget screen) => GabbroApp(
  registry: VaultRegistry([]),
  vaultPath: null,
  settings: AppSettings(language: lang),
  initialScreen: screen,
);

/// String entries of an ARB file, dropping `@`-prefixed metadata (`@@locale`,
/// per-key `@description`/`@placeholders`), which are not user-facing strings.
Map<String, String> _readArb(File f) {
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (e.value is String && !e.key.startsWith('@')) e.key: e.value as String,
  };
}

/// A key names a language endonym: `langFrench`, `langDutch`, … but not
/// `langSystem` (which IS localised — "System default" / "Système par défaut").
bool _isEndonymKey(String key) =>
    key.startsWith('lang') &&
    key.length > 4 &&
    key[4] == key[4].toUpperCase() &&
    key[4] != key[4].toLowerCase() &&
    key != 'langSystem';

/// Every `app_*.arb` under lib/l10n, sorted for stable test order.
List<File> _arbFiles() => (Directory('lib/l10n')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.arb'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path)));

void main() {
  group('AppLocalizations', () {
    testWidgets('delegate resolves appName for all supported locales',
        (tester) async {
      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: gabbroLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (ctx) => Text(AppLocalizations.of(ctx).appName),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Gabbro'), findsOneWidget);
      }
    });

    testWidgets('AppearanceScreen title switches to French', (tester) async {
      await tester.pumpWidget(
        _buildWithLocale(LanguageChoice.fr, const AppearanceScreen()),
      );
      await tester.pump();
      expect(find.text('Apparence'), findsOneWidget);
      expect(find.text('Appearance'), findsNothing);
    });

    testWidgets('AppearanceScreen title switches to German', (tester) async {
      await tester.pumpWidget(
        _buildWithLocale(LanguageChoice.de, const AppearanceScreen()),
      );
      await tester.pump();
      expect(find.text('Darstellung'), findsOneWidget);
      expect(find.text('Appearance'), findsNothing);
    });
  });

  // ── Language-label endonym convention ──────────────────────────────────────
  //
  // Language names shown in the language picker are ENDONYMS (the language's own
  // name) and must be identical in every locale's ARB — e.g. langGerman is
  // "Deutsch" and langDutch is "Nederlands" everywhere, never translated into the
  // UI locale's exonym (no "Holland"/"Hollandi"/"Nederländska"). This guards the
  // alpha.6 langDutch fix and catches the same mistake for any future language.
  //
  // The endonym keys match `lang<UpperCase>...`. langSystem ("System default") is
  // a normal translatable string, not an endonym, so it is excluded. languageHeader
  // and languageNote start with lowercase "langu" and never match `lang[A-Z]`.

  group('language-label endonym convention', () {
    final base = _readArb(File('lib/l10n/app_en.arb'));
    final endonymKeys = base.keys.where(_isEndonymKey).toList()..sort();

    test('base ARB exposes language labels to check', () {
      // Sanity: if this ever hits zero the matcher above has silently broken and
      // the per-locale checks below would vacuously pass.
      expect(endonymKeys, isNotEmpty);
      expect(endonymKeys, contains('langDutch'));
      expect(endonymKeys, isNot(contains('langSystem')));
    });

    for (final f in _arbFiles()) {
      final name = f.uri.pathSegments.last;
      test('$name uses endonyms for all language labels', () {
        final values = _readArb(f);
        for (final key in endonymKeys) {
          // A locale may omit an endonym key entirely — gen-l10n then falls back
          // to the (correct) English endonym. Only a present value can be wrong.
          if (!values.containsKey(key)) continue;
          expect(
            values[key],
            base[key],
            reason: '$name overrides $key with "${values[key]}" but the endonym '
                'convention requires "${base[key]}" (same in every locale).',
          );
        }
      });
    }
  });

  group('ARB completeness across locales', () {
    // Behaviour 1: a key missing from one locale means that user silently reads
    // English for that string. Behaviour 2: a key whose message renames or drops
    // a placeholder renders broken. Neither is caught by rendering — these read
    // the ARB files directly.
    final base = _readArb(File('lib/l10n/app_en.arb'));
    final files = _arbFiles();

    // Distinct placeholder names in a message. DISTINCT, not occurrences: a
    // plural repeats its token once per arm, and Slavic locales carry arms
    // English lacks (`few`), so counting occurrences reports false mismatches.
    Set<String> placeholders(String message) => RegExp(r'\{(\w+)\}')
        .allMatches(message)
        .map((m) => m.group(1)!)
        .toSet();

    test('the ARB listing is complete, so the checks are not vacuous', () {
      // A wrong path would return an empty list and pass every per-file loop
      // below while checking nothing (the probe had this exact hole). Adding or
      // removing a language fails HERE first — update the count deliberately.
      expect(
        files.length,
        37,
        reason: 'expected 37 app_*.arb files under lib/l10n; found '
            '${files.length}. Added or removed a locale? Update this count.',
      );
      expect(base.length, greaterThan(500), reason: 'base ARB looks truncated');
    });

    for (final f in files) {
      final name = f.uri.pathSegments.last;
      test('$name has exactly the base key set', () {
        final keys = _readArb(f).keys.toSet();
        expect(
          keys.difference(base.keys.toSet()),
          isEmpty,
          reason: '$name has keys absent from app_en.arb (stale after a rename?)',
        );
        expect(
          base.keys.toSet().difference(keys),
          isEmpty,
          reason: '$name is MISSING keys — that string falls back to English for '
              'this locale.',
        );
      });

      test('$name matches base placeholders on every shared key', () {
        final values = _readArb(f);
        for (final key in base.keys) {
          if (!values.containsKey(key)) continue; // absence is the test above
          expect(
            placeholders(values[key]!),
            placeholders(base[key]!),
            reason: '$name key "$key" changes placeholders from '
                '${placeholders(base[key]!)} — the message will render broken.',
          );
        }
      });
    }
  });

  group('every listed language is present in every locale', () {
    // The in-app language menu lists N languages; each must have its endonym in
    // every ARB file, or a user in locale X sees a blank / English name for
    // language Y in the picker. Pins the COUNT too, so adding a language without
    // its endonym fails here.
    final base = _readArb(File('lib/l10n/app_en.arb'));
    final endonymKeys = base.keys.where(_isEndonymKey).toSet();

    test('the base lists the expected number of languages', () {
      // 34 selectable languages (LanguageChoice minus `system`). langSystem is
      // excluded by _isEndonymKey because it is itself localised.
      expect(
        endonymKeys.length,
        34,
        reason: 'expected 34 language endonyms; found ${endonymKeys.length}. '
            'Added or removed a language? Update this count and the ARB files.',
      );
    });

    for (final f in _arbFiles()) {
      final name = f.uri.pathSegments.last;
      test('$name lists every language', () {
        final keys = _readArb(f).keys.toSet();
        expect(
          endonymKeys.difference(keys),
          isEmpty,
          reason: '$name is missing language endonyms — those languages show '
              'blank or English in the picker for this locale.',
        );
      });
    }
  });

  // ── localeFor complex locale branches ──────────────────────────────────────
  //
  // These 5 locales have explicit switch arms in localeFor (they need a country
  // or script subtag). The other LanguageChoices hit the wildcard arm already
  // covered by the French/German tests above.

  group('localeFor complex locales', () {
    for (final (lang, tag) in [
      (LanguageChoice.ptPt, 'pt-PT'),
      (LanguageChoice.ptBr, 'pt-BR'),
      (LanguageChoice.srLatn, 'sr-Latn'),
      (LanguageChoice.zhCn, 'zh-CN'),
      (LanguageChoice.zhTw, 'zh-TW'),
    ]) {
      testWidgets('GabbroApp renders with $tag locale', (tester) async {
        await tester.pumpWidget(
          _buildWithLocale(lang, const AppearanceScreen()),
        );
        await tester.pump();
        // If localeFor returns the wrong Locale the app would fail to resolve
        // AppLocalizations and throw — reaching this line proves the mapping works.
        expect(find.byType(AppearanceScreen), findsOneWidget);
      });
    }
  });

  // ── _FallbackMaterialLocalizationsDelegate fallback branch ─────────────────
  //
  // Norwegian Nynorsk (nn) and Yoruba (yo) are in LanguageChoice but not in
  // GlobalMaterialLocalizations, so _FallbackMaterialLocalizationsDelegate.load()
  // falls back to English localizations instead of crashing.

  testWidgets(
      '_FallbackMaterialLocalizationsDelegate falls back to English for nn locale',
      (tester) async {
    await tester.pumpWidget(
      _buildWithLocale(LanguageChoice.nn, const AppearanceScreen()),
    );
    await tester.pump();
    // No crash = fallback loaded English MaterialLocalizations successfully.
    expect(find.byType(AppearanceScreen), findsOneWidget);
  });

  // ── textScale applied to MediaQuery (ADR-016) ──────────────────────────────

  group('textScale applied to MediaQuery', () {
    Widget buildWithScale(double scale) => GabbroApp(
          registry: VaultRegistry([]),
          vaultPath: null,
          settings: AppSettings(textScale: scale),
          initialScreen: Builder(
            builder: (ctx) => Text(
              MediaQuery.of(ctx).textScaler.scale(1.0).toStringAsFixed(2),
            ),
          ),
        );

    // Default test surface is 800x600 -> shortestSide 600 -> tablet tier
    // (max 5.0), so these values apply unclamped.
    for (final (scale, expected) in [
      (0.85, '0.85'),
      (1.15, '1.15'),
      (1.30, '1.30'),
      (1.50, '1.50'),
      (2.00, '2.00'),
    ]) {
      testWidgets('textScale $scale applies ${expected}x on tablet-tier surface',
          (tester) async {
        await tester.pumpWidget(buildWithScale(scale));
        await tester.pump();
        expect(find.text(expected), findsOneWidget);
      });
    }

    testWidgets('stored 8.0 clamps to device max 2.0 on a phone-sized surface',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildWithScale(8.0));
      await tester.pump();
      expect(find.text('2.00'), findsOneWidget);
    });
  });
}
