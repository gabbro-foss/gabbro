import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

void main() {
  group('PasswordBreakdownSheet', () {
    testWidgets('renders one column per character', (tester) async {
      const password = 'Ab1!';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordBreakdownSheet(password: password),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    });

    testWidgets('renders 0-based position indices', (tester) async {
      const password = 'Ab1!';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordBreakdownSheet(password: password),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('renders all four type symbols', (tester) async {
      const password = 'Ab1!';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordBreakdownSheet(password: password),
          ),
        ),
      );

      expect(find.text('▲'), findsOneWidget);
      expect(find.text('▼'), findsOneWidget);
      expect(find.text('●'), findsOneWidget);
      expect(find.text('■'), findsOneWidget);
    });

    testWidgets('renders legend with all four labels', (tester) async {
      const password = 'Ab1!';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordBreakdownSheet(password: password),
          ),
        ),
      );

      expect(find.text('Uppercase'), findsOneWidget);
      expect(find.text('Lowercase'), findsOneWidget);
      expect(find.text('Digit'), findsOneWidget);
      expect(find.text('Symbol'), findsOneWidget);
    });
  });
}