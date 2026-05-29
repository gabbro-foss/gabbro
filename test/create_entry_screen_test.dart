import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

CardEntryData _cardEntry({String? pin}) => CardEntryData(
      id: 'card-id-1',
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
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
    );

// ── Widget helpers ────────────────────────────────────────────────────────────

Widget _buildCreateScreen(
  String entryType, {
  Future<void> Function(VaultEntryData)? onCreateEntry,
  List<String> Function()? listFolders,
}) =>
    testApp(CreateEntryScreen(
      entryType: entryType,
      onCreateEntry: onCreateEntry ?? (_) async {},
      onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
      listFolders: listFolders ?? () => ['Work', 'Private'],
    ));

Widget _buildEditScreen(VaultEntryData existing) => testApp(CreateEntryScreen(
      entryType: 'Login',
      existing: existing,
      onCreateEntry: (_) async {},
      onGetEntry: (_) => existing,
    ));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('required field validation fires on empty save', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Login'));

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Title is required'), findsOneWidget);
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
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
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
      find.widgetWithText(TextFormField, 'Card label (e.g. "Visa Platinum")'),
      'Visa Platinum',
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
      find.widgetWithText(TextFormField, 'CVV (optional)'),
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
      testApp(CreateEntryScreen(
        entryType: 'Card',
        existing: VaultEntryData.card(_cardEntry(pin: '1234')),
        onCreateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.card(_cardEntry(pin: '1234')),
      )),
    );
    final pinField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'PIN (optional)'),
    );
    expect(pinField.controller?.text, equals('1234'));
  });

  testWidgets('card form accepts 6-digit card number', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Card'));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Card label (e.g. "Visa Platinum")'),
      'Debit Card',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cardholder name'),
      'Rob Bastian',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Card number'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Expiry (MM/YY)'),
      '12/28',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Card number must be 6–19 digits'), findsNothing);
  });

  testWidgets('card form saves without CVV', (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen('Card', onCreateEntry: (e) async => captured = e),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Card label (e.g. "Visa Platinum")'),
      'Debit Card',
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
    // intentionally leave CVV empty
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isA<VaultEntryData_Card>());
    final card = (captured! as VaultEntryData_Card).field0;
    expect(card.cvv, equals(''));
  });

  // ── End card PIN tests ────────────────────────────────────────────────────

  // ── Login notes tests ─────────────────────────────────────────────────────

  testWidgets('login notes field pre-populates in edit mode', (tester) async {
    final entry = LoginEntryData(
      id: 'test-id-2',
      title: 'Basalt Blog',
      url: 'https://basalt.example.com',
      username: 'rob',
      password: 'p@ss',
      notes: 'remember to update this annually',
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(
      testApp(CreateEntryScreen(
        entryType: 'Login',
        existing: VaultEntryData.login(entry),
        onCreateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.login(entry),
      )),
    );
    final notesField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'remember to update this annually'),
    );
    expect(
      notesField.controller?.text,
      equals('remember to update this annually'),
    );
  });

  testWidgets('login notes field pre-populated value persists after title edit',
      (tester) async {
    final entry = LoginEntryData(
      id: 'test-id-3',
      title: 'Gabbro Vault',
      url: 'https://gabbro.example.com',
      username: 'rob',
      password: 'p@ss',
      notes: 'do not delete',
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
    );
    await tester.pumpWidget(
      testApp(CreateEntryScreen(
        entryType: 'Login',
        existing: VaultEntryData.login(entry),
        onCreateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.login(entry),
      )),
    );
    // Edit the title — notes field should be unaffected
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Gabbro Vault'),
      'Gabbro Vault Updated',
    );
    await tester.pump();
    // Notes field still shows the original value
    final notesField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'do not delete'),
    );
    expect(notesField.controller?.text, equals('do not delete'));
  });

  testWidgets('login notes field absent when entry has no notes',
      (tester) async {
    await tester.pumpWidget(
      _buildEditScreen(VaultEntryData.login(_loginEntry())),
    );
    // _loginEntry() has notes: null — notes field should render empty
    // notes field is optional — find it by label text
    final notesFieldFinder = find.widgetWithText(
      TextFormField,
      'Notes (optional)',
    );
    expect(notesFieldFinder, findsOneWidget);
    final notesField = tester.widget<TextFormField>(notesFieldFinder);
    expect(notesField.controller?.text, isEmpty);
  });

  testWidgets('login notes are passed to onCreateEntry', (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen(
        'Login',
        onCreateEntry: (e) async => captured = e,
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Obsidian Site',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL (optional)'),
      'https://obsidian.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'rob',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'p@ssw0rd',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes (optional)'),
      'created during hardware test',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(captured, isA<VaultEntryData_Login>());
    final login = (captured! as VaultEntryData_Login).field0;
    expect(login.notes, equals('created during hardware test'));
  });

  // ── End login notes tests ─────────────────────────────────────────────────

  testWidgets('login can be saved without a URL', (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen(
        'Login',
        onCreateEntry: (e) async => captured = e,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Basalt Computer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'rob',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'p@ssw0rd',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isA<VaultEntryData_Login>());
    expect((captured! as VaultEntryData_Login).field0.url, equals(''));
  });

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
      find.widgetWithText(TextFormField, 'URL (optional)'),
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

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured, isA<VaultEntryData_Login>());
  });

  testWidgets('folder picker renders with None option', (tester) async {
    await tester.pumpWidget(
      _buildCreateScreen('Login', listFolders: () => ['Work', 'Private']),
    );

    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('creating entry with folder selected passes folder to onCreateEntry',
      (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen(
        'Login',
        onCreateEntry: (e) async => captured = e,
        listFolders: () => ['Work', 'Private'],
      ),
    );

    // Pick 'Work' from the folder dropdown
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Granite');
    await tester.enterText(find.widgetWithText(TextFormField, 'URL (optional)'), 'https://granite.example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'rob');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'p@ss');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isA<VaultEntryData_Login>());
    expect((captured! as VaultEntryData_Login).field0.folder, equals('Work'));
  });

  testWidgets('creating entry with no folder selected passes empty string',
      (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen(
        'Login',
        onCreateEntry: (e) async => captured = e,
        listFolders: () => ['Work', 'Private'],
      ),
    );

    // Leave folder as None
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Pumice');
    await tester.enterText(find.widgetWithText(TextFormField, 'URL (optional)'), 'https://pumice.example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'rob');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'p@ss');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isA<VaultEntryData_Login>());
    expect((captured! as VaultEntryData_Login).field0.folder, equals(''));
  });

  testWidgets('edit mode pre-selects existing entry folder', (tester) async {
    await tester.pumpWidget(
      testApp(CreateEntryScreen(
        entryType: 'Login',
        existing: VaultEntryData.login(_loginEntry()),
        onCreateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
        listFolders: () => ['Work', 'Personal', 'Private'],
      )),
    );

    // _loginEntry() has folder: 'Personal' — should be pre-selected
    expect(find.text('Personal'), findsOneWidget);
  });

  // ── Card _hasChanges regression ───────────────────────────────────────────────

  testWidgets('editing card notes in edit mode reaches review screen',
      (tester) async {
    await tester.pumpWidget(
      testApp(CreateEntryScreen(
        entryType: 'Card',
        existing: VaultEntryData.card(_cardEntry()),
        onCreateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.card(_cardEntry()),
        listFolders: () => ['Personal'],
      )),
    );

    final notesField = find.widgetWithText(TextFormField, 'Notes (optional)').last;
    await tester.ensureVisible(notesField);
    await tester.pumpAndSettle();
    await tester.enterText(notesField, 'primary travel card');
    await tester.tap(find.text('Review →'));
    await tester.pumpAndSettle();

    expect(find.text('No changes to save.'), findsNothing);
  });

  // ── Custom field tests ────────────────────────────────────────────────────

  testWidgets('note form shows Add custom field button', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Note'));
    await tester.ensureVisible(find.text('Add custom field'));
    expect(find.text('Add custom field'), findsOneWidget);
  });

  testWidgets('file form shows Add custom field button', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('File'));
    await tester.ensureVisible(find.text('Add custom field'));
    expect(find.text('Add custom field'), findsOneWidget);
  });

  testWidgets('login form shows Add custom field button', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Login'));
    await tester.ensureVisible(find.text('Add custom field'));
    expect(find.text('Add custom field'), findsOneWidget);
  });

  testWidgets('adding a custom field to a note includes it in saved entry',
      (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen('Note', onCreateEntry: (e) async => captured = e),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Deploy guide',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Content'),
      'Step 1...',
    );
    await tester.ensureVisible(find.text('Add custom field'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add custom field'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Label'),
      'Token',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Value'),
      'abc123',
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isA<VaultEntryData_Note>());
    final note = (captured! as VaultEntryData_Note).field0;
    expect(note.customFields.length, equals(1));
    expect(note.customFields[0].label, equals('Token'));
    expect(note.customFields[0].value, equals('abc123'));
  });

  testWidgets('note edit mode pre-populates custom fields', (tester) async {
    final entry = NoteEntryData(
      id: 'note-1',
      title: 'My note',
      content: 'some content',
      customFields: const [
        CustomFieldData(label: 'Pin', value: '1234', hidden: true),
      ],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: '',
    );
    await tester.pumpWidget(
      testApp(CreateEntryScreen(
        entryType: 'Note',
        existing: VaultEntryData.note(entry),
        onCreateEntry: (_) async {},
        onGetEntry: (_) => VaultEntryData.note(entry),
      )),
    );

    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Pin'));
    expect(find.widgetWithText(TextFormField, 'Pin'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Pin'))
          .controller
          ?.text,
      equals('Pin'),
    );
    expect(find.widgetWithText(TextFormField, '1234'), findsOneWidget);
  });

  testWidgets('adding a custom field to a login includes it in saved entry',
      (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen('Login', onCreateEntry: (e) async => captured = e),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'GitHub',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'rob',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'p@ssw0rd',
    );
    await tester.ensureVisible(find.text('Add custom field'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add custom field'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Label'),
      'Recovery code',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Value'),
      'ABC-123',
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, isA<VaultEntryData_Login>());
    final login = (captured! as VaultEntryData_Login).field0;
    expect(login.customFields.length, equals(1));
    expect(login.customFields[0].label, equals('Recovery code'));
    expect(login.customFields[0].value, equals('ABC-123'));
  });

  // ── End custom field tests ────────────────────────────────────────────────
}
