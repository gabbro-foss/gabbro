import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/screens/change_passphrase_screen.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/screens/export_screen.dart';
import 'package:gabbro/screens/generator_screen.dart';
import 'package:gabbro/screens/help_screen.dart';
import 'package:gabbro/screens/language_screen.dart';
import 'package:gabbro/screens/manage_folders_screen.dart';
import 'package:gabbro/screens/manage_vaults_screen.dart';
import 'package:gabbro/screens/onboarding_screen.dart';
import 'package:gabbro/screens/recovery_history_screen.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// ADR-016 Phase 2 headless overflow probe. Renders each screen at the device's
// MAX text scale on a phone and a tablet surface and asserts no RenderFlex /
// layout overflow (an overflow reports a FlutterError -> takeException()).
//
// Blind spot (tracked in docs/PHASE2_OVERFLOW_COVERAGE.md): a child clipped
// inside a FIXED width/height throws nothing, so this probe cannot see it.

class _Surface {
  final String name;
  final Size physical;
  final double dpr;
  const _Surface(this.name, this.physical, this.dpr);
}

// physical / dpr chosen so the logical shortest side lands in each tier:
// phone 1080/3 = 360dp (-> 4x), tablet 1732/2 = 866dp (-> 6x).
const _phone = _Surface('phone 360dp->4x', Size(1080, 2400), 3.0);
const _tablet = _Surface('tablet 866dp->6x', Size(1732, 2400), 2.0);

// textScale 8.0 is above every device max; clampToDevice caps it to the tier
// max, so each surface renders at its ceiling (4x phone / 6x tablet).
Widget _app(Widget screen) => GabbroApp(
  registry: VaultRegistry([]),
  vaultPath: null,
  settings: const AppSettings(textScale: 8.0),
  initialScreen: screen,
);

EntropyResult _strong(String _) =>
    EntropyResult(bits: 100, tier: StrengthTier.veryStrong);

// Headless-instantiable screens. Platform-channel defaults are seamed out so a
// MissingPluginException can't masquerade as a layout overflow.
final Map<String, Widget Function()> _screens = {
  'about': () => const AboutScreen(),
  'help': () => const HelpScreen(),
  'appearance': () => const AppearanceScreen(),
  'language': () => const LanguageScreen(),
  'generator': () => const GeneratorScreen(),
  'export': () => ExportScreen(isAndroid: false),
  'change_passphrase': () =>
      const ChangePassphraseScreen(vaultPath: '/tmp/probe.gabbro'),
  'security': () => SecurityScreen(
    settings: const AppSettings(),
    onUpdate: (_) {},
    isAndroid: false,
  ),
  'manage_folders': () => ManageFoldersScreen(
    listFolders: () async => [
      'Work',
      'Personal',
      'A rather long folder name to stress the row',
    ],
    createFolder: (_) async {},
    renameFolder: (_, _) async {},
    deleteFolder: (_, _) async {},
  ),
  'manage_vaults': () => ManageVaultsScreen(
    registry: VaultRegistry([
      VaultRecord(
        path: '/tmp/a.gabbro',
        alias: 'A rather long personal vault name',
        lastUsedAt: DateTime(2025),
      ),
    ]),
    onRename: (_, _) async {},
    onDelete: (_) async {},
    onAddVault: () {},
    onSwitchToVault: (_, _) {},
    onConfirmYubikey: (_, _, _, _) async {},
    onConfirmAnyYubikey: (_, _, _) async {},
  ),
  'entry_detail': () => EntryDetailScreen(
    entry: VaultEntryData.login(
      LoginEntryData(
        id: 'e1',
        title: 'A long entry title to stress the app bar at large text',
        url: 'https://example.com',
        username: 'user@example.com',
        password: 'secret',
        notes: 'Some notes here',
        customFields: [],
        createdAt: '2025-01-01T00:00:00Z',
        updatedAt: '2025-01-01T00:00:00Z',
        folder: 'Personal',
      ),
    ),
    onFetchHistory: (_) async => [],
  ),
  'recovery_history': () => RecoveryHistoryScreen(
    records: [
      const HistoryRecordData(
        field: 'password',
        value: 'a previous value',
        savedAt: '2025-01-01T00:00:00Z',
        expiresAt: null,
      ),
    ],
    onRestore: (_) async {},
    onDelete: (_) async {},
  ),
  'create_entry (card)': () => CreateEntryScreen(
    entryType: 'card',
    listFolders: () => [
      'Personal',
      'Work',
      'A rather long folder name to stress the field',
    ],
    recentAppsFetcher: () async => const [],
  ),
  'onboarding': () => OnboardingScreen(
    initialPath: '/tmp/probe.gabbro',
    onInitVault: (a, b, c) async {},
    onEstimateEntropy: _strong,
    blockPassphraseCopyPaste: true,
    isAndroid: false,
    showYubikey: false,
    onInitVaultWithYubikey: (a, b, c, s2, s3, awaitBk, s4, t, alias) async {},
    resolveDataDir: GabbroPaths.dataDir,
  ),
};

// Screens with a KNOWN unfixed large-text layout issue, skipped (not silently
// passing) and tracked in PHASE2_OVERFLOW_COVERAGE.md; remove the entry once
// fixed so the probe re-arms on it.
const Map<String, String> _knownOverflow = {
  // ListTile with a trailing action Row can't fit horizontally at 4x, so the
  // list item fails to size (hasSize). A control-layout problem -> Phase 3.
  'recovery_history': 'ListTile trailing-actions do not fit at 4x (Phase 3)',
};

void main() {
  for (final surface in const [_phone, _tablet]) {
    for (final entry in _screens.entries) {
      testWidgets(
        '${entry.key} @ ${surface.name}: no overflow',
        (tester) async {
          tester.view.physicalSize = surface.physical;
          tester.view.devicePixelRatio = surface.dpr;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(_app(entry.value()));
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} @ ${surface.name} overflowed',
          );
        },
        skip: _knownOverflow.containsKey(entry.key),
      );
    }
  }
}
