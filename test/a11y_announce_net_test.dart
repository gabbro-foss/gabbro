import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'screen_catalog.dart';
import 'test_helpers.dart';

// Net-first floor for the REST of Phase 4 — the announcement work (the new-entry
// picker's doubled labels, and the shortcuts / sheet / region entry that say
// nothing). Every test here is GREEN against the current code.
//
// Two kinds of pin, both needed:
//   * what must not regress when the change lands;
//   * what is ABSENT or WRONG today, so the red step is real and cannot be
//     claimed by an accidental match.
//
// Why this file exists at all, beyond a11y_region_net_test.dart: that file
// proves region entry works by asserting `liveRegion`, and the Linux embedder
// ignores liveRegion completely (LEARNINGS.md, proven from engine source). What
// actually reaches Orca is the NAMED CONTAINER that FocusRegion wraps each
// region in — and that container is also what repeats on every arrow press, so
// it is exactly what the announcement work will remove. Nothing pinned it.
// Without section C below, that removal would stay green here and go silent on
// hardware, which is how round 19 was lost.

/// A vault list with folders and six entries, so every region exists and the
/// entry list has somewhere to arrow to. [quit] wires onQuit, without which
/// Ctrl+Q is inert by design.
VaultListScreen netVaultList({bool android = false, bool quit = false}) {
  const titles = ['Apple', 'Banana', 'Cherry', 'Date', 'Elder', 'Fig'];
  return VaultListScreen(
    vaultPath: '/tmp/probe.gabbro',
    vaultAlias: 'Net',
    isAndroid: android,
    yubikeyRecords: const [],
    listEntries: () => [
      for (var i = 0; i < titles.length; i++)
        EntrySummaryData(
          id: 'e$i',
          entryType: 'login',
          title: titles[i],
          folder: ['Work', 'Personal'][i % 2],
          searchBlob: titles[i].toLowerCase(),
        ),
    ],
    listFolders: () => const ['Work', 'Personal'],
    getEntryFn: (_) => login('secret', 'notes'),
    onDeleteEntryFn: (_) async {},
    onRefreshFn: () {},
    onLock: () {},
    onQuit: quit ? () {} : null,
  );
}

