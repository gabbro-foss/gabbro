import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/help_screen.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('HelpScreen renders without error', (tester) async {
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets('HelpScreen contains a PageView', (tester) async {
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('HelpScreen shows dot indicators', (tester) async {
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();
    // 13 slides → 13 AnimatedContainer dots in the indicator row.
    expect(find.byType(AnimatedContainer), findsNWidgets(13));
  });

  testWidgets('HelpScreen first slide caption is visible on open', (tester) async {
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsWidgets);
  });

  testWidgets('HelpScreen chevron-right advances to the next slide', (tester) async {
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();

    // chevron_right is enabled on first slide.
    final nextBtn = find.byIcon(Icons.chevron_right);
    expect(nextBtn, findsOneWidget);
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // After advancing, chevron_left becomes enabled.
    final prevBtn = find.byIcon(Icons.chevron_left);
    final iconBtn = tester.widget<IconButton>(
        find.ancestor(of: prevBtn, matching: find.byType(IconButton)).first);
    expect(iconBtn.onPressed, isNotNull,
        reason: 'back button must be enabled after advancing past first slide');
  });

  testWidgets('HelpScreen chevron-left is disabled on first slide', (tester) async {
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();

    final prevBtn = find.byIcon(Icons.chevron_left);
    final iconBtn = tester.widget<IconButton>(
        find.ancestor(of: prevBtn, matching: find.byType(IconButton)).first);
    expect(iconBtn.onPressed, isNull,
        reason: 'back button must be disabled on the first slide');
  });

  // A11y: the prev/next chevrons must carry a semantic label so screen readers
  // announce them, not a bare "button". Advance one slide so both are enabled.
  testWidgets('navigation chevrons meet labelled-tap-target guideline',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const HelpScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  // ── Phase 2b: pinch-to-zoom on help images (textScaler can't scale a PNG;
  // FLAG_SECURE blocks an external magnifier) ──────────────────────────────────
  group('image zoom', () {
    testWidgets('help image carries an enlarge affordance and label',
        (tester) async {
      await tester.pumpWidget(testApp(const HelpScreen()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Enlarge image'), findsWidgets);
      expect(find.byIcon(Icons.zoom_in), findsWidgets);
    });

    testWidgets('tapping a help image opens a full-screen zoom viewer',
        (tester) async {
      await tester.pumpWidget(testApp(const HelpScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);

      await tester.tap(find.byTooltip('Enlarge image').first);
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      // the same image is shown inside the zoomable viewer
      expect(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the zoom viewer closes back to the help pages', (tester) async {
      await tester.pumpWidget(testApp(const HelpScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Enlarge image').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
    });
  });
}
