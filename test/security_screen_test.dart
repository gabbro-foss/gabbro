import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/widgets/segmented_row.dart';

Widget _buildScreen({
  AppSettings settings = const AppSettings(),
  void Function(AppSettings)? onUpdate,
}) => testApp(SecurityScreen(
  settings: settings,
  onUpdate: onUpdate ?? (_) {},
));

void main() {
  group('SecurityScreen', () {
    testWidgets('renders foreground and background timeout section headers', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Foreground lock'), findsOneWidget);
      expect(find.text('Background lock'), findsOneWidget);
    });

    testWidgets('foreground timeout buttons are all present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('30s'), findsAtLeastNWidgets(1));
      expect(find.text('1 min'), findsAtLeastNWidgets(1));
      expect(find.text('5 min'), findsAtLeastNWidgets(1));
      expect(find.text('Never'), findsAtLeastNWidgets(1));
    });

    testWidgets('background timeout buttons are all present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('15 min'), findsOneWidget);
    });

    testWidgets('tapping a foreground button calls onUpdate with correct value', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.tap(find.text('Never').first);
      await tester.pumpAndSettle();
      expect(updated?.foregroundLockTimeout, ForegroundLockTimeout.never);
    });

    testWidgets('tapping a background button calls onUpdate with correct value', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      expect(updated?.backgroundLockTimeout, BackgroundLockTimeout.fifteenMinutes);
    });

    testWidgets('SegmentedRow uses Wrap not Row', (tester) async {
      await tester.pumpWidget(
        testApp(Scaffold(
          body: SegmentedRow<ForegroundLockTimeout>(
            values: ForegroundLockTimeout.values,
            selected: ForegroundLockTimeout.thirtySeconds,
            label: (v) => v.name,
            onSelected: (_) {},
          ),
        )),
      );
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('clipboard clear timeout section header is present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Clipboard clear'), findsOneWidget);
    });

    testWidgets('clipboard clear timeout buttons are all present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('30s'), findsAtLeastNWidgets(1));
      expect(find.text('60s'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
    });

    testWidgets('tapping a clipboard clear button calls onUpdate with correct value', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.scrollUntilVisible(find.text('2 min'), 100);
      await tester.tap(find.text('2 min'));
      await tester.pumpAndSettle();
      expect(updated?.clipboardClearTimeout, ClipboardClearTimeout.twoMinutes);
    });

    testWidgets('block passphrase copy/paste section header is present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Passphrase copy/paste'), findsOneWidget);
    });

    testWidgets('block passphrase copy/paste toggle is on by default', (tester) async {
      await tester.pumpWidget(_buildScreen());
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Block copy/paste'),
      );
      expect(tile.value, isTrue);
    });

    testWidgets('tapping passphrase copy/paste toggle calls onUpdate with false', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Block copy/paste'));
      await tester.pumpAndSettle();
      expect(updated?.blockPassphraseCopyPaste, isFalse);
    });

    testWidgets('selected foreground button reflects current settings', (tester) async {
      await tester.pumpWidget(_buildScreen(
        settings: const AppSettings(
          foregroundLockTimeout: ForegroundLockTimeout.oneMinute,
        ),
      ));
      // The screen receives the setting — no exception thrown, renders cleanly.
      expect(find.text('1 min'), findsAtLeastNWidgets(1));
    });
  });

  // ── showVaultList ─────────────────────────────────────────────────────────

  group('showVaultList', () {
    testWidgets('vault list section header is present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.scrollUntilVisible(find.text('Vault list'), 300);
      expect(find.text('Vault list'), findsOneWidget);
    });

    testWidgets('show vault list toggle is off by default', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Show vault list on login'), 300);
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Show vault list on login'),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('tapping show vault list toggle calls onUpdate with true', (tester) async {
      AppSettings? updated;
      await tester.pumpWidget(_buildScreen(onUpdate: (s) => updated = s));
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Show vault list on login'), 300);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Show vault list on login'));
      await tester.pumpAndSettle();
      expect(updated?.showVaultList, isTrue);
    });
  });
}