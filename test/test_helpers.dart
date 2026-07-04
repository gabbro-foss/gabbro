import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';

/// Wraps [home] in a MaterialApp configured with the app's localizations.
/// Use this in place of a bare MaterialApp in widget tests.
Widget testApp(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// Finds every reveal-eye (show/hide) [IconButton] on screen — those whose icon
/// is `Icons.visibility` or `Icons.visibility_off` — regardless of the current
/// obscured/revealed state. Used by the ADR-016 large-text scaling tests to
/// assert each toggle's `iconSize` grows with the text.
Finder revealEyeButtons() => find.byWidgetPredicate(
  (w) =>
      w is IconButton &&
      w.icon is Icon &&
      ((w.icon as Icon).icon == Icons.visibility ||
          (w.icon as Icon).icon == Icons.visibility_off),
);
