import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/review_changes_screen.dart';
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
  Future<PickedFile?> Function()? pickFile,
}) =>
    testApp(CreateEntryScreen(
      entryType: entryType,
      onCreateEntry: onCreateEntry ?? (_) async {},
      onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
      listFolders: listFolders ?? () => ['Work', 'Private'],
      pickFile: pickFile ?? (() async => null),
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
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Title is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    // Username is optional now — it must NOT be required.
    expect(find.text('Username is required'), findsNothing);
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
      find.widgetWithText(TextFormField, 'Username (optional)'),
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
      find.widgetWithText(TextFormField, 'Username (optional)'),
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
      find.widgetWithText(TextFormField, 'Username (optional)'),
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
    await tester.enterText(find.widgetWithText(TextFormField, 'Username (optional)'), 'rob');
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
    await tester.enterText(find.widgetWithText(TextFormField, 'Username (optional)'), 'rob');
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

  // Attaching a file has no manual fallback, so an unavailable picker (sandbox/
  // no portal) shows the no-portal SnackBar instead of crashing the isolate.
  testWidgets('file form: an unavailable picker shows a SnackBar, no crash',
      (tester) async {
    await tester.pumpWidget(_buildCreateScreen(
      'File',
      pickFile: () async => throw const SocketException('no bus'),
    ));
    await tester.ensureVisible(find.text('Pick file'));
    await tester.tap(find.text('Pick file'));
    await tester.pump();
    expect(
      find.text(
          "File dialog unavailable here. The system file portal isn't reachable."),
      findsOneWidget,
    );
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
      find.widgetWithText(TextFormField, 'Username (optional)'),
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

  // ── Password field visibility toggle ─────────────────────────────────────

  testWidgets('login password field starts obscured and toggles visible',
      (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Login'));
    await tester.pumpAndSettle();

    // Initially obscured → eye-off icon shown.
    expect(find.byIcon(Icons.visibility_off), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Password'),
        matching: find.byIcon(Icons.visibility_off),
      ).first,
    );
    await tester.pumpAndSettle();

    // After toggle, eye icon shown (not eye-off).
    expect(find.byIcon(Icons.visibility), findsWidgets);
  });

  // ── Custom field deletion ─────────────────────────────────────────────────

  testWidgets('custom field can be removed after being added', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Note'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add custom field'));
    await tester.tap(find.text('Add custom field'));
    await tester.pumpAndSettle();

    // Field is now present.
    expect(find.widgetWithText(TextFormField, 'Label'), findsOneWidget);

    // Tap the remove button.
    await tester.ensureVisible(find.byIcon(Icons.remove_circle_outline));
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();

    // Field is gone.
    expect(find.widgetWithText(TextFormField, 'Label'), findsNothing);
  });

  // ── Custom field hidden toggle ────────────────────────────────────────────

  testWidgets('custom field value can be toggled hidden', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Note'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add custom field'));
    await tester.tap(find.text('Add custom field'));
    await tester.pumpAndSettle();

    // Initially the value field shows the "visible" eye (not hidden).
    final valueField = find.widgetWithText(TextFormField, 'Value');
    final visIcon = find.descendant(
      of: valueField,
      matching: find.byIcon(Icons.visibility),
    );
    await tester.ensureVisible(visIcon);
    await tester.tap(visIcon);
    await tester.pumpAndSettle();

    // After toggle, value is obscured → eye-off icon shown.
    expect(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Value'),
        matching: find.byIcon(Icons.visibility_off),
      ),
      findsOneWidget,
    );
  });

  // ── CVV visibility toggle (card form) ────────────────────────────────────

  testWidgets('card CVV field starts obscured and can be toggled', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Card'));
    await tester.pumpAndSettle();

    // CVV field: initially obscured.
    final cvvField = find.widgetWithText(TextFormField, 'CVV (optional)');
    await tester.ensureVisible(cvvField);
    final offIcon = find.descendant(
      of: cvvField,
      matching: find.byIcon(Icons.visibility_off),
    ).first;
    await tester.tap(offIcon);
    await tester.pumpAndSettle();

    // After toggle, visibility icon appears.
    expect(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'CVV (optional)'),
        matching: find.byIcon(Icons.visibility),
      ),
      findsOneWidget,
    );
  });

  // ── Custom entry type ─────────────────────────────────────────────────────

  testWidgets('custom entry form renders title field', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Custom'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Title'), findsOneWidget);
  });

  testWidgets('custom entry required title validation fires on empty save',
      (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Custom'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Title is required'), findsOneWidget);
  });

  testWidgets('custom entry saves with title', (tester) async {
    VaultEntryData? saved;
    await tester.pumpWidget(
      _buildCreateScreen(
        'Custom',
        onCreateEntry: (e) async {
          saved = e;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Rock Collection',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved, isA<VaultEntryData_Custom>());
    final custom = (saved! as VaultEntryData_Custom).field0;
    expect(custom.title, 'Rock Collection');
  });

  // ── Note entry validation ─────────────────────────────────────────────────

  testWidgets('note entry required title validation fires on empty save',
      (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Note'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Title is required'), findsOneWidget);
  });

  // ── Identity entry ────────────────────────────────────────────────────────

  testWidgets('identity form renders first and last name fields',
      (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Identity'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'First name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Last name'), findsOneWidget);
  });

  // ── Edit mode: no-changes guard ───────────────────────────────────────────

  testWidgets('review without changes shows no-changes snackbar',
      (tester) async {
    await tester.pumpWidget(
      _buildEditScreen(VaultEntryData.login(_loginEntry())),
    );
    await tester.pumpAndSettle();

    // Tap Review → without touching any field: _hasChanges() returns false.
    await tester.ensureVisible(find.text('Review →'));
    await tester.tap(find.text('Review →'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
  });

  // ── End custom field tests ────────────────────────────────────────────────

  // ── Android app ID (native-app autofill matching) ─────────────────────────

  testWidgets('login form shows the Android app ID field and helper note',
      (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Login'));
    expect(
      find.widgetWithText(TextFormField, 'Android app ID (optional)'),
      findsOneWidget,
    );
    expect(find.textContaining('Only an exact match works'), findsOneWidget);
  });

  testWidgets('login app ID is passed to onCreateEntry', (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen('Login', onCreateEntry: (e) async => captured = e),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Example');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username (optional)'), 'user');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Android app ID (optional)'),
      'com.company.app',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(captured, isA<VaultEntryData_Login>());
    expect((captured! as VaultEntryData_Login).field0.appId, equals('com.company.app'));
  });

  testWidgets('login app ID pre-populates in edit mode', (tester) async {
    final login = LoginEntryData(
      id: 'id-1',
      title: 'Example',
      url: '',
      username: 'user',
      password: 'secret',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      appId: 'com.company.app',
    );
    await tester.pumpWidget(_buildEditScreen(VaultEntryData.login(login)));
    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'com.company.app'),
    );
    expect(field.controller?.text, equals('com.company.app'));
  });

  testWidgets('recent app chips render and fill the app ID field',
      (tester) async {
    await tester.pumpWidget(testApp(CreateEntryScreen(
      entryType: 'Login',
      onCreateEntry: (_) async {},
      onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
      recentAppsFetcher: () async => ['com.company.app', 'com.other.app'],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Recently used apps'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ActionChip, 'com.other.app'));
    await tester.tap(find.widgetWithText(ActionChip, 'com.other.app'));
    await tester.pump();
    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'com.other.app'),
    );
    expect(field.controller?.text, equals('com.other.app'));
  });

  testWidgets('changing only the Android app ID is detected as a change',
      (tester) async {
    await tester.pumpWidget(_buildEditScreen(VaultEntryData.login(_loginEntry())));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Android app ID (optional)'),
      'com.company.app',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Review →'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review →'));
    await tester.pumpAndSettle();
    // The app-id change must be detected — not dismissed as "no changes".
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(ReviewChangesScreen), findsOneWidget);
  });

  testWidgets('no recent app chips when the list is empty', (tester) async {
    await tester.pumpWidget(testApp(CreateEntryScreen(
      entryType: 'Login',
      onCreateEntry: (_) async {},
      onGetEntry: (_) => VaultEntryData.login(_loginEntry()),
      recentAppsFetcher: () async => const [],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Recently used apps'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });

  // ── Login email field ─────────────────────────────────────────────────────

  testWidgets('login form shows the email field', (tester) async {
    await tester.pumpWidget(_buildCreateScreen('Login'));
    expect(find.widgetWithText(TextFormField, 'Email (optional)'), findsOneWidget);
  });

  testWidgets('login can be saved with no username (now optional)',
      (tester) async {
    VaultEntryData? captured;
    await tester.pumpWidget(
      _buildCreateScreen('Login', onCreateEntry: (e) async => captured = e),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Example');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email (optional)'),
      'user@example.com',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
    await tester.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(captured, isA<VaultEntryData_Login>());
    final login = (captured! as VaultEntryData_Login).field0;
    expect(login.username, isEmpty);
    expect(login.email, equals('user@example.com'));
  });

  testWidgets('login email pre-populates in edit mode', (tester) async {
    final login = LoginEntryData(
      id: 'id-1',
      title: 'Example',
      url: '',
      username: 'user',
      password: 'secret',
      notes: null,
      customFields: [],
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
      folder: 'Personal',
      email: 'user@example.com',
    );
    await tester.pumpWidget(_buildEditScreen(VaultEntryData.login(login)));
    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'user@example.com'),
    );
    expect(field.controller?.text, equals('user@example.com'));
  });
}
