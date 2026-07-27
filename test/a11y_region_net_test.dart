import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'screen_catalog.dart';
import 'test_helpers.dart';

// Net-first floor for Phase 4 (the a11y layer). Every test here is GREEN against
// the current code: it pins what Phase 4 must not break, and pins the absence of
// what Phase 4 will add, so the red step is real and cannot be claimed by an
// accidental match.
//
// The catalog-wide sweeps (contrast, tap size, labels) live in a11y_net_test.dart.
// This file holds the targeted pins that a sweep cannot express.
//
// Not repeated here: the alphabet index bar's per-letter labels and its
// exclusion of absent letters / the gap ellipsis are already pinned in
// alphabet_index_bar_test.dart.

/// A vault list with folders and two entries, so the folder region exists and
/// the entry rows are addressable by title.
VaultListScreen vaultList({bool isAndroid = false}) => VaultListScreen(
  vaultPath: '/tmp/probe.gabbro',
  isAndroid: isAndroid,
  yubikeyRecords: const [],
  listEntries: () => const [
    EntrySummaryData(
      id: 'e1',
      entryType: 'login',
      title: 'Alpha',
      folder: 'Work',
      searchBlob: '',
    ),
    EntrySummaryData(
      id: 'e2',
      entryType: 'login',
      title: 'Bravo',
      folder: 'Work',
      searchBlob: '',
    ),
  ],
  listFolders: () => const ['Work', 'Personal'],
  onRefreshFn: () {},
);

