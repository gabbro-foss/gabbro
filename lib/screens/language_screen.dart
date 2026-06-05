import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';

/// Returns the display label for [v] in the current UI language.
///
/// Single source of truth for language names — update here when adding new
/// [LanguageChoice] values and both the settings screen and onboarding picker
/// pick up the change automatically.
String languageChoiceLabel(LanguageChoice v, AppLocalizations l) => switch (v) {
      LanguageChoice.system => l.langSystem,
      LanguageChoice.en => l.langEnglish,
      LanguageChoice.fr => l.langFrench,
      LanguageChoice.de => l.langGerman,
      LanguageChoice.it => l.langItalian,
      LanguageChoice.es => l.langSpanish,
    };

/// Returns [LanguageChoice.values] sorted for display: [LanguageChoice.system]
/// first, then the rest alphabetically by their localized label.
List<LanguageChoice> sortedLanguageChoices(AppLocalizations l) {
  return LanguageChoice.values.toList()
    ..sort((a, b) {
      if (a == LanguageChoice.system) return -1;
      if (b == LanguageChoice.system) return 1;
      return languageChoiceLabel(a, l).compareTo(languageChoiceLabel(b, l));
    });
}

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = GabbroApp.of(context);
    final current = app.settings.language;

    return Scaffold(
      appBar: AppBar(title: Text(l.sectionLanguage)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                l.languageNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: RadioGroup<LanguageChoice>(
                groupValue: current,
                onChanged: (v) {
                  if (v == null) return;
                  app.updateSettings(app.settings.copyWith(language: v));
                },
                child: ListView(
                  children: [
                    for (final lang in sortedLanguageChoices(l))
                      RadioListTile<LanguageChoice>(
                        title: Text(languageChoiceLabel(lang, l)),
                        value: lang,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
