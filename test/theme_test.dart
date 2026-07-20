import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';

void main() {
  group('gabbroLightTheme', () {
    test('normal mode uses seed colour', () {
      final theme = gabbroLightTheme(highContrast: false);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('high-contrast primary is pure black', () {
      final theme = gabbroLightTheme(highContrast: true);
      expect(theme.colorScheme.primary, const Color(0xFF000000));
    });

    test('high-contrast surface is pure white', () {
      final theme = gabbroLightTheme(highContrast: true);
      expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
    });

    test('high-contrast error meets WCAG 1.4.6 on white', () {
      final theme = gabbroLightTheme(highContrast: true);
      // #7A0000 on #FFFFFF ≈ 8.2:1 — passes AAA
      expect(theme.colorScheme.error, const Color(0xFF7A0000));
    });
  });

  group('gabbroDarkTheme', () {
    test('normal mode uses seed colour', () {
      final theme = gabbroDarkTheme(highContrast: false);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('high-contrast primary is pure white', () {
      final theme = gabbroDarkTheme(highContrast: true);
      expect(theme.colorScheme.primary, const Color(0xFFFFFFFF));
    });

    test('high-contrast surface is pure black', () {
      final theme = gabbroDarkTheme(highContrast: true);
      expect(theme.colorScheme.surface, const Color(0xFF000000));
    });

    test('high-contrast error meets WCAG 1.4.6 on black', () {
      final theme = gabbroDarkTheme(highContrast: true);
      // #FF9999 on #000000 ≈ 7.3:1 — passes AAA
      expect(theme.colorScheme.error, const Color(0xFFFF9999));
    });
  });

  // In high contrast every container / variant role collapses to the
  // surface / onSurface pair, so no screen can render mid-tone text on a
  // mid-tone container. Left unset, these roles fall back to Material's
  // non-HC defaults (review_changes rendered 1.74:1 that way).
  group('high-contrast collapses container/variant roles', () {
    test('dark: on-container + variant text roles are pure white', () {
      final cs = gabbroDarkTheme(highContrast: true).colorScheme;
      expect(cs.onErrorContainer, const Color(0xFFFFFFFF));
      expect(cs.onPrimaryContainer, const Color(0xFFFFFFFF));
      expect(cs.onSurfaceVariant, const Color(0xFFFFFFFF));
    });

    test('dark: container backgrounds are pure black', () {
      final cs = gabbroDarkTheme(highContrast: true).colorScheme;
      expect(cs.errorContainer, const Color(0xFF000000));
      expect(cs.primaryContainer, const Color(0xFF000000));
    });

    test('light: on-container + variant text roles are pure black', () {
      final cs = gabbroLightTheme(highContrast: true).colorScheme;
      expect(cs.onErrorContainer, const Color(0xFF000000));
      expect(cs.onPrimaryContainer, const Color(0xFF000000));
      expect(cs.onSurfaceVariant, const Color(0xFF000000));
    });

    test('light: container backgrounds are pure white', () {
      final cs = gabbroLightTheme(highContrast: true).colorScheme;
      expect(cs.errorContainer, const Color(0xFFFFFFFF));
      expect(cs.primaryContainer, const Color(0xFFFFFFFF));
    });
  });
}