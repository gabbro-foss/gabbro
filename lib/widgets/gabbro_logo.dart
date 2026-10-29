import 'package:flutter/material.dart';
import 'package:gabbro/gabbro_contrast.dart';

class GabbroLogo extends StatelessWidget {
  final bool withText;
  final double? width;

  const GabbroLogo({super.key, this.withText = false, this.width});

  /// The mark's share of [width] when the name is drawn below it.
  static const _markShareWithText = 0.55;

  /// Green mark in both themes; high contrast is pure black or white.
  static String assetPath({required bool dark, required bool highContrast}) {
    if (!highContrast) return 'assets/images/logo_192.png';
    return 'assets/images/logo_hc_${dark ? 'dark' : 'light'}_192.png';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // App setting (via the theme) or the OS accessibility flag.
    final hc =
        GabbroContrast.of(context) || MediaQuery.of(context).highContrast;
    final path = assetPath(dark: dark, highContrast: hc);
    if (!withText) return Image.asset(path, width: width);

    // The artwork has no wordmark (by design): the app draws the name.
    final w = width;
    return SizedBox(
      width: w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(path, width: w == null ? null : w * _markShareWithText),
          const SizedBox(height: 8),
          Text(
            'gabbro',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
