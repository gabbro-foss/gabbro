import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/focus_region.dart';

import 'screen_catalog.dart';

// Phase 3 — the region Tab-cycle (Linux-desktop only). This is the SPEC net for
// the maintainer-approved cycle, rebuilt after round-10 hardware FAIL where the
// old body-scoped Actions override never fired on real hardware and the sparse
// net couldn't see it. Mechanism now: Tab/Shift+Tab is intercepted GLOBALLY
// (main.dart _onKeyEvent, like Ctrl+L/F) and routed to the vault list's cycle.
//
// Cycle (narrow): search -> folder(if any) -> chips -> list -> wrap.
// Cycle (wide): ... -> list -> detail(skip if no entry selected) -> wrap.
// Excluded everywhere: FAB, select-entries, lock, menu, alphabet bar
// (the bar is a touch scroll-shortcut; Up/Down in the list already covers it — DRY),
// and the search-mode toggle icon (Ctrl+F / Ctrl+Shift+F reach + set it directly — DRY).
//
// The fixture is DENSE (3 folders, 7 chips, 12 lettered entries) so a real
// region-jump and plain per-control traversal give different stop sequences —
// the round-10 net was blind because its fixture was too thin.

List<EntrySummaryData> _denseEntries() {
  const titles = [
    'Apple', 'Banana', 'Cherry', 'Date', 'Elder', 'Fig',
    'Grape', 'Honey', 'Iris', 'Jam', 'Kiwi', 'Lemon',
  ];
  return [
    for (var i = 0; i < titles.length; i++)
      EntrySummaryData(
        id: 'e$i',
        entryType: 'login',
        title: titles[i],
        folder: ['Work', 'Personal', 'Archive'][i % 3],
        searchBlob: titles[i].toLowerCase(),
      ),
  ];
}

Widget _denseVaultList({
  bool android = false,
  List<String> folders = const ['Work', 'Personal', 'Archive'],
}) => VaultListScreen(
  vaultPath: '/tmp/probe.gabbro',
  vaultAlias: 'Dense',
  isAndroid: android,
  yubikeyRecords: const [],
  listEntries: _denseEntries,
  listFolders: () => folders,
  getEntryFn: (_) => login('secret', 'notes'),
  onDeleteEntryFn: (_) async {},
  onRefreshFn: () {},
);

/// Canonical name of the currently-focused Tab stop, read from the WIDGET the
/// user can see holds focus — never from a FocusNode debugLabel. Labels are
/// assigned inside an assert, so they exist in this (debug) test run and are
/// null in the release build the maintainer hardware-tests; a label-based net
/// agrees with label-based production code and both are blind together. That is
/// how round 11 shipped green. See also test/no_debug_only_state_test.dart.
String _stop() {
  final n = FocusManager.instance.primaryFocus;
  if (n == null) return 'none';
  final ctx = n.context;
  if (ctx == null) return 'other';
  if (ctx.findAncestorWidgetOfExactType<FloatingActionButton>() != null) {
    return 'fab';
  }
  // The search field is the node with an EditableText above it; the search-mode
  // toggle is the other focusable inside the same TextField.
  if (ctx.findAncestorStateOfType<EditableTextState>() != null) return 'search';
  if (ctx.findAncestorWidgetOfExactType<TextField>() != null) return 'searchtype';
  if (ctx.findAncestorWidgetOfExactType<DropdownButton<String>>() != null) {
    return 'folder';
  }
  if (ctx.findAncestorWidgetOfExactType<FilterChip>() != null) return 'chips';
  // Detail before list: the detail pane contains ListTiles of its own.
  if (ctx.findAncestorWidgetOfExactType<EntryDetailScreen>() != null) {
    return 'detail';
  }
  if (ctx.findAncestorWidgetOfExactType<ListTile>() != null) return 'list';
  if (ctx.findAncestorWidgetOfExactType<AppBar>() != null) return 'appbar';
  return 'other';
}

/// Make this debug test run like a RELEASE build for focus purposes: null every
/// FocusNode debugLabel in the tree (the setter is a no-op in release, so this
/// is the state the user's machine is always in). Called from [_pump], so the
/// whole net is release-shaped.
void _stripDebugLabels(WidgetTester t) {
  for (final w in t.allWidgets) {
    if (w is Focus) w.focusNode?.debugLabel = null; // FocusScope extends Focus
  }
}

bool _frameShown(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((c) => c.foregroundPainter is FocusFramePainter);

Future<void> _tab(WidgetTester t, {bool shift = false}) async {
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pump();
}

/// Press Tab (or Shift+Tab) [count] times, recording the stop after each.
Future<List<String>> _walk(
  WidgetTester t,
  int count, {
  bool shift = false,
}) async {
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    await _tab(t, shift: shift);
    out.add(_stop());
  }
  return out;
}

