import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/widgets/generator_widget.dart';
import 'package:gabbro/src/rust/api/password_generator.dart';
import 'package:gabbro/src/rust/api/passphrase_generator.dart';

// ---------------------------------------------------------------------------
// Minimal stub — GeneratorWidget is not yet implemented. All tests below
// should FAIL until the widget exists.
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// Stub generator functions — no Rust FFI in tests.
String _stubPassword(PasswordConfig config) => 'A' * config.length;
Future<String> _stubPassphrase(PassphraseConfig config) async =>
    List.generate(config.wordCount, (i) => 'word$i').join(config.separator);
Future<double> _stubEntropyBits(int wordCount, Language language) async =>
    wordCount * 12.92;
double _stubEntropy(int poolSize, int length) => poolSize * length * 0.1;

GeneratorWidget _stubWidget({void Function(String)? onUsePassword}) =>
    GeneratorWidget(
      onUsePassword: onUsePassword,
      generatePasswordFn: _stubPassword,
      generatePassphraseFn: _stubPassphrase,
      passphraseEntropyBitsFn: _stubEntropyBits,
      entropyBitsFn: _stubEntropy,
    );

void main() {
  group('GeneratorWidget — mode toggle', () {
    testWidgets('shows classic mode by default', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Passphrase'), findsOneWidget);
      // Length slider present in classic mode
      expect(find.byKey(const Key('length_slider')), findsOneWidget);
    });

    testWidgets('switches to passphrase mode on tap', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      await tester.tap(find.text('Passphrase'));
      await tester.pumpAndSettle();
      // Word count slider present in passphrase mode
      expect(find.byKey(const Key('word_count_slider')), findsOneWidget);
      // Length slider gone
      expect(find.byKey(const Key('length_slider')), findsNothing);
    });
  });

  group('GeneratorWidget — generated value display', () {
    testWidgets('shows generate button', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.byKey(const Key('generate_button')), findsOneWidget);
    });

    testWidgets('shows copy button', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.byKey(const Key('copy_button')), findsOneWidget);
    });

    testWidgets('shows show/hide toggle', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.byKey(const Key('visibility_toggle')), findsOneWidget);
    });

    testWidgets('shows entropy display', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.byKey(const Key('entropy_display')), findsOneWidget);
    });
  });

  group('GeneratorWidget — Use this password button', () {
    testWidgets('absent when onUsePassword is null', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.byKey(const Key('use_password_button')), findsNothing);
    });

    testWidgets('present when onUsePassword is provided', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget(onUsePassword: (v) {})));
      expect(find.byKey(const Key('use_password_button')), findsOneWidget);
    });

    testWidgets('calls onUsePassword with generated value on tap',
        (tester) async {
      String? received;
      await tester.pumpWidget(_wrap(_stubWidget(onUsePassword: (v) => received = v)));
      await tester.pumpAndSettle();
      // Generate first
      await tester.tap(find.byKey(const Key('generate_button')));
      await tester.pumpAndSettle();
      // Then use
      await tester.tap(find.byKey(const Key('use_password_button')));
      await tester.pumpAndSettle();
      expect(received, isNotNull);
      expect(received!.isNotEmpty, isTrue);
    });
  });

  group('GeneratorWidget — classic mode controls', () {
    testWidgets('shows all four character set toggles', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.byKey(const Key('toggle_uppercase')), findsOneWidget);
      expect(find.byKey(const Key('toggle_lowercase')), findsOneWidget);
      expect(find.byKey(const Key('toggle_digits')), findsOneWidget);
      expect(find.byKey(const Key('toggle_symbols')), findsOneWidget);
    });

    testWidgets('shows exclude ambiguous toggle', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      expect(find.byKey(const Key('toggle_exclude_ambiguous')), findsOneWidget);
    });
  });

  group('GeneratorWidget — password breakdown sheet', () {
    testWidgets('long-pressing revealed password shows breakdown sheet',
        (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      await tester.pumpAndSettle();

      // Reveal the password
      await tester.tap(find.byKey(const Key('visibility_toggle')));
      await tester.pump();

      // Long-press the revealed value
      await tester.longPress(find.byKey(const Key('generated_value')));
      await tester.pumpAndSettle();

      expect(find.text('Password breakdown'), findsOneWidget);
    });
  });

  group('GeneratorWidget — passphrase mode controls', () {
    Future<void> switchToPassphrase(WidgetTester tester) async {
      await tester.tap(find.text('Passphrase'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows word count slider', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      await switchToPassphrase(tester);
      expect(find.byKey(const Key('word_count_slider')), findsOneWidget);
    });

    testWidgets('shows language selector', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      await switchToPassphrase(tester);
      expect(find.byKey(const Key('language_selector')), findsOneWidget);
    });

    testWidgets('shows capitalise toggle', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      await switchToPassphrase(tester);
      expect(find.byKey(const Key('toggle_capitalise')), findsOneWidget);
    });

    testWidgets('shows append number toggle', (tester) async {
      await tester.pumpWidget(_wrap(_stubWidget()));
      await switchToPassphrase(tester);
      expect(find.byKey(const Key('toggle_append_number')), findsOneWidget);
    });
  });
}