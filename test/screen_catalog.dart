import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/csv_mapping_screen.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/manage_yubikeys_screen.dart';
import 'package:gabbro/screens/review_changes_screen.dart';
import 'package:gabbro/screens/save_confirm_screen.dart';
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
import 'package:gabbro/screens/tablet_vault_layout.dart';
import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';
import 'package:gabbro/widgets/generator_widget.dart';
import 'package:gabbro/widgets/password_breakdown_sheet.dart';
import 'package:gabbro/widgets/sync_review.dart';
import 'package:gabbro/widgets/url_link.dart';
import 'package:gabbro/screens/import_failures_dialog.dart';
import 'package:gabbro/screens/import_skipped_dialog.dart';
import 'package:gabbro/widgets/path_field.dart';
import 'package:gabbro/widgets/segmented_row.dart';
import 'package:gabbro/widgets/text_size_slider.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/import.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';

// Shared catalog of every headless-renderable screen, widget and dialog, plus
// the surfaces and app shell used to render them. Both "every screen" nets sweep
// this one source: the overflow probe (overflow_probe_test.dart) and the
// accessibility net (a11y_net_test.dart). One catalog, no drift.

class Surface {
  final String name;
  final Size physical;
  final double dpr;
  const Surface(this.name, this.physical, this.dpr);
}

// physical / dpr chosen so the logical shortest side lands in each tier:
// phone 1080/3 = 360dp (-> 2.0x), tablet 1732/2 = 866dp (-> 3x).
const phone = Surface('phone 360dp->2.0x', Size(1080, 2400), 3.0);
const tablet = Surface('tablet 866dp->3x', Size(1732, 2400), 2.0);

/// The real app shell around [screen]. [textScale] 8.0 is above every device
/// max, so `clampToDevice` renders each surface at its ceiling (overflow probe);
/// pass 1.0 for a natural render (accessibility net). [localizationsDelegates]
/// defaults to production; the overflow probe's padded axis swaps it.
Widget appShell(
  Widget screen, {
  double textScale = 8.0,
  Iterable<LocalizationsDelegate<dynamic>> localizationsDelegates =
      gabbroLocalizationsDelegates,
}) => GabbroApp(
  registry: VaultRegistry([]),
  vaultPath: null,
  settings: AppSettings(textScale: textScale),
  initialScreen: screen,
  localizationsDelegates: localizationsDelegates,
);

EntropyResult strong(String _) =>
    EntropyResult(bits: 100, tier: StrengthTier.veryStrong);

const probeEntry = EntrySummaryData(
  id: 'e1',
  entryType: 'login',
  title: 'An entry title long enough to stress the row at max text',
  folder: 'A rather long folder name',
  searchBlob: '',
);

/// A login entry with overridable password/notes, for screens that diff or
/// display one.
VaultEntryData login(String password, String notes) => VaultEntryData.login(
  LoginEntryData(
    id: 'e1',
    title: 'A long entry title to stress the app bar at large text',
    url: 'https://example.com',
    username: 'user@example.com',
    password: password,
    notes: notes,
    customFields: [],
    createdAt: '2025-01-01T00:00:00Z',
    updatedAt: '2025-01-01T00:00:00Z',
    folder: 'Personal',
  ),
);

