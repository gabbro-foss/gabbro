import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';
import 'package:gabbro/passkey_daemon.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/src/rust/api/passkey_daemon_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// TDD list "entry-list refresh on daemon store" (ARCHITECTURE.md): the vault
// list must show a passkey the moment the daemon stores it - the user is
// watching the list and otherwise concludes the create failed. Real
// VaultListScreen + real PasskeyDaemon; only I/O and the bridge are faked, so
// whatever production mechanism connects them is what is under test.

EntrySummaryData _entry(String id, String title) => EntrySummaryData(
      id: id,
      entryType: 'Passkey',
      title: title,
      folder: '',
      searchBlob: '',
    );

/// A device with a fixed queue of inbound requests; records every response.
class _FakeDevice implements PasskeyDevice {
  _FakeDevice(this._requests);
  final List<Uint8List> _requests;
  final List<Uint8List> sent = [];
  int _i = 0;

  @override
  Future<Uint8List?> nextRequest() async =>
      _i < _requests.length ? _requests[_i++] : null;

  @override
  Future<void> sendResponse(Uint8List response) async => sent.add(response);
}

PasskeyPlan _ask({bool isCreate = true}) => PasskeyPlan(
  immediateResponse: null,
  isCreate: isCreate,
  rpId: 'webauthn.io',
  accounts: const ['user@example.com'],
);

/// Pumps a vault list that counts its reloads, so a test can assert whether
/// the daemon triggered one.
Future<int Function()> _pumpCountingList(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  var loads = 0;
  await tester.pumpWidget(testApp(VaultListScreen(
    vaultPath: '/tmp/test.gabbro',
    listEntries: () {
      loads++;
      return <EntrySummaryData>[];
    },
  )));
  await tester.pumpAndSettle();
  return () => loads;
}

void main() {
  testWidgets('R1: approved create shows the stored entry with no interaction',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var entries = <EntrySummaryData>[];
    await tester.pumpWidget(testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => entries,
    )));
    await tester.pumpAndSettle();
    expect(find.text('webauthn.io'), findsNothing);

    final device = _FakeDevice([Uint8List.fromList([0x01, 0x11])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async => 0, // user approves in the consent dialog
      plan: (_) async => _ask(),
      perform: (_, _) async {
        // The Rust side stores the entry into the session.
        entries = [_entry('1', 'webauthn.io')];
        return Uint8List.fromList([0x00]);
      },
      denied: () async => fail('not cancelled'),
    );
    await daemon.run();
    await tester.pumpAndSettle();

    expect(device.sent, [
      [0x00],
    ], reason: 'the CTAP response reached the host');
    expect(find.text('webauthn.io'), findsOneWidget,
        reason: 'the list refreshes itself when the daemon stores a passkey');
  });

  testWidgets('R2: cancelled consent does not reload the list',
      (tester) async {
    final loads = await _pumpCountingList(tester);
    final before = loads();

    final device = _FakeDevice([Uint8List.fromList([0x01, 0x11])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async => null, // user cancels
      plan: (_) async => _ask(),
      perform: (_, _) async => fail('perform must not run when cancelled'),
      denied: () async => Uint8List.fromList([0x27]),
    );
    await daemon.run();
    await tester.pumpAndSettle();

    expect(device.sent, [
      [0x27],
    ]);
    expect(loads(), before, reason: 'nothing changed, so no reload');
  });

  testWidgets(
      'R3: an immediate-response request (getInfo/locked/no-match) does not '
      'reload the list', (tester) async {
    final loads = await _pumpCountingList(tester);
    final before = loads();

    final device = _FakeDevice([Uint8List.fromList([0x04])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async => fail('no consent for an immediate plan'),
      plan: (_) async => PasskeyPlan(
        immediateResponse: Uint8List.fromList([0x00, 0xAA]),
        isCreate: false,
        rpId: '',
        accounts: const [],
      ),
      perform: (_, _) async => fail('perform must not run'),
      denied: () async => fail('denied must not run'),
    );
    await daemon.run();
    await tester.pumpAndSettle();

    expect(device.sent, [
      [0x00, 0xAA],
    ]);
    expect(loads(), before, reason: 'nothing changed, so no reload');
  });

  testWidgets('R4: an approved sign-in reloads the list too', (tester) async {
    final loads = await _pumpCountingList(tester);
    final before = loads();

    final device = _FakeDevice([Uint8List.fromList([0x02, 0x22])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async => 0,
      plan: (_) async => _ask(isCreate: false),
      perform: (_, _) async => Uint8List.fromList([0x00]),
      denied: () async => fail('not cancelled'),
    );
    await daemon.run();
    await tester.pumpAndSettle();

    expect(loads(), before + 1,
        reason: 'an assert can touch entry metadata; show current state');
  });

  testWidgets(
      'R5: no list mounted at perform -> no crash, current on next mount',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    expect(reloadVaultList, isNull, reason: 'no vault list is mounted');

    var entries = <EntrySummaryData>[];
    final device = _FakeDevice([Uint8List.fromList([0x01, 0x11])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async => 0,
      plan: (_) async => _ask(),
      perform: (_, _) async {
        entries = [_entry('1', 'webauthn.io')];
        return Uint8List.fromList([0x00]);
      },
      denied: () async => fail('not cancelled'),
    );
    await daemon.run();

    expect(device.sent, [
      [0x00],
    ], reason: 'the store completed with no list to notify');

    await tester.pumpWidget(testApp(VaultListScreen(
      vaultPath: '/tmp/test.gabbro',
      listEntries: () => entries,
    )));
    await tester.pumpAndSettle();
    expect(find.text('webauthn.io'), findsOneWidget,
        reason: 'the next mount loads fresh');
  });

  test('R6: a throwing refresh never breaks the loop', () async {
    reloadVaultList = () => throw StateError('refresh blew up');
    addTearDown(() => reloadVaultList = null);

    final device = _FakeDevice([
      Uint8List.fromList([0x01, 0x11]),
      Uint8List.fromList([0x02, 0x22]),
    ]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async => 0,
      plan: (_) async => _ask(),
      perform: (_, _) async => Uint8List.fromList([0x00]),
      denied: () async => fail('not cancelled'),
    );
    await daemon.run();

    expect(device.sent, [
      [0x00],
      [0x00],
    ], reason: 'both hosts got their response despite the throwing refresh');
  });
}
