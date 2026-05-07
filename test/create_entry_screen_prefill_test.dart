import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

LoginEntryData _loginEntry() => LoginEntryData(
      id: 'test-id-1',
      title: 'Test',
      url: '',
      username: '',
      password: '',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
    );

Widget _buildCardScreenWithPrefill(Map<String, String> prefill) => MaterialApp(
      home: CreateEntryScreen(
        entryType: 'Card',
        prefill: prefill,
        onCreateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('card prefill populates card number field', (tester) async {
    await tester.pumpWidget(
      _buildCardScreenWithPrefill({'card_number': '4111111111111111'}),
    );
    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, '4111111111111111'),
    );
    expect(field.controller?.text, equals('4111111111111111'));
  });

  testWidgets('card prefill populates cardholder name field', (tester) async {
    await tester.pumpWidget(
      _buildCardScreenWithPrefill({'cardholder_name': 'Rob Bastian'}),
    );
    expect(
      find.widgetWithText(TextFormField, 'Rob Bastian'),
      findsOneWidget,
    );
  });

  testWidgets('card prefill populates expiry field', (tester) async {
    await tester.pumpWidget(
      _buildCardScreenWithPrefill({'expiry': '12/28'}),
    );
    expect(find.widgetWithText(TextFormField, '12/28'), findsOneWidget);
  });

  testWidgets('card prefill populates cvv field', (tester) async {
    await tester.pumpWidget(
      _buildCardScreenWithPrefill({'cvv': '123'}),
    );
    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, '123'),
    );
    expect(field.controller?.text, equals('123'));
  });

  testWidgets('card prefill with multiple fields populates all', (tester) async {
    await tester.pumpWidget(
      _buildCardScreenWithPrefill({
        'card_number': '1234',
        'cardholder_name': 'Rob Bastian',
        'expiry': '06/27',
        'cvv': '999',
      }),
    );
    expect(find.widgetWithText(TextFormField, '1234'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Rob Bastian'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '06/27'), findsOneWidget);
  });

  testWidgets('card without prefill starts with empty fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateEntryScreen(
          entryType: 'Card',
          onCreateEntry: (_) async {},
          onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
        ),
      ),
    );
    final cardNumberField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Card number'),
    );
    expect(cardNumberField.controller?.text, isEmpty);
  });

  testWidgets('prefill does not affect existing edit mode', (tester) async {
    // existing takes precedence over prefill — both should not be set
    // simultaneously in production, but if they are, existing wins because
    // _initControllers checks existing first.
    final card = CardEntryData(
      id: 'card-id-1',
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
      cardholderName: 'Rob Bastian',
      cardNumber: '4111111111111111',
      expiry: '12/28',
      cvv: '123',
      status: 'active',
      customFields: [],
      pin: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreateEntryScreen(
          entryType: 'Card',
          existing: VaultEntryData.card(card),
          prefill: const {'card_number': 'should-not-appear'},
          onCreateEntry: (_) async {},
          onGetEntry: (_) => VaultEntryData.card(card),
        ),
      ),
    );
    // The existing card number should be shown, not the prefill value
    expect(
      find.widgetWithText(TextFormField, '4111111111111111'),
      findsOneWidget,
    );
    expect(find.text('should-not-appear'), findsNothing);
  });
}
