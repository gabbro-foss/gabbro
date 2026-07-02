import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

YubikeyRecordData _fakeRecord() => YubikeyRecordData(
      credentialId: Uint8List.fromList([1, 2, 3, 4]),
      salt: Uint8List(32),
    );

// Opens SyncPassphraseDialog and returns the popped credentials (if any).
Future<SyncCredentials?> _open(
  WidgetTester tester, {
  required bool keyProtected,
  bool Function()? onHmac,
}) async {
  SyncCredentials? result;
  await tester.pumpWidget(testApp(Builder(
    builder: (context) => ElevatedButton(
      onPressed: () async {
        result = await showDialog<SyncCredentials>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SyncPassphraseDialog(
            filePath: '/tmp/source.gabbro',
            isKeyProtected: keyProtected,
            sourceRecords: keyProtected ? [_fakeRecord()] : const [],
            onGetYubikeyHmac: (_, _, _) async {
              onHmac?.call();
              return (hmac: <int>[1], credentialId: <int>[1, 2]);
            },
          ),
        );
      },
      child: const Text('open'),
    ),
  )));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  bool focused(WidgetTester tester, String label) => tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .focusNode!
      .hasFocus;

  testWidgets('Enter on the passphrase submits a passphrase-only source',
      (tester) async {
    await _open(tester, keyProtected: false);
    await tester.enterText(
        find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // Dialog popped (submitted): its fields are gone.
    expect(find.widgetWithText(TextField, 'Vault passphrase'), findsNothing);
  });

  testWidgets('Enter on the passphrase advances to the PIN (key-protected)',
      (tester) async {
    var hmacCalled = false;
    await _open(tester, keyProtected: true, onHmac: () => hmacCalled = true);
    await tester.enterText(
        find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(hmacCalled, isFalse, reason: 'must not submit before the PIN');
    expect(focused(tester, 'YubiKey PIN'), isTrue);
  });

  testWidgets('Enter on the PIN submits a key-protected source', (tester) async {
    var hmacCalled = false;
    await _open(tester, keyProtected: true, onHmac: () => hmacCalled = true);
    await tester.enterText(
        find.widgetWithText(TextField, 'Vault passphrase'), 'pw');
    await tester.enterText(
        find.widgetWithText(TextField, 'YubiKey PIN'), '1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(hmacCalled, isTrue);
  });
}
