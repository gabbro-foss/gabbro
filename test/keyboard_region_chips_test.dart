import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/focus_region.dart';

import 'screen_catalog.dart';

// Phase 3, increment 1 - prove the region pattern on the filter chips: the row is
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

/// A vault list with folders and two entries, so the folder region exists and
/// search filtering is observable.
VaultListScreen _screen({required bool isAndroid}) => VaultListScreen(
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

Future<void> _pumpScreen(
  WidgetTester t, {
  required bool isAndroid,
  Surface surface = phone,
}) async {
  t.view.physicalSize = surface.physical;
  t.view.devicePixelRatio = surface.dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(appShell(_screen(isAndroid: isAndroid), textScale: 1.0));
  await t.pump(const Duration(milliseconds: 300));
}

/// The search field's decoration - the only TextField on the vault list.
InputDecoration _searchDecoration(WidgetTester t) =>
    t.widget<TextField>(find.byType(TextField).first).decoration!;

/// What the field draws when it is NOT focused.
InputBorder? _unfocusedBorder(InputDecoration d) => d.enabledBorder ?? d.border;

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
  // check the region FocusScopes are present on desktop and ABSENT on Android -
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

  // D5 - the focus highlight exists to serve keyboard navigation, which is
  // Linux-desktop only. So NOTHING of it may appear on Android: no FocusRegion
  // frame widgets, and a search field whose focused border equals its
  // unfocused one (Material's own default suppressed too). N1/N2 pin what
  // Linux must keep; R1-R3 are the Android change.
  group('D5 focus highlight is Linux-only', () {
    testWidgets('N1 desktop keeps a focus frame on folder, chips and list',
        (tester) async {
      await _pumpScreen(tester, isAndroid: false);
      expect(find.byType(FocusRegion), findsAtLeast(3),
          reason: 'folder, chips and list each draw a region frame on desktop');
    });

    testWidgets('N2 desktop search field lights up when focused',
        (tester) async {
      await _pumpScreen(tester, isAndroid: false);
      final d = _searchDecoration(tester);
      expect(d.focusedBorder, isNotNull);
      expect(d.focusedBorder!.borderSide,
          isNot(_unfocusedBorder(d)!.borderSide),
          reason: 'the desktop search box is its own focus indicator');
    });

    testWidgets('R1 Android has NO focus frame, narrow', (tester) async {
      await _pumpScreen(tester, isAndroid: true);
      expect(find.byType(FocusRegion), findsNothing,
          reason: 'no focus frame may enter the Android widget tree');
    });

    testWidgets('R1 Android has NO focus frame, wide', (tester) async {
      await _pumpScreen(tester, isAndroid: true, surface: tablet);
      expect(find.byType(FocusRegion), findsNothing,
          reason: 'a wide Android device gains nothing from a focus frame');
    });

    testWidgets('R2 Android search field looks the same focused or not',
        (tester) async {
      await _pumpScreen(tester, isAndroid: true);
      final d = _searchDecoration(tester);
      expect(d.focusedBorder, isNotNull);
      expect(_unfocusedBorder(d), isNotNull);
      expect(d.focusedBorder!.borderSide, _unfocusedBorder(d)!.borderSide,
          reason: 'tapping the Android search box must not highlight it');
    });

    testWidgets('R3 Android search still focuses, types and filters',
        (tester) async {
      await _pumpScreen(tester, isAndroid: true);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Alph');
      await tester.pump(const Duration(milliseconds: 300));
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue,
          reason: 'the field still takes focus so the keyboard opens');
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsNothing,
          reason: 'typing still filters the list');
    });
  });
}
