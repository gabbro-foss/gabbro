import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/autofill_unlock_screen.dart';

void main() {
  testWidgets('shows passphrase field and unlock button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AutofillUnlockScreen()),
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('unlock button is disabled when passphrase is empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AutofillUnlockScreen()),
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('unlock button is enabled when passphrase is non-empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AutofillUnlockScreen()),
    );
    await tester.enterText(find.byType(TextField), 'correct horse battery staple');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });
}