import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/autofill_unlock_screen.dart';

void main() {
  const autofillChannel = MethodChannel('app.gabbro.gabbro/autofill');

  testWidgets('shows passphrase field and unlock button', (tester) async {
    await tester.pumpWidget(testApp(const AutofillUnlockScreen()));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('unlock button is disabled when passphrase is empty', (tester) async {
    await tester.pumpWidget(testApp(const AutofillUnlockScreen()));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('unlock button is enabled when passphrase is non-empty', (tester) async {
    await tester.pumpWidget(testApp(const AutofillUnlockScreen()));
    await tester.enterText(find.byType(TextField), 'correct horse battery staple');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('tapping unlock invokes the autofill channel with the passphrase',
      (tester) async {
    MethodCall? captured;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(autofillChannel, (call) async {
      captured = call;
      return null; // native side closes the activity on success
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(autofillChannel, null));

    await tester.pumpWidget(testApp(const AutofillUnlockScreen()));
    await tester.enterText(find.byType(TextField), 'open sesame');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(captured?.method, 'unlock');
    expect((captured?.arguments as Map)['passphrase'], 'open sesame');
  });

  testWidgets('shows the error message when the unlock channel rejects',
      (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(autofillChannel, (call) async {
      throw PlatformException(code: 'WRONG_PASSPHRASE', message: 'Wrong passphrase');
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(autofillChannel, null));

    await tester.pumpWidget(testApp(const AutofillUnlockScreen()));
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump(); // run the async handler
    await tester.pump(); // apply the error setState

    expect(find.text('Wrong passphrase'), findsOneWidget);
    // The spinner must clear so the user can retry.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });
}