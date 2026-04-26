import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildBar({
  required Set<String> presentLetters,
  void Function(String)? onLetterSelected,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 36,
          height: 600,
          child: AlphabetIndexBar(
            presentLetters: presentLetters,
            onLetterSelected: onLetterSelected ?? (_) {},
          ),
        ),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('present letters are rendered', (tester) async {
    await tester.pumpWidget(
      _buildBar(presentLetters: {'A', 'B', 'C'}),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('tapping a present letter fires callback', (tester) async {
    String? selected;

    await tester.pumpWidget(
      _buildBar(
        presentLetters: {'G'},
        onLetterSelected: (l) => selected = l,
      ),
    );

    await tester.tap(find.text('G'));
    await tester.pump();

    expect(selected, equals('G'));
  });

  testWidgets('tapping an absent letter does not fire callback', (tester) async {
    String? selected;

    await tester.pumpWidget(
      _buildBar(
        presentLetters: {'A'},
        onLetterSelected: (l) => selected = l,
      ),
    );

    await tester.tap(find.text('Z'));
    await tester.pump();

    expect(selected, isNull);
  });
}
