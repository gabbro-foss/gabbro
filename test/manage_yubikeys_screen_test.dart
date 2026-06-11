import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/screens/manage_yubikeys_screen.dart';
import 'package:gabbro/src/rust/api/fido_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'test_helpers.dart';

const _yubiKeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

// Valid 32-hex-char credential ID and 64-hex-char HMAC secret for channel mocks.
const _fakeCredIdHex = 'aabbccddaabbccddaabbccddaabbccdd';
const _fakeHmacHex = 'eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011eeff0011';

void _setChannelMock(Future<dynamic> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_yubiKeyChannel, handler);
}

void _clearChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_yubiKeyChannel, null);
}

Future<void> _fillAndRegister(WidgetTester tester, {String pin = '123456'}) async {
  await tester.enterText(find.byType(TextField), pin);
  await tester.tap(find.text('Register'));
  await tester.pumpAndSettle();
}

// ── Factories ─────────────────────────────────────────────────────────────────

YubikeyRecordData _record(String hexPrefix) => YubikeyRecordData(
      credentialId: Uint8List.fromList(
          List.generate(16, (i) => int.parse(hexPrefix.padRight(2, '0'), radix: 16) + i)),
      salt: Uint8List(32),
    );

YubikeyAliasData _alias(String hex, String name) =>
    YubikeyAliasData(credentialIdHex: hex, alias: name);

FidoCredentialData _fakeCredential() => FidoCredentialData(
      credentialId: Uint8List.fromList(List.filled(16, 0xAB)),
      salt: Uint8List(32),
    );

// ── Screen builder ────────────────────────────────────────────────────────────

Widget _buildScreen({
  List<YubikeyRecordData> records = const [],
  List<YubikeyAliasData> aliases = const [],
  Future<void> Function(String hex, String alias)? onSetAlias,
  Future<void> Function(List<int> credId)? onRemoveKey,
  List<String> Function()? onFidoListDevices,
  Future<FidoCredentialData> Function({
    required String devicePath,
    required String pin,
  })? onFidoRegister,
  Future<List<int>> Function({
    required String devicePath,
    required List<int> credentialId,
    required List<int> salt,
    required String pin,
  })? onFidoGetHmacSecret,
  Future<void> Function({
    required List<int> newCredId,
    required List<int> newHmacSecret,
    required List<int> newSalt,
  })? onAddYubikey,
  bool throwOnLoad = false,
  bool? isAndroid,
}) =>
    testApp(ManageYubiKeysScreen(
      vaultPath: '/tmp/test.gabbro',
      isAndroid: isAndroid,
      onListKeys: (_) {
        if (throwOnLoad) throw Exception('disk read error');
        return records;
      },
      onListAliases: () => aliases,
      onSetAlias: onSetAlias ?? (_, _) async {},
      onRemoveKey: onRemoveKey ?? (_) async {},
      onAddYubikey: onAddYubikey ??
          ({required newCredId, required newHmacSecret, required newSalt}) async {},
      onFidoListDevices: onFidoListDevices ?? () => [],
      onFidoRegister: onFidoRegister ??
          ({required devicePath, required pin}) async => _fakeCredential(),
      onFidoGetHmacSecret: onFidoGetHmacSecret ??
          ({required devicePath, required credentialId, required salt, required pin}) async =>
              List.filled(32, 0),
    ));

