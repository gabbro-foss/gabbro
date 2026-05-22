import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ── Fake data helpers ─────────────────────────────────────────────────────────

EntrySummaryData _entry(String id, String title, String type) =>
    EntrySummaryData(
      id: id,
      entryType: type,
      title: title,
      folder: 'Personal',
    );

List<EntrySummaryData> _oneEntry() => [_entry('1', 'Quartz', 'Login')];

// ── Widget helper ─────────────────────────────────────────────────────────────

YubikeyRecordData _fakeRecord() => YubikeyRecordData(
      credentialId: Uint8List.fromList([1, 2, 3, 4]),
      salt: Uint8List(32),
    );

Widget _buildScreen({
  required Future<void> Function() deleteVault,
  List<YubikeyRecordData>? yubikeyRecords,
  Future<void> Function(List<int>, List<int>, String, String)? onConfirmYubikey,
  Future<void> Function(List<YubikeyRecordData>, String, String)? onConfirmAnyYubikey,
}) =>
    MaterialApp(
      home: VaultListScreen(
        vaultPath: '/tmp/test.gabbro',
        listEntries: _oneEntry,
        deleteVault: deleteVault,
        yubikeyRecords: yubikeyRecords ?? [],
        onConfirmYubikey: onConfirmYubikey ?? (_, _, _, _) async {},
        onConfirmAnyYubikey: onConfirmAnyYubikey ?? (_, _, _) async {},
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('delete vault menu item is enabled', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final item = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Delete vault'),
    );
    expect(item.enabled, isTrue);
  });

  testWidgets('step 1 dialog appears on delete vault tap', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();

    expect(find.text('Delete vault?'), findsOneWidget);
    expect(
      find.text(
        'This will permanently delete all entries. This cannot be undone.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('cancel on step 1 dismisses dialog, vault intact', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete vault?'), findsNothing);
    expect(find.text('Quartz'), findsOneWidget);
  });

  testWidgets('step 2 dialog appears after continuing step 1', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Type DELETE to confirm'), findsOneWidget);
  });

  testWidgets('confirm button disabled until DELETE typed', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Confirm'),
    );
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('delete_vault_confirm_field')), 'DELETE');
    await tester.pump();

    final confirmButtonAfter = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Confirm'),
    );
    expect(confirmButtonAfter.onPressed, isNotNull);
  });

  testWidgets('wrong text keeps confirm button disabled', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('delete_vault_confirm_field')), 'delete');
    await tester.pump();

    final confirmButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Confirm'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('cancel on step 2 dismisses dialog, vault intact', (tester) async {
    await tester.pumpWidget(_buildScreen(deleteVault: () async {}));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Type DELETE to confirm'), findsNothing);
    expect(find.text('Quartz'), findsOneWidget);
  });

  testWidgets('full confirm calls deleteVault and navigates to onboarding',
      (tester) async {
    var deleteCalled = false;
    await tester.pumpWidget(
      _buildScreen(deleteVault: () async => deleteCalled = true),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('delete_vault_confirm_field')), 'DELETE');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isTrue);
    expect(
      find.text('Your vault has been deleted. Create a new one to continue.'),
      findsOneWidget,
    );
  });

  // ── YubiKey vault delete ──────────────────────────────────────────────────────

  testWidgets('step 1 dialog mentions YubiKey binding for YubiKey vault',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(
        deleteVault: () async {},
        yubikeyRecords: [_fakeRecord()],
      ),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();

    expect(find.textContaining('YubiKey binding'), findsOneWidget);
  });

  testWidgets('step 1 dialog does not mention YubiKey for passphrase-only vault',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(deleteVault: () async {}, yubikeyRecords: []),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();

    expect(find.textContaining('YubiKey'), findsNothing);
  });

  // ── Step 3: YubiKey tap authorization ────────────────────────────────────────

  Future<void> throughStep2(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete_vault_confirm_field')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets('yubikey vault shows YubiKey authorization dialog after step 2',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      deleteVault: () async {},
      yubikeyRecords: [_fakeRecord()],
    ));
    await throughStep2(tester);

    expect(find.text('Touch your YubiKey'), findsOneWidget);
    expect(
      find.text(
        'Enter your PIN and touch your YubiKey to authorize this deletion.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'single-key yubikey vault calls onConfirmYubikey and deleteVault on authorize',
      (tester) async {
    bool confirmCalled = false;
    bool deleteCalled = false;
    await tester.pumpWidget(_buildScreen(
      deleteVault: () async => deleteCalled = true,
      yubikeyRecords: [_fakeRecord()],
      onConfirmYubikey: (_, _, _, _) async => confirmCalled = true,
    ));
    await throughStep2(tester);

    await tester.enterText(
      find.byKey(const Key('delete_vault_yubikey_pin_field')),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Authorize'));
    await tester.pumpAndSettle();

    expect(confirmCalled, isTrue);
    expect(deleteCalled, isTrue);
    expect(
      find.text('Your vault has been deleted. Create a new one to continue.'),
      findsOneWidget,
    );
  });

  testWidgets('multi-key yubikey vault shows YubiKey authorization dialog after step 2',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      deleteVault: () async {},
      yubikeyRecords: [_fakeRecord(), _fakeRecord()],
    ));
    await throughStep2(tester);

    expect(find.text('Touch your YubiKey'), findsOneWidget);
    expect(
      find.text(
        'Enter your PIN and touch your YubiKey to authorize this deletion.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'multi-key yubikey vault calls onConfirmAnyYubikey and deleteVault on authorize',
      (tester) async {
    bool confirmAnyCalled = false;
    bool deleteCalled = false;
    await tester.pumpWidget(_buildScreen(
      deleteVault: () async => deleteCalled = true,
      yubikeyRecords: [_fakeRecord(), _fakeRecord()],
      onConfirmAnyYubikey: (_, _, _) async => confirmAnyCalled = true,
    ));
    await throughStep2(tester);

    await tester.enterText(
      find.byKey(const Key('delete_vault_yubikey_pin_field')),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Authorize'));
    await tester.pumpAndSettle();

    expect(confirmAnyCalled, isTrue);
    expect(deleteCalled, isTrue);
    expect(
      find.text('Your vault has been deleted. Create a new one to continue.'),
      findsOneWidget,
    );
  });
}