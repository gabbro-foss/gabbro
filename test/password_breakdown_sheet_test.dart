import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

void main() {
  group('PasswordBreakdownSheet', () {
    testWidgets('high contrast: character markers use full-contrast onSurface',
        (tester) async {
      final theme = gabbroLightTheme(highContrast: true);
      await tester.pumpWidget(
        testApp(
          const Scaffold(body: PasswordBreakdownSheet(password: 'aA1#')),
          theme: theme,
        ),
      );
      // The digit marker '●' is coloured via the type palette in normal mode;
      // in high contrast it must collapse to onSurface so it stays readable.
      final marker = tester.widget<Text>(find.text('●').first);
      expect(marker.style!.color, theme.colorScheme.onSurface);
    });

    testWidgets('renders one column per character', (tester) async {
      const password = 'Zx9#';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: PasswordBreakdownSheet(password: password),
          ),
        ));

      expect(find.text('Z'), findsOneWidget);
      expect(find.text('x'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('#'), findsOneWidget);
    });

    testWidgets('renders 0-based position indices', (tester) async {
      const password = 'Zx9#';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: PasswordBreakdownSheet(password: password),
          ),
        ));

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('renders all four type symbols', (tester) async {
      const password = 'Ab1!';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: PasswordBreakdownSheet(password: password),
          ),
        ));

      expect(find.text('▲'), findsNWidgets(2));
      expect(find.text('▼'), findsNWidgets(2));
      expect(find.text('●'), findsNWidgets(2));
      expect(find.text('■'), findsNWidgets(2));
    });

    testWidgets('renders legend with all four labels', (tester) async {
      const password = 'Ab1!';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: PasswordBreakdownSheet(password: password),
          ),
        ));

      expect(find.text('Uppercase'), findsOneWidget);
      expect(find.text('Lowercase'), findsOneWidget);
      expect(find.text('Digit'), findsOneWidget);
      expect(find.text('Symbol'), findsOneWidget);
    });
  testWidgets('shows right chevron when content overflows viewport',
        (tester) async {
      // 32 characters forces overflow in a standard test viewport (800px wide).
      const password = 'Abcdefgh1234!@#\$Abcdefgh1234!@#\$';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: SizedBox(
              width: 300,
              child: PasswordBreakdownSheet(password: password),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('tapping right chevron scrolls content right', (tester) async {
      const password = 'Abcdefgh1234!@#\$Abcdefgh1234!@#\$';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: SizedBox(
              width: 300,
              child: PasswordBreakdownSheet(password: password),
            ),
          ),
        ),
      );
      await tester.pump();

      // Grab scroll position before tap.
      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      final controller = scrollable.controller!;
      final before = controller.offset;

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(before));
    });

    testWidgets('tapping left chevron scrolls content left', (tester) async {
      const password = 'Abcdefgh1234!@#\$Abcdefgh1234!@#\$';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: SizedBox(
              width: 300,
              child: PasswordBreakdownSheet(password: password),
            ),
          ),
        ),
      );
      await tester.pump();

      // Scroll right first so the left chevron becomes visible.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      final controller = scrollable.controller!;
      final afterRight = controller.offset;

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(controller.offset, lessThan(afterRight));
    });

    testWidgets('right chevron carries a tooltip and a button label',
        (tester) async {
      const password = 'Abcdefgh1234!@#\$Abcdefgh1234!@#\$';
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        testApp(Scaffold(
          body: SizedBox(
            width: 300,
            child: PasswordBreakdownSheet(password: password),
          ),
        )),
      );
      // Settle the fade-in: the chevron starts at opacity 0 (semantics dropped)
      // and only animates in once overflow is detected.
      await tester.pumpAndSettle();

      // Desktop hover discoverability + screen-reader label, consistent with
      // the alphabet index bar. Same translated strings.
      expect(find.byTooltip('Next page'), findsOneWidget);
      expect(find.bySemanticsLabel('Next page'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Next page')).flagsCollection
            .isButton,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('left chevron carries a tooltip and a button label once shown',
        (tester) async {
      const password = 'Abcdefgh1234!@#\$Abcdefgh1234!@#\$';
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        testApp(Scaffold(
          body: SizedBox(
            width: 300,
            child: PasswordBreakdownSheet(password: password),
          ),
        )),
      );
      await tester.pump();

      // Scroll right so the left chevron is no longer hidden (opacity 0 drops
      // it from the semantics tree until it appears).
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Previous page'), findsOneWidget);
      expect(find.bySemanticsLabel('Previous page'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('classifies CJK characters as letter, not symbol',
        (tester) async {
      // 字 (U+5B57) is Unicode category Lo — has no case.
      // Before the fix it falls through to symbol (■); after it should be letter (◆).
      const password = '字A1!';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: PasswordBreakdownSheet(password: password),
        )),
      );

      // ◆ appears once in the character row (字) + once in the legend = 2.
      // If CJK were still symbol, ■ would be 4 and ◆ would be 0.
      expect(find.text('◆'), findsNWidgets(2));
      expect(find.text('■'), findsNWidgets(2)); // only ! + legend
    });

    testWidgets('classifies non-Latin uppercase and lowercase correctly',
        (tester) async {
      // Cyrillic А (U+0410) = uppercase, а (U+0430) = lowercase, 1 = digit, ! = symbol.
      // Without unicode-aware classification all non-ASCII letters fall through to symbol.
      const password = 'Аа1!';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: PasswordBreakdownSheet(password: password),
        )),
      );

      // Each type symbol appears once in the character row + once in the legend = 2.
      expect(find.text('▲'), findsNWidgets(2)); // Cyrillic А + legend
      expect(find.text('▼'), findsNWidgets(2)); // Cyrillic а + legend
      expect(find.text('●'), findsNWidgets(2)); // digit 1 + legend
      expect(find.text('■'), findsNWidgets(2)); // symbol ! + legend
    });

    testWidgets('drag gesture scrolls through characters', (tester) async {
      const password = 'Abcdefgh1234!@#\$Abcdefgh1234!@#\$';

      await tester.pumpWidget(
        testApp(Scaffold(
          body: SizedBox(
              width: 300,
              child: PasswordBreakdownSheet(password: password),
            ),
          ),
        ),
      );
      await tester.pump();

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      final controller = scrollable.controller!;
      final before = controller.offset;

      // Drag left across the character row (simulates finger swipe left).
      await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(-150, 0));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(before));
    });

    // ── Legend shows only the character types present in the password ─────────
    testWidgets('legend omits the caseless-letter row for a Latin-only password',
        (tester) async {
      // Regression: the Letter (Lo/Lt/Lm) legend row hard-codes a CJK example
      // (字) and was shown even when the password has no caseless letters.
      const password = 'Abcd12!';

      await tester.pumpWidget(
        testApp(Scaffold(body: PasswordBreakdownSheet(password: password))),
      );

      expect(find.text('字'), findsNothing);
      expect(find.text('Letter'), findsNothing);
      // Types that ARE present still show.
      expect(find.text('Uppercase'), findsOneWidget);
      expect(find.text('Lowercase'), findsOneWidget);
      expect(find.text('Digit'), findsOneWidget);
      expect(find.text('Symbol'), findsOneWidget);
    });

    testWidgets('legend includes the Letter row when a caseless letter is present',
        (tester) async {
      const password = 'café字'; // 字 is a caseless (Lo) letter

      await tester.pumpWidget(
        testApp(Scaffold(body: PasswordBreakdownSheet(password: password))),
      );

      expect(find.text('Letter'), findsOneWidget);
      // No uppercase/digit/symbol here -> those rows are omitted.
      expect(find.text('Uppercase'), findsNothing);
      expect(find.text('Digit'), findsNothing);
      expect(find.text('Symbol'), findsNothing);
    });

    testWidgets('legend shows only the lowercase row for an all-lowercase password',
        (tester) async {
      const password = 'abcdef';

      await tester.pumpWidget(
        testApp(Scaffold(body: PasswordBreakdownSheet(password: password))),
      );

      expect(find.text('Lowercase'), findsOneWidget);
      expect(find.text('Uppercase'), findsNothing);
      expect(find.text('Digit'), findsNothing);
      expect(find.text('Symbol'), findsNothing);
      expect(find.text('Letter'), findsNothing);
    });

    // ADR-016 Phase 3 Slice D: the scroll chevrons are icons (icons don't apply
    // textScaler), so scale them at large text to match the enlarged content.
    testWidgets('scroll chevrons scale up at large text', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        testApp(
          Scaffold(body: PasswordBreakdownSheet(password: r'Xy7$kQ9!mZ2pR8wL')),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.chevron_right).first);
      expect(icon.size, isNotNull);
      expect(icon.size! > 16, isTrue);
    });
  });
}