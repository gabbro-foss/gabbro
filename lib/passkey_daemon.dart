import 'dart:async';
import 'dart:typed_data';

import 'src/rust/api/passkey_daemon_bridge.dart';

/// The transport the daemon reads requests from and writes responses to. The
/// real one wraps the uhid device (20b-iii); tests inject a fake.
abstract class PasskeyDevice {
  /// The next reassembled CTAP2 request (command byte + CBOR), or null when
  /// the device closes and the daemon should stop.
  Future<Uint8List?> nextRequest();

  /// Frame and write one CTAP2 response back to the host.
  Future<void> sendResponse(Uint8List response);
}

/// What the consent UI is shown for one request: the site and, when several
/// accounts match a sign-in, the choices.
class PasskeyRequest {
  PasskeyRequest({
    required this.isCreate,
    required this.rpId,
    required this.accounts,
  });
  final bool isCreate;
  final String rpId;
  final List<String> accounts;
}

/// Shows consent and returns the chosen account index, or null to cancel.
typedef ConsentFn = Future<int?> Function(PasskeyRequest request);

typedef PlanFn = Future<PasskeyPlan> Function(List<int> payload);
typedef PerformFn = Future<Uint8List> Function(List<int> payload, int accountIndex);
typedef DeniedFn = Future<Uint8List> Function();

/// Drives each CTAP2 request across the Rust seam: plan it, ask the user only
/// when a choice applies, perform (or deny), and write exactly one response.
/// I/O and the bridge calls are injected so the decision logic is testable
/// without a real device or the native library.
class PasskeyDaemon {
  PasskeyDaemon({
    required this.device,
    required this.onConsent,
    PlanFn? plan,
    PerformFn? perform,
    DeniedFn? denied,
  }) : _plan = plan ?? _defaultPlan,
       _perform = perform ?? _defaultPerform,
       _denied = denied ?? _defaultDenied;

  final PasskeyDevice device;
  final ConsentFn onConsent;
  final PlanFn _plan;
  final PerformFn _perform;
  final DeniedFn _denied;

  /// Serve requests until the device closes. One response per request: an
  /// immediate plan (getInfo, locked, no match, malformed) is written straight
  /// back; anything else shows consent, then performs or denies.
  Future<void> run() async {
    while (true) {
      final payload = await device.nextRequest();
      if (payload == null) return;

      final plan = await _plan(payload);
      final immediate = plan.immediateResponse;
      if (immediate != null) {
        await device.sendResponse(immediate);
        continue;
      }

      final choice = await onConsent(
        PasskeyRequest(
          isCreate: plan.isCreate,
          rpId: plan.rpId,
          accounts: plan.accounts,
        ),
      );
      final response = choice == null
          ? await _denied()
          : await _perform(payload, choice);
      await device.sendResponse(response);
    }
  }
}

Future<PasskeyPlan> _defaultPlan(List<int> payload) =>
    passkeyPlan(payload: payload);
Future<Uint8List> _defaultPerform(List<int> payload, int accountIndex) =>
    passkeyPerform(payload: payload, accountIndex: BigInt.from(accountIndex));
Future<Uint8List> _defaultDenied() => passkeyDenied();

/// The real device: the Rust daemon owns `/dev/uhid` and streams complete
/// CTAP2 requests; responses go back through the bridge. Matrix-only (needs
/// the native library and a real uhid device), so it carries no unit test —
/// the orchestration it feeds is covered by [PasskeyDaemon]'s tests.
class UhidPasskeyDevice implements PasskeyDevice {
  UhidPasskeyDevice() : _requests = StreamIterator(passkeyDaemonStart());

  final StreamIterator<Uint8List> _requests;

  @override
  Future<Uint8List?> nextRequest() async =>
      await _requests.moveNext() ? _requests.current : null;

  @override
  Future<void> sendResponse(Uint8List response) =>
      passkeyDaemonRespond(response: response);

  /// Stop the daemon and unplug the virtual device.
  Future<void> dispose() async {
    await _requests.cancel();
    await passkeyDaemonStop();
  }
}
