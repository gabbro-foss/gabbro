import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/language_screen.dart';
import 'package:gabbro/vault_registry.dart';

Widget _buildScreen({AppSettings settings = const AppSettings()}) => GabbroApp(
      registry: VaultRegistry([]),
      vaultPath: null,
      settings: settings,
      initialScreen: const LanguageScreen(),
    );

void main() {
  group('LanguageScreen', () {
    testWidgets('renders Language title', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Language'), findsOneWidget);
    });

    testWidgets('shows all language options', (tester) async {
      await tester.pumpWidget(_buildScreen());
      // System is always first.
      expect(find.text('System'), findsOneWidget);
      // The list is lazy and scrollable. Verify items near the top of the
      // alphabetical sort (Dansk, Deutsch, English) which are always in the
      // initial viewport. Set completeness is asserted by the
      // sortedLanguageChoices invariants below, not a magic count here.
      expect(find.text('Dansk'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('current language radio is selected', (tester) async {
      await tester.pumpWidget(
        _buildScreen(settings: const AppSettings(language: LanguageChoice.fr)),
      );
      final group = tester.widget<RadioGroup<LanguageChoice>>(
        find.byType(RadioGroup<LanguageChoice>),
      );
      expect(group.groupValue, LanguageChoice.fr);
    });
  });

  // Pure-function invariants on the picker's label/sort helpers. These guard the
  // picker against silent breakage as languages and locales are added — a blank
  // or duplicated label means an ambiguous/unusable row, and a sort that drops a
  // choice means a language the user can never select. Auto-covers future
  // LanguageChoice values; replaces the old `values.length == 35` magic number.
  group('languageChoiceLabel', () {
    test('every choice has a non-empty label in every locale', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = lookupAppLocalizations(locale);
        for (final choice in LanguageChoice.values) {
          expect(
            languageChoiceLabel(choice, l),
            isNotEmpty,
            reason: 'empty label for $choice in ${locale.toLanguageTag()}',
          );
        }
      }
    });

    test('labels are unique within every locale', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = lookupAppLocalizations(locale);
        final labels =
            LanguageChoice.values.map((c) => languageChoiceLabel(c, l)).toList();
        expect(
          labels.toSet().length,
          labels.length,
          reason: 'duplicate language label in ${locale.toLanguageTag()}: '
              '${_duplicates(labels)}',
        );
      }
    });
  });

  group('sortedLanguageChoices', () {
    final l = lookupAppLocalizations(const Locale('en'));

    test('returns exactly the full LanguageChoice set', () {
      expect(
        sortedLanguageChoices(l).toSet(),
        LanguageChoice.values.toSet(),
      );
    });

    test('places system first', () {
      expect(sortedLanguageChoices(l).first, LanguageChoice.system);
    });

    test('orders the remainder alphabetically by label', () {
      final rest = sortedLanguageChoices(l).skip(1).toList();
      final labels = rest.map((c) => languageChoiceLabel(c, l)).toList();
      final sorted = [...labels]..sort();
      expect(labels, sorted);
    });
  });
}

/// The labels that appear more than once, for a readable failure message.
List<String> _duplicates(List<String> labels) {
  final seen = <String>{};
  final dups = <String>{};
  for (final label in labels) {
    if (!seen.add(label)) dups.add(label);
  }
  return dups.toList();
}
