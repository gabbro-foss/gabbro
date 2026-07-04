import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/tablet_vault_layout.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'test_helpers.dart';

// Builds a TabletVaultLayout with one entry and an injected getEntryFn. The
// detail pane fetches the full entry synchronously during build; this lets us
// drive the "entry vanished / session race" path that crashed on hardware.
TabletVaultLayout _layout({
  required VaultEntryData Function(String id) getEntryFn,
}) {
  final entry = EntrySummaryData(
    id: 'e1',
    entryType: 'Login',
    title: 'Example',
    folder: '',
    searchBlob: 'example',
  );
  return TabletVaultLayout(
    groupedEntries: [entry],
    filteredEntries: [entry],
    letterIndex: const {},
    onLetterSelected: (_) {},
    displayTitle: (e) => e.title,
    displayType: (t) => t,
    entryTypeIcon: (_) => Icons.lock,
    searchBar: const SizedBox.shrink(),
    filterChipRow: const SizedBox.shrink(),
    searchActive: false,
    onEntryTap: (_) {},
    onRefresh: () {},
    vaultPath: '/tmp/v.gabbro',
    clipboardClearTimeout: ClipboardClearTimeout.thirtySeconds,
    getEntryFn: getEntryFn,
    selectionMode: false,
    selectedIds: const {},
    onToggleSelection: (_) {},
  );
}

// A tablet-tier viewport (shortestSide >= 600) so control-scaling uses the
// tablet ceiling (ADR-016). Optionally applies a large text scale.
void _setTablet(WidgetTester tester, {double? textScale}) {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

// getEntryFn is only invoked when an entry is tapped; these tests never tap, so
// a throwing stub is never reached.
TabletVaultLayout _listLayout() =>
    _layout(getEntryFn: (id) => throw Exception('unused'));

Finder _railIcons() => find.descendant(
      of: find.byType(NavigationRail),
      matching: find.byType(Icon),
    );

void main() {
  // ADR-016 Phase 3: the NavigationRail destination icons (default 24) don't
  // grow with the text scale — scale them for low-vision users.
  testWidgets('NavigationRail destination icons are base 24 at normal text',
      (tester) async {
    _setTablet(tester);
    await tester.pumpWidget(testApp(_listLayout()));
    await tester.pumpAndSettle();

    final icons = _railIcons();
    expect(icons, findsWidgets);
    for (final icon in tester.widgetList<Icon>(icons)) {
      expect(icon.size, 24);
    }
  });

  testWidgets('NavigationRail destination icons scale up at large text',
      (tester) async {
    _setTablet(tester, textScale: 2.0);
    await tester.pumpWidget(testApp(_listLayout()));
    await tester.pumpAndSettle();

    final icons = _railIcons();
    expect(icons, findsWidgets);
    for (final icon in tester.widgetList<Icon>(icons)) {
      expect(icon.size, isNotNull);
      expect(icon.size, greaterThan(24));
    }
  });

  // ADR-016 Phase 3: the tablet list-row type icon is a fixed size 20 — scale
  // it with the text.
  testWidgets('tablet list-row entry icon is base 20 at normal text',
      (tester) async {
    _setTablet(tester);
    await tester.pumpWidget(testApp(_listLayout()));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Example'),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.size, 20);
  });

  testWidgets('tablet list-row entry icon scales up at large text',
      (tester) async {
    _setTablet(tester, textScale: 2.0);
    await tester.pumpWidget(testApp(_listLayout()));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Example'),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.size, isNotNull);
    expect(icon.size, greaterThan(20));
  });

  testWidgets(
      'R-03 P6: selecting an entry whose getEntry throws falls back to the '
      'empty state instead of crashing the build', (tester) async {
    await tester.pumpWidget(testApp(_layout(
      // The selected entry no longer exists in the session (deleted, or a
      // refresh race against a locked/corrupted vault).
      getEntryFn: (id) => throw Exception('No entry found with id: $id'),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a failed entry fetch must not throw during build');
    expect(find.text('Select an entry'), findsOneWidget,
        reason: 'the detail pane must fall back to the empty state');
  });
}
