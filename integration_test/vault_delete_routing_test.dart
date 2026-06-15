// Phase 1 - Linux desktop, no hardware. ADR-014 vault-deletion routing.
//
// Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/vault_delete_routing_test.dart -d linux --profile
//
// Profile (not debug) is required: real Argon2id runs in initVault, which is far
// too slow in a debug Rust build. RustLib.init() loads the actual compiled lib so
// the post-delete navigation builds REAL screens — UnlockScreen's readability
// probe, the registry save, deleteVaultFiles — all of which go through FFI. Under
// plain `flutter test` (no Rust isolate) those futures never complete and the
// routing hangs, which is exactly why ADR-014's `deleteVaultFromManager` routing
// is verified here instead of in main_navigation_test.dart.
//
// What this pins (ADR-014): the active vault can be deleted even with siblings,
// and routing is - active+sibling -> remaining last-used vault's unlock screen;
// sole vault -> onboarding; non-active -> stay on Manage Vaults.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gabbro/app_paths.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';

import 'package:gabbro/src/rust/frb_generated.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

class _InitialScreen extends StatelessWidget {
  const _InitialScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('initial')));
}

Widget _app(VaultRegistry registry) => GabbroApp(
      registry: registry,
      vaultPath: registry.records.first.path,
      settings: const AppSettings(),
      initialScreen: const _InitialScreen(),
    );

// Seal a real passphrase-only vault on disk and return its registry record.
// [lastUsedAt] controls which vault registry.lastUsed reports as the active one.
Future<VaultRecord> _initRealVault(
  String dir,
  List<int> passphrase,
  String alias,
  DateTime lastUsedAt,
) async {
  final path = '$dir/$alias.gabbro';
  await initVault(passphrase: passphrase, path: path, alias: alias);
  return VaultRecord(path: path, alias: alias, lastUsedAt: lastUsedAt);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  late Directory tmp;
  String? previousSandbox;
  final passphrase = utf8.encode('correct horse battery staple');
  final base = DateTime(2026);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gabbro_it_delroute_');
    // Isolation (non-negotiable): registry.save() resolves through GabbroPaths,
    // and flutter_test_config's sandbox does NOT apply under `flutter drive`.
    // Without this the test would write the user's real ~/.config/gabbro.
    previousSandbox = GabbroPaths.sandboxRoot;
    GabbroPaths.sandboxRoot = tmp.path;
  });

  tearDown(() async {
    lockVault(); // drop session state regardless of outcome
    GabbroPaths.sandboxRoot = previousSandbox;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('deleting the active vault with a sibling routes to the remaining vault',
      (tester) async {
    final alpha = await _initRealVault(
        tmp.path, passphrase, 'Alpha', base.add(const Duration(days: 1)));
    final beta = await _initRealVault(tmp.path, passphrase, 'Beta', base);

    await tester.pumpWidget(_app(VaultRegistry([alpha, beta])));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;

    await state.deleteVaultFromManager(alpha.path); // Alpha is active (newest)
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing,
        reason: 'a remaining vault exists, so onboarding is not shown');
    expect(find.byType(UnlockScreen), findsOneWidget,
        reason: "routes to the remaining last-used vault's unlock screen");
    expect(state.registry.records.single.alias, 'Beta',
        reason: 'only the non-deleted vault remains in the registry');
    expect(File(alpha.path).existsSync(), isFalse,
        reason: 'the deleted vault file was really removed via FFI');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('deleting the sole vault routes to onboarding', (tester) async {
    final alpha = await _initRealVault(tmp.path, passphrase, 'Alpha', base);

    await tester.pumpWidget(_app(VaultRegistry([alpha])));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;

    await state.deleteVaultFromManager(alpha.path);
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget,
        reason: 'no vault remains -> onboarding');
    expect(state.registry.records, isEmpty);
    expect(File(alpha.path).existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('deleting a non-active vault stays on Manage Vaults', (tester) async {
    final alpha = await _initRealVault(
        tmp.path, passphrase, 'Alpha', base.add(const Duration(days: 1)));
    final beta = await _initRealVault(tmp.path, passphrase, 'Beta', base);

    await tester.pumpWidget(_app(VaultRegistry([alpha, beta])));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;

    state.navigateToManageVaults();
    await tester.pumpAndSettle();
    expect(find.byType(ManageVaultsScreen), findsOneWidget);

    await state.deleteVaultFromManager(beta.path); // Alpha is active
    await tester.pumpAndSettle();

    expect(find.byType(ManageVaultsScreen), findsOneWidget,
        reason: 'deleting a non-active vault must not navigate away');
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(state.registry.records.single.alias, 'Alpha',
        reason: 'the active vault is untouched');
    expect(File(beta.path).existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
