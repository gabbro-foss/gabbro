// Net for the vault-switch route stack (unlocked vault -> Manage vaults ->
// another vault).
//
// The rule the switch flow has to satisfy, in the user's terms:
//   - Cancel (Esc) BEFORE the new vault opens -> fall back to the vault that is
//     still unlocked. Cancelling must cost you your session.
//   - A SUCCESSFUL unlock of the new vault -> the previous vault is closed and
//     unreachable. Rust drops and zeroizes its keys (session.rs:105); the UI
//     must not keep a screen that still renders its entries.
//
// This file pins the first half green against the current code. The second half
// is red-first in the tests that follow it.
//
// All file I/O is sandboxed globally by test/flutter_test_config.dart.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/vault_registry.dart';

const alphaPath = '/nonexistent-sandbox/Alpha.gabbro';
const betaPath = '/nonexistent-sandbox/Beta.gabbro';

EntrySummaryData entry(String id, String title) => EntrySummaryData(
      id: id,
      entryType: 'Login',
      title: title,
      folder: 'Personal',
      searchBlob: '',
    );

VaultRegistry twoVaults() => VaultRegistry([
      VaultRecord(path: alphaPath, alias: 'Alpha', lastUsedAt: DateTime.now()),
      VaultRecord(path: betaPath, alias: 'Beta', lastUsedAt: DateTime.now()),
    ]);

/// The unlocked vault the user is sitting in when they open Manage vaults.
/// `yubikeyRecords: []` forces passphrase-only so nothing probes the vault file.
Widget alphaList() => VaultListScreen(
      vaultPath: alphaPath,
      vaultAlias: 'Alpha',
      listEntries: () => [entry('a1', 'Alpha entry')],
      listFolders: () => const ['Personal'],
      yubikeyRecords: const [],
    );

Widget app() => GabbroApp(
      registry: twoVaults(),
      vaultPath: alphaPath,
      settings: const AppSettings(),
      initialScreen: alphaList(),
    );

