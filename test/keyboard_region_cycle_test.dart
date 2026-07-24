import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
// Cycle (narrow): searchtype -> search -> folder(if any) -> chips -> list -> wrap.
// Cycle (wide): ... -> list -> detail(skip if no entry selected) -> wrap.
// Excluded everywhere: FAB, select-entries, lock, menu, nav rail, alphabet bar
// (the bar is a touch scroll-shortcut; Up/Down in the list already covers it — DRY).
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

/// Nearest enclosing region FocusScope ('region:search' -> 'search'), else ''.
String _regionOf(FocusNode n) {
  FocusScopeNode? s = n.enclosingScope;
  while (s != null) {
    final lbl = s.debugLabel ?? '';
    if (lbl.startsWith('region:')) return lbl.substring('region:'.length);
    final p = s.parent;
    s = p is FocusScopeNode ? p : null;
  }
  return '';
}

/// Canonical name of the currently-focused Tab stop.
String _stop() {
  final n = FocusManager.instance.primaryFocus;
  if (n == null) return 'none';
  final ctx = n.context;
  final region = _regionOf(n);
  if (region == 'search') {
    // searchtype toggle and the field share the search region; the field is the
    // one with an EditableText ancestor.
    final field = ctx?.findAncestorStateOfType<EditableTextState>() != null;
    return field ? 'search' : 'searchtype';
  }
  if (region.isNotEmpty) return region; // folder, chips, alphabet, list, detail
  if (ctx != null) {
    if (ctx.findAncestorWidgetOfExactType<NavigationRail>() != null) return 'rail';
    if (ctx.findAncestorWidgetOfExactType<FloatingActionButton>() != null) {
      return 'fab';
    }
    if (ctx.findAncestorWidgetOfExactType<AppBar>() != null) return 'appbar';
  }
  return 'other';
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
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  t.view.physicalSize = surface.physical;
  t.view.devicePixelRatio = surface.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(appShell(screen, textScale: 1.0));
  await t.pump(const Duration(milliseconds: 300));
}

const _excluded = {'fab', 'appbar', 'rail'};

// SKIPPED = the RED spec for Phase 3 green work (not yet built). Verified RED for
// the right reasons on 2026-07-24 (current app does default per-control traversal:
// appbar/fab/rail, never a region). A fresh instance: un-skip each test as it
// wires the matching region green. See ARCHITECTURE.md `### Next task`.
const _pendingGreen = 'RED spec: Phase 3 region cycle green work not yet built';

void main() {
  group('narrow region Tab-cycle', skip: _pendingGreen, () {
    testWidgets('Tab from cold start enters the cycle at searchtype', (t) async {
      await _pump(t, phone, _denseVaultList());
      await _tab(t);
      expect(_stop(), 'searchtype',
          reason: 'first Tab enters the cycle, not an app-bar button');
    });

    testWidgets('forward cycle is one stop per region, in order, wrapping',
        (t) async {
      await _pump(t, phone, _denseVaultList());
      final seq = await _walk(t, 6);
      expect(seq, [
        'searchtype',
        'search',
        'folder',
        'chips',
        'list',
        'searchtype', // wrap
      ]);
    });

    testWidgets('Shift+Tab reverses the cycle', (t) async {
      await _pump(t, phone, _denseVaultList());
      final seq = await _walk(t, 6, shift: true);
      expect(seq, [
        'list',
        'chips',
        'folder',
        'search',
        'searchtype',
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
      // Tab to folder (stop 3), then list (stop 5).
      await _walk(t, 3);
      expect(_stop(), 'folder');
      expect(_frameShown(t), isTrue, reason: 'folder region shows a frame');
      await _walk(t, 2);
      expect(_stop(), 'list');
      expect(_frameShown(t), isTrue, reason: 'entry list region shows a frame');
    });

    testWidgets('folder stop is skipped when there are no folders', (t) async {
      await _pump(t, phone, _denseVaultList(folders: const []));
      final seq = await _walk(t, 4);
      expect(seq, ['searchtype', 'search', 'chips', 'list']);
    });
  });

  group('wide (two-pane) region Tab-cycle', skip: _pendingGreen, () {
    testWidgets('detail is skipped in the cycle when no entry is selected',
        (t) async {
      await _pump(t, tablet, _denseVaultList());
      final seq = await _walk(t, 6);
      expect(seq, [
        'searchtype',
        'search',
        'folder',
        'chips',
        'list',
        'searchtype', // wrap, detail skipped
      ]);
    });

    testWidgets('detail is a stop after list once an entry is selected',
        (t) async {
      await _pump(t, tablet, _denseVaultList());
      await t.tap(find.text('Apple'));
      await t.pump(const Duration(milliseconds: 300));
      // Start from cold and walk a full loop; detail sits after list.
      FocusManager.instance.primaryFocus?.unfocus();
      final seq = await _walk(t, 7);
      expect(seq, [
        'searchtype',
        'search',
        'folder',
        'chips',
        'list',
        'detail',
        'searchtype', // wrap
      ]);
    });

    testWidgets('the nav rail is never in the cycle', (t) async {
      await _pump(t, tablet, _denseVaultList());
      final seq = await _walk(t, 12);
      for (final s in seq) {
        expect(_excluded.contains(s), isFalse,
            reason: 'excluded control "$s" must not be a Tab stop');
      }
    });
  });
}
