import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';

void main() {
  group('PasswordBreakdownSheet', () {
    testWidgets('renders one column per character', (tester) async {
      const password = 'Zx9#';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordBreakdownSheet(password: password),
          ),
        ),
      );

      expect(find.text('Z'), findsOneWidget);
      expect(find.text('x'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('#'), findsOneWidget);
    });

    testWidgets('renders 0-based position indices', (tester) async {
      const password = 'Zx9#';

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

      expect(find.text('▲'), findsNWidgets(2));
      expect(find.text('▼'), findsNWidgets(2));
      expect(find.text('●'), findsNWidgets(2));
      expect(find.text('■'), findsNWidgets(2));
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