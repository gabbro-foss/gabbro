import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'screen_catalog.dart';
import 'test_helpers.dart';

// Phase 4 — the a11y layer. A screen-reader user hears the app instead of
// seeing it, so the focus frame can never be the only region cue.
//
// D5 splits this by platform:
//   BOTH  — every region-cycle control says what Enter / the arrows do (a hint).
//           Names are already covered: labeledTapTargetGuideline sweeps all 27
//           screens in a11y_net_test.dart. Hints are what nothing has yet.
//   LINUX — each region is named and announces itself when entered. Android has
//           no regions, so nothing there may announce one; that negative is
//           pinned in a11y_region_net_test.dart, not repeated here.
//
// The matching baselines (hint empty, region silent, no live region) are pinned
// GREEN in a11y_region_net_test.dart and flip when this file goes green — that
// is the point of them.

List<EntrySummaryData> denseEntries() {
  const titles = ['Apple', 'Banana', 'Cherry', 'Date', 'Elder', 'Fig'];
  return [
    for (var i = 0; i < titles.length; i++)
      EntrySummaryData(
        id: 'e$i',
        entryType: 'login',
        title: titles[i],
        folder: ['Work', 'Personal'][i % 2],
        searchBlob: titles[i].toLowerCase(),
      ),
  ];
}

VaultListScreen denseVaultList({bool android = false}) => VaultListScreen(
  vaultPath: '/tmp/probe.gabbro',
  vaultAlias: 'Dense',
  isAndroid: android,
  yubikeyRecords: const [],
  listEntries: denseEntries,
  listFolders: () => const ['Work', 'Personal'],
  getEntryFn: (_) => login('secret', 'notes'),
  onDeleteEntryFn: (_) async {},
  onRefreshFn: () {},
);

Future<SemanticsHandle> pumpDense(
  WidgetTester t, {
  Surface surface = phone,
  bool android = false,
}) async {
  t.view.physicalSize = surface.physical;
  t.view.devicePixelRatio = surface.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final handle = t.ensureSemantics();
  await t.pumpWidget(appShell(denseVaultList(android: android), textScale: 1.0));
  await t.pump(const Duration(milliseconds: 300));
  return handle;
}

Future<void> tab(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  await t.pump(const Duration(milliseconds: 300));
}

/// The hint a screen reader reads for the node [finder] resolves to.
String hintOf(WidgetTester t, Finder finder) =>
    t.getSemantics(finder).getSemanticsData().hint;

void main() {
  // ── Both platforms: every region control says what its keys do ───────────
  // Each of these controls already has a NAME. None of them says what happens
  // when the user presses Enter or an arrow, so a screen-reader user reaches a
  // control and cannot tell what it will do.

  testWidgets('the search box says that typing filters the entries', (t) async {
    final handle = await pumpDense(t);
    expect(
      hintOf(t, find.byType(EditableText).first),
      isNotEmpty,
      reason: 'the search box does not say what typing in it does',
    );
    handle.dispose();
  });

  testWidgets('a filter chip says that Enter toggles it', (t) async {
    final handle = await pumpDense(t);
    expect(
      hintOf(t, find.byType(FilterChip).first),
      isNotEmpty,
      reason: 'a filter chip does not say what Enter does to it',
    );
    handle.dispose();
  });

  testWidgets('an entry row says that Enter opens it', (t) async {
    final handle = await pumpDense(t);
    expect(
      hintOf(t, find.text('Apple')),
      isNotEmpty,
      reason: 'an entry row does not say what Enter does to it',
    );
    handle.dispose();
  });

  // The two layouts build their own row, so the hint has to be wired in both.
  testWidgets('wide: an entry row says that Enter opens it', (t) async {
    final handle = await pumpDense(t, surface: tablet);
    expect(
      hintOf(t, find.text('Apple')),
      isNotEmpty,
      reason: 'the two-pane entry row does not say what Enter does to it',
    );
    handle.dispose();
  });

  testWidgets('the folder selector says that it filters by folder', (t) async {
    final handle = await pumpDense(t);
    expect(
      hintOf(t, find.byType(DropdownButton<String>).first),
      isNotEmpty,
      reason: 'the folder selector does not say what choosing one does',
    );
    handle.dispose();
  });

  // ── Linux only: the regions speak ────────────────────────────────────────
  // Tab moves between REGIONS, not controls, so a screen-reader user who Tabs
  // hears the newly-focused control with no idea they changed region. Entering
  // one must announce it ("Folder list"), which is what liveRegion does.

  testWidgets('entering each region announces a distinct name', (t) async {
    final handle = await pumpDense(t);
    // Narrow cycle: search -> folder -> chips -> list.
    final announced = <String>[];
    for (var i = 0; i < 4; i++) {
      await tab(t);
      final live = liveRegionLabels(t).where((l) => l.isNotEmpty).toList();
      expect(
        live,
        hasLength(1),
        reason: 'stop ${i + 1}: expected exactly one region to announce itself, '
            'got $live',
      );
      announced.add(live.single);
    }
    expect(
      announced.toSet(),
      hasLength(4),
      reason: 'each region must announce its OWN name; got $announced',
    );
    handle.dispose();
  });

  testWidgets('wide: the detail pane announces itself when entered', (t) async {
    final handle = await pumpDense(t, surface: tablet);
    // Select an entry so the detail region joins the cycle, then walk to it:
    // search -> folder -> chips -> list -> detail.
    await tab(t);
    await tab(t);
    await tab(t);
    await tab(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 300));
    await tab(t);
    expect(
      liveRegionLabels(t).where((l) => l.isNotEmpty),
      hasLength(1),
      reason: 'the detail pane does not announce itself',
    );
    handle.dispose();
  });

  // The announcement must be the REGION's, not a stray live region on some
  // control inside it: leaving the cycle must silence it again.
  testWidgets('Esc out of the cycle leaves nothing announcing', (t) async {
    final handle = await pumpDense(t);
    await tab(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 300));
    expect(
      liveRegionLabels(t).where((l) => l.isNotEmpty),
      isEmpty,
      reason: 'a region still announces itself after Esc left the cycle',
    );
    handle.dispose();
  });
}
