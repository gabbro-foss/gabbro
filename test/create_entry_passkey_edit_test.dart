import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// Net for the passkey edit form (edit-only; entries are registered by the
// provider flow): site and account are identity, locked read-only; notes are
// the one free-text field. Labels must say so - a field inviting input that
// refuses it reads as broken.

PasskeyEntryData _passkeyEntry() => PasskeyEntryData(
      id: 'pk-id-1',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      folder: '',
      rpId: 'webauthn.example.com',
      userName: 'user@example.com',
      userDisplayName: 'Sample User',
      credentialIdB64: 'Y3JlZC1pZA',
      notes: 'a note',
      customFields: const [],
    );

Widget _buildEditScreen() {
  final existing = VaultEntryData.passkey(_passkeyEntry());
  return testApp(CreateEntryScreen(
    entryType: 'Passkey',
    existing: existing,
    onCreateEntry: (_) async => '',
    onGetEntry: (_) => existing,
  ));
}

void main() {
  testWidgets('site and account are read-only, notes editable', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildEditScreen());
    await tester.pumpAndSettle();

    // Identity fields shown but locked.
    expect(find.text('webauthn.example.com'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    await tester.enterText(find.text('webauthn.example.com'), 'evil.example');
    await tester.enterText(find.text('user@example.com'), 'other@example.com');
    await tester.pump();
    expect(find.text('webauthn.example.com'), findsOneWidget,
        reason: 'the site a passkey is bound to cannot be edited');
    expect(find.text('user@example.com'), findsOneWidget,
        reason: 'the account a passkey belongs to cannot be edited');

    // Notes accept input.
    await tester.enterText(find.text('a note'), 'an edited note');
    await tester.pump();
    expect(find.text('an edited note'), findsOneWidget);
  });

  testWidgets('read-only fields are not labelled optional', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildEditScreen());
    await tester.pumpAndSettle();

    // "(optional)" invites input on fields that refuse it.
    expect(find.text('URL'), findsOneWidget);
    expect(find.text('URL (optional)'), findsNothing);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Username (optional)'), findsNothing);
    // Notes really are editable and optional.
    expect(find.text('Notes (optional)'), findsOneWidget);
  });
}
