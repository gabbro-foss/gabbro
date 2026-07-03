import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';

// ── Widget helpers ────────────────────────────────────────────────────────────

// Pump the bar at a specific logical height by resizing the test surface.
// This bypasses MaterialApp/Scaffold height consumption entirely.
Future<void> pumpBar(
  WidgetTester tester, {
  required double height,
  required Set<String> presentLetters,
  String? initialLetter,
  List<String>? letters,
  String? scrollUpLabel,
  String? scrollDownLabel,
  void Function(String)? onLetterSelected,
}) async {
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Omit `letters` to exercise the widget's default (Latin) canon.
  final bar = letters == null
      ? AlphabetIndexBar(
          presentLetters: presentLetters,
          initialLetter: initialLetter,
          scrollUpLabel: scrollUpLabel ?? 'Scroll up',
          scrollDownLabel: scrollDownLabel ?? 'Scroll down',
          onLetterSelected: onLetterSelected ?? (_) {},
        )
      : AlphabetIndexBar(
          letters: letters,
          presentLetters: presentLetters,
          initialLetter: initialLetter,
          scrollUpLabel: scrollUpLabel ?? 'Scroll up',
          scrollDownLabel: scrollDownLabel ?? 'Scroll down',
          onLetterSelected: onLetterSelected ?? (_) {},
        );

  await tester.pumpWidget(MaterialApp(home: bar));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Existing tests ────────────────────────────────────────────────────────

  testWidgets('present letters are rendered', (tester) async {
    await pumpBar(tester, height: 756, presentLetters: {'A', 'B', 'C'});

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('tapping a present letter fires callback', (tester) async {
    String? selected;
    await pumpBar(
      tester,
      height: 756,
      presentLetters: {'G'},
      onLetterSelected: (l) => selected = l,
    );

    await tester.tap(find.text('G'));
    await tester.pump();

    expect(selected, equals('G'));
  });

  testWidgets('tapping an absent letter does not fire callback', (tester) async {
    String? selected;
    await pumpBar(
      tester,
      height: 756,
      presentLetters: {'A'},
      onLetterSelected: (l) => selected = l,
    );

    await tester.tap(find.text('Z'));
    await tester.pump();

    expect(selected, isNull);
  });

  // ── Greying contract ──────────────────────────────────────────────────────

  testWidgets('full canon is rendered even when only one letter is present',
      (tester) async {
    await pumpBar(tester, height: 756, presentLetters: {'A'});

    // Absent letters are still drawn (greyed), not omitted.
    expect(find.text('Z'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('absent letters render dimmer than present letters',
      (tester) async {
    await pumpBar(tester, height: 756, presentLetters: {'A'});

    Color colorOf(String letter) {
      final text = tester.widget<Text>(find.text(letter));
      return text.style!.color!;
    }

    // 'A' is present (full opacity); 'B' is absent (dimmed to alpha 0.25).
    expect(colorOf('A').a, greaterThan(colorOf('B').a));
  });

  // ── A11y semantics ────────────────────────────────────────────────────────

  testWidgets('present letter slot is a button labelled with its letter',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, height: 756, presentLetters: {'A'});

    expect(find.bySemanticsLabel('A'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('A'));
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('absent letter slot is excluded from semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, height: 756, presentLetters: {'A'});

    expect(find.bySemanticsLabel('B'), findsNothing);
    handle.dispose();
  });

  testWidgets('# slot is labelled with the # glyph', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, height: 756, presentLetters: {'A', '#'});

    expect(find.bySemanticsLabel('#'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('chevrons expose the provided scroll labels', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'Z'},
      scrollUpLabel: 'EARLIER',
      scrollDownLabel: 'LATER',
    );

    expect(find.bySemanticsLabel('EARLIER'), findsOneWidget);
    expect(find.bySemanticsLabel('LATER'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('chevrons expose a hover tooltip with the scroll label',
      (tester) async {
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'Z'},
      scrollUpLabel: 'EARLIER',
      scrollDownLabel: 'LATER',
    );

    // Desktop discoverability: the bare arrow icons surface their label on
    // hover/long-press as a Tooltip popup, not only via a screen reader.
    expect(find.byTooltip('EARLIER'), findsOneWidget);
    expect(find.byTooltip('LATER'), findsOneWidget);
  });

  testWidgets('chevron tooltip does not double-up screen-reader semantics',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'Z'},
      scrollUpLabel: 'EARLIER',
      scrollDownLabel: 'LATER',
    );

    // The Tooltip sits inside the existing excludeSemantics wrapper, so each
    // label still announces exactly once.
    expect(find.bySemanticsLabel('EARLIER'), findsOneWidget);
    expect(find.bySemanticsLabel('LATER'), findsOneWidget);
    handle.dispose();
  });

  // ── Custom letter set (Cycle 1: locale-driven canon) ──────────────────────

  testWidgets('letters param drives the slot set (Cyrillic)', (tester) async {
    await pumpBar(
      tester,
      height: 756,
      letters: const ['А', 'Б', 'В', 'Г', 'Д', '#'],
      presentLetters: {'Б'},
    );

    expect(find.text('Б'), findsOneWidget); // present
    expect(find.text('А'), findsOneWidget); // greyed, still rendered
    expect(find.text('Q'), findsNothing); // no Latin canon
  });

  // ── Full mode ─────────────────────────────────────────────────────────────

  testWidgets('full mode: all 27 letters visible when height >= 756dp',
      (tester) async {
    await pumpBar(tester, height: 756, presentLetters: {'A', 'M', 'Z'});

    for (final letter in [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
    ]) {
      expect(find.text(letter), findsOneWidget,
          reason: '$letter should be visible in full mode');
    }
  });

  testWidgets('full mode: no chevrons rendered', (tester) async {
    await pumpBar(tester, height: 756, presentLetters: {'A', 'B', 'C'});

    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets('full mode: no ellipsis rendered', (tester) async {
    await pumpBar(tester, height: 756, presentLetters: {'A', 'B', 'C'});

    expect(find.text('…'), findsNothing);
  });

  // ── Windowed mode ─────────────────────────────────────────────────────────

  testWidgets('windowed mode: chevrons rendered when height < 756dp',
      (tester) async {
    await pumpBar(tester, height: 400, presentLetters: {'A', 'M', 'Z'});

    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
  });

  testWidgets('windowed mode: not all letters visible', (tester) async {
    await pumpBar(tester, height: 400, presentLetters: {'A', 'M', 'Z'});

    int visibleCount = 0;
    for (final letter in [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
    ]) {
      if (tester.any(find.text(letter))) visibleCount++;
    }
    expect(visibleCount, lessThan(27));
  });

  testWidgets('windowed mode: ellipsis shown above window when not at top',
      (tester) async {
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'M', 'Z'},
      initialLetter: 'M',
    );

    expect(find.text('…'), findsWidgets);
  });

  testWidgets('windowed mode: no ellipsis above when window starts at A',
      (tester) async {
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'M', 'Z'},
      initialLetter: 'A',
    );

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('windowed mode: initialLetter centres window on first present letter',
      (tester) async {
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'M', 'Z'},
    );

    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('windowed mode: chevron tap shifts window', (tester) async {
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'Z'},
      initialLetter: 'A',
    );

    final before = <String>{};
    for (final letter in [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
    ]) {
      if (tester.any(find.text(letter))) before.add(letter);
    }

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pump();

    final after = <String>{};
    for (final letter in [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
    ]) {
      if (tester.any(find.text(letter))) after.add(letter);
    }

    expect(after, isNot(equals(before)));
  });

  testWidgets('windowed mode: tapping present letter fires callback',
      (tester) async {
    String? selected;
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'M'},
      initialLetter: 'M',
      onLetterSelected: (l) => selected = l,
    );

    await tester.tap(find.text('M'));
    await tester.pump();

    expect(selected, equals('M'));
  });

  testWidgets('windowed mode: tapping absent letter does not fire callback',
      (tester) async {
    String? selected;
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'M'},
      initialLetter: 'M',
      onLetterSelected: (l) => selected = l,
    );

    await tester.tap(find.text('N'));
    await tester.pump();

    expect(selected, isNull);
  });

  // ── Drag-to-scroll ────────────────────────────────────────────────────────

  testWidgets('drag down shifts visible window downward', (tester) async {
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'M', 'Z'},
      initialLetter: 'A',
    );

    final before = <String>{};
    for (final l in ['A','B','C','D','E','F','G','H','I','J','K','L','M',
                     'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','#']) {
      if (tester.any(find.text(l))) before.add(l);
    }

    // Drag down by several slot heights to trigger a window shift.
    await tester.drag(find.text('A'), const Offset(0, 84));
    await tester.pump();

    final after = <String>{};
    for (final l in ['A','B','C','D','E','F','G','H','I','J','K','L','M',
                     'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','#']) {
      if (tester.any(find.text(l))) after.add(l);
    }

    expect(after, isNot(equals(before)));
  });

  testWidgets('drag up shifts visible window upward', (tester) async {
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'M', 'Z'},
      initialLetter: 'Z',
    );

    final before = <String>{};
    for (final l in ['A','B','C','D','E','F','G','H','I','J','K','L','M',
                     'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','#']) {
      if (tester.any(find.text(l))) before.add(l);
    }

    await tester.drag(find.text('Z'), const Offset(0, -84));
    await tester.pump();

    final after = <String>{};
    for (final l in ['A','B','C','D','E','F','G','H','I','J','K','L','M',
                     'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','#']) {
      if (tester.any(find.text(l))) after.add(l);
    }

    expect(after, isNot(equals(before)));
  });

  testWidgets('drag fires onLetterSelected', (tester) async {
    final selected = <String>[];
    await pumpBar(
      tester,
      height: 400,
      presentLetters: {'A', 'M', 'Z'},
      initialLetter: 'A',
      onLetterSelected: (l) => selected.add(l),
    );

    await tester.drag(find.text('A'), const Offset(0, 84));
    await tester.pump();

    expect(selected, isNotEmpty);
  });

  // ADR-016 Phase 3 Slice D: the letters scale with text but are CAPPED so they
  // never bleed off the 48px strip — the bar stays usable at every text size.
  testWidgets('letter size is capped at large text (no bleed)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpBar(
      tester,
      height: 900,
      presentLetters: {'A'},
      initialLetter: 'A',
    );
    // base 14 * cap 1.5 = 21; uncapped would be 14 * 2.0 = 28.
    expect(tester.getSize(find.text('A').first).height, lessThanOrEqualTo(22));
  });

  // ── Chevron scaling (ADR-016 accessibility follow-up) ─────────────────────
  // The windowed-mode up/down chevrons grow with the text scale so a low-vision
  // user gets bigger targets, capped at 1.5x (the 48px strip). At normal text
  // the glyph stays 18 so the windowing height math is unchanged.

  double upChevronSize(WidgetTester tester) =>
      tester.widget<Icon>(find.byIcon(Icons.keyboard_arrow_up)).size!;

  testWidgets('chevron grows at large text (windowed mode)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpBar(tester, height: 400, presentLetters: {'A', 'M', 'Z'},
        initialLetter: 'M');
    expect(upChevronSize(tester), greaterThan(18));
  });

  testWidgets('chevron is capped at large text (no bleed off the strip)',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpBar(tester, height: 400, presentLetters: {'A', 'M', 'Z'},
        initialLetter: 'M');
    // base 18 * cap 1.5 = 27; uncapped would be 18 * 2.0 = 36.
    expect(upChevronSize(tester), lessThanOrEqualTo(27));
  });

  testWidgets('windowed mode stays overflow-free with a bigger chevron',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpBar(tester, height: 400, presentLetters: {'A', 'M', 'Z'},
        initialLetter: 'M');
    expect(tester.takeException(), isNull);
    // The window still centres on M, so at least one letter remains visible.
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('chevron size is unchanged at normal text (no-op guard)',
      (tester) async {
    await pumpBar(tester, height: 400, presentLetters: {'A', 'M', 'Z'},
        initialLetter: 'M');
    expect(upChevronSize(tester), 18);
  });

  // Script-agnostic: the same scaling + overflow safety must hold for a
  // non-Latin canon (Russian Cyrillic here) that still renders the bar.
  testWidgets('chevron grows and stays overflow-free with a Cyrillic canon',
      (tester) async {
    const russian = [
      'А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'З', 'И', 'К', 'Л', 'М',
      'Н', 'О', 'П', 'Р', 'С', 'Т', 'У', 'Ф', 'Х', 'Ц', 'Ч', 'Ш',
      'Щ', 'Э', 'Ю', 'Я', '#',
    ];
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpBar(tester, height: 400, letters: russian,
        presentLetters: {'М'}, initialLetter: 'М');

    expect(upChevronSize(tester), greaterThan(18));
    expect(upChevronSize(tester), lessThanOrEqualTo(27));
    expect(tester.takeException(), isNull);
    expect(find.text('М'), findsOneWidget); // window still centres on present
  });
}
