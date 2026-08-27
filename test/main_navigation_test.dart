// Widget tests for GabbroApp's navigation methods (the GabbroAppState interface).
// These are navigation + in-memory registry methods, not real-FFI paths, so they
// belong in `flutter test`: the app shell mounts via injectable constructor args
// and the target screens build without the native lib.
//
// Vault-deletion routing (`deleteVaultFromManager`, ADR-014) is NOT covered here:
// its post-delete navigation builds real FFI-backed screens (UnlockScreen's
// readability probe, etc.) which cannot run under `flutter test` (no Rust
// isolate). Its routing decision is unit-tested as a pure function
// (`postDeleteRoute`, see 5c49c19).
//
// All file I/O is sandboxed globally by test/flutter_test_config.dart, so nothing
// here can reach the user's real settings or vault folders.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/adopt_vault_screen.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

class _InitialScreen extends StatelessWidget {
  const _InitialScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('initial')));
}

VaultRegistry _registryWith(List<String> aliases) => VaultRegistry([
  for (final a in aliases)
    VaultRecord(
      path: '/nonexistent-sandbox/$a.gabbro',
      alias: a,
      lastUsedAt: DateTime.now(),
    ),
]);

Widget _app(VaultRegistry registry) => GabbroApp(
  registry: registry,
  vaultPath: registry.records.first.path,
  settings: const AppSettings(),
  initialScreen: const _InitialScreen(),
);

void main() {
  testWidgets('navigateToManageVaults pushes ManageVaultsScreen', (tester) async {
    await tester.pumpWidget(_app(_registryWith(['Alpha', 'Beta'])));
    await tester.pumpAndSettle();
    expect(find.byType(ManageVaultsScreen), findsNothing,
        reason: 'precondition: not on the manage screen yet');

    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;
    state.navigateToManageVaults();
    await tester.pumpAndSettle();

    expect(find.byType(ManageVaultsScreen), findsOneWidget,
        reason: 'navigateToManageVaults pushes the manage-vaults route');
  });

  // Security: switching vaults must clear the back stack so a back-press can
  // never reveal a prior (possibly unlocked) vault's screen. Mirrors auto-lock,
  // which already uses pushAndRemoveUntil.
  testWidgets('switchToVault clears the back stack (no pop back to a prior route)',
      (tester) async {
    await tester.pumpWidget(_app(_registryWith(['Alpha', 'Beta'])));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;

    // Build up a back stack on top of the initial route.
    state.navigateToManageVaults();
    await tester.pumpAndSettle();
    expect(find.byType(ManageVaultsScreen), findsOneWidget);

    state.switchToVault('/nonexistent-sandbox/Beta.gabbro', 'Beta');
    await tester.pumpAndSettle();

    // Attempt to go back: nothing prior must be reachable.
    final nav = tester.firstState<NavigatorState>(find.byType(Navigator));
    final popped = await nav.maybePop();
    await tester.pumpAndSettle();

    expect(popped, isFalse,
        reason: 'after switching vaults the stack is cleared; nothing to pop');
    expect(find.text('initial'), findsNothing,
        reason: 'must not be able to return to the pre-switch route');
    expect(find.byType(ManageVaultsScreen), findsNothing,
        reason: 'the prior manage-vaults route must not survive the switch');
  });

  testWidgets('openAdoptVault pushes AdoptVaultScreen with the live registry',
      (tester) async {
    await tester.pumpWidget(_app(_registryWith(['Alpha'])));
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;
    state.openAdoptVault();
    await tester.pumpAndSettle();

    final screen = tester.widget<AdoptVaultScreen>(find.byType(AdoptVaultScreen));
    expect(screen.registry.records.map((r) => r.alias), ['Alpha'],
        reason: 'the screen must see the real registry (alias collisions)');
  });

  // F9: registering an adopted vault must land on its unlock screen, locked,
  // with the back stack cleared — adopting grants no access.
  testWidgets('F9: adopt registration lands on the unlock screen for the vault',
      (tester) async {
    await tester.pumpWidget(_app(_registryWith(['Alpha'])));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;
    state.openAdoptVault();
    await tester.pumpAndSettle();

    // Drive production's registration callback exactly as the screen would.
    // runAsync: the callback saves the registry with real (sandboxed) file
    // I/O, which the fake-clock test zone would otherwise never complete
    // (async dart:io inside testWidgets).
    final screen = tester.widget<AdoptVaultScreen>(find.byType(AdoptVaultScreen));
    await tester.runAsync(
      () => screen.onRegistered('/nonexistent-sandbox/adopted.gabbro', 'Adopted'),
    );
    await tester.pumpAndSettle();

    final unlock = tester.widget<UnlockScreen>(find.byType(UnlockScreen));
    expect(unlock.vaultPath, '/nonexistent-sandbox/adopted.gabbro');
    expect(unlock.vaultAlias, 'Adopted');

    final nav = tester.firstState<NavigatorState>(find.byType(Navigator));
    expect(await nav.maybePop(), isFalse,
        reason: 'adopt must clear the back stack like any vault switch');
  });
}
