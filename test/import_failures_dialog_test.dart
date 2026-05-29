import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/import_failures_dialog.dart';
import 'package:gabbro/src/rust/api/import.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ImportFailureData _cardFailure({
  String title = 'Bad Card',
  String category = 'creditcard',
  String reason = 'card number must be 12–19 digits',
  List<(String, String)>? rawFields,
}) => ImportFailureData(
      title: title,
      category: category,
      reason: reason,
      rawFields: rawFields ?? [('card_number', '1234'), ('cardholder_name', 'Rob')],
    );

/// Pumps a minimal app that immediately shows the failures dialog.
Future<void> _pumpDialog(
  WidgetTester tester,
  List<ImportFailureData> failures,
) async {
  await tester.pumpWidget(
    testApp(Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showImportFailuresDialog(context, failures),
          child: const Text('Show'),
        ),
      ),
    )),
  );
  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('dialog shows failure title', (tester) async {
    await _pumpDialog(tester, [_cardFailure(title: 'My Visa')]);
    expect(find.text('My Visa'), findsOneWidget);
  });

  testWidgets('dialog shows rejection reason', (tester) async {
    await _pumpDialog(tester, [
      _cardFailure(reason: 'card number must be 12–19 digits'),
    ]);
    expect(find.text('card number must be 12–19 digits'), findsOneWidget);
  });

  testWidgets('dialog shows source category', (tester) async {
    await _pumpDialog(tester, [_cardFailure(category: 'creditcard')]);
    expect(find.textContaining('creditcard'), findsOneWidget);
  });

  testWidgets('dialog shows index and total', (tester) async {
    await _pumpDialog(tester, [_cardFailure(), _cardFailure(title: 'Second')]);
    expect(find.textContaining('1 of 2'), findsOneWidget);
  });

  testWidgets('Skip button advances to next failure', (tester) async {
    await _pumpDialog(tester, [
      _cardFailure(title: 'First Card'),
      _cardFailure(title: 'Second Card'),
    ]);
    expect(find.text('First Card'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Second Card'), findsOneWidget);
    expect(find.textContaining('2 of 2'), findsOneWidget);
  });

  testWidgets('Skip all failures closes dialog', (tester) async {
    await _pumpDialog(tester, [_cardFailure()]);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Dialog gone — only the underlying scaffold button remains
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('Edit button is present', (tester) async {
    await _pumpDialog(tester, [_cardFailure()]);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('dialog is not dismissible by barrier tap', (tester) async {
    await _pumpDialog(tester, [_cardFailure()]);
    // Tap outside the dialog area
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    // Dialog should still be showing
    expect(find.text('Bad Card'), findsOneWidget);
  });

  testWidgets('single failure shows 1 of 1', (tester) async {
    await _pumpDialog(tester, [_cardFailure()]);
    expect(find.textContaining('1 of 1'), findsOneWidget);
  });
}
