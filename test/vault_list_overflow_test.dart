import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/text_scale.dart';

// Regression coverage for the "BOTTOM OVERFLOWED" the keyboard caused on the
// vault list. Each case opens the keyboard (a large bottom view inset) across
// the layout permutations — phone (alphabet bar left/right, with the FAB),
// tablet portrait/landscape, and a dragged list-pane width — and asserts the
// frame renders without a RenderFlex overflow.

List<EntrySummaryData> _entries() => [
      EntrySummaryData(
        id: 'id-1',
        entryType: 'Login',
        title: 'Alpha',
        folder: 'Work',
        searchBlob: '',
      ),
      EntrySummaryData(
        id: 'id-2',
        entryType: 'Note',
        title: 'Beta',
        folder: 'Work',
        searchBlob: '',
      ),
    ];

/// Pumps the vault list at [w]x[h] logical px with the keyboard "open"
/// (bottom view inset), optional alphabet-bar [bar] position.
Future<void> _pumpWithKeyboard(
  WidgetTester tester, {
  required double w,
  required double h,
  AlphabetBarPosition? bar,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(testApp(Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewInsets: const EdgeInsets.only(bottom: 680),
      ),
      child: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: _entries,
        listFolders: () => ['Work', 'Personal'],
        alphabetBarPosition: bar,
      ),
    ),
  )));
  await tester.pumpAndSettle();
}

/// Pumps the vault list at [w]x[h] logical px at [textScale], no keyboard.
///
/// Large text is where the two-pane layout is most fragile. In a Row, changing
/// any child's width changes every sibling's height: a narrower left-hand
/// column gives the detail pane more room, its placeholder wraps onto fewer
/// lines, and the vertical extent changes throughout. That is what made a
/// previous overflow look like the nav rail's fault when it was not — a layout
/// fix that "works" can be pure correlation — so any
/// change to the row's children needs this pinned before and after.
Future<void> _pumpAtTextScale(
  WidgetTester tester, {
  required double w,
  required double h,
  required double textScale,
  bool isAndroid = false,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(testApp(VaultListScreen(
    vaultPath: '/tmp/test.gabbro',
    listEntries: _entries,
    listFolders: () => ['Work', 'Personal'],
    isAndroid: isAndroid,
  )));
  await tester.pumpAndSettle();
}

/// Height of the entry list itself. Zero means the header ate the screen and
/// the user can see no entries at all — the failure this file guards.
double _listHeight(WidgetTester tester) =>
    tester.getSize(find.byType(ScrollablePositionedList).first).height;

void main() {
  // Two-pane layout at large text, no keyboard. Pins the current geometry so a
  // change to the row's children is judged against a known-good baseline.
  for (final scale in <double>[2.0, kTabletMaxScale]) {
    testWidgets('two-pane at ${scale}x text: no overflow', (tester) async {
      await _pumpAtTextScale(tester, w: 900, h: 700, textScale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  // Phone width at large text. The header (search, folder, chips) is fixed
  // height and the list takes what is left, so a header that grows without
  // bound leaves the list nothing: the unclamped search placeholder once
  // wrapped to as many lines as it liked and left the entry list 0 px tall.
  for (final scale in <double>[1.0, kPhoneMaxScale]) {
    testWidgets('phone 360dp at ${scale}x text: list still has room',
        (tester) async {
      await _pumpAtTextScale(tester, w: 360, h: 800, textScale: scale);
      expect(tester.takeException(), isNull);
      expect(_listHeight(tester), greaterThan(0));
    });
  }

  // Both branches: Android keeps Flutter's own placeholder (hintText), Linux
  // passes it as a widget so its name can be excluded from the semantics
  // (a11y_region_net_test.dart). Capping one and not the other would fix the
  // overflow on one platform only.
  for (final android in <bool>[false, true]) {
    testWidgets(
        'search box stays one line at 2x text (isAndroid: $android)',
        (tester) async {
      await _pumpAtTextScale(
        tester,
        w: 360,
        h: 800,
        textScale: kPhoneMaxScale,
        isAndroid: android,
      );
      // One line plus the field's own padding stays well under 300; a
      // placeholder that wraps instead of ellipsizing pushes past it.
      expect(
        tester.getSize(find.byType(TextField).first).height,
        lessThan(300),
        reason: 'the search placeholder is wrapping instead of ellipsizing',
      );
    });
  }

  testWidgets('phone portrait, alphabet bar left + FAB: no overflow with keyboard',
      (tester) async {
    await _pumpWithKeyboard(tester, w: 400, h: 800, bar: AlphabetBarPosition.left);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone portrait, alphabet bar right: no overflow with keyboard',
      (tester) async {
    await _pumpWithKeyboard(tester, w: 400, h: 800, bar: AlphabetBarPosition.right);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet portrait: no overflow with keyboard', (tester) async {
    await _pumpWithKeyboard(tester, w: 800, h: 1100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet landscape: no overflow with keyboard', (tester) async {
    await _pumpWithKeyboard(tester, w: 1100, h: 800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet: no overflow with keyboard after widening the list pane',
      (tester) async {
    await _pumpWithKeyboard(tester, w: 900, h: 800);
    await tester.drag(
      find.byKey(const ValueKey('list-pane-divider')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
