import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

void main() {
  group('PasswordBreakdownSheet', () {
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
  });
}