// Headless-instantiable screens. Platform-channel defaults are seamed out so a
// MissingPluginException can't masquerade as a layout overflow or a11y failure.
final Map<String, Widget Function()> screens = {
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
  // lib/widgets/ — nothing enumerated these before, which is how the
  // sync_review clipped-value bug reached a release. Each is wrapped in a
  // Scaffold because they are page fragments, not screens.
  'gabbro_logo': () => const Scaffold(body: GabbroLogo(withText: true)),
  'segmented_row': () => Scaffold(
    body: Column(
      children: [
        const SectionHeader(label: 'A section header long enough to wrap'),
        SegmentedRow<String>(
          values: const ['Classic', 'Passphrase', 'A third longer option'],
          selected: 'Classic',
          label: (v) => v,
          onSelected: (_) {},
        ),
      ],
    ),
  ),
  'text_size_slider': () => Scaffold(
    body: TextSizeSlider(
      scale: 1.0,
      deviceMax: 3.0,
      onChanged: (_) {},
      previewText: 'A preview line long enough to stress the row at max text',
    ),
  ),
  'path_field': () => Scaffold(
    body: PathField(
      mode: PathFieldMode.save,
      hint: 'A hint long enough to stress the field at max text scale',
      initialPath: '/tmp/probe.gabbro',
      onPathSelected: (_) {},
      savePicker: () async => null,
    ),
  ),
  // A 256-char password is the generator's maximum, so this is the widest the
  // character row can ever be.
  'password_breakdown_sheet': () => Scaffold(
    body: PasswordBreakdownSheet(password: 'aA1#' * 64),
  ),
  'generator_widget': () => Scaffold(
    body: GeneratorWidget(
      generatePasswordFn: (_) => 'aA1#' * 8,
      generatePassphraseFn: (_) async => 'correct horse battery staple',
      passphraseEntropyBitsFn: (_, _) async => 100.0,
      entropyBitsFn: (_, _) => 100.0,
    ),
  ),
  // Seams all have defaults and none fire at build time, so the real bridge is
  // never reached; leaving initialGabbroPath null keeps source detection (an
  // FFI call) out of the constructor.
  'import': () => ImportScreen(isAndroid: false),
  // The two-pane tablet layout. Probed on both surfaces even though it only
  // ships on the tablet path, so a phone-width regression cannot hide.
  'tablet_vault_layout': () => TabletVaultLayout(
    groupedEntries: const ['A', probeEntry],
    filteredEntries: const [probeEntry],
    letterIndex: const {'A': 0},
    onLetterSelected: (_) {},
    displayTitle: (e) => e.title,
    displayType: (t) => t,
    entryTypeIcon: (_) => Icons.lock,
    searchBar: const SizedBox(height: 48),
    filterChipRow: const SizedBox(height: 48),
    searchActive: false,
    onEntryTap: (_) {},
    onRefresh: () {},
    vaultPath: '/tmp/probe.gabbro',
    clipboardClearTimeout: ClipboardClearTimeout.sixtySeconds,
    getEntryFn: (_) => login('secret', 'Some notes'),
    onDeleteEntryFn: (_) async {},
    selectionMode: false,
    selectedIds: const {},
    onToggleSelection: (_) {},
  ),
  // listEntries defaults to a real FFI call that fires at build, so it must be
  // seamed or the probe reaches the bridge instead of rendering.
  'vault_list': () => VaultListScreen(
    vaultPath: '/tmp/probe.gabbro',
    vaultAlias: 'A rather long vault alias to stress the header',
    isAndroid: false,
    yubikeyRecords: const [],
    listEntries: () => const [
      EntrySummaryData(
        id: 'e1',
        entryType: 'login',
        title: 'An entry title long enough to stress the row at max text',
        folder: 'A rather long folder name',
        searchBlob: '',
      ),
    ],
    listFolders: () => const ['A rather long folder name', 'Work'],
    getEntryFn: (_) => login('secret', 'Some notes'),
    onDeleteEntryFn: (_) async {},
    onRefreshFn: () {},
  ),
  // yubikeyRecords: [] forces passphrase-only; left null it probes the vault
  // file over FFI at construction. The async checks below fire on init, so they
  // are seamed too or the probe would hit the real bridge.
  'unlock': () => UnlockScreen(
    vaultPath: '/tmp/probe.gabbro',
    vaultAlias: 'A rather long vault alias to stress the header',
    yubikeyRecords: const [],
    isAndroid: false,
    onEstimateEntropy: strong,
    onBiometricIsEnrolled: (_) async => false,
    onVaultIsReadable: (_) async => true,
    onVaultFormatTooOld: (_) async => false,
    onBackupUsable: (_) async => false,
  ),
  'csv_mapping': () => CsvMappingScreen(
    csvContent: 'title,url,username\nMail,https://example.com,user',
    preview: const CsvPreviewData(
      headers: [
        'A column header long enough to stress the dropdown',
        'url',
        'username',
      ],
      rows: [
        ['Mail', 'https://accounts.example.com/very/long/path', 'user'],
      ],
    ),
    onImport: (_, _) async => throw UnimplementedError(),
  ),
  'manage_yubikeys': () => ManageYubiKeysScreen(
    vaultPath: '/tmp/probe.gabbro',
    transport: 'usb',
    isAndroid: false,
    onListKeys: (_) => const [],
    onListAliases: () => const [],
    onSetAlias: (_, _) async {},
    onRemoveKey: (_) async {},
    onAddYubikey: ({
      required List<int> newCredId,
      required List<int> newHmacSecret,
      required List<int> newSalt,
    }) async {},
    onFidoListDevices: () => const [],
  ),
  'review_changes': () => ReviewChangesScreen(
    original: login('secret', 'Old notes'),
    updated: login(
      'a long replacement password to stress the diff row at max text',
      'Replacement notes long enough to wrap on a narrow phone screen',
    ),
    expiryDays: 30,
    onSave: (_, _) async {},
  ),
  'alphabet_index_bar': () => Scaffold(
    body: AlphabetIndexBar(
      presentLetters: const {'A', 'B', 'C'},
      onLetterSelected: (_) {},
    ),
  ),
  'save_confirm': () => SaveConfirmScreen(
    saveContext: const SaveContext(
      username: 'user@example.com',
      email: 'user@example.com',
      password: 'a long password value to stress the row at max text',
      url: 'https://accounts.example.com/very/long/path/for/the/save/prompt',
      appId: 'com.company.app',
      action: SaveActionKind.create,
      matchedId: null,
      candidates: [
        SaveCandidate(
          id: 'c1',
          label: 'An existing entry label long enough to wrap on a phone',
        ),
      ],
    ),
    onDone: () {},
    onCancel: () {},
    onCreate: (_) async {},
    onGetEntry: (_) => VaultEntryData.login(
      LoginEntryData(
        id: 'c1',
        title: 'Existing',
        url: 'https://example.com',
        username: 'user@example.com',
        password: 'secret',
        notes: '',
        customFields: [],
        createdAt: '2025-01-01T00:00:00Z',
        updatedAt: '2025-01-01T00:00:00Z',
        folder: '',
      ),
    ),
    onUpdate: (_, _) async {},
  ),
  'onboarding': () => OnboardingScreen(
    initialPath: '/tmp/probe.gabbro',
    onInitVault: (a, b, c) async {},
    onEstimateEntropy: strong,
    blockPassphraseCopyPaste: true,
    isAndroid: false,
    showYubikey: false,
    onInitVaultWithYubikey: (a, b, c, s2, s3, awaitBk, s4, t, alias) async {},
    resolveDataDir: GabbroPaths.dataDir,
  ),
};

