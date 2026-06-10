import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';

void main() {
  // Guards against a half-wired language: if a LanguageChoice maps (via
  // localeFor) to a Locale that is not actually backed by an ARB — i.e. not in
  // AppLocalizations.supportedLocales — MaterialApp silently resolves it to the
  // English fallback, so the user picks e.g. "Polski" and gets English with no
  // error. Asserting exact membership catches that at test time.
  group('localeFor resolves to a supported locale', () {
    final supported = AppLocalizations.supportedLocales.toSet();

    test('every non-system LanguageChoice maps to a supported locale', () {
      for (final choice in LanguageChoice.values) {
        if (choice == LanguageChoice.system) continue;
        expect(
          supported,
          contains(localeFor(choice)),
          reason: '$choice maps to ${localeFor(choice)}, which is not in '
              'AppLocalizations.supportedLocales -> would silently fall back to '
              'English. Add the ARB / fix the mapping.',
        );
      }
    });

    test('guard covers every non-system choice', () {
      final checked = LanguageChoice.values
          .where((c) => c != LanguageChoice.system)
          .length;
      expect(checked, LanguageChoice.values.length - 1);
    });
  });
}
