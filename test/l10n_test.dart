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
}
