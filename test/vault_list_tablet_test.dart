import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ---------------------------------------------------------------------------
// Fake entry list — avoids hitting the Rust bridge in tests.
// Two entries so the list is non-empty and we can test selection.
// ---------------------------------------------------------------------------
List<EntrySummaryData> _fakeEntries() => [
      EntrySummaryData(
        id: 'id-1',
        entryType: 'Login',
        title: 'Alice',
        folder: 'Personal',
        tags: [],
        favourite: false,
      ),
      EntrySummaryData(
        id: 'id-2',
        entryType: 'Note',
        title: 'Bob',
        folder: 'Personal',
        tags: [],
        favourite: false,
      ),
    ];

// ---------------------------------------------------------------------------
// Helper — builds VaultListScreen inside GabbroApp.
// Width is controlled via tester.view.physicalSize in each test — that is
// the only reliable way to make LayoutBuilder see a specific width inside
// MaterialApp, which otherwise expands to fill the full test surface.
// ---------------------------------------------------------------------------
Widget _buildScreen() => GabbroApp(
      vaultPath: '/tmp/test.gabbro',
      vaultExists: false,
      settings: const AppSettings(),
      initialScreen: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: _fakeEntries,
      ),
    );

// Sets the test surface to [width]×900 logical pixels (devicePixelRatio=1)
// and registers a teardown to reset it after the test.
void _setWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('VaultListScreen — tablet two-pane layout', () {
    // -----------------------------------------------------------------------
    // Test 1: NavigationRail present at ≥600dp
    // -----------------------------------------------------------------------
    testWidgets('NavigationRail visible at ≥600dp', (tester) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 2: NavigationBar (bottom) absent at ≥600dp
    // On phone we use the bottom NavigationBar; on tablet we don't.
    // -----------------------------------------------------------------------
    testWidgets('NavigationBar absent at ≥600dp', (tester) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationBar), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 3: NavigationRail absent below 600dp (phone layout unchanged)
    // -----------------------------------------------------------------------
    testWidgets('NavigationRail absent below 600dp', (tester) async {
      _setWidth(tester, 400);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationRail), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 4: List pane present at ≥600dp — search field is the landmark.
    // -----------------------------------------------------------------------
    testWidgets('list pane present at ≥600dp (search field visible)',
        (tester) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.widgetWithIcon(TextField, Icons.search), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 5: Empty state shown in detail pane when no entry is selected.
    // -----------------------------------------------------------------------
    testWidgets('detail pane shows empty state when no entry selected',
        (tester) async {
      _setWidth(tester, 700);
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Select an entry'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 6: List pane dims when editing (_isEditing = true).
    // Skipped — requires _isEditing state wired up in phase 2.
    // -----------------------------------------------------------------------
    testWidgets(
      'list pane dims when edit mode active',
      (tester) async {
        _setWidth(tester, 700);
        await tester.pumpWidget(_buildScreen());
        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        final opacityWidget = tester.widget<Opacity>(
          find.ancestor(
            of: find.widgetWithIcon(TextField, Icons.search),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacityWidget.opacity, lessThan(1.0));
      },
      skip: true, // requires _isEditing implementation — add in phase 2
    );

    // -----------------------------------------------------------------------
    // Test 7: Layout switches when width crosses 600dp threshold.
    // This is the Linux window-resize scenario.
    // -----------------------------------------------------------------------
    testWidgets('layout switches across 600dp threshold', (tester) async {
      // Narrow — phone layout
      _setWidth(tester, 400);
      await tester.pumpWidget(_buildScreen());
      expect(find.byType(NavigationRail), findsNothing);

      // Wide — tablet layout
      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });
}