Future<SemanticsHandle> pumpVaultList(
  WidgetTester t, {
  bool isAndroid = false,
  Surface surface = phone,
  ThemeChoice theme = ThemeChoice.system,
  bool highContrast = false,
}) async {
  t.view.physicalSize = surface.physical;
  t.view.devicePixelRatio = surface.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final handle = t.ensureSemantics();
  await t.pumpWidget(
    appShell(
      vaultList(isAndroid: isAndroid),
      textScale: 1.0,
      theme: theme,
      highContrast: highContrast,
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return handle;
}

/// The grey placeholder inside the empty search box, in the test locale.
final searchPlaceholder =
    lookupAppLocalizations(const Locale('en')).searchEntriesHint;

/// The style actually applied to that placeholder under one platform/theme.
Future<TextStyle?> placeholderStyleUnder(
  WidgetTester t, {
  required bool isAndroid,
  required ThemeChoice theme,
  required bool highContrast,
}) async {
  final handle = await pumpVaultList(
    t,
    isAndroid: isAndroid,
    theme: theme,
    highContrast: highContrast,
  );
  final style = t.widget<Text>(find.text(searchPlaceholder).first).style;
  handle.dispose();
  return style;
}

/// WCAG relative luminance.
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colours, 1.0 to 21.0.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// The ThemeData the app actually builds under [theme] / [highContrast].
Future<ThemeData> themeUnder(
  WidgetTester t, {
  required ThemeChoice theme,
  required bool highContrast,
}) async {
  late ThemeData captured;
  await t.pumpWidget(
    KeyedSubtree(
      // Unique key per combo: without it GabbroApp's State is reused across
      // pumps in one test and the second render keeps the first settings.
      key: ValueKey('$theme-$highContrast'),
      child: appShell(
        Builder(
          builder: (ctx) {
            captured = Theme.of(ctx);
            return const SizedBox();
          },
        ),
        textScale: 1.0,
        theme: theme,
        highContrast: highContrast,
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return captured;
}

void main() {
  // Guard on the guard. Every "no live region" pin below asserts an ABSENCE, so
  // if the tree walk ever stopped finding nodes they would report green forever
  // and prove nothing. This pins that the walk sees a live region when there is
  // one.
  testWidgets('the tree walk detects a live region when one exists', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Semantics(
              liveRegion: true,
              label: 'announced',
              child: const Text('x'),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(
      allSemanticsNodes(
        t,
      ).where((n) => n.getSemanticsData().flagsCollection.isLiveRegion),
      isNotEmpty,
      reason: 'the walk cannot see a live region, so the absence pins are void',
    );
    handle.dispose();
  });

  // ── B. What a Semantics wrapper can strip ────────────────────────────────
  // Phase 4 wraps these controls to give them labels and hints. Wrapping has
  // already cost this app a control's actions once: the text-size slider lost
  // its increase/decrease actions to a Semantics/MergeSemantics wrapper and
  // became unadjustable under TalkBack. These pin what each control exposes
  // TODAY, so the same class of regression fails here instead of on hardware.

  testWidgets('search field keeps its text-field actions and hint', (t) async {
    final handle = await pumpVaultList(t);
    // The isTextField flag lives on the EditableText's node, not on the
    // TextField wrapper above it.
    final data = t
        .getSemantics(find.byType(EditableText).first)
        .getSemanticsData();
    expect(
      data.flagsCollection.isTextField,
      isTrue,
      reason: 'the search box stopped being a text field to a screen reader',
    );
    // The decoration's hintText is what currently NAMES the box to a screen
    // reader (Flutter maps it to the label, not the hint), so losing it would
    // leave the field anonymous.
    expect(
      data.label,
      isNotEmpty,
      reason: 'the search box lost the name a screen reader reads',
    );
    // On Linux the name carries everything: what the box IS and what it does.
    // A hint here would be dead text — the Linux embedder never reads one
    // (round 16, LEARNINGS.md). Android's hint is pinned in section F.
    expect(
      data.hint,
      isEmpty,
      reason: 'the search box carries a hint on Linux, where nothing reads '
          'one — the text belongs in the name',
    );
    handle.dispose();
  });

  testWidgets('filter chips keep tap action, selected state and name', (
    t,
  ) async {
    final handle = await pumpVaultList(t);
    final data = t
        .getSemantics(find.byType(FilterChip).first)
        .getSemanticsData();
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'a filter chip stopped being tappable to a screen reader',
    );
    expect(
      data.flagsCollection.isSelected,
      isNot(Tristate.none),
      reason: 'a filter chip no longer reports whether it is on or off',
    );
    expect(data.label, isNotEmpty, reason: 'a filter chip lost its name');
    handle.dispose();
  });

  testWidgets('narrow: an entry row keeps its tap action and its title', (
    t,
  ) async {
    final handle = await pumpVaultList(t);
    final data = t.getSemantics(find.text('Alpha')).getSemanticsData();
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'the entry row stopped being tappable to a screen reader',
    );
    expect(data.label, contains('Alpha'));
    handle.dispose();
  });

  testWidgets('wide: an entry row keeps its tap action and its title', (
    t,
  ) async {
    final handle = await pumpVaultList(t, surface: tablet);
    final data = t.getSemantics(find.text('Alpha')).getSemanticsData();
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'the two-pane entry row stopped being tappable',
    );
    expect(data.label, contains('Alpha'));
    handle.dispose();
  });

  testWidgets('folder selector keeps its tap action and its name', (t) async {
    final handle = await pumpVaultList(t);
    final data = t
        .getSemantics(find.byType(DropdownButton<String>).first)
        .getSemanticsData();
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'the folder selector stopped being tappable to a screen reader',
    );
    expect(data.label, isNotEmpty, reason: 'the folder selector lost its name');
    handle.dispose();
  });

  // ── C. A region is silent unless it is named and focused ────────────────
  // Phase 4 gives the vault list's regions a name and announces the focused
  // one. These two pin the other side of that: an UNLABELLED region stays
  // silent, and a labelled one announces only while it holds focus — otherwise
  // a screen reader would read region names it was never meant to, or announce
  // every region at once.

  testWidgets('an unlabelled region contributes no name of its own', (t) async {
    t.view.physicalSize = phone.physical;
    t.view.devicePixelRatio = phone.dpr;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      appShell(screens['focus_region (focused)']!(), textScale: 1.0),
    );
    await t.pump(const Duration(milliseconds: 300));

    final labels = allSemanticsNodes(t)
        .map((n) => n.getSemanticsData().label)
        .where((l) => l.isNotEmpty)
        .toList();
    expect(
      labels,
      ['A focused region long enough to stress the row'],
      reason: 'only the button inside the region is named; a region with no '
          'label of its own must stay silent',
    );
    handle.dispose();
  });

  testWidgets('an untouched vault list announces nothing', (t) async {
    final handle = await pumpVaultList(t);
    expect(
      liveRegionLabels(t),
      isEmpty,
      reason: 'a region announced itself before the user Tabbed into one',
    );
    handle.dispose();
  });

  // ── D. The D5 platform split must survive Phase 4 ────────────────────────
  // Regions exist only on Linux, so the region announcement must never reach
  // Android. These are green now and must stay green: they are the negative
  // half of the Phase 4 work, mirroring R1/R2/R3 in keyboard_region_chips_test.

  for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
    testWidgets('Android $name: no live region on the vault list', (t) async {
      final handle = await pumpVaultList(
        t,
        isAndroid: true,
        surface: surface,
      );
      expect(
        liveRegionLabels(t),
        isEmpty,
        reason: 'Android has no regions, so nothing may announce one',
      );
      handle.dispose();
    });
  }

  // Wrapping a region in another widget must not change the widget tree's
  // SHAPE across a rebuild: that disposes the focus node inside it and drops
  // focus. It has happened here before — a row decoration flipped between null
  // and non-null and Enter silently moved focus to a neighbouring row.
  testWidgets('a focused region keeps focus across a rebuild', (t) async {
    final handle = await pumpVaultList(t);
    await t.tap(find.byType(FilterChip).first);
    await t.pump();
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull, reason: 'tapping a chip did not focus anything');

    // Type into the search box to force a setState rebuild of the whole list.
    await t.enterText(find.byType(TextField).first, 'Al');
    await t.pump(const Duration(milliseconds: 300));

    expect(
      FocusManager.instance.primaryFocus,
      isNotNull,
      reason: 'the rebuild dropped focus out of the tree entirely',
    );
    handle.dispose();
  });

  // ── E. The focus frame must be visible, not just present ─────────────────
  // The frame is painted by a CustomPainter, so textContrastGuideline cannot
  // see it — it only ever measures text. A keyboard user who cannot make out
  // the frame has no idea which region they are in, in whichever theme they
  // use. WCAG asks 3:1 for a non-text UI component boundary.
  // Guard on the guard: the ratio maths must produce the known WCAG extremes,
  // or a frame that is genuinely invisible could still score above 3:1.
  test('the contrast ratio maths matches the known WCAG extremes', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21.0, 0.01));
    expect(contrastRatio(Colors.white, Colors.white), closeTo(1.0, 0.01));
  });

  for (final (name, theme, hc) in const [
    ('light', ThemeChoice.light, false),
    ('dark', ThemeChoice.dark, false),
    ('high-contrast light', ThemeChoice.light, true),
    ('high-contrast dark', ThemeChoice.dark, true),
  ]) {
    testWidgets('focus frame is visible against its background ($name)', (
      t,
    ) async {
      final theme0 = await themeUnder(t, theme: theme, highContrast: hc);
      // focus_region.dart paints the frame in colorScheme.primary, over the
      // scaffold background the regions sit on.
      final ratio = contrastRatio(
        theme0.colorScheme.primary,
        theme0.scaffoldBackgroundColor,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason: 'the focus frame is only ${ratio.toStringAsFixed(2)}:1 against '
            'the background in $name — a keyboard user cannot see which '
            'region they are in',
      );
    });
  }

  // ── H. An entry row must still say what TYPE it is ───────────────────────
  // The type reaches a screen reader twice today (the row icon carries it as
  // its label and the subtitle repeats it). Removing one of the two must not
  // remove both: the type is how a user tells a card from a note without
  // opening it. Green now, and green after the fix.

  for (final platform in const [true, false]) {
    final who = platform ? 'Android' : 'Linux';
    for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
      testWidgets('$who $name: an entry row still names its type', (t) async {
        final handle = await pumpVaultList(
          t,
          isAndroid: platform,
          surface: surface,
        );
        expect(
          labelOf(t, find.text('Alpha')),
          contains('login'),
          reason: 'the row no longer says what kind of entry it is',
        );
        handle.dispose();
      });
    }
  }

  // ── G. The search placeholder must look identical on both platforms ──────
  // The grey "Search entries…" text is also the box's NAME to a screen reader.
  // To speak that name before what the box does, Linux hands the placeholder
  // to Flutter as a widget — and Flutter then stops styling it. So Linux has
  // to restate the styling itself. These compare the Linux placeholder against
  // the Android one, which still goes through Flutter's own path: green before
  // the change (one shared path), and green after it only if the restatement
  // matches exactly. A wrong shade fails here instead of on hardware.

  for (final (name, theme, hc) in const [
    ('light', ThemeChoice.light, false),
    ('dark', ThemeChoice.dark, false),
    ('high-contrast light', ThemeChoice.light, true),
    ('high-contrast dark', ThemeChoice.dark, true),
  ]) {
    testWidgets('the search placeholder is styled the same on both platforms '
        '($name)', (t) async {
      final android = await placeholderStyleUnder(
        t,
        isAndroid: true,
        theme: theme,
        highContrast: hc,
      );
      final linux = await placeholderStyleUnder(
        t,
        isAndroid: false,
        theme: theme,
        highContrast: hc,
      );
      // Guard on the guard: comparing two nulls would pass and prove nothing.
      expect(
        android,
        isNotNull,
        reason: 'the placeholder carries no style at all, so this pin is void',
      );
      expect(
        linux,
        equals(android),
        reason: 'the search placeholder no longer looks the same on Linux as '
            'it does on Android — it is meant to stay grey, not read as '
            'typed text',
      );
    });
  }

  // ── F. Android keeps its hints ───────────────────────────────────────────
  // Round 16 (Orca) proved Linux never receives a semantics HINT at all: the
  // Linux embedder reads only the label. The fix moves the outcome text into
  // the label ON LINUX. TalkBack passed 4/4 with the hint, so Android must be
  // left exactly as it is — these pin that, green before the fix and after.
  // See LEARNINGS.md, "On Linux a screen reader gets the semantics NAME".

  testWidgets('Android: the search box keeps its hint', (t) async {
    final handle = await pumpVaultList(t, isAndroid: true);
    expect(
      hintOf(t, find.byType(EditableText).first),
      isNotEmpty,
      reason: 'the Linux fix stripped the hint TalkBack reads',
    );
    handle.dispose();
  });

  // Android has no keyboard to press them on, so naming the shortcuts there
  // would send a TalkBack user looking for keys that do not exist.
  testWidgets('Android: the search box names no keyboard shortcut', (t) async {
    final handle = await pumpVaultList(t, isAndroid: true);
    expect(
      hintOf(t, find.byType(EditableText).first),
      isNot(contains('Ctrl')),
      reason: 'Android is told about a key combination it cannot press',
    );
    handle.dispose();
  });

  testWidgets('Android: a filter chip keeps its hint', (t) async {
    final handle = await pumpVaultList(t, isAndroid: true);
    expect(
      hintOf(t, find.byType(FilterChip).first),
      isNotEmpty,
      reason: 'the Linux fix stripped the hint TalkBack reads',
    );
    handle.dispose();
  });

  // Both layouts build their own folder selector and their own entry row, so
  // each has its own call site and each can regress on its own.
  for (final (name, surface) in const [('narrow', phone), ('wide', tablet)]) {
    testWidgets('Android $name: the folder selector keeps its hint', (t) async {
      final handle = await pumpVaultList(
        t,
        isAndroid: true,
        surface: surface,
      );
      expect(
        hintOf(t, find.byType(DropdownButton<String>).first),
        isNotEmpty,
        reason: 'the Linux fix stripped the hint TalkBack reads',
      );
      handle.dispose();
    });

    testWidgets('Android $name: an entry row keeps its hint', (t) async {
      final handle = await pumpVaultList(
        t,
        isAndroid: true,
        surface: surface,
      );
      expect(
        hintOf(t, find.text('Alpha')),
        isNotEmpty,
        reason: 'the Linux fix stripped the hint TalkBack reads',
      );
      handle.dispose();
    });

    // Selection mode taps the row to tick it, so "opens this entry" would be a
    // lie. Guard on the guard: the pin directly above proves the same lookup
    // finds a hint when there is one, so this absence is real.
    testWidgets('Android $name: a row in selection mode has no hint', (t) async {
      final handle = await pumpVaultList(
        t,
        isAndroid: true,
        surface: surface,
      );
      await t.tap(find.byIcon(Icons.checklist));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        hintOf(t, find.text('Alpha')),
        isEmpty,
        reason: 'a tickable row still claims that it opens the entry',
      );
      // The checkbox carries the entry title, so the row is not read as a bare
      // "tick box". A merge wrapper has swallowed this label once before.
      expect(
        labelOf(t, find.text('Alpha')),
        contains('Alpha'),
        reason: 'the row in selection mode lost the entry title',
      );
      handle.dispose();
    });
  }
}
