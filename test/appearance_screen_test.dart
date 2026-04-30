import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/widgets/segmented_row.dart';

Widget _buildScreen({AppSettings settings = const AppSettings()}) => GabbroApp(
  vaultPath: '/tmp/test.gabbro',
  vaultExists: true,
  settings: settings,
  initialScreen: const AppearanceScreen(),
);

void main() {
  group('AppearanceScreen', () {
    testWidgets('renders theme and text size section headers', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Text size'), findsOneWidget);
    });

    testWidgets('all theme buttons are present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('SegmentedRow uses Wrap not Row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SegmentedRow<ThemeChoice>(
              values: ThemeChoice.values,
              selected: ThemeChoice.system,
              label: (v) => v.name,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byType(Row), findsNothing);
    });
  });
}
