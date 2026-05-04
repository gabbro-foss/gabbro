import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

CardEntryData _cardEntry({String? pin}) => CardEntryData(
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
      pin: pin,
    );

LoginEntryData _loginEntry() => LoginEntryData(
      id: 'test-id-1',
      title: 'Gneiss Bank',
      url: 'https://gneiss.example.com',
      username: 'rob@example.com',
      password: 's3cr3tP@ss',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      tags: [],
      favourite: false,
    );

// ── Widget helpers ────────────────────────────────────────────────────────────

Widget _buildCreateScreen(
  String entryType, {
  Future<void> Function(VaultEntryData)? onCreateEntry,
}) =>
    MaterialApp(
      home: CreateEntryScreen(
        entryType: entryType,
        onCreateEntry: onCreateEntry ?? (_) async {},
        onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
      ),
    );

Widget _buildEditScreen(VaultEntryData existing) => MaterialApp(
      home: CreateEntryScreen(
        entryType: 'Login',
        existing: existing,
        onCreateEntry: (_) async {},
        onGetEntry: (_) => existing,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('required field validation fires on empty save', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Login'));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Title is required'), findsOneWidget);
    expect(find.text('URL is required'), findsOneWidget);
    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('edit mode pre-populates fields', (tester) async {
    await tester.pumpWidget(
      _buildEditScreen(VaultEntryData.login(_loginEntry())),
    );

    expect(find.widgetWithText(TextFormField, 'Gneiss Bank'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'https://gneiss.example.com'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'rob@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('file entry shows pick file button not load button',
      (tester) async {
    await tester.pumpWidget(_buildCreateScreen('File'));
    expect(find.text('Pick file'), findsOneWidget);
    expect(find.text('Load'), findsNothing);
  });

  testWidgets('identity entry saves without email', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Identity'));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Ada',
    );
    // intentionally leave email empty
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Email is required'), findsNothing);
  });

  // ── Card PIN tests ────────────────────────────────────────────────────────

  testWidgets('card form renders PIN field', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Card'));
    expect(find.widgetWithText(TextFormField, 'PIN (optional)'), findsOneWidget);
  });

  testWidgets('card PIN field is obscured by default', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Card'));
    final pinField = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'PIN (optional)'),
        matching: find.byType(TextField),
      ),
    );
    expect(pinField.obscureText, isTrue);
  });

  testWidgets('card PIN show/hide toggle changes obscureText', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Card'));
    // Initially obscured — visibility_off icon present
    expect(find.byTooltip('Show PIN'), findsOneWidget);
    await tester.tap(find.byTooltip('Show PIN'));
    await tester.pump();
    expect(find.byTooltip('Hide PIN'), findsOneWidget);
  });

  testWidgets('card PIN value is passed to onCreateEntry', (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen('Card', onCreateEntry: (e) async => captured = e),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cardholder name'),
      'Rob Bastian',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Card number'),
      '4111111111111111',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Expiry (MM/YY)'),
      '12/28',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'CVV'),
      '123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN (optional)'),
      '9876',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(captured, isA<VaultEntryData_Card>());
    final card = (captured! as VaultEntryData_Card).field0;
    expect(card.pin, equals('9876'));
  });

  testWidgets('card PIN pre-populates in edit mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateEntryScreen(
          entryType: 'Card',
          existing: VaultEntryData.card(_cardEntry(pin: '1234')),
          onCreateEntry: (_) async {},
          onGetEntry: (_) => VaultEntryData.card(_cardEntry(pin: '1234')),
        ),
      ),
    );
    final pinField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'PIN (optional)'),
    );
    expect(pinField.controller?.text, equals('1234'));
  });

  // ── End card PIN tests ────────────────────────────────────────────────────

  testWidgets('save button calls onCreateEntry with correct type',
      (tester) async {
    VaultEntryData? captured;

    await tester.pumpWidget(
      _buildCreateScreen(
        'Login',
        onCreateEntry: (entry) async => captured = entry,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Schist Site',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL'),
      'https://schist.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'testuser',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'p@ssw0rd',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured, isA<VaultEntryData_Login>());
  });
}
