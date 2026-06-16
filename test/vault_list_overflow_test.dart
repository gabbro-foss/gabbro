import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

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

void main() {
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
