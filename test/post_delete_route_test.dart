// Pure routing decision for ADR-014 vault deletion. Unit-tested here (no FFI, no
// widgets) instead of via a flutter_drive integration suite: routing to real
// FFI-backed screens hangs under `flutter test` and is flaky in the GL driver.
// The actual navigation wiring is exercised by the manage-vaults widget tests
// and confirmed on hardware.

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';

void main() {
  group('postDeleteRoute (ADR-014)', () {
    test('deleting a non-active vault stays on Manage Vaults', () {
      expect(postDeleteRoute(wasActive: false, hasRemaining: true),
          PostDeleteRoute.stayOnManageVaults);
      expect(postDeleteRoute(wasActive: false, hasRemaining: false),
          PostDeleteRoute.stayOnManageVaults);
    });

    test('deleting the active vault with a sibling routes to the remaining vault',
        () {
      expect(postDeleteRoute(wasActive: true, hasRemaining: true),
          PostDeleteRoute.remainingVault);
    });

    test('deleting the sole (active) vault routes to onboarding', () {
      expect(postDeleteRoute(wasActive: true, hasRemaining: false),
          PostDeleteRoute.onboarding);
    });
  });
}