// Dialog-shaped files export a `show*` function, not a widget, so they are
// opened rather than rendered.
final Map<String, Future<void> Function(BuildContext)> dialogs = {
  'url_link': (ctx) => showUrlDialog(
    ctx,
    title: 'A dialog title long enough to wrap at max text scale',
    url: 'https://accounts.example.com/very/long/path?token=abcdefghijklmnop',
  ),
  'sync_review': (ctx) async => showSyncReview(
    context: ctx,
    steps: buildSyncReviewSteps(
      const MergeSummary(
        added: 0,
        updated: 1,
        addedEntries: [],
        broughtOver: [],
        pendingDeletes: [],
        folderConflicts: [],
        fieldConflicts: [
          FieldConflictItem(
            id: 'e1',
            title: 'Mail',
            field: 'password',
            localValue: 'a long local password value to stress the row',
            incomingValue: 'a long incoming password value to stress the row',
          ),
        ],
        pendingItemDeletes: [],
      ),
    ),
  ),
  'import_skipped_dialog': (ctx) => showSkippedEntriesDialog(ctx, const [
    SkippedEntryData(
      title: 'An entry title long enough to stress the row at max text',
      reason: 'A skip reason long enough to wrap on a narrow phone',
    ),
  ]),
  'import_failures_dialog': (ctx) => showImportFailuresDialog(ctx, const [
    ImportFailureData(
      title: 'An entry title long enough to stress the row at max text',
      category: 'creditcard',
      reason: 'A failure reason long enough to wrap on a narrow phone',
      rawFields: [('card_number', '4111111111111111')],
    ),
  ]),
};

