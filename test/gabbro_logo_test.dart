import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/gabbro_contrast.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';

Widget _wrap(
  Widget child, {
  bool dark = false,
  bool highContrast = false,
}) =>
    MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(highContrast: highContrast),
          child: child,
        ),
      ),
    );

Finder _findAsset(String path) => find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == path,
    );

void main() {
  // The name is drawn by the app, not baked into the artwork: the artist's
  // logo has no wordmark, and app text stays sharp at every text size.
  group('GabbroLogo.assetPath - green mark, hc mark per theme', () {
    test('light -> green mark', () {
      expect(
        GabbroLogo.assetPath(dark: false, highContrast: false),
        'assets/images/logo_192.png',
      );
    });

    test('dark -> green mark', () {
      expect(
        GabbroLogo.assetPath(dark: true, highContrast: false),
        'assets/images/logo_192.png',
      );
    });

    test('hc light', () {
      expect(
        GabbroLogo.assetPath(dark: false, highContrast: true),
        'assets/images/logo_hc_light_192.png',
      );
    });

    test('hc dark', () {
      expect(
        GabbroLogo.assetPath(dark: true, highContrast: true),
        'assets/images/logo_hc_dark_192.png',
      );
    });
  });

  group('logo asset files', () {
    test('every themed mark exists', () {
      for (final dark in [false, true]) {
        for (final hc in [false, true]) {
          final p = GabbroLogo.assetPath(dark: dark, highContrast: hc);
          expect(File(p).existsSync(), isTrue, reason: p);
        }
      }
    });

    test('the old per-theme non-hc marks are gone', () {
      for (final b in ['light', 'dark']) {
        final p = 'assets/images/logo_${b}_192.png';
        expect(File(p).existsSync(), isFalse, reason: p);
      }
    });

    test('the old baked-wordmark images are gone', () {
      expect(
        Directory('assets/images')
            .listSync()
            .where((e) => e.path.contains('_with_text_')),
        isEmpty,
      );
    });
  });

  group('GabbroLogo widget rendering', () {
    testWidgets('light theme -> green mark, no name', (tester) async {
      await tester.pumpWidget(_wrap(const GabbroLogo()));
      expect(_findAsset('assets/images/logo_192.png'), findsOneWidget);
      expect(find.text('gabbro'), findsNothing);
    });

    testWidgets('dark theme -> green mark', (tester) async {
      await tester.pumpWidget(_wrap(const GabbroLogo(), dark: true));
      expect(_findAsset('assets/images/logo_192.png'), findsOneWidget);
    });

    testWidgets('hc light -> hc light mark', (tester) async {
      await tester.pumpWidget(
        _wrap(const GabbroLogo(), highContrast: true),
      );
      expect(_findAsset('assets/images/logo_hc_light_192.png'), findsOneWidget);
    });

    testWidgets('hc dark -> hc dark mark', (tester) async {
      await tester.pumpWidget(
        _wrap(const GabbroLogo(), dark: true, highContrast: true),
      );
      expect(_findAsset('assets/images/logo_hc_dark_192.png'), findsOneWidget);
    });

    testWidgets("the app's own high-contrast setting picks the hc mark",
        (tester) async {
      // Gabbro's setting reaches widgets via the theme (GabbroContrast), not
      // the OS accessibility flag; the logo once read only the latter.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [GabbroContrast(highContrast: true)],
          ),
          home: const Scaffold(body: GabbroLogo()),
        ),
      );
      expect(_findAsset('assets/images/logo_hc_dark_192.png'), findsOneWidget);
    });

    testWidgets('with text -> themed mark plus the name as app text',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const GabbroLogo(withText: true), dark: true, highContrast: true),
      );
      expect(_findAsset('assets/images/logo_hc_dark_192.png'), findsOneWidget);
      expect(find.text('gabbro'), findsOneWidget);
    });

    testWidgets('with text keeps the total width it is given', (tester) async {
      await tester.pumpWidget(
        _wrap(const Center(child: GabbroLogo(withText: true, width: 200))),
      );
      expect(tester.getSize(find.byType(GabbroLogo)).width, 200);
    });
  });
}
