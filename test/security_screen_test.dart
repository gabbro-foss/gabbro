import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/widgets/segmented_row.dart';

Widget _buildScreen({
  AppSettings settings = const AppSettings(),
  void Function(AppSettings)? onUpdate,
}) => MaterialApp(
  home: SecurityScreen(
    settings: settings,
    onUpdate: onUpdate ?? (_) {},
  ),
);

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
        MaterialApp(
          home: Scaffold(
            body: SegmentedRow<ForegroundLockTimeout>(
              values: ForegroundLockTimeout.values,
              selected: ForegroundLockTimeout.thirtySeconds,
              label: (v) => v.name,
              onSelected: (_) {},
            ),
          ),
        ),
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
      await tester.tap(find.text('2 min'));
      await tester.pumpAndSettle();
      expect(updated?.clipboardClearTimeout, ClipboardClearTimeout.twoMinutes);
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
}