// Entries that only exist above a width breakpoint. Probing them narrower than
// the app ever builds them reports a failure the user can never meet — a harness
// artifact. vault_list_screen.dart gates the two-pane layout at >= 600dp.
const Map<String, String> tabletOnly = {
  'tablet_vault_layout': 'built only at width >= 600dp',
};

/// Source files each catalog entry stands for. Declared explicitly rather than
/// inferred from the map key, so the coverage guard cannot be satisfied by a
/// coincidental name match.
const Map<String, String> covers = {
  'about': 'about_screen',
  'help': 'help_screen',
  'appearance': 'appearance_screen',
  'language': 'language_screen',
  'generator': 'generator_screen',
  'export': 'export_screen',
  'change_passphrase': 'change_passphrase_screen',
  'security': 'security_screen',
  'manage_folders': 'manage_folders_screen',
  'manage_vaults': 'manage_vaults_screen',
  'entry_detail': 'entry_detail_screen',
  'recovery_history': 'recovery_history_screen',
  'create_entry (card)': 'create_entry_screen',
  'onboarding': 'onboarding_screen',
  'gabbro_logo': 'gabbro_logo',
  'segmented_row': 'segmented_row',
  'text_size_slider': 'text_size_slider',
  'path_field': 'path_field',
  'password_breakdown_sheet': 'password_breakdown_sheet',
  'generator_widget': 'generator_widget',
  'url_link': 'url_link',
  'sync_review': 'sync_review',
  'import_skipped_dialog': 'import_skipped_dialog',
  'import_failures_dialog': 'import_failures_dialog',
  'alphabet_index_bar': 'alphabet_index_bar',
  'save_confirm': 'save_confirm_screen',
  'review_changes': 'review_changes_screen',
  'import': 'import_screen',
  'unlock': 'unlock_screen',
  'vault_list': 'vault_list_screen',
  'tablet_vault_layout': 'tablet_vault_layout',
  'csv_mapping': 'csv_mapping_screen',
  'manage_yubikeys': 'manage_yubikeys_screen',
};

/// Files deliberately left out of the sweep, each with the reason. A waiver is a
/// claim that the file cannot render — not that it is "covered elsewhere", which
/// has previously overstated real coverage.
const Map<String, String> waived = <String, String>{
  'yubikey_tap': 'no widget class — platform-channel calls only, nothing renders',
  'section_index': 'no widget — alphabet/bucket helper functions, nothing renders',
};

/// Dart file stems directly under [dir].
List<String> sourcesIn(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) {
    fail('$dir does not exist — the coverage guard would pass vacuously');
  }
  return d
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.dart'))
      .map((n) => n.substring(0, n.length - 5))
      .toList()
    ..sort();
}

/// Every UI file the catalog must account for.
List<String> uiSources() =>
    [...sourcesIn('lib/screens'), ...sourcesIn('lib/widgets')]..sort();

// Pinned file counts. An empty or partial listing (wrong working directory,
// renamed folder) would otherwise leave `missing` empty and pass while checking
// nothing. Adding a screen or widget fails here first: the new file must be
// swept or waived deliberately.
const screenFileCount = 26;
const widgetFileCount = 9;
