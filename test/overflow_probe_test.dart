import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/l10n/app_localizations.dart';
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

// ADR-016 Phase 2 headless overflow probe. Renders each screen at the device's
// MAX text scale on a phone and a tablet surface and asserts no RenderFlex /
// layout overflow (an overflow reports a FlutterError -> takeException()).
//
// Blind spot: a child clipped inside a FIXED width/height throws nothing, so
// this probe cannot see it. Both defects found in the l10n/a11y sweep so far
// (recovery-history actions, sync_review chip values) were of exactly that kind
// and came from hardware use, not from here.

class _Surface {
  final String name;
  final Size physical;
  final double dpr;
  const _Surface(this.name, this.physical, this.dpr);
}

// physical / dpr chosen so the logical shortest side lands in each tier:
// phone 1080/3 = 360dp (-> 2.0x), tablet 1732/2 = 866dp (-> 3x).
const _phone = _Surface('phone 360dp->2.0x', Size(1080, 2400), 3.0);
const _tablet = _Surface('tablet 866dp->3x', Size(1732, 2400), 2.0);

// textScale 8.0 is above every device max; clampToDevice caps it to the tier
// max, so each surface renders at its ceiling (2.0x phone / 3x tablet).
Widget _app(Widget screen) => GabbroApp(
  registry: VaultRegistry([]),
  vaultPath: null,
  settings: const AppSettings(textScale: 8.0),
  initialScreen: screen,
);

// --- Longer-language (padded) axis (ADR-016 item 3) -----------------------
// A layout overflows on rendered width, and width does not care which language
// produced it: "le renard..." and "the fox..." stress the same box. So instead
// of rendering all 37 real locales, render each screen ONCE under a synthetic
// locale whose every ARB label is ~2x its English length. One pass catches what
// any real language could; it may over-report (the safe direction). See
// ARCHITECTURE.md Current Focus.

// The real English strings, read from the template ARB so the padded axis tracks
// every new UI string automatically. `@key` metadata and `@@locale` are skipped.
final Map<String, String> _enArb = () {
  final raw =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (!k.startsWith('@') && v is String) out[k] = v;
  });
  return out;
}();

// ~2x the English length. A Latin pad under-models CJK glyph width (wider per
// character), so doubling with a space is a generous, not tight, margin.
String _pad(String v) => '$v $v';

// Every AppLocalizations member returns String and is abstract, so one
// noSuchMethod handler pads all ~600 of them. The member name is recovered from
// the invocation symbol (no dart:mirrors) and mapped back to its English value.
class _PaddedLocalizations implements AppLocalizations {
  static final _symbolName = RegExp(r'Symbol\("([^"]+)"\)');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final match = _symbolName.firstMatch(invocation.memberName.toString());
    final base = match == null ? null : _enArb[match.group(1)];
    return _pad(base ?? 'padded');
  }
}

class _PaddingDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _PaddingDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_PaddedLocalizations());
  @override
  bool shouldReload(_PaddingDelegate old) => false;
}

// The real delegate list with only AppLocalizations.delegate swapped for the
// padding one, so the fallback Material/Cupertino delegates are kept verbatim
// (no drift from production). Locale stays the default (en, supported), so the
// padded strings reach dialogs — which are root routes an in-body
// Localizations.override could not touch.
final List<LocalizationsDelegate<dynamic>> _paddedDelegates = [
  const _PaddingDelegate(),
  ...gabbroLocalizationsDelegates.where((d) => d != AppLocalizations.delegate),
];

Widget _paddedApp(Widget screen) => GabbroApp(
  registry: VaultRegistry([]),
  vaultPath: null,
  settings: const AppSettings(textScale: 8.0),
  initialScreen: screen,
  localizationsDelegates: _paddedDelegates,
);

EntropyResult _strong(String _) =>
    EntropyResult(bits: 100, tier: StrengthTier.veryStrong);

const _probeEntry = EntrySummaryData(
  id: 'e1',
  entryType: 'login',
  title: 'An entry title long enough to stress the row at max text',
  folder: 'A rather long folder name',
  searchBlob: '',
);

