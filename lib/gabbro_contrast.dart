import 'package:flutter/material.dart';

/// Carries the high-contrast flag on the active [ThemeData], so any widget can
/// ask whether it is rendering in high-contrast mode without threading a bool
/// through every screen. Attached by the app's theme builders (see main.dart).
@immutable
class GabbroContrast extends ThemeExtension<GabbroContrast> {
  final bool highContrast;

  const GabbroContrast({required this.highContrast});

  /// True when the active theme is high-contrast. Defaults to false when the
  /// extension is absent (e.g. a bare MaterialApp in a widget test).
  static bool of(BuildContext context) =>
      Theme.of(context).extension<GabbroContrast>()?.highContrast ?? false;

  @override
  GabbroContrast copyWith({bool? highContrast}) =>
      GabbroContrast(highContrast: highContrast ?? this.highContrast);

  // Discrete flag: no meaningful interpolation, so snap rather than blend.
  @override
  GabbroContrast lerp(GabbroContrast? other, double t) => this;
}
