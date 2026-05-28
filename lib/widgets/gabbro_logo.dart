import 'package:flutter/material.dart';

class GabbroLogo extends StatelessWidget {
  final bool withText;
  final double? width;

  const GabbroLogo({super.key, this.withText = false, this.width});

  static String assetPath({
    required bool dark,
    required bool highContrast,
    required bool withText,
  }) {
    final hc = highContrast ? 'hc_' : '';
    final brightness = dark ? 'dark' : 'light';
    final text = withText ? '_with_text' : '';
    return 'assets/images/logo_$hc$brightness${text}_192.png';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hc = MediaQuery.of(context).highContrast;
    return Image.asset(
      assetPath(dark: dark, highContrast: hc, withText: withText),
      width: width,
    );
  }
}