/// A login entry with overridable password/notes, for screens that diff or
/// display one.
VaultEntryData _login(String password, String notes) => VaultEntryData.login(
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
    groupedEntries: const ['A', _probeEntry],
    filteredEntries: const [_probeEntry],
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
    getEntryFn: (_) => _login('secret', 'Some notes'),
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
    getEntryFn: (_) => _login('secret', 'Some notes'),
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
    onEstimateEntropy: _strong,
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
    original: _login('secret', 'Old notes'),
    updated: _login(
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
    onEstimateEntropy: _strong,
    blockPassphraseCopyPaste: true,
    isAndroid: false,
    showYubikey: false,
    onInitVaultWithYubikey: (a, b, c, s2, s3, awaitBk, s4, t, alias) async {},
    resolveDataDir: GabbroPaths.dataDir,
  ),
};

// Screens with a KNOWN unfixed large-text layout issue, skipped (not silently
// passing); remove the entry once fixed so the probe re-arms on it. Empty now:
// recovery_history's ListTile-trailing case was fixed in Phase 3 Slice C.
const Map<String, String> _knownOverflow = <String, String>{};

// Entries that overflow only under the padded (longer-language) axis, each with
// a reason. Empty means every screen and dialog survives a ~2x-length locale.
const Map<String, String> _paddedKnownOverflow = <String, String>{};

// Entries that only exist above a width breakpoint. Probing them narrower than
// the app ever builds them reports an overflow the user can never meet — a
// harness artifact, not a defect. vault_list_screen.dart:1517 gates the
// two-pane layout at >= 600dp.
const Map<String, String> _tabletOnly = {
  'tablet_vault_layout': 'built only at width >= 600dp',
};

/// Render [screen] on [surface] at max text scale and return whatever layout
/// exception it threw, or null. Shared by the screen sweep and the self-test
/// below so both exercise the identical path.
Future<Object?> _probe(
  WidgetTester tester,
  Widget screen,
  _Surface surface, {
  Widget Function(Widget) app = _app,
}) async {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(app(screen));
  await tester.pump(const Duration(milliseconds: 300));
  return tester.takeException();
}

// Dialog-shaped files export a `show*` function, not a widget, so they are
// opened rather than rendered. Same surfaces, same max text scale, same
// assertion — only the pumping differs.
final Map<String, Future<void> Function(BuildContext)> _dialogs = {
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

/// Open [dialog] on [surface] at max text scale and return any layout exception.
Future<Object?> _probeDialog(
  WidgetTester tester,
  Future<void> Function(BuildContext) dialog,
  _Surface surface, {
  Widget Function(Widget) app = _app,
}) async {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    app(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => dialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 300));
  return tester.takeException();
}

// A Row far wider than any surface: guaranteed to overflow.
Widget _deliberateOverflow() => const Scaffold(
  body: Row(
    children: [SizedBox(width: 10000, height: 10, child: Placeholder())],
  ),
);

