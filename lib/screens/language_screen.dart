import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  String _label(LanguageChoice v, AppLocalizations l) => switch (v) {
        LanguageChoice.system => l.langSystem,
        LanguageChoice.en => l.langEnglish,
        LanguageChoice.fr => l.langFrench,
        LanguageChoice.de => l.langGerman,
        LanguageChoice.it => l.langItalian,
        LanguageChoice.es => l.langSpanish,
      };

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
                    for (final lang in LanguageChoice.values)
                      RadioListTile<LanguageChoice>(
                        title: Text(_label(lang, l)),
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
