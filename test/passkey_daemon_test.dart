import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/passkey_daemon.dart';
import 'package:gabbro/src/rust/api/passkey_daemon_bridge.dart';

// Orchestration net for the Linux passkey daemon (20b-ii): given a device that
// yields reassembled CTAP2 requests, the daemon plans each one, asks the user
// only when a choice applies, and writes exactly one response back. The uhid /
// CTAPHID byte plumbing (20b-iii) is out of scope here; bridge calls and the
// device are injected so this runs with no native library and no real device.

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

/// A device that fails on first read, like the uhid stream erroring when
/// /dev/uhid cannot be opened.
class _ThrowingDevice implements PasskeyDevice {
  @override
  Future<Uint8List?> nextRequest() async =>
      throw StateError('open /dev/uhid: EACCES');

  @override
  Future<void> sendResponse(Uint8List response) async =>
      fail('nothing to respond to on a dead device');
}

PasskeyPlan _ask({
  bool isCreate = true,
  String rpId = 'example.com',
  List<String> accounts = const ['user@example.com'],
}) => PasskeyPlan(
  immediateResponse: null,
  isCreate: isCreate,
  rpId: rpId,
  accounts: accounts,
);

PasskeyPlan _respond(List<int> bytes) => PasskeyPlan(
  immediateResponse: Uint8List.fromList(bytes),
  isCreate: false,
  rpId: '',
  accounts: const [],
);

void main() {
  test('an immediate-response plan is written back with no consent', () async {
    var consentAsked = false;
    final device = _FakeDevice([Uint8List.fromList([0x04])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async {
        consentAsked = true;
        return 0;
      },
      plan: (_) async => _respond([0x00, 0xAA]),
      perform: (_, _) async => fail('perform must not run for an immediate plan'),
      denied: () async => fail('denied must not run for an immediate plan'),
    );

    await daemon.run();

    expect(consentAsked, isFalse, reason: 'getInfo etc. never ask the user');
    expect(device.sent, [
      [0x00, 0xAA],
    ]);
  });

  test('an approved request is performed and its response written', () async {
    final device = _FakeDevice([Uint8List.fromList([0x01, 0x11])]);
    PasskeyRequest? seen;
    var performIndex = -1;
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (req) async {
        seen = req;
        return 0;
      },
      plan: (_) async => _ask(),
      perform: (_, index) async {
        performIndex = index;
        return Uint8List.fromList([0x00, 0xBB]);
      },
      denied: () async => fail('denied must not run when approved'),
    );

    await daemon.run();

    expect(seen?.isCreate, isTrue);
    expect(seen?.rpId, 'example.com');
    expect(performIndex, 0, reason: 'the chosen account index reaches perform');
    expect(device.sent, [
      [0x00, 0xBB],
    ]);
  });

  test('a cancelled request writes the denied response', () async {
    final device = _FakeDevice([Uint8List.fromList([0x01, 0x11])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (_) async => null, // user cancels
      plan: (_) async => _ask(),
      perform: (_, _) async => fail('perform must not run when cancelled'),
      denied: () async => Uint8List.fromList([0x27]),
    );

    await daemon.run();

    expect(device.sent, [
      [0x27],
    ]);
  });

  test('a device error completes run() cleanly and reports the failure',
      () async {
    // The real trigger: missing uhid module or udev rule surfaces as a
    // stream error on first read. run() must not leak it as an unhandled
    // async error -- it reports and returns, leaving the provider inactive.
    Object? reported;
    final daemon = PasskeyDaemon(
      device: _ThrowingDevice(),
      onConsent: (_) async => fail('no consent on a dead device'),
      plan: (_) async => fail('no plan on a dead device'),
      perform: (_, _) async => fail('no perform on a dead device'),
      denied: () async => fail('no denied on a dead device'),
      onFailure: (e) => reported = e,
    );

    await daemon.run(); // must complete, not throw

    expect(reported, isA<StateError>());
    expect('$reported', contains('/dev/uhid'));
  });

  group('failure status', () {
    setUp(() => passkeyProviderFailure.value = null);

    test('a reported failure lands in the provider-status notifier', () {
      reportPasskeyFailure(StateError('open /dev/uhid: boom'));
      expect(passkeyProviderFailure.value, isNotNull);
    });

    test('missing module (ENOENT) is told apart from a missing udev rule '
        '(EACCES)', () {
      // The banner's fix instructions differ: ENOENT means the uhid module
      // is not loaded, EACCES means the module is there but the udev rule
      // is not -- the wrong hint sends the user to the wrong command.
      expect(
        classifyPasskeyFailure(
          StateError('open /dev/uhid: No such file or directory (os error 2)'),
        ),
        PasskeyFailureReason.moduleMissing,
      );
      expect(
        classifyPasskeyFailure(
          StateError('open /dev/uhid: Permission denied (os error 13)'),
        ),
        PasskeyFailureReason.noAccess,
      );
      expect(
        classifyPasskeyFailure(StateError('anything else')),
        PasskeyFailureReason.other,
      );
    });
  });

  test('the chooser index for several accounts reaches perform', () async {
    final device = _FakeDevice([Uint8List.fromList([0x02, 0x22])]);
    final daemon = PasskeyDaemon(
      device: device,
      onConsent: (req) async => req.accounts.indexOf('b@example.com'),
      plan: (_) async =>
          _ask(isCreate: false, accounts: ['a@example.com', 'b@example.com']),
      perform: (_, index) async => Uint8List.fromList([0x00, index]),
      denied: () async => fail('not cancelled'),
    );

    await daemon.run();

    expect(device.sent, [
      [0x00, 1],
    ], reason: 'account index 1 (b@example.com) reaches perform');
  });
}
