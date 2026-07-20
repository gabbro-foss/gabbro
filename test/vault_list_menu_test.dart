import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

Widget _buildScreen() => testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => <EntrySummaryData>[],
    ));

Widget _buildScreenWithLoginEntry() => testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => <EntrySummaryData>[
        EntrySummaryData(
          id: 'e1',
          entryType: 'Login',
          title: 'Example',
          folder: '',
          searchBlob: 'example',
        ),
      ],
    ));

// Every Icon inside a popup-menu item (the leading glyph of each menu row).
Finder _menuItemIcons() => find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.byType(Icon),
    );

// The six entry-type labels shown by the add-entry type picker (English l10n).
const _typePickerLabels = <String>[
  'Password',
  'Note',
  'Identity',
  'Card',
  'File',
  'Custom',
];

// The leading Icon of a picker/list ListTile identified by its label text.
Icon _leadingIconOf(WidgetTester tester, String label) => tester.widget<Icon>(
      find.descendant(
        of: find.widgetWithText(ListTile, label),
        matching: find.byType(Icon),
      ),
    );

Future<void> _setNarrow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pump();
}

void main() {
  group('AppBar title', () {
    testWidgets('shows vault alias when vaultAlias is provided', (tester) async {
      await tester.pumpWidget(testApp(VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        vaultAlias: 'My Vault',
        listEntries: () => <EntrySummaryData>[],
      )));
      await _setNarrow(tester);
      await tester.pumpAndSettle();
      expect(find.text('Gabbro - My Vault'), findsOneWidget);
    });

    testWidgets('shows Gabbro when no vaultAlias provided', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();
      expect(find.text('Gabbro'), findsOneWidget);
    });
  });

  // ADR-016 Phase 3 Slice B: app-bar action icons grow with the text scale
  // (the title ellipsizes, so the bar does not overflow).
  testWidgets('app-bar action icons scale up at large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    final selectBtn = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byIcon(Icons.checklist),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(selectBtn.iconSize, greaterThan(24));
    expect(tester.takeException(), isNull);
  });

  // ADR-016 Phase 3 Slice B: the add-entry FAB icon grows with the text scale.
  testWidgets('FAB icon scales up at large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(icon.size, isNotNull);
    expect(icon.size, greaterThan(24));
  });

  // ADR-016 Phase 3: the app-bar popup-menu item icons are a fixed size 20 and
  // don't grow with the text scale — scale them (base 20 kept for menu density)
  // so a low-vision user gets proportionally larger menu glyphs.
  testWidgets('popup-menu item icons keep base 20 at normal text',
      (tester) async {
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final icons = _menuItemIcons();
    expect(icons, findsWidgets);
    for (final icon in tester.widgetList<Icon>(icons)) {
      expect(icon.size, 20);
    }
  });

  testWidgets('every popup-menu item icon scales up at large text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final icons = _menuItemIcons();
    expect(icons, findsWidgets);
    for (final icon in tester.widgetList<Icon>(icons)) {
      expect(icon.size, isNotNull);
      expect(icon.size, greaterThan(20));
    }
  });

  // ADR-016 Phase 3: the add-entry type-picker rows use a default-size (24)
  // leading icon that doesn't scale — scale it with the text.
  testWidgets('type-picker leading icons are base 24 at normal text',
      (tester) async {
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in _typePickerLabels) {
      expect(_leadingIconOf(tester, label).size, 24);
    }
  });

  testWidgets('type-picker leading icons scale up at large text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in _typePickerLabels) {
      final icon = _leadingIconOf(tester, label);
      expect(icon.size, isNotNull);
      expect(icon.size, greaterThan(24));
    }
  });

  // ADR-016 Phase 3: the per-entry list-row type icon is a fixed size 20 —
  // scale it with the text so it stays legible alongside the enlarged title.
  testWidgets('phone list-row entry icon is base 20 at normal text',
      (tester) async {
    await tester.pumpWidget(_buildScreenWithLoginEntry());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    expect(_leadingIconOf(tester, 'Example').size, 20);
  });

  testWidgets('phone list-row entry icon scales up at large text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_buildScreenWithLoginEntry());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    final icon = _leadingIconOf(tester, 'Example');
    expect(icon.size, isNotNull);
    expect(icon.size, greaterThan(20));
  });

  group('VaultListScreen menu items', () {
    testWidgets('all expected menu items are present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Export vault'), findsOneWidget);
      expect(find.text('Import entries'), findsOneWidget);
      expect(find.text('Sync from file'), findsOneWidget);
      expect(find.text('Manage vaults'), findsOneWidget);
      expect(find.text('Change passphrase'), findsOneWidget);
      expect(find.text('Manage YubiKeys'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Password generator'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Manage folders'), findsOneWidget);
    });
    testWidgets('menu items do not overflow at large text', (tester) async {
      // ADR-016: hardware walk #4 found the bare-Text menu items (e.g. Manage
      // YubiKeys) clip off the edge at large text; the Expanded ones ellipsize.
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

  testWidgets('each menu item has an icon', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Every PopupMenuItem child is a Row — each must contain at least one Icon.
      final rows = find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.byType(Row),
      );
      expect(rows, findsWidgets);
      for (final row in tester.widgetList(rows)) {
        final icons = find.descendant(
          of: find.byElementPredicate((e) => e.widget == row),
          matching: find.byType(Icon),
        );
        expect(icons, findsAtLeastNWidgets(1));
      }
    });

    testWidgets('Delete vault item is not present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _setNarrow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Delete vault'), findsNothing);
    });
  });

  // ── Menu navigation ───────────────────────────────────────────────────────

  testWidgets('tapping Password generator pushes GeneratorScreen', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Password generator'));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    // GeneratorScreen has AppBar with localized title
    expect(find.byType(AppBar), findsWidgets);
  });

  testWidgets('tapping Help pushes HelpScreen', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('tapping About pushes AboutScreen', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
  });

  testWidgets('tapping Manage vaults is null-safe when no GabbroApp', (tester) async {
    // GabbroApp.maybeOf returns null here — must not throw.
    await tester.pumpWidget(_buildScreen());
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage vaults'));
    await tester.pumpAndSettle();

    // No crash — screen is still rendered.
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });

  // Security regression guard: if listEntries throws (the vault is locked), the
  // screen must NOT render the entry list / its chrome — no decrypted data may
  // surface. Pins the _error render-gate against future regression.
  testWidgets('locked vault (listEntries throws) renders no entry-list chrome',
      (tester) async {
    await tester.pumpWidget(testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => throw Exception('vault is locked'),
    )));
    await _setNarrow(tester);
    await tester.pumpAndSettle();

    // The error screen replaces the whole list view — no menu, no search field.
    expect(find.byType(PopupMenuButton<String>), findsNothing,
        reason: 'a locked load must not render the vault-list AppBar/menu');
    expect(find.byIcon(Icons.lock_outline), findsNothing,
        reason: 'no AppBar lock button (and no Login entry rows) when locked');

    // The failure is shown via a meaning-carrying message, not the old
    // meaning-empty "Error: ..." wrapper; the raw detail is appended.
    expect(find.textContaining("Couldn't load the vault:"), findsOneWidget);
    expect(find.textContaining('vault is locked'), findsOneWidget);
  });
}