Future<void> _pump(WidgetTester t, Surface surface, Widget screen) async {
  // The region cycle gates on VaultListScreen.isAndroid (false in the fixture),
  // not TargetPlatform, so no platform override is needed — and setting one leaks
  // past the per-test foundation-invariant check (addTearDown runs too late).
  t.view.physicalSize = surface.physical;
  t.view.devicePixelRatio = surface.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(appShell(screen, textScale: 1.0));
  await t.pump(const Duration(milliseconds: 300));
  _stripDebugLabels(t);
}

// 'rail' was here too, until the nav rail was removed — the widget is gone, so
// _stop() can no longer report it and an entry for it would guard nothing.
const _excluded = {'fab', 'appbar'};

const _cycleStops = {'search', 'folder', 'chips', 'list', 'detail'};

/// True while focus is anywhere inside the region cycle. Esc must clear this
/// (KEYBOARD_NAV: Esc is the only way back to the Unfocused state).
bool _inCycle() => _cycleStops.contains(_stop());

Future<void> _esc(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pump();
}

Future<void> _enter(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump(const Duration(milliseconds: 300));
}

/// Down-arrow within the focused region (Flutter's directional traversal).
Future<void> _down(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await t.pump();
}

/// Title of the entry row that currently holds focus, '' if focus is elsewhere.
String _focusedEntryTitle(WidgetTester t) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  final title = ctx?.findAncestorWidgetOfExactType<ListTile>()?.title;
  return title is Text ? (title.data ?? '') : '';
}