/// Desktop width: the switch flow is a Linux-desktop keyboard path.
void setDesktop(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

EntropyResult strongEntropy(String _) =>
    EntropyResult(bits: 120, tier: StrengthTier.veryStrong);

bool searchFocused(WidgetTester t) => t
    .widgetList<EditableText>(find.byType(EditableText))
    .any((w) => w.focusNode.hasFocus);

Future<void> pressCtrlF(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyF);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

/// Puts Beta's unlock screen over Alpha's list — the stack the Manage-vaults
/// tap builds, pinned by the first net test. Only the crypto call is stubbed,
/// so the real post-unlock routing runs.
Future<void> pushBetaUnlock(WidgetTester tester) async {
  final nav = tester.firstState<NavigatorState>(find.byType(Navigator));
  unawaited(nav.push(MaterialPageRoute(
    builder: (_) => UnlockScreen(
      vaultPath: betaPath,
      vaultAlias: 'Beta',
      yubikeyRecords: const [],
      onUnlock: (_, _) async {},
      onEstimateEntropy: strongEntropy,
    ),
  )));
  await tester.pumpAndSettle();
}

Future<void> completeUnlock(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'a-correct-passphrase');
  await tester.pump();
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

/// Walks the real path a user takes: Manage vaults, then tap the other vault's
/// row. Leaves the app on Beta's unlock screen.
Future<void> startSwitchToBeta(WidgetTester tester) async {
  final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;
  state.navigateToManageVaults();
  await tester.pumpAndSettle();
  expect(find.byType(ManageVaultsScreen), findsOneWidget,
      reason: 'precondition: the manage-vaults route is open');

  await tester.tap(find.text('Beta'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('net: Esc before the new vault opens falls back to the still-unlocked vault',
      (tester) async {
    setDesktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Alpha entry'), findsOneWidget,
        reason: 'precondition: sitting in the unlocked Alpha vault');

    await startSwitchToBeta(tester);
    final unlock = tester.widget<UnlockScreen>(find.byType(UnlockScreen));
    expect(unlock.vaultAlias, 'Beta',
        reason: 'the tap opens Beta unlock screen, nothing is unlocked yet');

    // D4 (main.dart:799): the passphrase field holds focus, so the first Esc
    // blurs it and the second leaves the screen. Pinning both steps, because
    // the fix must not turn cancelling into a one-key action either.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(UnlockScreen), findsOneWidget,
        reason: 'first Esc only blurs the passphrase field');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(UnlockScreen), findsNothing,
        reason: 'second Esc cancels the switch');
    expect(find.text('Alpha entry'), findsOneWidget,
        reason: 'cancelling returns to Alpha, which was never locked');
  });

  testWidgets('net: Esc on the vault list alone has nothing to pop',
      (tester) async {
    setDesktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final nav = tester.firstState<NavigatorState>(find.byType(Navigator));
    expect(await nav.maybePop(), isFalse,
        reason: 'a vault list reached normally is the only route on the stack');

    await tester.pumpAndSettle();
    expect(find.text('Alpha entry'), findsOneWidget,
        reason: 'Esc must never drop the user out of their open vault');
  });

  testWidgets('net: Esc still pops an ordinary pushed screen', (tester) async {
    setDesktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;
    state.navigateToManageVaults();
    await tester.pumpAndSettle();
    expect(find.byType(ManageVaultsScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ManageVaultsScreen), findsNothing,
        reason: 'Esc pops ordinary screens; the fix must not change this');
    expect(find.text('Alpha entry'), findsOneWidget);
  });

  // ── Red: the previous vault must be gone once the new one is open ────────

  testWidgets('a successful switch closes the previous vault screen',
      (tester) async {
    setDesktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await pushBetaUnlock(tester);
    await completeUnlock(tester);

    expect(find.byType(UnlockScreen), findsNothing,
        reason: 'the unlock succeeded, so its screen is done');
    expect(find.text('Alpha entry'), findsNothing,
        reason: "Alpha is closed; its entries must no longer be rendered");

    final nav = tester.firstState<NavigatorState>(find.byType(Navigator));
    expect(await nav.maybePop(), isFalse,
        reason: 'Esc must not reveal the vault that was just closed');
  });

  // The shortcut hooks are single global slots (vault_list_screen.dart:701):
  // the last vault list to mount owns them, and its dispose() clears them. If
  // Esc pops the newly opened vault back to a stranded one, the screen the user
  // is looking at owns no shortcuts at all — Tab and Ctrl+F do nothing.
  // (Asserted on the hooks, not on a focused search field: the vault list built
  // by production here loads through real FFI, so it renders its error state
  // and has no search field to focus.)
  testWidgets('Esc after a successful switch leaves a live vault list owning the shortcuts',
      (tester) async {
    setDesktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await pushBetaUnlock(tester);
    await completeUnlock(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(focusVaultSearch, isNotNull,
        reason: 'Ctrl+F must still reach a mounted vault list');
    expect(vaultRegionTab, isNotNull,
        reason: 'Tab must still drive the region cycle');
  });

  testWidgets('creating a vault from Manage vaults closes the previous vault',
      (tester) async {
    setDesktop(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(GabbroApp)) as GabbroAppState;
    state.navigateToManageVaults();
    await tester.pumpAndSettle();

    // A writable path: creation makes the parent directory before it calls
    // onInitVault, so an unwritable one never reaches the routing under test.
    final dir = Directory.systemTemp.createTempSync('gabbro_switch_');
    addTearDown(() => dir.deleteSync(recursive: true));

    // The add-vault route, as main.dart's onAddVault pushes it.
    final nav = tester.firstState<NavigatorState>(find.byType(Navigator));
    unawaited(nav.push(MaterialPageRoute(
      builder: (_) => OnboardingScreen(
        initialPath: '${dir.path}/Gamma.gabbro',
        onInitVault: (_, _, _) async {},
        onEstimateEntropy: strongEntropy,
        blockPassphraseCopyPaste: false,
        showYubikey: false,
      ),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Alias'), 'Gamma');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Master passphrase'),
        'a-correct-passphrase');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm passphrase'),
        'a-correct-passphrase');
    await tester.pump();
    // Creation saves the registry with real (sandboxed) file I/O, which the
    // fake-clock test zone would never complete — see LEARNINGS "Async dart:io
    // inside testWidgets".
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Create vault'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing,
        reason: 'precondition: the vault was created and its list opened');
    expect(find.text('Alpha entry'), findsNothing,
        reason: "the new vault is open; Alpha's entries must be gone");
    expect(find.byType(ManageVaultsScreen), findsNothing,
        reason: 'the manage-vaults route must not survive either');

    final navAfter = tester.firstState<NavigatorState>(find.byType(Navigator));
    expect(await navAfter.maybePop(), isFalse,
        reason: 'nothing from the previous vault may be reachable');
  });
}
