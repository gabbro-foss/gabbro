import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/focus_region.dart';

import 'screen_catalog.dart';

// Phase 3, increment 1 — prove the region pattern on the filter chips: the row is
// ONE Tab-stop, arrows move within it, Enter toggles, the FocusRegion frame shows.

FilterChip? _focusedChip(WidgetTester t) => FocusManager
    .instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<FilterChip>();

String? _focusedChipLabel(WidgetTester t) {
  final label = _focusedChip(t)?.label;
  return label is Text ? label.data : null;
}

bool _frameShown(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((c) => c.foregroundPainter is FocusFramePainter);

/// True if any region FocusScope (debugLabel 'region:...') is in the tree.
bool _hasRegionScope(WidgetTester t) => t
    .widgetList<FocusScope>(find.byType(FocusScope))
    .any((f) => (f.focusNode?.debugLabel ?? '').startsWith('region:'));

Future<bool> _tabToChip(WidgetTester t, {int max = 40}) async {
  for (var i = 0; i < max; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    if (_focusedChip(t) != null) return true;
  }
  return false;
}

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = phone.physical;
  t.view.devicePixelRatio = phone.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(appShell(screens['vault_list']!(), textScale: 1.0));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the chip row is a single Tab-stop', (tester) async {
    await _pump(tester);
    expect(await _tabToChip(tester), isTrue, reason: 'Tab reaches the chips');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusedChip(tester), isNull,
        reason: 'one Tab-stop: Tab leaves the chips, it does not step to the next chip');
  });

  testWidgets('arrow keys move focus between chips', (tester) async {
    await _pump(tester);
    expect(await _tabToChip(tester), isTrue);
    final first = _focusedChipLabel(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_focusedChipLabel(tester), isNot(first),
        reason: 'Right arrow moves to the next chip');
  });

  testWidgets('the chips region shows its focus frame', (tester) async {
    await _pump(tester);
    expect(await _tabToChip(tester), isTrue);
    expect(_frameShown(tester), isTrue,
        reason: 'the chip region frame shows while a chip is focused');
  });

  // The region cycle is Linux-desktop ONLY. Android is touch-only (no keyboard
  // at all), so none of the keyboard-nav wiring may enter its widget tree. These
  // check the region FocusScopes are present on desktop and ABSENT on Android —
  // no synthetic key events, just the structure.
  testWidgets('desktop build wraps regions in FocusScopes', (tester) async {
    await _pump(tester); // catalog vault_list is isAndroid:false
    expect(_hasRegionScope(tester), isTrue);
  });

  testWidgets('Android build has NO region FocusScopes (tree unchanged)',
      (tester) async {
    tester.view.physicalSize = phone.physical;
    tester.view.devicePixelRatio = phone.dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(appShell(
      VaultListScreen(
        vaultPath: '/tmp/probe.gabbro',
        isAndroid: true,
        yubikeyRecords: const [],
        listEntries: () => const [
          EntrySummaryData(
            id: 'e1',
            entryType: 'login',
            title: 'Example',
            folder: '',
            searchBlob: '',
          ),
        ],
      ),
      textScale: 1.0,
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_hasRegionScope(tester), isFalse,
        reason: 'no keyboard-nav wiring may enter the Android widget tree');
  });
}
