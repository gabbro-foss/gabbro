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

VaultListScreen denseVaultList({bool android = false, bool quit = false}) =>
    VaultListScreen(
      vaultPath: '/tmp/probe.gabbro',
      vaultAlias: 'Dense',
      isAndroid: android,
      yubikeyRecords: const [],
      listEntries: denseEntries,
      listFolders: () => const ['Work', 'Personal'],
      getEntryFn: (_) => login('secret', 'notes'),
      onDeleteEntryFn: (_) async {},
      onRefreshFn: () {},
      // Ctrl+Q is inert unless a quit hook is wired, so the announcement test
      // needs one; everything else leaves it off, as the app does on Android.
      onQuit: quit ? () {} : null,
    );

Future<SemanticsHandle> pumpDense(
  WidgetTester t, {
  Surface surface = phone,
  bool android = false,
  bool quit = false,
}) async {
  t.view.physicalSize = surface.physical;
  t.view.devicePixelRatio = surface.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final handle = t.ensureSemantics();
  await t.pumpWidget(
    appShell(denseVaultList(android: android, quit: quit), textScale: 1.0),
  );
  await t.pump(const Duration(milliseconds: 300));
  return handle;
}

Future<void> sendCtrl(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

/// Opens the new-entry type picker the way both platforms can: the FAB.
Future<void> openTypePicker(WidgetTester t) async {
  await t.tap(
    find.descendant(
      of: find.byType(FloatingActionButton),
      matching: find.byIcon(Icons.add),
    ),
  );
  await t.pumpAndSettle();
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

  // The search box says ONE thing (round 23): landing on it used to produce
  // "Search, Search entries, Filters the entries as you type, Ctrl+F Focus
  // search, Ctrl+Shift+F Search all fields" — five parts, too long to sit
  // through, and the maintainer could not catch the end of it on hardware.
  // The region above already says "Search", so the box's own placeholder was
  // a repeat, and "Ctrl+F: Focus search" is useless once you are in the box.
  // Both shortcuts stay documented on the Keyboard shortcuts screen.
  // The search region's container name merges into the field's node, so what
  // Orca actually reads is "Search" then this — two parts, which is the whole
  // point. The placeholder must NOT be in there: it would make "Search" thrice.
  testWidgets('the search box name is just what typing does', (t) async {
    final handle = await pumpDense(t);
    final label = labelOf(t, find.byType(EditableText).first);
    expect(
      label,
      contains(en.hintSearch),
      reason: 'the search box no longer says what typing does',
    );
    expect(
      label,
      isNot(contains(en.searchEntriesHint)),
      reason: 'the box repeats its placeholder on top of the "Search" region '
          'name: "$label"',
    );
    handle.dispose();
  });

  testWidgets('the search box name mentions no shortcut', (t) async {
    final handle = await pumpDense(t);
    final label = labelOf(t, find.byType(EditableText).first);
    expect(
      label,
      isNot(contains('Ctrl')),
      reason: 'a shortcut is being read out every time focus lands on the box; '
          'the Keyboard shortcuts screen is where they belong',
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

  // ── Nothing is said twice ────────────────────────────────────────────────
  // The row icon carried the entry type as its label and the subtitle said it
  // again, so a reader announced "card, amex, card, opens this entry". The
  // subtitle is the one to keep: it is visible text as well as spoken.

  for (final platform in const [true, false]) {
    final who = platform ? 'Android' : 'Linux';
    for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
      testWidgets('$who $name: an entry row names its type once, not twice', (
        t,
      ) async {
        final handle = await pumpDense(t, surface: surface, android: platform);
        final label = labelOf(t, find.text('Apple'));
        expect(
          occurrencesOf(label, 'login'),
          1,
          reason: 'the row says what kind of entry it is more than once: '
              '"${label.replaceAll('\n', ' / ')}"',
        );
        handle.dispose();
      });
    }
  }

  // The new-entry picker had the same fault as the entry row: the leading icon
  // carried the type name as its semanticLabel and the row title said it again,
  // so a reader worked through "Password, Password, Note, Note, …" for all six.
  // The title is the one to keep — it is visible text as well as spoken.

  for (final android in const [true, false]) {
    final who = android ? 'Android' : 'Linux';
    for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
      testWidgets('$who $name: the picker names each type once, not twice', (
        t,
      ) async {
        final handle = await pumpDense(t, surface: surface, android: android);
        await t.tap(
          find.descendant(
            of: find.byType(FloatingActionButton),
            matching: find.byIcon(Icons.add),
          ),
        );
        await t.pumpAndSettle();
        final heard = subtreeLabels(t, find.byType(BottomSheet)).join(' | ');
        for (final type in [
          en.entryTypePassword,
          en.entryTypeNote,
          en.entryTypeIdentity,
          en.entryTypeCard,
          en.entryTypeFile,
          en.entryTypeCustom,
        ]) {
          expect(
            occurrencesOf(heard, type),
            1,
            reason: 'the picker says "$type" more than once: "$heard"',
          );
        }
        handle.dispose();
      });
    }
  }

  // ── Linux only: events have to be announced ──────────────────────────────
  // A shortcut firing or a sheet opening is an EVENT, not a place, so there is
  // no node for a reader to land on and read. Linux ignores liveRegion
  // entirely, which leaves SemanticsService as the only way to
  // say anything at all. Android is excluded throughout: it has deprecated
  // announcement events, and TalkBack already passes.
  //
  // Ctrl+F deliberately announces nothing of its own — it lands in the search
  // region, which announces itself, and the field's own name already ends in
  // "Ctrl+F: Focus search". Ctrl+Shift+F does announce, because the all-fields
  // mode is otherwise completely inaudible.

  testWidgets('opening the new-entry picker says what it is', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t);
    await openTypePicker(t);
    expect(
      said.where((s) => s == en.newEntryTitle),
      hasLength(1),
      reason: 'the new-entry sheet does not say what it is, exactly once: '
          '$said',
    );
    handle.dispose();
  });

  testWidgets('Android: opening the picker announces nothing', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t, android: true);
    await openTypePicker(t);
    expect(
      said,
      isEmpty,
      reason: 'TalkBack has deprecated announcement events; Android must be '
          'left to its own semantics: $said',
    );
    handle.dispose();
  });

  testWidgets('Ctrl+Shift+F says that it searches every field', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t);
    await sendCtrl(t, LogicalKeyboardKey.keyF, shift: true);
    await t.pumpAndSettle();
    expect(
      said,
      contains(en.kbSearchAllFields),
      reason: 'nothing says the search switched to all-fields mode: $said',
    );
    handle.dispose();
  });

  testWidgets('Ctrl+M says the menu opened', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t);
    await sendCtrl(t, LogicalKeyboardKey.keyM);
    await t.pumpAndSettle();
    expect(
      said,
      contains(en.tooltipMenu),
      reason: 'the overflow menu opens silently: $said',
    );
    handle.dispose();
  });

  testWidgets('Ctrl+Q says the quit confirm opened', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t, quit: true);
    await sendCtrl(t, LogicalKeyboardKey.keyQ);
    await t.pumpAndSettle();
    expect(
      said,
      contains(en.quit),
      reason: 'the quit confirm appears silently: $said',
    );
    handle.dispose();
  });

  // A shortcut that does nothing must say nothing, or a reader is told the app
  // did something it did not do. Selection mode hides the FAB and the menu
  // button, so Ctrl+N and Ctrl+M are inert there by design.
  testWidgets('an inert shortcut announces nothing (selection mode)', (
    t,
  ) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t, quit: true);
    await t.tap(find.byIcon(Icons.checklist));
    await t.pumpAndSettle();
    said.clear();
    await sendCtrl(t, LogicalKeyboardKey.keyN);
    await sendCtrl(t, LogicalKeyboardKey.keyM);
    await sendCtrl(t, LogicalKeyboardKey.keyQ);
    await t.pumpAndSettle();
    expect(
      said,
      isEmpty,
      reason: 'a shortcut that did nothing still announced itself: $said',
    );
    handle.dispose();
  });

  testWidgets('Android: the shortcuts announce nothing', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t, android: true, quit: true);
    await sendCtrl(t, LogicalKeyboardKey.keyF, shift: true);
    await sendCtrl(t, LogicalKeyboardKey.keyM);
    await sendCtrl(t, LogicalKeyboardKey.keyQ);
    await t.pumpAndSettle();
    expect(said, isEmpty, reason: 'Android announced a shortcut: $said');
    handle.dispose();
  });

  testWidgets('the same keys without Ctrl announce nothing', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t, quit: true);
    for (final key in [
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyQ,
    ]) {
      await t.sendKeyEvent(key);
    }
    await t.pumpAndSettle();
    expect(
      said,
      isEmpty,
      reason: 'a bare letter key announced a shortcut: $said',
    );
    handle.dispose();
  });

  // ── Linux only: the regions speak ────────────────────────────────────────
  // Tab moves between REGIONS, not controls, so a screen-reader user who Tabs
  // hears the newly-focused control with no idea they changed region.
  //
  // The region's name lives on its Semantics container, which Orca reads as an
  // ATK panel when focus lands inside it (round 16). Round 22 replaced this
  // with SemanticsService announcements and every one that mattered was
  // inaudible: the Linux embedder sends them as ATK "polite", and Orca discards
  // a polite notification while it is speaking — which it always is right after
  // a focus change. Reverted.
  //
  // Accepted cost: the panel is an ancestor of every row, so the name is read
  // again on each arrow press inside the entry list. That repeat is a known,
  // maintainer-accepted defect (see ARCHITECTURE.md), not a regression.

  testWidgets('each region carries its own name, in cycle order', (t) async {
    final handle = await pumpDense(t);
    // Narrow cycle: search -> folders -> chips -> list. No detail pane.
    expect(
      containerNames(t),
      containsAllInOrder([
        en.regionSearch,
        en.regionFolders,
        en.regionFilters,
        en.regionEntries,
      ]),
      reason: 'a region lost the name Orca reads when focus enters it',
    );
    handle.dispose();
  });

  testWidgets('wide: the detail pane is named once entered', (t) async {
    final handle = await pumpDense(t, surface: tablet);
    // Walk to the list and open an entry so the detail region mounts.
    for (var i = 0; i < 4; i++) {
      await tab(t);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 300));
    expect(
      containerNames(t),
      contains(en.regionDetails),
      reason: 'the detail pane has no name for Orca to read',
    );
    handle.dispose();
  });

  testWidgets('Android: no region is named', (t) async {
    final handle = await pumpDense(t, android: true);
    expect(
      containerNames(t),
      isNot(anyElement(isIn([
        en.regionSearch,
        en.regionFolders,
        en.regionFilters,
        en.regionEntries,
        en.regionDetails,
      ]))),
      reason: 'Android has no regions, so none may be named there',
    );
    handle.dispose();
  });

  // Tab must not announce anything: the region name travels on the container,
  // and a second copy as an announcement would be heard twice wherever Orca
  // did accept it.
  testWidgets('Tabbing the cycle announces nothing', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpDense(t);
    for (var i = 0; i < 4; i++) {
      await tab(t);
    }
    expect(
      said,
      isEmpty,
      reason: 'the region name is being both named and announced: $said',
    );
    handle.dispose();
  });

  // The container names the REGION, not the row. If its name were merged down,
  // every row would be read as "Entry list, Apple, …".
  testWidgets('the region name stays off the controls inside it', (t) async {
    final handle = await pumpDense(t);
    expect(labelOf(t, find.text('Apple')), contains('Apple'));
    expect(labelOf(t, find.text('Apple')), isNot(contains(en.regionEntries)));
    expect(
      labelOf(t, find.byType(FilterChip).first),
      isNot(contains(en.regionFilters)),
    );
    handle.dispose();
  });
}