/// Source files each probe entry stands for. Declared explicitly rather than
/// inferred from the map key, so the coverage guard below cannot be satisfied by
/// a coincidental name match.
const Map<String, String> _covers = {
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
/// claim that the file cannot overflow or cannot be reached headless — not that
/// it is "covered elsewhere", which has previously overstated real coverage.
const Map<String, String> _waived = <String, String>{
  'yubikey_tap': 'no widget class — platform-channel calls only, nothing renders',
  'section_index': 'no widget — alphabet/bucket helper functions, nothing renders',
};

/// Dart file stems directly under [dir].
List<String> _sourcesIn(String dir) {
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

/// Every UI file the probe must account for.
List<String> _uiSources() =>
    [..._sourcesIn('lib/screens'), ..._sourcesIn('lib/widgets')]..sort();

// Pinned file counts. An empty or partial listing (wrong working directory,
// renamed folder) would otherwise leave `missing` empty and pass while checking
// nothing. Adding a screen or widget fails here first, which is the point: the
// new file must be probed or waived deliberately.
const _screenFileCount = 26;
const _widgetFileCount = 9;

void main() {
  // Nothing enumerated lib/widgets/ before, so sync_review's clipped-value bug
  // sat in a file no sweep touched. This fails until every screen AND widget is
  // either probed or explicitly waived with a reason.
  test('the file listing finds every screen and widget', () {
    expect(
      _sourcesIn('lib/screens').length,
      _screenFileCount,
      reason: 'screen count changed — probe or waive the new file, then update '
          '_screenFileCount',
    );
    expect(
      _sourcesIn('lib/widgets').length,
      _widgetFileCount,
      reason: 'widget count changed — probe or waive the new file, then update '
          '_widgetFileCount',
    );
  });

  test('every probe entry named in _covers really exists', () {
    // Otherwise a bare line in _covers satisfies the guard below while nothing
    // is actually rendered.
    final declared = _covers.keys.toSet();
    final real = {..._screens.keys, ..._dialogs.keys};
    expect(
      declared.difference(real),
      isEmpty,
      reason: '_covers names probe entries that do not exist',
    );
    expect(
      real.difference(declared),
      isEmpty,
      reason: 'probe entries missing from _covers, so they cover nothing',
    );
  });

  test('every screen and widget is probed or waived', () {
    final accounted = {..._covers.values, ..._waived.keys};
    final missing = _uiSources().where((s) => !accounted.contains(s)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          'not in the overflow probe and not waived:\n  ${missing.join('\n  ')}',
    );
  });

  // The guard on the guard. Every test below asserts an exception is ABSENT, so
  // if the probe ever stopped detecting overflow it would report green forever
  // and prove nothing. This pins that the mechanism still fires.
  testWidgets('the probe detects an overflow when one happens', (tester) async {
    expect(await _probe(tester, _deliberateOverflow(), _phone), isNotNull);
  });

  for (final surface in const [_phone, _tablet]) {
    for (final entry in _screens.entries) {
      testWidgets(
        '${entry.key} @ ${surface.name}: no overflow',
        (tester) async {
          expect(
            await _probe(tester, entry.value(), surface),
            isNull,
            reason: '${entry.key} @ ${surface.name} overflowed',
          );
        },
        skip: _knownOverflow.containsKey(entry.key) ||
            (surface == _phone && _tabletOnly.containsKey(entry.key)),
      );
    }

    for (final entry in _dialogs.entries) {
      testWidgets(
        '${entry.key} @ ${surface.name}: no overflow',
        (tester) async {
          expect(
            await _probeDialog(tester, entry.value, surface),
            isNull,
            reason: '${entry.key} @ ${surface.name} overflowed',
          );
        },
        skip: _knownOverflow.containsKey(entry.key),
      );
    }
  }

  // --- Longer-language (padded) axis --------------------------------------
  // Guard on the guard 1: the padded delegate must actually win at MaterialApp
  // level, or every assertion below passes vacuously against real English.
  testWidgets('the padded delegate reaches the widget tree', (tester) async {
    late String seen;
    await tester.pumpWidget(
      _paddedApp(
        Builder(
          builder: (ctx) {
            seen = AppLocalizations.of(ctx).appName;
            return const SizedBox();
          },
        ),
      ),
    );
    // appName is "Gabbro" in en; the padded locale doubles it.
    expect(seen, _pad('Gabbro'));
  });

  // Guard on the guard 2: overflow detection still fires under the padded app,
  // not only under the English one.
  testWidgets('the probe detects an overflow under the padded app', (
    tester,
  ) async {
    expect(
      await _probe(tester, _deliberateOverflow(), _phone, app: _paddedApp),
      isNotNull,
    );
  });

  // One pass at max text on the phone (narrowest x largest) under the padded
  // locale. Tablet-only screens are skipped as on the English phone pass.
  for (final entry in _screens.entries) {
    testWidgets(
      '${entry.key} @ padded phone: no overflow',
      (tester) async {
        expect(
          await _probe(tester, entry.value(), _phone, app: _paddedApp),
          isNull,
          reason: '${entry.key} overflowed under a ~2x-length locale',
        );
      },
      skip: _paddedKnownOverflow.containsKey(entry.key) ||
          _tabletOnly.containsKey(entry.key),
    );
  }

  for (final entry in _dialogs.entries) {
    testWidgets(
      '${entry.key} @ padded phone: no overflow',
      (tester) async {
        expect(
          await _probeDialog(tester, entry.value, _phone, app: _paddedApp),
          isNull,
          reason: '${entry.key} overflowed under a ~2x-length locale',
        );
      },
      skip: _paddedKnownOverflow.containsKey(entry.key),
    );
  }
}