Future<SemanticsHandle> pumpNet(
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
    appShell(netVaultList(android: android, quit: quit), textScale: 1.0),
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

Future<void> tabTo(WidgetTester t, int stops) async {
  for (var i = 0; i < stops; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump(const Duration(milliseconds: 300));
  }
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

/// The English strings, to assert against what a reader would actually hear.
final en = lookupAppLocalizations(const Locale('en'));

/// The six entry-type names the picker offers, in the order it lists them.
List<String> get typeNames => [
  en.entryTypePassword,
  en.entryTypeNote,
  en.entryTypeIdentity,
  en.entryTypeCard,
  en.entryTypeFile,
  en.entryTypeCustom,
];

/// Every region name that exists in the narrow cycle. Detail is wide-only and
/// mounts only once an entry is selected, so it is asserted separately.
List<String> get narrowRegionNames => [
  en.regionSearch,
  en.regionFolders,
  en.regionFilters,
  en.regionEntries,
];

void main() {
  // ── A. The announcement recorder ─────────────────────────────────────────
  // Everything in section B/D asserts that NOTHING is announced. If the
  // recorder never saw an announcement in the first place, all of those pass
  // forever and prove nothing. This pins that it sees one when there is one.

  testWidgets('the recorder captures an announcement when one is made', (
    t,
  ) async {
    final said = recordAnnouncements(t);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    // sendAnnouncement, not the deprecated announce: same channel and payload,
    // but it is what the Phase 4 code has to call (announce is deprecated as of
    // 3.35 and is incompatible with multiple windows).
    await SemanticsService.sendAnnouncement(t.view, 'probe', TextDirection.ltr);
    expect(
      said,
      ['probe'],
      reason: 'the recorder cannot see SemanticsService.announce, so every '
          '"announces nothing" pin in this file is void',
    );
  });

  // ── B. The new-entry type picker ─────────────────────────────────────────
  // Ctrl+N's sheet reads every type twice: the row icon carries the type as
  // its semanticLabel and the row title says it again. Only the icon sizes
  // were ever tested (vault_list_menu_test), never what a reader hears.

  for (final android in const [false, true]) {
    final who = android ? 'Android' : 'Linux';
    for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
      // Green now and after: dropping one of the two names must not drop both,
      // or the sheet becomes six unnamed rows.
      testWidgets('$who $name: the picker names every entry type', (t) async {
        final handle = await pumpNet(t, surface: surface, android: android);
        await openTypePicker(t);
        final heard = subtreeLabels(t, find.byType(BottomSheet)).join(' | ');
        for (final type in typeNames) {
          expect(
            occurrencesOf(heard, type),
            greaterThan(0),
            reason: 'the picker no longer names the "$type" type at all',
          );
        }
        handle.dispose();
      });

      // The "says it twice" defect that used to be pinned here has been fixed
      // (the row icon's semanticLabel is gone); the exactly-once assertion now
      // lives in a11y_semantics_test.dart, which owns the fix.
    }
  }

  testWidgets('picking a type opens the create screen for that type', (
    t,
  ) async {
    final handle = await pumpNet(t);
    await openTypePicker(t);
    await t.tap(find.widgetWithText(ListTile, en.entryTypeNote));
    await t.pumpAndSettle();
    expect(
      t.widget<CreateEntryScreen>(find.byType(CreateEntryScreen)).entryType,
      'Note',
      reason: 'the picker stopped passing the chosen type through',
    );
    handle.dispose();
  });

  testWidgets('Esc closes the picker and creates nothing', (t) async {
    final handle = await pumpNet(t);
    await openTypePicker(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'Esc no longer closes the new-entry picker',
    );
    expect(find.byType(CreateEntryScreen), findsNothing);
    handle.dispose();
  });

  // ── C. The named container is the region mechanism on Linux ──────────────
  // Orca is handed a node's NAME and nothing else. It says "Entry list" when
  // focus lands on a row because the row sits inside a named container, read as
  // an ATK panel — not because anything is a live region, which Linux ignores.
  //
  // Round 22 replaced this with SemanticsService announcements and every one
  // that mattered was inaudible on hardware: the embedder sends announcements
  // as ATK "polite", and Orca discards a polite notification while it is
  // speaking, which it always is straight after a focus change. These pin the
  // container so that swap cannot be made again without going red first.

  for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
    testWidgets('Linux $name: each region is a named container', (t) async {
      final handle = await pumpNet(t, surface: surface);
      final containers = containerNames(t);
      for (final region in narrowRegionNames) {
        expect(
          containers.where((l) => l == region).length,
          1,
          reason: 'the "$region" region is no longer a named container, which '
              'is the only thing Orca reads when focus enters it',
        );
      }
      handle.dispose();
    });
  }

  testWidgets('wide: the detail pane is a named container once entered', (
    t,
  ) async {
    final handle = await pumpNet(t, surface: tablet);
    // search -> folder -> chips -> list, then open the row so detail mounts.
    await tabTo(t, 4);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 300));
    expect(
      containerNames(t).where((l) => l == en.regionDetails).length,
      1,
      reason: 'the detail pane is no longer a named container',
    );
    handle.dispose();
  });

  // The region name must not reach the row by any route. If it were merged down,
  // every row would be read as "Entry list, Apple, …" on every move.
  testWidgets('the region name is not merged into a row name', (t) async {
    final handle = await pumpNet(t);
    expect(
      labelOf(t, find.text('Apple')),
      isNot(contains(en.regionEntries)),
      reason: 'the entry row now carries the region name too, so a reader '
          'hears it on every single row',
    );
    handle.dispose();
  });

  // D5: regions do not exist on Android, so none of these names may appear
  // there — before or after the change.
  for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
    testWidgets('Android $name: no region is a named container', (t) async {
      final handle = await pumpNet(t, surface: surface, android: true);
      final containers = containerNames(t);
      for (final region in [...narrowRegionNames, en.regionDetails]) {
        expect(
          containers,
          isNot(contains(region)),
          reason: 'Android has no regions, so "$region" must not be a named '
              'container there',
        );
      }
      handle.dispose();
    });
  }

  // ── D. No shortcut says the same thing twice ─────────────────────────────
  // What each shortcut announces is owned by a11y_semantics_test.dart. What a
  // per-shortcut test cannot see is the OVERLAP: a shortcut that also moves
  // focus would fire its own announcement on top of the region name the
  // container already gives. Ctrl+F is the case that decided it — it announces
  // nothing of its own, because it lands in the search region (named) and the
  // field's own name already ends in "Ctrl+F: Focus search".

  testWidgets('Ctrl+F announces nothing of its own', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpNet(t);
    await sendCtrl(t, LogicalKeyboardKey.keyF);
    await t.pumpAndSettle();
    expect(
      said,
      isEmpty,
      reason: 'Ctrl+F speaks on top of the region name and the box name it '
          'already triggers: $said',
    );
    handle.dispose();
  });

  // Hardware round 22: this is the one the maintainer heard and approved —
  // "Search all fields" alone, nothing else competing with it.
  testWidgets('Ctrl+Shift+F announces the mode, once, and nothing else', (
    t,
  ) async {
    final said = recordAnnouncements(t);
    final handle = await pumpNet(t);
    await sendCtrl(t, LogicalKeyboardKey.keyF, shift: true);
    await t.pumpAndSettle();
    expect(
      said,
      [en.kbSearchAllFields],
      reason: 'Ctrl+Shift+F did not announce the all-fields mode exactly '
          'once, on its own: $said',
    );
    handle.dispose();
  });

  // Ctrl+N and Ctrl+M open something over the list without moving focus into
  // another region, so each must produce exactly one announcement.
  for (final (name, key, expected) in [
    ('Ctrl+N', LogicalKeyboardKey.keyN, 'newEntry'),
    ('Ctrl+M', LogicalKeyboardKey.keyM, 'menu'),
  ]) {
    testWidgets('$name announces once, not twice', (t) async {
      final said = recordAnnouncements(t);
      final handle = await pumpNet(t);
      await sendCtrl(t, key);
      await t.pumpAndSettle();
      expect(
        said,
        [expected == 'newEntry' ? en.newEntryTitle : en.tooltipMenu],
        reason: '$name did not announce exactly one thing: $said',
      );
      handle.dispose();
    });
  }

  testWidgets('Ctrl+Q announces once, not twice', (t) async {
    final said = recordAnnouncements(t);
    final handle = await pumpNet(t, quit: true);
    await sendCtrl(t, LogicalKeyboardKey.keyQ);
    await t.pumpAndSettle();
    expect(
      said,
      [en.quit],
      reason: 'Ctrl+Q did not announce exactly one thing: $said',
    );
    handle.dispose();
  });

  // ── E. Ticking an entry in selection mode ────────────────────────────────
  // Hardware round 29, listening only: ticking a row says NOTHING about the
  // state. Orca speaks "space" — that is its echo of the key, not the tick.
  // The state is only heard on re-focus, where the merged row node reads the
  // title and then the tick state.
  //
  // So this is the shape rounds 26-27 already solved: a change under a control
  // that ALREADY holds focus. A name that changes under the focus is not
  // re-read, and ticking moves no focus, so an announcement survives.
  //
  // What it says is the selection count the app bar is already showing, which
  // exists in every locale and goes up or down with the tick. Section E6 pins
  // it to the app bar's own text so the two cannot drift apart.
  //
  // Both layouts build their own rows and their own checkbox, and the toggle
  // exists three times over (narrow checkbox, narrow row tap, and the wide
  // layout's onToggleSelection callback) — so every case runs on both surfaces.

  Future<void> enterSelectionMode(WidgetTester t) async {
    await t.tap(find.byTooltip(en.tooltipSelectEntries));
    await t.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester t, String title) async {
    await t.tap(find.text(title).first);
    await t.pumpAndSettle();
  }

  for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
    testWidgets('Linux $name: ticking a row announces the new count', (
      t,
    ) async {
      final said = recordAnnouncements(t);
      final handle = await pumpNet(t, surface: surface);
      await enterSelectionMode(t);
      await tapRow(t, 'Apple');
      expect(
        said,
        [en.selectedCount(1)],
        reason: 'ticking a row said nothing about the tick — the state lives '
            'on the row a reader is already sitting on, so it is only heard '
            'on re-focus: $said',
      );
      handle.dispose();
    });

    testWidgets('Linux $name: unticking announces the reduced count', (
      t,
    ) async {
      final said = recordAnnouncements(t);
      final handle = await pumpNet(t, surface: surface);
      await enterSelectionMode(t);
      await tapRow(t, 'Apple');
      await tapRow(t, 'Banana');
      await tapRow(t, 'Apple');
      expect(
        said,
        [en.selectedCount(1), en.selectedCount(2), en.selectedCount(1)],
        reason: 'taking a tick off must be as audible as putting one on, or '
            'the count is the only way to tell them apart: $said',
      );
      handle.dispose();
    });

    testWidgets('Linux $name: ticking the checkbox itself announces too', (
      t,
    ) async {
      final said = recordAnnouncements(t);
      final handle = await pumpNet(t, surface: surface);
      await enterSelectionMode(t);
      await t.tap(find.byType(Checkbox).first);
      await t.pumpAndSettle();
      expect(
        said,
        [en.selectedCount(1)],
        reason: 'the checkbox is a separate tick path from the row tap and '
            'must not be the silent one: $said',
      );
      handle.dispose();
    });

    // Green now and after. Outside selection mode a row tap OPENS the entry —
    // a focus change, which is the one thing an announcement cannot survive
    // (round 22). Speaking here would talk over what the user moved to.
    testWidgets('Linux $name: opening an entry announces nothing', (t) async {
      final said = recordAnnouncements(t);
      final handle = await pumpNet(t, surface: surface);
      await tapRow(t, 'Apple');
      expect(
        said,
        isEmpty,
        reason: 'opening an entry now speaks over the screen the user just '
            'moved to: $said',
      );
      handle.dispose();
    });

    // Green now and after: D5. TalkBack reads the checkbox state from the
    // widget itself and announcements make it drop its queue.
    testWidgets('Android $name: ticking announces nothing', (t) async {
      final said = recordAnnouncements(t);
      final handle = await pumpNet(t, surface: surface, android: true);
      await enterSelectionMode(t);
      await tapRow(t, 'Apple');
      expect(
        said,
        isEmpty,
        reason: 'Android must stay silent — TalkBack already reads the tick, '
            'and an announcement makes it drop its speech queue: $said',
      );
      handle.dispose();
    });
  }

  // E6. The spoken text and the app bar's text must be the same string, not two
  // literals that agree today. If the bar's wording is ever changed, this fails
  // rather than letting a reader hear something the screen no longer shows.
  testWidgets('Linux: the tick announcement is the app bar text itself', (
    t,
  ) async {
    final said = recordAnnouncements(t);
    final handle = await pumpNet(t);
    await enterSelectionMode(t);
    await tapRow(t, 'Apple');
    final barTitle = t
        .widget<Text>(
          find
              .descendant(of: find.byType(AppBar), matching: find.byType(Text))
              .first,
        )
        .data;
    expect(
      said.single,
      barTitle,
      reason: 'the tick speaks something other than what the app bar shows, '
          'so the two can drift: $said vs "$barTitle"',
    );
    handle.dispose();
  });
}
