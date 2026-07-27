import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_catalog.dart';

// NET-FIRST floor for Phase 3 (region Tab-cycle + within-region arrows). Pins
// that today's keyboard-reachable vault-list controls STAY reachable. Phase 3
// changes the reach PATH (Tab lands on a region, arrows move within it) — when a
// pin's path changes, update it deliberately. A control going PERMANENTLY
// unreachable must fail here, not slip through.

/// Press Tab up to [maxTabs] times; true once primary focus is inside a [T].
Future<bool> tabReaches<T extends Widget>(WidgetTester tester,
    {int maxTabs = 60}) async {
  for (var i = 0; i < maxTabs; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null && ctx.findAncestorWidgetOfExactType<T>() != null) {
      return true;
    }
  }
  return false;
}

Future<void> pumpVaultList(WidgetTester tester, Surface surface) async {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('BASELINE: Tab reaches the search field (narrow layout)',
      (tester) async {
    await pumpVaultList(tester, phone);
    expect(await tabReaches<EditableText>(tester), isTrue,
        reason: 'the search field must stay keyboard-reachable');
  });

  testWidgets('BASELINE: Tab reaches a filter chip (narrow layout)',
      (tester) async {
    await pumpVaultList(tester, phone);
    expect(await tabReaches<FilterChip>(tester), isTrue,
        reason: 'a filter chip must stay keyboard-reachable');
  });

  // Phase 3 excluded the two-pane nav rail from the region Tab-cycle, and the
  // rail has since been removed outright, so the old "Tab reaches the navigation
  // rail" pin is doubly gone. The floor that DOES hold: the wide layout's content
  // stays keyboard-reachable — Tab still reaches the search field. Full wide
  // reachability (search/folder/chips/list/detail) is pinned in
  // keyboard_region_cycle_test.dart.
  testWidgets('BASELINE: Tab reaches the search field (wide two-pane)',
      (tester) async {
    await pumpVaultList(tester, tablet);
    expect(await tabReaches<EditableText>(tester), isTrue,
        reason: 'the search field must stay keyboard-reachable (wide layout)');
  });
}
