import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/screens/keyboard_shortcuts_list_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

import 'test_helpers.dart';

AppLocalizations lOf(WidgetTester tester, Type screen) =>
    AppLocalizations.of(tester.element(find.byType(screen)));

Future<void> openMenu(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every documented shortcut with its description',
      (tester) async {
    // Tall viewport so the whole (lazy) list renders - the no-copy note sits at
    // the very bottom and would otherwise not be built.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(testApp(const KeyboardShortcutsListScreen()));
    final l = lOf(tester, KeyboardShortcutsListScreen);

    for (final combo in const [
      'Ctrl+L',
      'Ctrl+N',
      'Ctrl+M',
      'Ctrl+Q',
      'Ctrl+F',
      'Ctrl+Shift+F',
      'Esc',
    ]) {
      expect(find.text(combo), findsOneWidget, reason: '$combo combo missing');
    }
    expect(find.textContaining('Tab'), findsWidgets);
    expect(find.textContaining('Enter'), findsWidgets);

    for (final desc in [
      l.kbLockVault,
      // Ctrl+N / Ctrl+M / Ctrl+Q reuse existing localized action labels (DRY).
      l.newEntryTitle,
      l.tooltipMenu,
      l.quit,
      l.kbFocusSearch,
      l.kbSearchAllFields,
      l.kbMoveBetweenControls,
      l.kbActivateControl,
      l.kbCloseDialog,
    ]) {
      expect(find.text(desc), findsOneWidget, reason: 'missing description: $desc');
    }
    expect(find.text(l.kbNoCopyNote), findsOneWidget,
        reason: 'the no-copy security note is missing');
  });

  testWidgets('the desktop menu entry opens the screen', (tester) async {
    await tester.pumpWidget(testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      isAndroid: false,
      listEntries: () => <EntrySummaryData>[],
    )));
    await openMenu(tester);
    final l = lOf(tester, VaultListScreen);

    expect(find.text(l.keyboardShortcutsTitle), findsOneWidget);
    await tester.tap(find.text(l.keyboardShortcutsTitle));
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsListScreen), findsOneWidget);
  });

  testWidgets('the menu entry is absent on Android', (tester) async {
    await tester.pumpWidget(testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      isAndroid: true,
      listEntries: () => <EntrySummaryData>[],
    )));
    await openMenu(tester);
    final l = lOf(tester, VaultListScreen);

    expect(find.text(l.keyboardShortcutsTitle), findsNothing,
        reason: 'keyboard shortcuts are desktop-only; no menu clutter on Android');
  });
}