void main() {
  // ── Loading and list states ───────────────────────────────────────────────

  testWidgets('credential hint is shown in subtitle for each key', (tester) async {
    // _credHint truncates long credential IDs to 16 hex chars + ellipsis.
    await tester
        .pumpWidget(_buildScreen(records: [_record('AA'), _record('BB')]));
    await tester.pumpAndSettle();

    // Each ListTile subtitle should start with "ID: ".
    expect(find.textContaining('ID: '), findsNWidgets(2));
  });

  testWidgets('shows empty state when no keys are registered', (tester) async {
    await tester.pumpWidget(_buildScreen(records: []));
    await tester.pumpAndSettle();

    expect(find.textContaining('No YubiKeys'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('lists keys with default titles when no alias set',
      (tester) async {
    final r1 = _record('AA');
    final r2 = _record('BB');
    await tester.pumpWidget(_buildScreen(records: [r1, r2]));
    await tester.pumpAndSettle();

    expect(find.text('Key 1'), findsOneWidget);
    expect(find.text('Key 2'), findsOneWidget);
  });

  testWidgets('shows alias when one is set for a key', (tester) async {
    final r = _record('CC');
    // Build the alias hex from the record's credentialId.
    final hex = r.credentialId
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await tester.pumpWidget(_buildScreen(
      records: [r, _record('DD')],
      aliases: [_alias(hex, 'My Backup Key')],
    ));
    await tester.pumpAndSettle();

    expect(find.text('My Backup Key'), findsOneWidget);
  });

  testWidgets('shows warning banner when only one key is registered',
      (tester) async {
    await tester.pumpWidget(_buildScreen(records: [_record('EE')]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('no warning banner when two or more keys are registered',
      (tester) async {
    await tester.pumpWidget(
        _buildScreen(records: [_record('FF'), _record('00')]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('shows error message when loading fails', (tester) async {
    await tester.pumpWidget(_buildScreen(throwOnLoad: true));
    await tester.pumpAndSettle();

    expect(find.textContaining('disk read error'), findsOneWidget);
  });

  // ── Delete button rules ───────────────────────────────────────────────────

  testWidgets('delete button is disabled when only one key exists',
      (tester) async {
    await tester.pumpWidget(_buildScreen(records: [_record('11')]));
    await tester.pumpAndSettle();

    final deleteBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline));
    expect(deleteBtn.onPressed, isNull);
  });

  testWidgets('delete button is enabled when two or more keys exist',
      (tester) async {
    await tester
        .pumpWidget(_buildScreen(records: [_record('22'), _record('33')]));
    await tester.pumpAndSettle();

    final deleteBtns = tester.widgetList<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline));
    expect(deleteBtns.every((b) => b.onPressed != null), isTrue);
  });

  // ── FAB visibility ────────────────────────────────────────────────────────

  testWidgets('add-key FAB is shown when fewer than four keys registered',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
        records: [_record('44'), _record('55'), _record('66')]));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('add-key FAB is hidden when four keys are registered',
      (tester) async {
    await tester.pumpWidget(_buildScreen(records: [
      _record('77'),
      _record('88'),
      _record('99'),
      _record('AA'),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  // ── Remove key flow ───────────────────────────────────────────────────────

  testWidgets('remove key: confirmation dialog appears on tap', (tester) async {
    await tester
        .pumpWidget(_buildScreen(records: [_record('A1'), _record('A2')]));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('remove key: cancel does not call onRemoveKey', (tester) async {
    bool removed = false;
    await tester.pumpWidget(_buildScreen(
      records: [_record('B1'), _record('B2')],
      onRemoveKey: (_) async => removed = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(removed, isFalse);
  });

  testWidgets('remove key: confirm calls onRemoveKey', (tester) async {
    bool removed = false;
    await tester.pumpWidget(_buildScreen(
      records: [_record('C1'), _record('C2')],
      onRemoveKey: (_) async => removed = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(removed, isTrue);
  });

  testWidgets(
      'remove key: extra warning shown when removing the second-to-last key',
      (tester) async {
    await tester
        .pumpWidget(_buildScreen(records: [_record('D1'), _record('D2')]));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();

    // The dialog should contain both the "last key warning" text and
    // the security-warning title.
    expect(find.textContaining('Security warning'), findsOneWidget);
  });

  // ── Edit alias flow ───────────────────────────────────────────────────────

  testWidgets('edit alias: dialog opens when edit button tapped',
      (tester) async {
    await tester
        .pumpWidget(_buildScreen(records: [_record('E1'), _record('E2')]));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('edit alias: cancel does not call onSetAlias', (tester) async {
    bool aliasSaved = false;
    await tester.pumpWidget(_buildScreen(
      records: [_record('F1'), _record('F2')],
      onSetAlias: (_, _) async => aliasSaved = true,
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(aliasSaved, isFalse);
  });

  testWidgets('edit alias: save calls onSetAlias with entered text',
      (tester) async {
    String? savedAlias;
    await tester.pumpWidget(_buildScreen(
      records: [_record('01'), _record('02')],
      onSetAlias: (_, alias) async => savedAlias = alias,
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work YubiKey');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedAlias, 'Work YubiKey');
  });

  // ── Linux FIDO add-key flow ───────────────────────────────────────────────

  testWidgets('add key Linux: shows snackbar when no FIDO device found',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      records: [_record('10')],
      onFidoListDevices: () => [],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('No FIDO'), findsOneWidget);
  });

  testWidgets('add key Linux: PIN cancel aborts the flow', (tester) async {
    bool registered = false;
    await tester.pumpWidget(_buildScreen(
      records: [_record('10')],
      onFidoListDevices: () => ['/dev/hidraw0'],
      onFidoRegister: ({required devicePath, required pin}) async {
        registered = true;
        return _fakeCredential();
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle(); // PIN dialog appears

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(registered, isFalse);
  });

  testWidgets('add key Linux: success path calls onAddYubikey and shows snackbar',
      (tester) async {
    bool addedKey = false;
    await tester.pumpWidget(_buildScreen(
      records: [_record('10')],
      onFidoListDevices: () => ['/dev/hidraw0'],
      onFidoRegister: ({required devicePath, required pin}) async =>
          _fakeCredential(),
      onFidoGetHmacSecret:
          ({required devicePath, required credentialId, required salt, required pin}) async =>
              List.filled(32, 0),
      onAddYubikey: ({required newCredId, required newHmacSecret, required newSalt}) async =>
          addedKey = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle(); // PIN dialog appears

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle(); // Register → hmac → addYubikey → load → snackbar

    expect(addedKey, isTrue);
    expect(find.textContaining('YubiKey added'), findsOneWidget);
  });

  testWidgets('add key Linux: register failure shows error snackbar',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      records: [_record('10')],
      onFidoListDevices: () => ['/dev/hidraw0'],
      onFidoRegister: ({required devicePath, required pin}) async =>
          throw Exception('device error'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to add key'), findsOneWidget);
  });

  testWidgets('add key Linux: hmac failure shows error snackbar', (tester) async {
    await tester.pumpWidget(_buildScreen(
      records: [_record('10')],
      onFidoListDevices: () => ['/dev/hidraw0'],
      onFidoRegister: ({required devicePath, required pin}) async =>
          _fakeCredential(),
      onFidoGetHmacSecret:
          ({required devicePath, required credentialId, required salt, required pin}) async =>
              throw Exception('hmac error'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to add key'), findsOneWidget);
  });

  // ── Error and success snackbars ───────────────────────────────────────────

  testWidgets('edit alias: error snackbar shown when onSetAlias throws',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      records: [_record('20'), _record('21')],
      onSetAlias: (_, _) async => throw Exception('storage full'),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('storage full'), findsOneWidget);
  });

  testWidgets('remove key: success snackbar shown after removal', (tester) async {
    await tester.pumpWidget(_buildScreen(
      records: [_record('30'), _record('31')],
      onRemoveKey: (_) async {},
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.textContaining('YubiKey removed'), findsOneWidget);
  });

  testWidgets('remove key: error snackbar shown when onRemoveKey throws',
      (tester) async {
    await tester.pumpWidget(_buildScreen(
      records: [_record('40'), _record('41')],
      onRemoveKey: (_) async => throw Exception('vault locked'),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.textContaining('vault locked'), findsOneWidget);
  });

  testWidgets('remove key: standard dialog shown when not the second-to-last key',
      (tester) async {
    // Three keys → removing one is not the second-to-last scenario.
    await tester.pumpWidget(_buildScreen(
        records: [_record('50'), _record('51'), _record('52')]));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();

    // Standard dialog title, not the security-warning variant.
    expect(find.textContaining('Remove YubiKey'), findsOneWidget);
    expect(find.textContaining('Security warning'), findsNothing);
  });

  // ── Android FIDO add-key flow (MethodChannel mocked) ─────────────────────

  testWidgets('add key Android: PIN cancel aborts the flow', (tester) async {
    bool addCalled = false;
    _setChannelMock((_) async => _fakeCredIdHex);
    addTearDown(_clearChannelMock);

    await tester.pumpWidget(_buildScreen(
      records: [_record('60')],
      isAndroid: true,
      onAddYubikey: ({required newCredId, required newHmacSecret, required newSalt}) async =>
          addCalled = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle(); // _promptPinAndTransport dialog appears

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(addCalled, isFalse);
  });

  testWidgets('add key Android: success via USB calls onAddYubikey and shows snackbar',
      (tester) async {
    bool addCalled = false;
    _setChannelMock((call) async {
      if (call.method == 'register') return _fakeCredIdHex;
      if (call.method == 'get_hmac_secret') return _fakeHmacHex;
      return null;
    });
    addTearDown(_clearChannelMock);

    await tester.pumpWidget(_buildScreen(
      records: [_record('61')],
      isAndroid: true,
      onAddYubikey: ({required newCredId, required newHmacSecret, required newSalt}) async =>
          addCalled = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await _fillAndRegister(tester);

    expect(addCalled, isTrue);
    expect(find.textContaining('YubiKey added'), findsOneWidget);
  });

  testWidgets('add key Android: register failure shows failedToRegisterKey snackbar',
      (tester) async {
    _setChannelMock((_) async => throw PlatformException(code: 'CTAP_ERR', message: 'tap failed'));
    addTearDown(_clearChannelMock);

    await tester.pumpWidget(_buildScreen(records: [_record('62')], isAndroid: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await _fillAndRegister(tester);

    expect(find.textContaining('Failed to register'), findsOneWidget);
  });

  testWidgets('add key Android: hmac failure shows failedToActivateKey snackbar',
      (tester) async {
    _setChannelMock((call) async {
      if (call.method == 'register') return _fakeCredIdHex;
      throw PlatformException(code: 'CTAP_ERR', message: 'activate failed');
    });
    addTearDown(_clearChannelMock);

    await tester.pumpWidget(_buildScreen(records: [_record('63')], isAndroid: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await _fillAndRegister(tester);

    expect(find.textContaining('Failed to activate'), findsOneWidget);
  });

  testWidgets('add key Android: NFC chip can be selected before registering',
      (tester) async {
    String? capturedTransport;
    _setChannelMock((call) async {
      capturedTransport = (call.arguments as Map)['transport'] as String?;
      if (call.method == 'register') return _fakeCredIdHex;
      if (call.method == 'get_hmac_secret') return _fakeHmacHex;
      return null;
    });
    addTearDown(_clearChannelMock);

    await tester.pumpWidget(_buildScreen(
      records: [_record('64')],
      isAndroid: true,
      onAddYubikey: ({required newCredId, required newHmacSecret, required newSalt}) async {},
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NFC'));
    await tester.pumpAndSettle();

    await _fillAndRegister(tester);

    expect(capturedTransport, 'nfc');
  });

  testWidgets('add key Android: Cancel aborts the in-flight tap via cancel_tap',
      (tester) async {
    final registerGate = Completer<String>();
    var cancelInvoked = false;
    _setChannelMock((call) async {
      if (call.method == 'register') return registerGate.future;
      if (call.method == 'cancel_tap') {
        cancelInvoked = true;
        return null;
      }
      return null;
    });
    addTearDown(_clearChannelMock);

    await tester.pumpWidget(_buildScreen(records: [_record('70')], isAndroid: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Register'));
    await tester.pump(); // PIN dialog starts closing, progress dialog opens
    await tester.pump(const Duration(milliseconds: 400)); // PIN dialog exit done

    await tester.tap(find.text('Cancel')); // progress dialog's Cancel
    await tester.pump();

    expect(cancelInvoked, isTrue);

    registerGate.completeError(PlatformException(code: 'TAP_CANCELLED'));
    await tester.pumpAndSettle();
  });

  testWidgets('add key Android: TAP_CANCELLED shows no error snackbar',
      (tester) async {
    _setChannelMock((call) async {
      if (call.method == 'register') {
        throw PlatformException(code: 'TAP_CANCELLED', message: 'cancelled');
      }
      return null;
    });
    addTearDown(_clearChannelMock);

    await tester.pumpWidget(_buildScreen(records: [_record('71')], isAndroid: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await _fillAndRegister(tester);

    expect(find.textContaining('Failed to register'), findsNothing);
  });
}
