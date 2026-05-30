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
      expect(find.text('System'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('Italiano'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
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
