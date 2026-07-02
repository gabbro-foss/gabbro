import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('AboutScreen renders without error', (tester) async {
    await tester.pumpWidget(testApp(const AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
  });

  testWidgets('AboutScreen shows app version string', (tester) async {
    await tester.pumpWidget(testApp(const AboutScreen()));
    await tester.pumpAndSettle();
    // The version is injected at build time via --dart-define=APP_VERSION
    // (from pubspec, build metadata stripped); test builds pass no define, so
    // the version line falls back to "dev". Release builds show e.g.
    // "0.1.0-alpha.10" — see BUILD_AND_RELEASE.md.
    expect(find.text('Version dev'), findsOneWidget);
  });

  testWidgets('AboutScreen link tile tapped opens dialog with URL', (tester) async {
    await tester.pumpWidget(testApp(const AboutScreen()));
    await tester.pumpAndSettle();

    // Tap the first ListTile (Source Code).
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    // Dialog appears with the GitHub URL in selectable text.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('github.com'), findsWidgets);
  });

  testWidgets('AboutScreen URL dialog closes on Close button', (tester) async {
    await tester.pumpWidget(testApp(const AboutScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('AboutScreen licence section is present', (tester) async {
    await tester.pumpWidget(testApp(const AboutScreen()));
    await tester.pumpAndSettle();

    // Scroll to make the licence section visible.
    await tester.scrollUntilVisible(
      find.textContaining('GPL'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('GPL'), findsWidgets);
  });
}
