import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/screens/language_screen.dart';
import 'package:gabbro/vault_registry.dart';

Widget _buildScreen({AppSettings settings = const AppSettings()}) => GabbroApp(
      registry: VaultRegistry([]),
      vaultPath: null,
      settings: settings,
      initialScreen: const LanguageScreen(),
    );

void main() {
  group('LanguageScreen', () {
    testWidgets('renders Language title', (tester) async {
      await tester.pumpWidget(_buildScreen());
      expect(find.text('Language'), findsOneWidget);
    });

    testWidgets('shows all language options', (tester) async {
      await tester.pumpWidget(_buildScreen());
      // System is always first.
      expect(find.text('System'), findsOneWidget);
      // The list is lazy and scrollable (35 items). Verify items near the top
      // of the alphabetical sort (Dansk, Deutsch, English) which are always
      // in the initial viewport.
      expect(find.text('Dansk'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      // Full set: system + 33 user-facing languages = 34 total.
      expect(LanguageChoice.values.length, 34);
    });

    testWidgets('current language radio is selected', (tester) async {
      await tester.pumpWidget(
        _buildScreen(settings: const AppSettings(language: LanguageChoice.fr)),
      );
      final group = tester.widget<RadioGroup<LanguageChoice>>(
        find.byType(RadioGroup<LanguageChoice>),
      );
      expect(group.groupValue, LanguageChoice.fr);
    });
  });
}
