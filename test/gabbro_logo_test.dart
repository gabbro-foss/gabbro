import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  group('GabbroLogo.assetPath - all 8 combinations', () {
    test('light icon-only', () {
      expect(
        GabbroLogo.assetPath(dark: false, highContrast: false, withText: false),
        'assets/images/logo_light_192.png',
      );
    });

    test('dark icon-only', () {
      expect(
        GabbroLogo.assetPath(dark: true, highContrast: false, withText: false),
        'assets/images/logo_dark_192.png',
      );
    });

    test('hc light icon-only', () {
      expect(
        GabbroLogo.assetPath(dark: false, highContrast: true, withText: false),
        'assets/images/logo_hc_light_192.png',
      );
    });

    test('hc dark icon-only', () {
      expect(
        GabbroLogo.assetPath(dark: true, highContrast: true, withText: false),
        'assets/images/logo_hc_dark_192.png',
      );
    });

    test('light with text', () {
      expect(
        GabbroLogo.assetPath(dark: false, highContrast: false, withText: true),
        'assets/images/logo_light_with_text_192.png',
      );
    });

    test('dark with text', () {
      expect(
        GabbroLogo.assetPath(dark: true, highContrast: false, withText: true),
        'assets/images/logo_dark_with_text_192.png',
      );
    });

    test('hc light with text', () {
      expect(
        GabbroLogo.assetPath(dark: false, highContrast: true, withText: true),
        'assets/images/logo_hc_light_with_text_192.png',
      );
    });

    test('hc dark with text', () {
      expect(
        GabbroLogo.assetPath(dark: true, highContrast: true, withText: true),
        'assets/images/logo_hc_dark_with_text_192.png',
      );
    });
  });

  group('GabbroLogo widget rendering', () {
    testWidgets('light theme -> light icon asset', (tester) async {
      await tester.pumpWidget(_wrap(const GabbroLogo()));
      expect(_findAsset('assets/images/logo_light_192.png'), findsOneWidget);
    });

    testWidgets('dark theme -> dark icon asset', (tester) async {
      await tester.pumpWidget(_wrap(const GabbroLogo(), dark: true));
      expect(_findAsset('assets/images/logo_dark_192.png'), findsOneWidget);
    });

    testWidgets('hc light -> hc light icon asset', (tester) async {
      await tester.pumpWidget(
        _wrap(const GabbroLogo(), highContrast: true),
      );
      expect(_findAsset('assets/images/logo_hc_light_192.png'), findsOneWidget);
    });

    testWidgets('hc dark -> hc dark icon asset', (tester) async {
      await tester.pumpWidget(
        _wrap(const GabbroLogo(), dark: true, highContrast: true),
      );
      expect(_findAsset('assets/images/logo_hc_dark_192.png'), findsOneWidget);
    });

    testWidgets('light with text -> light with-text asset', (tester) async {
      await tester.pumpWidget(_wrap(const GabbroLogo(withText: true)));
      expect(
        _findAsset('assets/images/logo_light_with_text_192.png'),
        findsOneWidget,
      );
    });

    testWidgets('dark with text -> dark with-text asset', (tester) async {
      await tester.pumpWidget(
        _wrap(const GabbroLogo(withText: true), dark: true),
      );
      expect(
        _findAsset('assets/images/logo_dark_with_text_192.png'),
        findsOneWidget,
      );
    });

    testWidgets('hc dark with text -> hc dark with-text asset', (tester) async {
      await tester.pumpWidget(
        _wrap(const GabbroLogo(withText: true), dark: true, highContrast: true),
      );
      expect(
        _findAsset('assets/images/logo_hc_dark_with_text_192.png'),
        findsOneWidget,
      );
    });
  });
}
