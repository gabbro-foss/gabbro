import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_catalog.dart';

// On Android 15+ the app draws under the system bars, and a Scaffold strips
// the nav-bar padding from its body whenever bottomNavigationBar != null.
// The overflow probe cannot see that, so this renders every screen with a
// faked inset and asserts nothing reaches into the band.

/// One inset scenario: where the system bar sits and how thick it is (dp).
class Inset {
  final String name;
  final double bottom;
  final double right;
  const Inset(this.name, {this.bottom = 0, this.right = 0});
}

const none = Inset('no inset');
const gesture = Inset('gesture nav', bottom: 20);
const buttons = Inset('3-button nav', bottom: 48);
const sideBar = Inset('landscape side bar', right: 48);

/// Landscape twin of a portrait surface.
Surface landscape(Surface s) =>
    Surface('${s.name} landscape', Size(s.physical.height, s.physical.width), s.dpr);

/// Renders [screen] on [surface] with [inset] faked as system padding.
Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  Surface surface,
  Inset inset,
) async {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.dpr;
  tester.view.padding = FakeViewPadding(
    bottom: inset.bottom * surface.dpr,
    right: inset.right * surface.dpr,
  );
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(appShell(screen, textScale: 1.0));
  await tester.pump(const Duration(milliseconds: 300));
}

/// The band the system bar covers, in logical pixels.
Rect _band(WidgetTester tester, Surface surface, Inset inset) {
  final size = surface.physical / surface.dpr;
  if (inset.right > 0) {
    return Rect.fromLTWH(size.width - inset.right, 0, inset.right, size.height);
  }
  return Rect.fromLTWH(0, size.height - inset.bottom, size.width, inset.bottom);
}

/// Scrolls every scrollable to its end. A list may legitimately scroll under
/// a transparent bar; what must never happen is its LAST item, or any fixed
/// text, icon, FAB or snackbar, ending up in the band. At the end position
/// the last item is on screen, so one rect check decides it.
Future<void> _scrollAllToEnd(WidgetTester tester) async {
  for (final s in find.byType(Scrollable).evaluate()) {
    final state = (s as StatefulElement).state as ScrollableState;
    if (state.position.hasContentDimensions && state.position.axis == Axis.vertical) {
      state.position.jumpTo(state.position.maxScrollExtent);
    }
  }
  await tester.pump(const Duration(milliseconds: 300));
}

bool _inHorizontalScroller(Element e) {
  var found = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Scrollable && w.axisDirection.isHorizontal) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

extension on AxisDirection {
  bool get isHorizontal =>
      this == AxisDirection.left || this == AxisDirection.right;
}

/// Every element that must stay out of the band.
List<String> _offenders(WidgetTester tester, Surface surface, Inset inset) {
  final band = _band(tester, surface, inset);
  final screen = Offset.zero & (surface.physical / surface.dpr);
  final out = <String>[];
  void check(String label, Finder f) {
    for (final e in f.evaluate()) {
      // Content inside a horizontal scroller runs past the side edge by
      // design (a wide table); a side bar over it is not a layout fault.
      if (inset.right > 0 && _inHorizontalScroller(e)) continue;
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.isEmpty || !rect.overlaps(screen)) continue;
      if (rect.overlaps(band)) {
        out.add(
          '$label bottom=${rect.bottom.round()} right=${rect.right.round()}',
        );
      }
    }
  }

  check('text', find.byWidgetPredicate((w) => w is Text || w is RichText));
  check('icon', find.byType(Icon));
  check('fab', find.byType(FloatingActionButton));
  check('snackbar', find.byType(SnackBar));
  return out;
}

/// Widgets hosted by a real screen (catalogued under lib/widgets, or under
/// lib/screens but listed here): the catalog wraps them in a bare Scaffold
/// of its own, so the band is the harness's to keep, not theirs. The
/// hosting screen is what gets tested.
const Map<String, String> _hostedByHarness = {
  'alphabet_index_bar': 'vault_list hosts it',
  'tablet_vault_layout': 'vault_list (wide) hosts it',
};

bool _isWidgetEntry(String key) =>
    _hostedByHarness.containsKey(key) ||
    File('lib/widgets/${covers[key]}.dart').existsSync();

void main() {
  // Guard on the guard: a deliberate offender must be caught, or every green
  // below proves nothing.
  testWidgets('the net catches content under the bar', (tester) async {
    await _pump(
      tester,
      Scaffold(
        bottomNavigationBar: const SizedBox.shrink(),
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(child: const Text('under the bar')),
        ),
      ),
      phone,
      buttons,
    );
    expect(_offenders(tester, phone, buttons), isNotEmpty);
  });

  testWidgets('the net accepts content kept out of the bar', (tester) async {
    await _pump(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(child: Text('above the bar')),
        ),
      ),
      phone,
      buttons,
    );
    expect(_offenders(tester, phone, buttons), isEmpty);
  });

  for (final surface in [phone, tablet, landscape(phone), landscape(tablet)]) {
    // A side bar exists only in landscape.
    final insets = surface.physical.width > surface.physical.height
        ? const [none, gesture, buttons, sideBar]
        : const [none, gesture, buttons];
    for (final inset in insets) {
      for (final entry in screens.entries) {
        testWidgets(
          '${entry.key} @ ${surface.name}, ${inset.name}: nothing under the bar',
          (tester) async {
            await _pump(tester, entry.value(), surface, inset);
            await _scrollAllToEnd(tester);
            expect(
              _offenders(tester, surface, inset),
              isEmpty,
              reason: '${entry.key} @ ${surface.name}, ${inset.name}',
            );
          },
          skip: _isWidgetEntry(entry.key) ||
              surface.physical.shortestSide / surface.dpr < 600 &&
              tabletOnly.containsKey(entry.key),
        );
      }
    }
  }
}
