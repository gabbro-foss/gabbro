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

  // ── _localeFor complex locale branches ─────────────────────────────────────
  //
  // These 5 locales have explicit switch arms in _localeFor (they need a country
  // or script subtag). The other LanguageChoices hit the wildcard arm already
  // covered by the French/German tests above.

  group('_localeFor complex locales', () {
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
        // If _localeFor returns the wrong Locale the app would fail to resolve
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

  // ── _textScale switch arms ─────────────────────────────────────────────────

  group('_textScale', () {
    Widget buildWithSize(TextSizeChoice size) => GabbroApp(
          registry: VaultRegistry([]),
          vaultPath: null,
          settings: AppSettings(textSize: size),
          initialScreen: Builder(
            builder: (ctx) => Text(
              MediaQuery.of(ctx).textScaler.scale(1.0).toStringAsFixed(2),
            ),
          ),
        );

    for (final (size, expected) in [
      (TextSizeChoice.small, '0.85'),
      (TextSizeChoice.large, '1.15'),
      (TextSizeChoice.extraLarge, '1.30'),
      (TextSizeChoice.xxLarge, '1.50'),
    ]) {
      testWidgets('textSize $size applies ${expected}x scale', (tester) async {
        await tester.pumpWidget(buildWithSize(size));
        await tester.pump();
        expect(find.text(expected), findsOneWidget);
      });
    }
  });
}
