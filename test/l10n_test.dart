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
    bool isEndonymKey(String key) =>
        key.startsWith('lang') &&
        key.length > 4 &&
        key[4] == key[4].toUpperCase() &&
        key[4] != key[4].toLowerCase() && // 4th char is an A-Z style letter
        key != 'langSystem';

    Map<String, String> readArb(File f) {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final e in json.entries)
          if (e.value is String) e.key: e.value as String,
      };
    }

    final l10nDir = Directory('lib/l10n');
    final base = readArb(File('lib/l10n/app_en.arb'));
    final endonymKeys = base.keys.where(isEndonymKey).toList()..sort();

    test('base ARB exposes language labels to check', () {
      // Sanity: if this ever hits zero the matcher above has silently broken and
      // the per-locale checks below would vacuously pass.
      expect(endonymKeys, isNotEmpty);
      expect(endonymKeys, contains('langDutch'));
      expect(endonymKeys, isNot(contains('langSystem')));
    });

    final arbFiles = l10nDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final f in arbFiles) {
      final name = f.uri.pathSegments.last;
      test('$name uses endonyms for all language labels', () {
        final values = readArb(f);
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

    testWidgets('stored 8.0 clamps to device max 3.5 on a phone-sized surface',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildWithScale(8.0));
      await tester.pump();
      expect(find.text('3.50'), findsOneWidget);
    });
  });
}
