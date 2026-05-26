import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/review_changes_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

CardEntryData _originalCard() => CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '123',
      pin: '4567',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: null,
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );

CardEntryData _updatedCardCvvAndPin() => CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '999',
      pin: '8888',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: null,
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );

IdentityEntryData _originalIdentity() => IdentityEntryData(
      id: 'identity-id-1',
      firstName: 'Rob',
      lastName: 'Example',
      email: '',
      phone: null,
      address: null,
      customFields: [
        CustomFieldData(label: 'Passport', value: 'AB123456', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );

IdentityEntryData _updatedIdentityCustomField() => IdentityEntryData(
      id: 'identity-id-1',
      firstName: 'Rob',
      lastName: 'Example',
      email: '',
      phone: null,
      address: null,
      customFields: [
        CustomFieldData(label: 'Passport', value: 'ZZ999999', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );

CustomEntryData _originalCustom() => CustomEntryData(
      id: 'custom-id-1',
      title: 'Server creds',
      fields: [
        CustomFieldData(label: 'IP', value: '10.0.0.1', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );

CustomEntryData _updatedCustomField() => CustomEntryData(
      id: 'custom-id-1',
      title: 'Server creds',
      fields: [
        CustomFieldData(label: 'IP', value: '10.0.0.2', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );

LoginEntryData _original() => LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com',
      username: 'rob@example.com',
      password: 'old_password',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      previousPassword: null,
    );

LoginEntryData _updatedPasswordAndUrl() => LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com/login',
      username: 'rob@example.com',
      password: 'new_password',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      previousPassword: null,
    );

LoginEntryData _updatedUrlOnly() => LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com/login',
      username: 'rob@example.com',
      password: 'old_password',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      previousPassword: null,
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _buildReviewScreen({
  required VaultEntryData original,
  required VaultEntryData updated,
  Future<void> Function(VaultEntryData, int?)? onSave,
}) =>
    MaterialApp(
      home: ReviewChangesScreen(
        original: original,
        updated: updated,
        expiryDays: 30,
        onSave: onSave ?? _noOpSave,
      ),
    );

Future<void> _noOpSave(VaultEntryData entry, int? days) async {}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('shows sensitive fields section when password changed',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedPasswordAndUrl()),
    ));

    expect(find.text('Sensitive fields'), findsOneWidget);
    expect(find.text('Password changed'), findsOneWidget);
  });

  testWidgets('does not show sensitive fields section when password unchanged',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    expect(find.text('Sensitive fields'), findsNothing);
    expect(find.text('Password changed'), findsNothing);
  });

  testWidgets('shows before and after values for changed non-sensitive fields',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    expect(find.text('https://github.com'), findsOneWidget);
    expect(find.text('https://github.com/login'), findsOneWidget);
  });

  testWidgets('does not show unchanged fields in diff', (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    // Title and username unchanged — must not appear in diff grid
    expect(find.text('Title'), findsNothing);
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('save button calls onSave with updated entry', (tester) async {
    VaultEntryData? saved;
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
      onSave: (entry, _) async => saved = entry,
    ));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved, isA<VaultEntryData_Login>());
  });

  testWidgets('cancel button pops the screen', (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(_original()),
      updated: VaultEntryData.login(_updatedUrlOnly()),
    ));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewChangesScreen), findsNothing);
  });

  testWidgets('CVV sensitive row has a working eye icon toggle',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(_originalCard()),
      updated: VaultEntryData.card(_updatedCardCvvAndPin()),
    ));

    expect(find.text('CVV changed'), findsOneWidget);
    // Eye icon present — toggle is wired, not a no-op
    expect(find.byIcon(Icons.visibility_off), findsWidgets);
    // Tap to reveal CVV new value
    final cvvRow = find.ancestor(
      of: find.text('CVV changed'),
      matching: find.byType(Container),
    ).first;
    await tester.tap(find.descendant(
      of: cvvRow,
      matching: find.byIcon(Icons.visibility_off),
    ));
    await tester.pump();
    expect(find.text('999'), findsOneWidget);
  });

  testWidgets('PIN sensitive row has a working eye icon toggle',
      (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(_originalCard()),
      updated: VaultEntryData.card(_updatedCardCvvAndPin()),
    ));

    expect(find.text('PIN changed'), findsOneWidget);
    // Tap PIN row eye icon to reveal new value
    final pinRow = find.ancestor(
      of: find.text('PIN changed'),
      matching: find.byType(Container),
    ).first;
    await tester.tap(find.descendant(
      of: pinRow,
      matching: find.byIcon(Icons.visibility_off),
    ));
    await tester.pump();
    expect(find.text('8888'), findsOneWidget);
  });

  testWidgets('Identity diff shows changed custom field', (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.identity(_originalIdentity()),
      updated: VaultEntryData.identity(_updatedIdentityCustomField()),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('AB123456'), findsOneWidget);
    expect(find.text('ZZ999999'), findsOneWidget);
  });

  testWidgets('Custom diff shows new field added (empty → value)', (tester) async {
    // original has no fields; updated adds one — the new field must appear in diff
    final original = CustomEntryData(
      id: 'custom-id-2',
      title: 'Wifi',
      fields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    final updated = CustomEntryData(
      id: 'custom-id-2',
      title: 'Wifi',
      fields: [
        CustomFieldData(label: 'SSID', value: 'HomeNetwork', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.custom(original),
      updated: VaultEntryData.custom(updated),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('SSID'), findsOneWidget);
    expect(find.text('(empty)'), findsOneWidget);
    expect(find.text('HomeNetwork'), findsOneWidget);
  });

  testWidgets('Custom diff shows changed field', (tester) async {
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.custom(_originalCustom()),
      updated: VaultEntryData.custom(_updatedCustomField()),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('IP'), findsOneWidget);
    expect(find.text('10.0.0.1'), findsOneWidget);
    expect(find.text('10.0.0.2'), findsOneWidget);
  });

  // ── Card optional-field diff regression ──────────────────────────────────────

  testWidgets('card number change appears in diff', (tester) async {
    final updated = CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '5500000000000004',
      expiry: '12/26',
      cvv: '123',
      pin: '4567',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: null,
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(_originalCard()),
      updated: VaultEntryData.card(updated),
    ));

    expect(find.text('Card number'), findsOneWidget);
    expect(find.text('4111111111111111'), findsOneWidget);
    expect(find.text('5500000000000004'), findsOneWidget);
  });

  testWidgets('credit limit change appears in diff for Card', (tester) async {
    final updated = CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '123',
      pin: '4567',
      status: 'active',
      paymentNetwork: null,
      creditLimit: '5000',
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: null,
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(_originalCard()),
      updated: VaultEntryData.card(updated),
    ));

    expect(find.text('Credit limit'), findsOneWidget);
    expect(find.text('(empty)'), findsOneWidget);
    expect(find.text('5000'), findsOneWidget);
  });

  testWidgets('notes change appears in diff for Card', (tester) async {
    final updated = CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '123',
      pin: '4567',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: null,
      notes: 'Primary travel card',
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(_originalCard()),
      updated: VaultEntryData.card(updated),
    ));

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('(empty)'), findsOneWidget);
    expect(find.text('Primary travel card'), findsOneWidget);
  });

  // ── Note / File / Login / Card custom field and new-field diffs ──────────────

  testWidgets('Note diff shows changed custom field', (tester) async {
    final original = NoteEntryData(
      id: 'note-1',
      title: 'Deploy notes',
      content: 'Step 1...',
      customFields: const [
        CustomFieldData(label: 'Token', value: 'abc123', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    final updated = NoteEntryData(
      id: 'note-1',
      title: 'Deploy notes',
      content: 'Step 1...',
      customFields: const [
        CustomFieldData(label: 'Token', value: 'xyz789', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.note(original),
      updated: VaultEntryData.note(updated),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('Token'), findsOneWidget);
    expect(find.text('abc123'), findsOneWidget);
    expect(find.text('xyz789'), findsOneWidget);
  });

  testWidgets('File diff shows notes change and size change', (tester) async {
    final original = FileEntryData(
      id: 'file-1',
      filename: 'backup.tar',
      data: Uint8List.fromList([1, 2, 3]),
      notes: null,
      customFields: const [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    final updated = FileEntryData(
      id: 'file-1',
      filename: 'backup.tar',
      data: Uint8List.fromList([1, 2, 3, 4, 5]),
      notes: 'updated backup',
      customFields: const [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.file(original),
      updated: VaultEntryData.file(updated),
    ));

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('(empty)'), findsOneWidget);
    expect(find.text('updated backup'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('3 bytes'), findsOneWidget);
    expect(find.text('5 bytes'), findsOneWidget);
  });

  testWidgets('File diff shows changed custom field', (tester) async {
    final original = FileEntryData(
      id: 'file-1',
      filename: 'key.pem',
      data: Uint8List.fromList([1]),
      notes: null,
      customFields: const [
        CustomFieldData(label: 'Passphrase', value: 'old_pass', hidden: true),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    final updated = FileEntryData(
      id: 'file-1',
      filename: 'key.pem',
      data: Uint8List.fromList([1]),
      notes: null,
      customFields: const [
        CustomFieldData(label: 'Passphrase', value: 'new_pass', hidden: true),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.file(original),
      updated: VaultEntryData.file(updated),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('Passphrase'), findsOneWidget);
    expect(find.text('old_pass'), findsOneWidget);
    expect(find.text('new_pass'), findsOneWidget);
  });

  testWidgets('Login diff shows changed custom field', (tester) async {
    final original = LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com',
      username: 'rob',
      password: 'pass',
      notes: null,
      customFields: const [
        CustomFieldData(label: '2FA backup', value: 'code-old', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
      previousPassword: null,
    );
    final updated = LoginEntryData(
      id: 'test-id-1',
      title: 'GitHub',
      url: 'https://github.com',
      username: 'rob',
      password: 'pass',
      notes: null,
      customFields: const [
        CustomFieldData(label: '2FA backup', value: 'code-new', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
      previousPassword: null,
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(original),
      updated: VaultEntryData.login(updated),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('2FA backup'), findsOneWidget);
    expect(find.text('code-old'), findsOneWidget);
    expect(find.text('code-new'), findsOneWidget);
  });

  testWidgets('Card bank name change appears in diff', (tester) async {
    final updated = CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '123',
      pin: '4567',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: 'Gneiss Bank',
      transactionPassword: null,
      notes: null,
      customFields: const [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(_originalCard()),
      updated: VaultEntryData.card(updated),
    ));

    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('(empty)'), findsOneWidget);
    expect(find.text('Gneiss Bank'), findsOneWidget);
  });

  testWidgets(
      'Card transaction password change appears in sensitive fields section',
      (tester) async {
    final updated = CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '123',
      pin: '4567',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: 's3cr3t',
      notes: null,
      customFields: const [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(_originalCard()),
      updated: VaultEntryData.card(updated),
    ));

    expect(find.text('Sensitive fields'), findsOneWidget);
    expect(find.text('Transaction password changed'), findsOneWidget);
  });

  testWidgets('Card diff shows changed custom field', (tester) async {
    final original = CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '123',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: null,
      notes: null,
      pin: null,
      customFields: const [
        CustomFieldData(label: 'Membership', value: 'Gold', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    final updated = CardEntryData(
      id: 'card-id-1',
      cardName: 'Granite Visa',
      cardholderName: 'Rob Example',
      cardNumber: '4111111111111111',
      expiry: '12/26',
      cvv: '123',
      status: 'active',
      paymentNetwork: null,
      creditLimit: null,
      cardAccountNumber: null,
      bankName: null,
      transactionPassword: null,
      notes: null,
      pin: null,
      customFields: const [
        CustomFieldData(label: 'Membership', value: 'Platinum', hidden: false),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.card(original),
      updated: VaultEntryData.card(updated),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('Membership'), findsOneWidget);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('Platinum'), findsOneWidget);
  });

  // ── End custom field diff tests ───────────────────────────────────────────

  testWidgets('folder change appears in diff for Login entry', (tester) async {
    final original = LoginEntryData(
      id: 'test-id-1', title: 'GitHub', url: 'https://github.com',
      username: 'rob@example.com', password: 'old_password', notes: null,
      customFields: [], createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z', folder: 'Work',
      previousPassword: null,
    );
    final updated = LoginEntryData(
      id: 'test-id-1', title: 'GitHub', url: 'https://github.com',
      username: 'rob@example.com', password: 'old_password', notes: null,
      customFields: [], createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z', folder: 'Personal',
      previousPassword: null,
    );
    await tester.pumpWidget(_buildReviewScreen(
      original: VaultEntryData.login(original),
      updated: VaultEntryData.login(updated),
    ));

    expect(find.text('Other fields'), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
  });
}