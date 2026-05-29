import 'package:flutter/material.dart';
import 'package:gabbro/l10n/app_localizations.dart';

/// Wraps [home] in a MaterialApp configured with the app's localizations.
/// Use this in place of a bare MaterialApp in widget tests.
Widget testApp(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);
