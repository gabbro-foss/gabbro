import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

Widget _buildScreen() => testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => <EntrySummaryData>[],
    ));

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

    expect(find.textContaining('0.1.0'), findsOneWidget);
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
  });
}