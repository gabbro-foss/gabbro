import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/gabbro_contrast.dart';
import 'package:gabbro/widgets/focus_region.dart';

import 'screen_catalog.dart';

FocusFramePainter? _framePainter(WidgetTester t) {
  for (final c in t.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (c.foregroundPainter is FocusFramePainter) {
      return c.foregroundPainter as FocusFramePainter;
    }
  }
  return null;
}

Widget _wrap(Widget child, {bool highContrast = false}) => MaterialApp(
  theme: ThemeData(
    colorScheme: const ColorScheme.light(primary: Color(0xFF336699)),
    extensions: [GabbroContrast(highContrast: highContrast)],
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('focusFrameStyle', () {
    const c = Color(0xFF336699);
    test('no frame when the region is not focused', () {
      expect(focusFrameStyle(focused: false, highContrast: false, color: c), isNull);
      expect(focusFrameStyle(focused: false, highContrast: true, color: c), isNull);
    });
    test('normal mode: solid 2 dp', () {
      final s = focusFrameStyle(focused: true, highContrast: false, color: c)!;
      expect(s.width, 2);
      expect(s.dashed, isFalse);
      expect(s.color, c);
    });
    test('high-contrast: dashed and thicker (3 dp)', () {
      final s = focusFrameStyle(focused: true, highContrast: true, color: c)!;
      expect(s.width, 3);
      expect(s.dashed, isTrue);
    });
  });

  testWidgets('frame appears only when a descendant is focused', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_wrap(
      FocusRegion(
        child: Focus(focusNode: node, child: const SizedBox(width: 50, height: 50)),
      ),
    ));
    expect(_framePainter(tester), isNull, reason: 'no frame before focus');

    node.requestFocus();
    await tester.pump();
    final p = _framePainter(tester);
    expect(p, isNotNull, reason: 'frame shows when a descendant is focused');
    expect(p!.style.dashed, isFalse, reason: 'normal mode is solid');
  });

  // Regression pin (hardware round 7): the search box drew TWO borders — its
  // always-on native outline PLUS the FocusRegion frame. The field must make its
  // focus border transparent so the frame is the single indicator.
  testWidgets('search box: FocusRegion frame is the single focus indicator',
      (tester) async {
    tester.view.physicalSize = phone.physical;
    tester.view.devicePixelRatio = phone.dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
    await tester.pump(const Duration(milliseconds: 300));

    final search = tester.widget<TextField>(find.byType(TextField).first);
    final focused = search.decoration!.focusedBorder;
    expect(focused, isA<OutlineInputBorder>());
    expect((focused as OutlineInputBorder).borderSide.color, Colors.transparent,
        reason: 'search focus border must be transparent, or it doubles the frame');

    // And the FocusRegion frame does appear when the search field is focused.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(_framePainter(tester), isNotNull,
        reason: 'the search region shows its FocusRegion frame when focused');
  });

  testWidgets('high-contrast focused region uses a dashed, thicker frame',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_wrap(
      highContrast: true,
      FocusRegion(
        child: Focus(focusNode: node, child: const SizedBox(width: 50, height: 50)),
      ),
    ));
    node.requestFocus();
    await tester.pump();
    final p = _framePainter(tester);
    expect(p, isNotNull);
    expect(p!.style.dashed, isTrue);
    expect(p.style.width, 3);
  });
}