void main() {
  group('narrow region Tab-cycle', () {
    testWidgets('Tab from cold start enters the cycle at search', (t) async {
      await _pump(t, phone, _denseVaultList());
      await _tab(t);
      expect(_stop(), 'search',
          reason: 'first Tab enters the cycle, not an app-bar button');
    });

    testWidgets('forward cycle is one stop per region, in order, wrapping',
        (t) async {
      await _pump(t, phone, _denseVaultList());
      final seq = await _walk(t, 5);
      expect(seq, [
        'search',
        'folder',
        'chips',
        'list',
        'search', // wrap
      ]);
    });

    testWidgets('the cycle still steps when no debug labels exist (release)',
        (t) async {
      // The round-11 hardware bug in one test: with labels stripped (the
      // permanent state of a release build) Tab #1 landed on search and every
      // later Tab landed on search again, because the current-stop lookup read
      // a label that is null there. _pump already strips; re-strip after the
      // first Tab so nothing can quietly re-introduce one.
      await _pump(t, phone, _denseVaultList());
      await _tab(t);
      expect(_stop(), 'search');
      _stripDebugLabels(t);
      final seq = await _walk(t, 3);
      expect(seq, ['folder', 'chips', 'list'],
          reason: 'region identity must not depend on FocusNode.debugLabel');
    });

    testWidgets('Shift+Tab reverses the cycle', (t) async {
      await _pump(t, phone, _denseVaultList());
      final seq = await _walk(t, 5, shift: true);
      expect(seq, [
        'list',
        'chips',
        'folder',
        'search',
        'list', // wrap backwards
      ]);
    });

    testWidgets('FAB, app-bar buttons and rail are never in the cycle',
        (t) async {
      await _pump(t, phone, _denseVaultList());
      final seq = await _walk(t, 12);
      for (final s in seq) {
        expect(_excluded.contains(s), isFalse,
            reason: 'excluded control "$s" must not be a Tab stop');
      }
    });

    testWidgets('the focus frame follows folder and list (round-10 gap)',
        (t) async {
      await _pump(t, phone, _denseVaultList());
      // Tab to folder (stop 2), then list (stop 4).
      await _walk(t, 2);
      expect(_stop(), 'folder');
      expect(_frameShown(t), isTrue, reason: 'folder region shows a frame');
      await _walk(t, 2);
      expect(_stop(), 'list');
      expect(_frameShown(t), isTrue, reason: 'entry list region shows a frame');
    });

    testWidgets('folder stop is skipped when there are no folders', (t) async {
      await _pump(t, phone, _denseVaultList(folders: const []));
      final seq = await _walk(t, 3);
      expect(seq, ['search', 'chips', 'list']);
    });
  });

  // Round-12 hardware failure 1: focus could only be dropped from the search
  // field. From any other region Esc fell through to the app-root fallback,
  // which pops nothing on the root route, so focus stayed put.
  group('Esc leaves the region cycle', () {
    testWidgets('Esc drops focus from the folder region', (t) async {
      await _pump(t, phone, _denseVaultList());
      await _walk(t, 2);
      expect(_stop(), 'folder');
      await _esc(t);
      expect(_inCycle(), isFalse, reason: 'Esc must leave the cycle');
      expect(_frameShown(t), isFalse, reason: 'no region frame once unfocused');
    });

    testWidgets('Esc drops focus from the chips and the entry list', (t) async {
      await _pump(t, phone, _denseVaultList());
      await _walk(t, 3);
      expect(_stop(), 'chips');
      await _esc(t);
      expect(_inCycle(), isFalse, reason: 'Esc must leave the chips region');

      await _walk(t, 4);
      expect(_stop(), 'list');
      await _esc(t);
      expect(_inCycle(), isFalse, reason: 'Esc must leave the list region');
      expect(_frameShown(t), isFalse);
    });

    testWidgets('Esc drops focus from the search field too', (t) async {
      await _pump(t, phone, _denseVaultList());
      await _tab(t);
      expect(_stop(), 'search');
      await _esc(t);
      expect(_inCycle(), isFalse);
    });

    testWidgets('after Esc the next Tab re-enters at search (Unfocused state)',
        (t) async {
      await _pump(t, phone, _denseVaultList());
      await _walk(t, 3);
      await _esc(t);
      await _tab(t);
      expect(_stop(), 'search',
          reason: 'Esc returns to Unfocused, so Tab starts the cycle over');
    });

    testWidgets('that Esc only unfocuses — it does not leave the vault list',
        (t) async {
      await _pump(t, phone, _denseVaultList());
      await _walk(t, 2);
      await _esc(t);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(VaultListScreen), findsOneWidget,
          reason: 'one Esc = one level: unfocus, not go back');
    });

    testWidgets('wide: Esc drops focus from the list and the detail pane',
        (t) async {
      await _pump(t, tablet, _denseVaultList());
      await t.tap(find.text('Apple'));
      await t.pump(const Duration(milliseconds: 300));
      FocusManager.instance.primaryFocus?.unfocus();
      await _walk(t, 4);
      expect(_stop(), 'list');
      await _esc(t);
      expect(_inCycle(), isFalse, reason: 'Esc must leave the list region');

      await _walk(t, 5);
      expect(_stop(), 'detail');
      await _esc(t);
      expect(_inCycle(), isFalse, reason: 'Esc must leave the detail region');
      expect(_frameShown(t), isFalse);
    });
  });

  // Round-12 hardware failure 2: Enter opened the entry but the list's focused
  // row jumped to a neighbour.
  group('Enter opens an entry without moving list focus', () {
    testWidgets('wide: the same entry keeps focus when its detail opens',
        (t) async {
      await _pump(t, tablet, _denseVaultList());
      await _walk(t, 4);
      expect(_stop(), 'list');
      await _down(t);
      await _down(t);
      final entry = _focusedEntryTitle(t);
      expect(entry, isNotEmpty, reason: 'sanity: an entry row holds focus');

      await _enter(t);
      expect(find.byType(EntryDetailScreen), findsOneWidget,
          reason: 'Enter opens the entry');
      expect(_focusedEntryTitle(t), entry,
          reason: 'focus must stay on the entry that was opened');
    });

    testWidgets('wide: the focused row keeps its focus NODE across selection',
        (t) async {
      // The mechanism pin. Asserting only "an entry is focused" would pass on a
      // rebuilt node that happens to sit at the same index; identity is what
      // the selection rebuild actually destroyed.
      await _pump(t, tablet, _denseVaultList());
      await _walk(t, 4);
      await _down(t);
      final node = FocusManager.instance.primaryFocus;
      expect(node, isNotNull);

      await _enter(t);
      expect(identical(FocusManager.instance.primaryFocus, node), isTrue,
          reason: 'the row focus node must survive the selection rebuild');
    });

    testWidgets('narrow: focus returns to the same entry after Esc back',
        (t) async {
      await _pump(t, phone, _denseVaultList());
      await _walk(t, 4);
      expect(_stop(), 'list');
      await _down(t);
      final entry = _focusedEntryTitle(t);
      expect(entry, isNotEmpty);

      await _enter(t);
      await t.pumpAndSettle();
      expect(find.byType(EntryDetailScreen), findsOneWidget);

      await _esc(t);
      await t.pumpAndSettle();
      expect(find.byType(EntryDetailScreen), findsNothing,
          reason: 'Esc goes back from the pushed detail screen');
      expect(_focusedEntryTitle(t), entry,
          reason: 'focus returns to the entry it was opened from');
    });
  });

  group('wide (two-pane) region Tab-cycle', () {
    testWidgets('detail is skipped in the cycle when no entry is selected',
        (t) async {
      await _pump(t, tablet, _denseVaultList());
      final seq = await _walk(t, 5);
      expect(seq, [
        'search',
        'folder',
        'chips',
        'list',
        'search', // wrap, detail skipped
      ]);
    });

    testWidgets('detail is a stop after list once an entry is selected',
        (t) async {
      await _pump(t, tablet, _denseVaultList());
      await t.tap(find.text('Apple'));
      await t.pump(const Duration(milliseconds: 300));
      // Start from cold and walk a full loop; detail sits after list.
      FocusManager.instance.primaryFocus?.unfocus();
      final seq = await _walk(t, 6);
      expect(seq, [
        'search',
        'folder',
        'chips',
        'list',
        'detail',
        'search', // wrap
      ]);
    });

    testWidgets('the FAB and the app bar are never in the cycle', (t) async {
      await _pump(t, tablet, _denseVaultList());
      final seq = await _walk(t, 12);
      for (final s in seq) {
        expect(_excluded.contains(s), isFalse,
            reason: 'excluded control "$s" must not be a Tab stop');
      }
    });
  });
}
