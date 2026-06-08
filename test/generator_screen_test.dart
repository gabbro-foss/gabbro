import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/generator_screen.dart';
import 'package:gabbro/widgets/generator_widget.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('GeneratorScreen renders without error', (tester) async {
    await tester.pumpWidget(testApp(const GeneratorScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(GeneratorScreen), findsOneWidget);
  });

  testWidgets('GeneratorScreen contains a GeneratorWidget', (tester) async {
    await tester.pumpWidget(testApp(const GeneratorScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(GeneratorWidget), findsOneWidget);
  });

  testWidgets('GeneratorScreen AppBar shows generator title', (tester) async {
    await tester.pumpWidget(testApp(const GeneratorScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('GeneratorScreen passes 60-second duration when no app context',
      (tester) async {
    // GabbroApp.maybeOf returns null in tests → defaults to sixtySeconds.
    await tester.pumpWidget(testApp(const GeneratorScreen()));
    await tester.pumpAndSettle();

    final gen = tester.widget<GeneratorWidget>(find.byType(GeneratorWidget));
    expect(
      gen.clipboardClearDuration,
      const Duration(seconds: 60),
      reason: 'null GabbroApp context must fall back to the sixty-second default',
    );
  });
}
