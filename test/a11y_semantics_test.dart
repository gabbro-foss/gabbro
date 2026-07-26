import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
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

/// The English strings, to assert against what a reader would actually hear.
final en = lookupAppLocalizations(const Locale('en'));

/// Asserts that [finder]'s node speaks [outcome] to a Linux screen reader:
/// inside the NAME, after the control's own name, and never as a hint (which
/// the Linux embedder does not read).
void expectSpeaksOnLinux(
  WidgetTester t,
  Finder finder,
  String outcome, {
  required String what,
}) {
  final label = labelOf(t, finder);
  expect(
    label,
    contains(outcome),
    reason: '$what does not say what it does — Orca reads only the name, and '
        'the outcome is not in it',
  );
  expect(
    label.indexOf(outcome),
    greaterThan(0),
    reason: '$what says what it does before it says what it is; the name has '
        'to come first',
  );
  expect(
    hintOf(t, finder),
    isEmpty,
    reason: '$what still carries a hint on Linux, where nothing reads one — '
        'the text was duplicated instead of moved',
  );
}

void main() {
  // ── Linux: the outcome belongs in the NAME ───────────────────────────────
  // Round 16 (Orca) heard none of these. The Linux embedder reads only a
  // node's label — `hint` is never read at all — so on Linux "what this
  // control does" has to be part of the name, after the control's own name.
  // Android keeps the hint instead; that half is pinned green in
  // a11y_region_net_test.dart and must not move.

  testWidgets('the search box name says that typing filters', (t) async {
    final handle = await pumpDense(t);
    final finder = find.byType(EditableText).first;
    expectSpeaksOnLinux(t, finder, en.hintSearch, what: 'the search box');
    // Its own name is the field's placeholder, and it must be read first.
    final label = labelOf(t, finder);
    expect(
      label.indexOf(en.searchEntriesHint),
      lessThan(label.indexOf(en.hintSearch)),
      reason: 'the search box says what typing does before naming itself',
    );
    handle.dispose();
  });

  // The box is reached by two shortcuts that differ in WHAT they search, and
  // a screen-reader user has no other way to discover that. These may only be
  // spoken on Linux — Android has no keyboard to press them on, which is the
  // whole reason the wording is split per platform.
  testWidgets('the search box names both of its shortcuts', (t) async {
    final handle = await pumpDense(t);
    final label = labelOf(t, find.byType(EditableText).first);
    expect(
      label,
      contains(en.kbFocusSearch),
      reason: 'the search box never mentions Ctrl+F',
    );
    expect(
      label,
      contains(en.kbSearchAllFields),
      reason: 'the search box never mentions Ctrl+Shift+F, so nothing says '
          'that it can search every field',
    );
    handle.dispose();
  });

  testWidgets('a filter chip name says that Enter toggles it', (t) async {
    final handle = await pumpDense(t);
    expectSpeaksOnLinux(
      t,
      find.byType(FilterChip).first,
      en.hintFilterChip,
      what: 'a filter chip',
    );
    handle.dispose();
  });

  // Each layout builds its own row and its own folder selector, so each has a
  // separate call site that can regress on its own.
  for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
    testWidgets('$name: an entry row name says that Enter opens it', (t) async {
      final handle = await pumpDense(t, surface: surface);
      final finder = find.text('Apple');
      expectSpeaksOnLinux(t, finder, en.hintEntryRow, what: 'an entry row');
      // The entry's title is its name, and must be read before the outcome.
      final label = labelOf(t, finder);
      expect(
        label.indexOf('Apple'),
        lessThan(label.indexOf(en.hintEntryRow)),
        reason: 'the row says what Enter does before it says which entry it is',
      );
      handle.dispose();
    });

    testWidgets('$name: the folder selector name says that it filters', (
      t,
    ) async {
      final handle = await pumpDense(t, surface: surface);
      expectSpeaksOnLinux(
        t,
        find.byType(DropdownButton<String>).first,
        en.hintFolderSelector,
        what: 'the folder selector',
      );
      handle.dispose();
    });

    // Selection mode taps the row to tick it, so "opens this entry" is a lie.
    // Guard on the guard: the row pin above proves the same lookup finds the
    // outcome text when it is there, so this absence is real.
    testWidgets('$name: a row in selection mode does not claim to open', (
      t,
    ) async {
      final handle = await pumpDense(t, surface: surface);
      await t.tap(find.byIcon(Icons.checklist));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        labelOf(t, find.text('Apple')),
        isNot(contains(en.hintEntryRow)),
        reason: 'a tickable row still claims that it opens the entry',
      );
      handle.dispose();
    });
  }

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
