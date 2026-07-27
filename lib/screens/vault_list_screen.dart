import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/control_scale.dart';
import 'package:gabbro/nfc_capability.dart';
import 'package:gabbro/safe_file_picker.dart';
import 'package:gabbro/screens/alphabet_index_bar.dart';
import 'package:gabbro/screens/section_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:gabbro/screens/create_entry_screen.dart';
import 'package:gabbro/screens/import_screen.dart';
import 'package:gabbro/screens/entry_detail_screen.dart';
import 'package:gabbro/screens/about_screen.dart';
import 'package:gabbro/screens/help_screen.dart';
import 'package:gabbro/gabbro_contrast.dart';
import 'package:gabbro/screens/keyboard_shortcuts_list_screen.dart';
import 'package:gabbro/widgets/focus_region.dart';
import 'package:gabbro/screens/export_screen.dart';
import 'package:gabbro/screens/appearance_screen.dart';
import 'package:gabbro/screens/language_screen.dart';
import 'package:gabbro/screens/security_screen.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/change_passphrase_screen.dart';
import 'package:gabbro/screens/generator_screen.dart';
import 'package:gabbro/screens/manage_folders_screen.dart';
import 'package:gabbro/screens/manage_yubikeys_screen.dart';

import 'package:gabbro/screens/unlock_screen.dart';
import 'package:gabbro/screens/tablet_vault_layout.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/fido_bridge.dart';
import 'package:gabbro/src/rust/api/vault.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/yubikey_tap.dart';
import 'package:gabbro/widgets/sync_review.dart';

List<String> _defaultListFolders() => listFolders();
Future<MergeSummary> _defaultMergeVault(String path, List<int> passphrase) =>
    mergeVaultFromFile(path: path, passphrase: passphrase);

/// Sync from a key-protected source: passphrase + a tapped registered YubiKey
/// (ADR-013). The sync analogue of the import screen's keyed Gabbro path.
Future<MergeSummary> _defaultMergeVaultWithKey(
  String path,
  List<int> passphrase,
  List<int> hmac,
  List<int> credentialId,
) => mergeVaultFromFileWithKey(
  path: path,
  passphrase: passphrase,
  hmacSecret: hmac,
  credentialId: credentialId,
);

/// Fast auto-merge (incoming wins, no prompts) — the "Merge automatically" path.
Future<MergeSummary> _defaultFastMergeVault(
  String path,
  List<int> passphrase,
) => fastMergeVaultFromFile(path: path, passphrase: passphrase);

Future<MergeSummary> _defaultFastMergeVaultWithKey(
  String path,
  List<int> passphrase,
  List<int> hmac,
  List<int> credentialId,
) => fastMergeVaultFromFileWithKey(
  path: path,
  passphrase: passphrase,
  hmacSecret: hmac,
  credentialId: credentialId,
);

/// Cancel an in-progress granular sync: roll the vault back to its pre-sync state.
Future<void> _defaultCancelSync() => cancelSync();

/// Apply a whole granular-sync review in one FFI call (one vault re-seal for the
/// entire review, instead of one per decision).
Future<void> _defaultApplySyncDecisions({
  required List<SyncFieldResolutionInput> fieldResolutions,
  required List<SyncHistoryReplacementInput> historyReplacements,
  required List<SyncItemDeleteInput> itemDeletes,
  required List<SyncFolderInput> folders,
  required List<String> entryDeletes,
}) => applySyncDecisions(
  fieldResolutions: fieldResolutions,
  historyReplacements: historyReplacements,
  itemDeletes: itemDeletes,
  folders: folders,
  entryDeletes: entryDeletes,
);

/// Reads the source vault's YubiKey records to decide whether a key is required.
/// Non-empty means key-protected. Sync — header read only.
List<YubikeyRecordData> _defaultDetectSyncSourceRecords(String path) =>
    listVaultYubikeyRecords(path: path);

Future<YubikeyHmacMatch> _defaultGetSyncYubikeyHmac(
  List<YubikeyRecordData> records,
  String pin,
  String transport,
) => getAnyYubikeyHmacSecret(records: records, pin: pin, transport: transport);
Future<String?> _defaultPickSyncFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['gabbro'],
  );
  return result?.files.single.path;
}

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');
const _biometricChannel = MethodChannel('app.gabbro.gabbro/biometric');

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> confirmYubikey(
  List<int> credentialId,
  List<int> salt,
  String pin,
  String transport,
) async {
  if (Platform.isLinux) {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      // No English message: catch sites localize via the code (l.noFidoDeviceFound).
      throw PlatformException(code: 'NO_FIDO2_DEVICE');
    }
    await fidoGetHmacSecret(
      devicePath: devices.first,
      credentialId: credentialId,
      salt: salt,
      pin: pin,
    );
    return;
  }
  await _yubikeyChannel.invokeMethod<String>('get_hmac_secret', {
    'credentialId': _toHex(credentialId),
    'salt': _toHex(salt),
    'pin': pin,
    'transport': transport,
  });
}

Future<void> confirmAnyYubikey(
  List<YubikeyRecordData> records,
  String pin,
  String transport,
) async {
  if (Platform.isLinux) {
    final devices = fidoListDevices();
    if (devices.isEmpty) {
      // No English message: catch sites localize via the code (l.noFidoDeviceFound).
      throw PlatformException(code: 'NO_FIDO2_DEVICE');
    }
    await fidoGetHmacSecretAny(
      devicePath: devices.first,
      records: records
          .map(
            (r) => FidoRecordInput(credentialId: r.credentialId, salt: r.salt),
          )
          .toList(),
      pin: pin,
    );
    return;
  }
  final recordsArg = records
      .map(
        (r) => {'credentialId': _toHex(r.credentialId), 'salt': _toHex(r.salt)},
      )
      .toList();
  await _yubikeyChannel.invokeMethod<Map<Object?, Object?>>(
    'get_hmac_secret_multi',
    {'records': recordsArg, 'pin': pin, 'transport': transport},
  );
}

/// Set by the active vault list so the GLOBAL Tab / Shift+Tab handler in
/// main.dart can drive the region cycle regardless of where focus currently is.
/// Returns true when it consumed the key (focus moved to the next/previous
/// region stop), false to let Tab fall through to default traversal. Null when
/// no vault list is mounted. Mirrors [focusVaultSearch]; same reason — a
/// screen-local `Actions` override died on real hardware (round 10).
bool Function({required bool forward})? vaultRegionTab;

/// Set by the active vault list so the GLOBAL Esc handler (main.dart) can drop
/// focus out of the region cycle from ANY region, not just the search field —
/// Esc is the only exit back to the Unfocused state (KEYBOARD_NAV). Returns
/// true when it consumed the key. Null when no vault list is mounted.
bool Function()? vaultRegionEscape;

/// Set by the active vault list so main.dart's app-root traversal absorber knows
/// when to swallow Flutter's default Tab -> Next/PreviousFocusIntent traversal
/// (the [vaultRegionTab] driver moves focus instead). Returns true only on
/// desktop while the vault list is the current route; false elsewhere so Tab
/// stays normal on other screens and inside dialogs. Null when no vault list is
/// mounted. The absorber must sit BELOW WidgetsApp's default shortcuts (i.e.
/// MaterialApp.builder) or the default traversal fires first.
bool Function()? vaultRegionActive;

/// Set by the active vault list so the GLOBAL Ctrl+F / Ctrl+Shift+F handler in
/// main.dart can focus its search field regardless of where focus currently is.
/// A screen-local shortcut dies once focus leaves the screen subtree (hardware:
/// "Ctrl+F worked once then not"), so search focus rides the same global key
/// handler as Ctrl+L. `allFields` picks normal (false) vs all-fields (true) mode.
void Function({required bool allFields})? focusVaultSearch;

/// Set by the active vault list so the GLOBAL Ctrl+N handler (main.dart) can open
/// the new-entry type picker from anywhere. The region Tab-cycle excludes the
/// FAB, so this is the keyboard path to create an entry. No-op when null.
void Function()? openNewEntry;

/// Set by the active vault list so the GLOBAL Ctrl+M handler (main.dart) can open
/// the overflow menu from anywhere. The region Tab-cycle excludes the menu
/// button, so this is the keyboard path to it. No-op when null.
void Function()? openVaultMenu;

/// Set by the active vault list so the GLOBAL Ctrl+Q handler (main.dart) can
/// lock and quit from anywhere on that screen. It raises the SAME confirm dialog
/// as the menu's Quit item — an accidental keystroke must not end a live session.
/// Null when no vault list is mounted, or when quitting isn't offered (`onQuit`
/// is null off Linux), so the key is inert exactly where the menu item is absent.
void Function()? quitVault;

class VaultListScreen extends StatefulWidget {
  final String vaultPath;
  final String? vaultAlias;
  final List<EntrySummaryData> Function() listEntries;
  final List<String> Function()? listFolders;
  final Future<MergeSummary> Function(String path, List<int> passphrase)
  mergeVault;

  /// Sync from a key-protected source: passphrase + tapped YubiKey (ADR-013).
  final Future<MergeSummary> Function(
    String path,
    List<int> passphrase,
    List<int> hmac,
    List<int> credentialId,
  )
  mergeVaultWithKey;

  /// Fast auto-merge variants (incoming wins, no review) for the "Merge
  /// automatically" path. Mirror [mergeVault] / [mergeVaultWithKey].
  final Future<MergeSummary> Function(String path, List<int> passphrase)
  fastMergeVault;
  final Future<MergeSummary> Function(
    String path,
    List<int> passphrase,
    List<int> hmac,
    List<int> credentialId,
  )
  fastMergeVaultWithKey;

  /// Detects whether the chosen `.gabbro` sync source is key-protected.
  final List<YubikeyRecordData> Function(String path) onDetectSyncSourceRecords;

  /// Prompts for a YubiKey tap and returns the hmac + matched credential.
  final Future<YubikeyHmacMatch> Function(
    List<YubikeyRecordData> records,
    String pin,
    String transport,
  )
  onGetSyncYubikeyHmac;

  final Future<String?> Function() onPickSyncFile;
  final bool isAndroid;

  final VaultEntryData Function(String id)? getEntryFn;
  final Future<void> Function(String id)? onDeleteEntryFn;
  final void Function()? onRefreshFn;
  final AlphabetBarPosition? alphabetBarPosition;
  final Future<void> Function(List<String> ids, String folder)?
  onAssignFolderFn;

  /// Applies a whole granular-sync review in one call (one vault re-seal for the
  /// entire review, instead of one FFI call + re-seal per decision). Injectable
  /// for tests.
  final Future<void> Function({
    required List<SyncFieldResolutionInput> fieldResolutions,
    required List<SyncHistoryReplacementInput> historyReplacements,
    required List<SyncItemDeleteInput> itemDeletes,
    required List<SyncFolderInput> folders,
    required List<String> entryDeletes,
  })
  applySyncDecisions;

  /// Rolls an in-progress granular sync back to the pre-sync state (the review's
  /// "Cancel sync"). Injectable for tests.
  final Future<void> Function() cancelSync;

  /// Pre-injected YubiKey records. `null` = auto-detect from vault file at
  /// construction time. Pass `[]` to force passphrase-only mode (tests).
  final List<YubikeyRecordData>? yubikeyRecords;

  /// Quit the app from the menu — the item confirms first, then locks (wipes
  /// keys) and exits. Null → the confirm's Quit action does nothing (tests that
  /// don't drive Quit); production wires it to exit after the lock.
  final VoidCallback? onQuit;

  /// Locks the vault (wipes keys in Rust). Seam for tests; defaults to the real
  /// [lockVault] bridge call. Quit calls this before exiting.
  final void Function() onLock;

  VaultListScreen({
    super.key,
    required this.vaultPath,
    this.vaultAlias,
    this.listEntries = listEntrySummaries,
    this.listFolders,
    this.mergeVault = _defaultMergeVault,
    this.mergeVaultWithKey = _defaultMergeVaultWithKey,
    this.fastMergeVault = _defaultFastMergeVault,
    this.fastMergeVaultWithKey = _defaultFastMergeVaultWithKey,
    this.onDetectSyncSourceRecords = _defaultDetectSyncSourceRecords,
    this.onGetSyncYubikeyHmac = _defaultGetSyncYubikeyHmac,
    this.onPickSyncFile = _defaultPickSyncFile,
    this.getEntryFn,
    this.onDeleteEntryFn,
    this.onRefreshFn,
    this.alphabetBarPosition,
    this.onAssignFolderFn,
    this.applySyncDecisions = _defaultApplySyncDecisions,
    this.cancelSync = _defaultCancelSync,
    this.yubikeyRecords,
    this.onQuit,
    this.onLock = lockVault,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen>
    with WidgetsBindingObserver {
  static const _filters = [
    'All',
    'Password',
    'Note',
    'Card',
    'Identity',
    'File',
    'Custom',
  ];

  List<EntrySummaryData> _entries = [];
  List<String> _folders = [];
  String? _error;
  String _selectedFilter = 'All';
  String _selectedFolder = '';
  Set<String> _selectedIds = {};
  bool _selectionMode = false;
  bool _isDeleting = false;
  bool _isImporting = false;
  bool _isSyncing = false;
  bool get _isSelecting => _selectionMode || _selectedIds.isNotEmpty;
  final String _transport = 'usb';
  late final List<YubikeyRecordData> _yubikeyRecords;
  bool get _isYubikeyVault => _yubikeyRecords.isNotEmpty;

  String _searchQuery = '';
  bool _fullTextSearch = false;
  final TextEditingController _searchController = TextEditingController();
  // Shared by whichever layout (phone XOR tablet) is built, so Ctrl+F can focus
  // the search field without either layout duplicating the node. Esc-to-blur is
  // handled globally for every text field (main.dart _onKeyEvent).
  final FocusNode _searchFocus = FocusNode();

  // Phase 3: one FocusScope per Tab region, each labelled 'region:<name>'. Tab
  // (intercepted globally in main.dart, routed here via _handleRegionTab) steps
  // a fixed cycle of regions; arrows stay within a region (Flutter's default
  // directional focus). Order: search -> folder -> chips -> entry list (the
  // tablet layout adds its detail pane — handled there). The search-mode toggle
  // icon is NOT a stop: Ctrl+F / Ctrl+Shift+F reach and set it directly (DRY).
  final _searchScope = FocusScopeNode(debugLabel: 'region:search');
  final _folderScope = FocusScopeNode(debugLabel: 'region:folder');
  final _chipsScope = FocusScopeNode(debugLabel: 'region:chips');
  final _listScope = FocusScopeNode(debugLabel: 'region:list');
  // The two-pane detail pane's region. Owned here so the cycle can reach it, but
  // mounted by TabletVaultLayout ONLY when an entry is selected — so its being
  // non-empty is exactly "detail is a stop" (see _stopOrder). Never mounted in
  // the single-pane layout.
  final _detailScope = FocusScopeNode(debugLabel: 'region:detail');
  // The folder dropdown's own node, so the 'folder' stop lands on it directly.
  final FocusNode _folderFocus = FocusNode(debugLabel: 'folder');

  /// Wrap a Tab region in its FocusScope plus the focus frame on desktop; pass
  /// the child through UNCHANGED on Android. Keyboard navigation is
  /// Linux-desktop only and must not alter the Android widget tree at all — so
  /// scope and frame leave together, never one without the other.
  /// [frame] is false for the search box, which lights up its OWN outline
  /// instead (an overlay frame there gave a double border).
  /// [label] names the region aloud (Linux only — it rides the same gate, so
  /// Android gains no announcement, per D5).
  Widget _region(
    FocusScopeNode scope,
    Widget child, {
    bool frame = true,
    String? label,
  }) {
    if (widget.isAndroid) return child;
    return FocusScope(
      node: scope,
      child: FocusRegion(label: label, showFrame: frame, child: child),
    );
  }

  /// Says something that has no node for a reader to land on — a shortcut
  /// firing, a sheet opening, focus arriving in a region. On Linux the reader
  /// is handed a node's NAME and nothing else, so an event that changes no
  /// name is otherwise completely silent (round 16: Orca said nothing for any
  /// shortcut).
  ///
  /// Linux only, on the same D5 gate as the regions: Android has deprecated
  /// announcement events (they force TalkBack to drop its speech queue), and
  /// TalkBack already reads these flows from the widgets themselves.
  void _announce(String message) {
    if (widget.isAndroid || !mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  /// Makes a control say what it DOES, not just what it is.
  ///
  /// A Linux screen reader is given only a node's NAME — the embedder never
  /// reads a semantics hint at all (LEARNINGS.md), which is why Orca spoke
  /// none of these in round 16. So on Linux the outcome goes inside the name,
  /// after the control's own name. Android does read hints and TalkBack
  /// already passes, so there the hint is left exactly as it was.
  ///
  /// [outcome] null means the control has nothing to promise right now (a row
  /// in selection mode ticks rather than opens), so nothing is added at all.
  ///
  /// `isAndroid` is fixed for the life of the app, so this branch never
  /// reshapes the tree at runtime — unlike the decoration flip that once cost
  /// a row its focus node.
  Widget _saysWhatItDoes(
    Widget child, {
    required String name,
    String? outcome,
  }) {
    if (outcome == null) return child;
    return widget.isAndroid
        ? Semantics(hint: outcome, child: child)
        : Semantics(label: '$name. $outcome', child: child);
  }

  /// The `semanticsLabel` for the Text that shows a control's own name: blank
  /// where [_saysWhatItDoes] has already composed that name into the label, so
  /// it is not spoken twice; null (unchanged) otherwise.
  ///
  /// A blanked VALUE, not a wrapper widget: wrapping would change the widget
  /// tree's shape, which is what disposed a row's focus node once before.
  String? _ownNameLabel({String? outcome}) =>
      outcome != null && !widget.isAndroid ? '' : null;

  /// The Tab stops in cycle order for the current state. Folder appears only
  /// when there are folders. Detail appears only when the two-pane layout has
  /// mounted its region (i.e. wide AND an entry is selected) — its scope carries
  /// focusable descendants exactly then; empty (never a stop) single-pane.
  List<String> _stopOrder() => [
    'search',
    if (_folders.isNotEmpty) 'folder',
    'chips',
    'list',
    if (_detailScope.traversalDescendants.isNotEmpty) 'detail',
  ];

  /// The scope backing each cycle stop. Regions are matched by node IDENTITY,
  /// never by debugLabel: Flutter only assigns debugLabel inside an assert, so
  /// it is null in every release build — a label lookup passes in `flutter test`
  /// (debug) and silently matches nothing on the user's machine. That was the
  /// round-11 hardware failure: every Tab re-entered the cycle at stop 0.
  Map<String, FocusScopeNode> get _scopeOfStop => {
    'search': _searchScope,
    'folder': _folderScope,
    'chips': _chipsScope,
    'list': _listScope,
    'detail': _detailScope,
  };

  /// Which cycle stop currently holds focus, '' if none (cold / excluded).
  /// A region scope reports `hasFocus` when it or any descendant is the primary
  /// focus, and the regions are siblings, so at most one matches.
  String _currentStop() {
    for (final stop in _scopeOfStop.entries) {
      if (stop.value.hasFocus) return stop.key;
    }
    return '';
  }

  /// Focus a region scope's remembered child, else its first control.
  void _focusRegionScope(FocusScopeNode scope) {
    final target = scope.focusedChild ??
        (scope.traversalDescendants.isEmpty
            ? null
            : scope.traversalDescendants.first);
    target?.requestFocus();
  }

  void _focusStop(String name) {
    switch (name) {
      case 'search':
        _searchFocus.requestFocus();
      case 'folder':
        _folderFocus.requestFocus();
      case 'chips':
        _focusRegionScope(_chipsScope);
      case 'list':
        _focusRegionScope(_listScope);
      case 'detail':
        _focusRegionScope(_detailScope);
    }
  }

  /// True when the region cycle should own Tab: desktop, and the vault list is
  /// the current route (not behind a dialog / pushed screen). Gates both the
  /// global Tab driver [_handleRegionTab] and the app-root traversal absorber
  /// ([vaultRegionActive]) so Tab stays normal on Android, on other screens, and
  /// inside dialogs. Both layouts (single- and two-pane) are wired.
  bool _regionCycleActive() {
    if (widget.isAndroid) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  // Lets the Ctrl+M handler open the overflow menu programmatically.
  final GlobalKey<PopupMenuButtonState<String>> _menuKey = GlobalKey();

  /// Guard for the Ctrl+N / Ctrl+M action shortcuts: desktop, vault list is the
  /// current route, and NOT in selection mode (the FAB and menu button are both
  /// hidden then, so there is nothing to open).
  bool _actionShortcutActive() {
    if (widget.isAndroid || _isSelecting) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  // Ctrl+N (global): open the new-entry type picker — the keyboard path to the
  // FAB, which the region Tab-cycle excludes.
  void _handleNewEntryShortcut() {
    if (mounted && _actionShortcutActive()) _showTypePicker();
  }

  // Ctrl+M (global): open the overflow menu — the keyboard path to the menu
  // button, which the region Tab-cycle excludes.
  void _handleMenuShortcut() {
    if (mounted && _actionShortcutActive()) {
      _menuKey.currentState?.showButtonMenu();
      _announce(AppLocalizations.of(context).tooltipMenu);
    }
  }

  void _handleQuitShortcut() {
    if (mounted && _actionShortcutActive() && widget.onQuit != null) {
      _announce(AppLocalizations.of(context).quit);
      _confirmQuit();
    }
  }

  /// Esc handler (registered as the global [vaultRegionEscape] hook): drop focus
  /// out of the cycle, back to Unfocused. Returns true when it consumed the key.
  ///
  /// It unfocuses the REGION SCOPE, not the focused control: unfocusing a
  /// control only parks focus on its enclosing scope, which is still inside the
  /// region — the frame would stay lit and the next Tab would resume mid-cycle.
  /// Unfocusing the scope hands focus to the route scope above the cycle, while
  /// the region keeps its own memory of the control that was focused, so
  /// Tabbing back in returns there.
  bool _handleRegionEscape() {
    if (!_regionCycleActive()) return false;
    final stop = _currentStop();
    if (stop.isEmpty) return false;
    _scopeOfStop[stop]?.unfocus();
    return true;
  }

  /// Tab / Shift+Tab handler (registered as the global [vaultRegionTab] hook):
  /// move focus to the next / previous region stop, wrapping. Self-gates via
  /// [_regionCycleActive].
  bool _handleRegionTab({required bool forward}) {
    if (!_regionCycleActive()) return false;
    final stops = _stopOrder();
    if (stops.isEmpty) return false;
    final i = stops.indexOf(_currentStop());
    final next = i < 0
        ? (forward ? 0 : stops.length - 1)
        : (forward
            ? (i + 1) % stops.length
            : (i - 1 + stops.length) % stops.length);
    _focusStop(stops[next]);
    return true;
  }
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ScrollController _chipScrollController = ScrollController();
  bool _showLeftChevron = false;
  bool _showRightChevron = false;
  // Active UI locale; picks the index alphabet (script). Set in
  // didChangeDependencies so it tracks locale changes.
  Locale _locale = const Locale('en');
  // The app-level messenger, captured while mounted so dispose() can clear any
  // sync snackbar. Otherwise the "Vault synced" bar (shown on the app messenger)
  // outlives this screen and lingers on the unlock screen after lock, where its
  // Details action would dereference this disposed State.
  ScaffoldMessengerState? _messenger;

  List<YubikeyRecordData> _detectYubikeyRecords() {
    try {
      return listVaultYubikeyRecords(path: widget.vaultPath);
    } catch (_) {
      return [];
    }
  }

  // Driven by the global Ctrl+F / Ctrl+Shift+F handler (main.dart). Ctrl+F picks
  // normal (title) mode; Ctrl+Shift+F picks all-fields. Focus-independent, so it
  // keeps working after focus has left the search field.
  void _handleSearchShortcut({required bool allFields}) {
    setState(() => _fullTextSearch = allFields);
    _searchFocus.requestFocus();
    // Only the all-fields variant announces: plain Ctrl+F lands in the search
    // region, which names itself, and the field's own name already ends in
    // "Ctrl+F: Focus search". All-fields mode has no other audible sign.
    if (allFields) _announce(AppLocalizations.of(context).kbSearchAllFields);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    focusVaultSearch = _handleSearchShortcut;
    vaultRegionTab = _handleRegionTab;
    vaultRegionEscape = _handleRegionEscape;
    vaultRegionActive = _regionCycleActive;
    openNewEntry = _handleNewEntryShortcut;
    openVaultMenu = _handleMenuShortcut;
    quitVault = _handleQuitShortcut;
    _yubikeyRecords = widget.yubikeyRecords ?? _detectYubikeyRecords();
    _loadEntries();
    _chipScrollController.addListener(_updateChevrons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateChevrons());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reload on resume so changes made while backgrounded — e.g. a login saved by
    // the autofill SaveActivity into the shared session — appear without a manual
    // refresh or a lock/unlock cycle.
    if (state == AppLifecycleState.resumed) _loadEntries();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locale = Localizations.localeOf(context);
    _messenger = ScaffoldMessenger.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateChevrons());
  }

  @override
  void dispose() {
    // Clear any sync snackbar so it can't linger on the next screen (e.g. the
    // unlock screen after lock) and crash when its Details action is tapped.
    _messenger?.clearSnackBars();
    if (focusVaultSearch == _handleSearchShortcut) focusVaultSearch = null;
    if (vaultRegionTab == _handleRegionTab) vaultRegionTab = null;
    if (vaultRegionEscape == _handleRegionEscape) vaultRegionEscape = null;
    if (vaultRegionActive == _regionCycleActive) vaultRegionActive = null;
    if (openNewEntry == _handleNewEntryShortcut) openNewEntry = null;
    if (openVaultMenu == _handleMenuShortcut) openVaultMenu = null;
    if (quitVault == _handleQuitShortcut) quitVault = null;
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocus.dispose();
    _folderFocus.dispose();
    _searchScope.dispose();
    _folderScope.dispose();
    _chipsScope.dispose();
    _listScope.dispose();
    _detailScope.dispose();
    _chipScrollController.removeListener(_updateChevrons);
    _chipScrollController.dispose();
    super.dispose();
  }

  void _updateChevrons() {
    if (!_chipScrollController.hasClients) return;
    final pos = _chipScrollController.position;
    final overflows = pos.maxScrollExtent > 0;
    setState(() {
      _showLeftChevron = overflows && pos.pixels > 1.0;
      _showRightChevron = overflows && pos.pixels < pos.maxScrollExtent - 1.0;
    });
  }

  void _scrollChips(bool toRight) {
    if (!_chipScrollController.hasClients) return;
    final pos = _chipScrollController.position;
    final target = (pos.pixels + (toRight ? 120.0 : -120.0)).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    _chipScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void _loadEntries() {
    try {
      final entries = widget.listEntries();
      List<String> folders = [];
      try {
        folders = (widget.listFolders ?? _defaultListFolders)();
      } catch (_) {
        // folders unavailable (e.g. vault locked) — degrade gracefully
      }
      setState(() {
        _entries = entries;
        _folders = folders;
        if (!folders.contains(_selectedFolder)) {
          _selectedFolder = '';
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        // Drop any retained decrypted summaries: if the load failed (e.g. the
        // vault is locked) we must not keep plaintext entries in memory. The
        // _error gate also hides the list, but clearing is defence-in-depth.
        _entries = [];
        _folders = [];
      });
    }
  }

  IconData _entryTypeIcon(String entryType) => switch (entryType) {
    'Login' => Icons.lock_outline,
    'Note' => Icons.note_outlined,
    'Identity' => Icons.person_outline,
    'Card' => Icons.credit_card_outlined,
    'File' => Icons.insert_drive_file_outlined,
    _ => Icons.tune,
  };

  /// Returns the current vault alias, preferring the live registry value over
  /// the frozen prop so renames are reflected without a lock/unlock cycle.
  String? _currentAlias(BuildContext context) =>
      GabbroApp.maybeOf(context)?.registry.lastUsed?.alias ?? widget.vaultAlias;

  String _displayType(String entryType, AppLocalizations l) =>
      switch (entryType) {
        'Login' => l.entryTypePassword,
        'Note' => l.entryTypeNote,
        'Identity' => l.entryTypeIdentity,
        'Card' => l.entryTypeCard,
        'File' => l.entryTypeFile,
        'Custom' => l.entryTypeCustom,
        _ => entryType,
      };

  // Used internally for sort/group/search — English fallbacks are fine here.
  String _displayTitle(EntrySummaryData entry) {
    return switch (entry.entryType) {
      'Login' => entry.title.isNotEmpty ? entry.title : '(no URL)',
      'Identity' => entry.title.isNotEmpty ? entry.title : '(no name)',
      _ => entry.title.isNotEmpty ? entry.title : '(untitled)',
    };
  }

  // Used for display in build() — returns localized fallbacks.
  String _localizedDisplayTitle(EntrySummaryData entry, AppLocalizations l) =>
      switch (entry.entryType) {
        'Login' => entry.title.isNotEmpty ? entry.title : l.noUrlFallback,
        'Identity' => entry.title.isNotEmpty ? entry.title : l.noNameFallback,
        _ => entry.title.isNotEmpty ? entry.title : l.untitledFallback,
      };

  String _filterLabel(String f, AppLocalizations l) => switch (f) {
    'All' => l.entryTypeAll,
    'Password' => l.entryTypePassword,
    'Note' => l.entryTypeNote,
    'Card' => l.entryTypeCard,
    'Identity' => l.entryTypeIdentity,
    'File' => l.entryTypeFile,
    'Custom' => l.entryTypeCustom,
    _ => f,
  };

  List<EntrySummaryData> get _filteredEntries {
    final typeFiltered = _selectedFilter == 'All'
        ? _entries
        : _entries.where((e) {
            final rustType = _selectedFilter == 'Password'
                ? 'Login'
                : _selectedFilter;
            return e.entryType == rustType;
          }).toList();

    final folderFiltered = _selectedFolder.isEmpty
        ? typeFiltered
        : typeFiltered.where((e) => e.folder == _selectedFolder).toList();

    if (_searchQuery.isEmpty) return folderFiltered;
    final query = _searchQuery.toLowerCase();
    return folderFiltered
        .where(
          (e) => _fullTextSearch
              ? e.searchBlob.contains(query)
              : _displayTitle(e).toLowerCase().contains(query),
        )
        .toList();
  }

  Map<String, int> get _letterIndex {
    final map = <String, int>{};
    final items = _groupedEntries;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is String) map[item] = i;
    }
    return map;
  }

  String _sectionLetter(EntrySummaryData entry) =>
      sectionBucket(_displayTitle(entry), _locale);

  int _sortKey(EntrySummaryData entry) =>
      sectionSortRank(_displayTitle(entry), _locale);

  List<dynamic> get _groupedEntries {
    final sorted = List<EntrySummaryData>.from(_filteredEntries)
      ..sort((a, b) {
        final keyDiff = _sortKey(a) - _sortKey(b);
        if (keyDiff != 0) return keyDiff;
        return _displayTitle(
          a,
        ).toLowerCase().compareTo(_displayTitle(b).toLowerCase());
      });

    // Non-indexable locales (ja/zh) get a flat title-sorted list with no
    // section headers — there is no human-orderable bucket to label.
    if (!isIndexableLocale(_locale)) return sorted;

    final result = <dynamic>[];
    String? currentLetter;

    for (final entry in sorted) {
      final letter = _sectionLetter(entry);
      if (letter != currentLetter) {
        result.add(letter);
        currentLetter = letter;
      }
      result.add(entry);
    }
    return result;
  }

  AlphabetBarPosition get _alphabetBarPosition =>
      widget.alphabetBarPosition ??
      GabbroApp.maybeOf(context)?.settings.alphabetBarPosition ??
      AlphabetBarPosition.left;

  void _scrollToLetter(String letter) {
    final index = _letterIndex[letter];
    if (index == null) return;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _showTypePicker() async {
    final l = AppLocalizations.of(context);
    // The sheet has no name of its own, so without this a reader is given no
    // clue what just appeared over the vault list.
    _announce(l.newEntryTitle);
    final types = [
      ('Login', l.entryTypePassword),
      ('Note', l.entryTypeNote),
      ('Identity', l.entryTypeIdentity),
      ('Card', l.entryTypeCard),
      ('File', l.entryTypeFile),
      ('Custom', l.entryTypeCustom),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  AppLocalizations.of(context).newEntryTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              ...types.map(
                (t) => ListTile(
                  // No semanticLabel: the title below already says the type,
                  // and naming the icon too made a reader say each of the six
                  // types twice.
                  leading: Icon(
                    _entryTypeIcon(t.$1),
                    size: scaledIconSize(context),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(t.$2),
                  onTap: () => Navigator.of(context).pop(t.$1),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CreateEntryScreen(entryType: selected),
      ),
    );
    if (mounted) _loadEntries();
  }

  Future<void> _openExportScreen() async {
    final appState = GabbroApp.of(context);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          vaultAlias: widget.vaultAlias,
          isKeyProtected: _isYubikeyVault,
          // Remember the Android SAF export folder across runs (ADR-013).
          initialExportFolderUri: appState.settings.androidExportFolderUri,
          onSaveExportFolderUri: (uri) => appState.updateSettings(
            appState.settings.copyWith(androidExportFolderUri: uri),
          ),
        ),
      ),
    );
  }

  Future<void> _openImportScreen() async {
    setState(() => _isImporting = true);
    final count = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute(builder: (context) => ImportScreen()));
    if (mounted) {
      setState(() => _isImporting = false);
      if (count != null && count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).importedEntries(count)),
          ),
        );
        _loadEntries();
      }
    }
  }

  Future<void> _confirmAssignFolder(Set<String> ids) async {
    if (_folders.isEmpty) return;
    String? selected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.assignToFolderTitle),
            content: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              hint: Text(l.selectFolder),
              items: _folders
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => setLocal(() => selected = v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                child: Text(l.assign),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || selected == null) return;
    final fn = widget.onAssignFolderFn;
    if (fn != null) {
      await fn(ids.toList(), selected!);
    } else {
      await assignFolderToEntries(ids: ids.toList(), folder: selected!);
    }
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    _loadEntries();
  }

  Future<void> _confirmDelete(Set<String> ids) async {
    final count = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.deleteEntriesTitle(count)),
          content: Text(l.cannotBeUndone),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _isDeleting = true);
    await deleteEntries(ids: ids.toList());
    setState(() {
      _selectedIds.clear();
      _isDeleting = false;
    });
    _loadEntries();
  }

  Future<void> _syncFromFile() async {
    final String? picked;
    try {
      picked = await runPicker(widget.onPickSyncFile);
    } on FilePickerUnavailable {
      if (mounted) showPickerUnavailable(context, hasManualEntry: false);
      return;
    }
    if (picked == null || !mounted) return;
    // Bound here (not the try-assigned local) so it promotes to non-null inside
    // the passphrase-dialog builder closure below.
    final path = picked;

    // ADR-013: a key-protected source (passphrase + YubiKey) cannot be opened
    // with the passphrase alone — the crypto refuses it. Detect that up front so
    // the sync flow can ask for the key, mirroring the import-entries path. A
    // header-read failure (unreadable / not a gabbro file) falls through to the
    // passphrase-only path; mergeVault then surfaces the real error.
    List<YubikeyRecordData> sourceRecords;
    try {
      sourceRecords = widget.onDetectSyncSourceRecords(path);
    } catch (_) {
      sourceRecords = const [];
    }
    final isKeyProtected = sourceRecords.isNotEmpty;

    // SyncPassphraseDialog owns the controllers; returns passphrase (+ PIN and
    // transport when key-protected), or null on cancel.
    final creds = await showDialog<SyncCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SyncPassphraseDialog(
        filePath: path,
        isKeyProtected: isKeyProtected,
        isAndroid: widget.isAndroid,
        sourceRecords: sourceRecords,
        onGetYubikeyHmac: widget.onGetSyncYubikeyHmac,
      ),
    );
    if (creds == null || !mounted) return;

    // Choose how to apply: automatically (incoming wins, no prompts) or a
    // granular one-by-one review.
    final chooseL = AppLocalizations.of(context);
    final fast = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // The two choices are long buttons; at large text they must stay
        // reachable, so they live in scrollable content, not the actions bar
        // (which does not scroll). Cancel replaces the barrier tap (ADR-016).
        scrollable: true,
        title: Text(chooseL.syncMethodTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(chooseL.syncMergeAutomatically),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(chooseL.syncReviewAllChanges),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(chooseL.cancel),
          ),
        ],
      ),
    );
    if (fast == null || !mounted) return;

    final passphraseBytes = utf8.encode(creds.passphrase);
    setState(() => _isSyncing = true);
    try {
      if (fast) {
        // Fast auto-merge: everything applied, incoming wins, no review dialog.
        final MergeSummary fastSummary = isKeyProtected
            ? await widget.fastMergeVaultWithKey(
                path,
                passphraseBytes,
                creds.hmac!,
                creds.credentialId!,
              )
            : await widget.fastMergeVault(path, passphraseBytes);
        if (!mounted) return;
        _loadEntries();
        final nothing =
            fastSummary.added == 0 &&
            fastSummary.updated == 0 &&
            fastSummary.addedEntries.isEmpty &&
            fastSummary.broughtOver.isEmpty &&
            fastSummary.pendingDeletes.isEmpty &&
            fastSummary.folderConflicts.isEmpty &&
            fastSummary.fieldConflicts.isEmpty &&
            fastSummary.pendingItemDeletes.isEmpty;
        if (!mounted) return;
        if (nothing) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).nothingToSync)),
          );
        } else {
          final updatedIds = <String>{
            ...fastSummary.broughtOver.map((b) => b.id),
            ...fastSummary.fieldConflicts.map((c) => c.id),
            ...fastSummary.pendingItemDeletes.map((d) => d.id),
            ...fastSummary.folderConflicts.map((f) => f.id),
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).vaultSynced(
                  fastSummary.added,
                  updatedIds.length,
                  fastSummary.pendingDeletes.length,
                ),
              ),
            ),
          );
        }
        return;
      }
      final MergeSummary summary;
      if (isKeyProtected) {
        // The dialog already tapped the key (showing the inline tap note); use
        // the returned material to open the key-protected source and merge.
        summary = await widget.mergeVaultWithKey(
          path,
          passphraseBytes,
          creds.hmac!,
          creds.credentialId!,
        );
      } else {
        summary = await widget.mergeVault(path, passphraseBytes);
      }
      if (!mounted) return;

      final isIdentical =
          summary.added == 0 &&
          summary.updated == 0 &&
          summary.addedEntries.isEmpty &&
          summary.broughtOver.isEmpty &&
          summary.pendingDeletes.isEmpty &&
          summary.folderConflicts.isEmpty &&
          summary.fieldConflicts.isEmpty &&
          summary.pendingItemDeletes.isEmpty;

      if (isIdentical) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).nothingToSync)),
        );
        return;
      }

      _loadEntries();

      // One-by-one review: step through every entry's incoming changes (new
      // entries, brought-over values, clashes, item-deletes), then apply what the
      // user kept/picked/dropped. Drops and picks reuse the existing FFI calls.
      final steps = buildSyncReviewSteps(summary);
      // Default to the merge-time tally; once the user reviews, the snackbar
      // reflects what they actually kept/picked/dropped (decisions.*).
      var addedCount = summary.added;
      var updatedCount = summary.updated;
      var deletedCount = 0;
      // Entry titles behind the tallies, for the granular "Details" summary.
      var addedTitles = const <String>[];
      var updatedTitles = const <String>[];
      var deletedTitles = const <String>[];
      if (steps.isNotEmpty && mounted) {
        final decisions = await showSyncReview(context: context, steps: steps);
        if (decisions != null && decisions.cancelled) {
          // Full cancel: roll the vault back to the pre-sync state, apply nothing.
          await widget.cancelSync();
          if (mounted) _loadEntries();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).syncCancelled),
              ),
            );
          }
          return;
        }
        if (decisions != null) {
          // Apply the whole review in one call: one vault re-seal (Argon2id) for
          // all decisions, instead of one per decision. An interrupted review
          // therefore applies all-or-nothing — re-syncing re-surfaces the same
          // choices with nothing lost.
          await widget.applySyncDecisions(
            fieldResolutions: [
              for (final f in decisions.fieldResolutions)
                SyncFieldResolutionInput(
                  id: f.id,
                  field: f.field,
                  keepIncoming: f.keepIncoming,
                  value: f.value,
                ),
            ],
            historyReplacements: [
              for (final h in decisions.historyReplacements)
                SyncHistoryReplacementInput(
                  id: h.id,
                  field: h.field,
                  newValue: h.newValue,
                  replacedValue: h.replacedValue,
                ),
            ],
            itemDeletes: [
              for (final d in decisions.itemDeletes)
                SyncItemDeleteInput(id: d.id, field: d.field, delete: d.delete),
            ],
            folders: [
              for (final fo in decisions.folders)
                SyncFolderInput(id: fo.id, folder: fo.folder),
            ],
            entryDeletes: decisions.entryDeletes,
          );
          addedCount = decisions.added;
          updatedCount = decisions.updated;
          deletedCount = decisions.deleted;
          addedTitles = decisions.addedTitles;
          updatedTitles = decisions.updatedTitles;
          deletedTitles = decisions.deletedTitles;
          if (mounted) _loadEntries();
        }
      }

      if (mounted) {
        final l = AppLocalizations.of(context);
        // Offer an itemized breakdown only when a review produced per-entry
        // titles (the fast-merge path keeps the totals-only snackbar).
        final hasDetails =
            addedTitles.isNotEmpty ||
            updatedTitles.isNotEmpty ||
            deletedTitles.isNotEmpty;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.vaultSynced(addedCount, updatedCount, deletedCount),
            ),
            // An actioned snackbar never auto-dismisses (Material accessibility
            // rule), so give it an explicit close button. Its "Close" label is
            // localized + screen-reader-exposed via MaterialLocalizations.
            showCloseIcon: hasDetails,
            action: hasDetails
                ? SnackBarAction(
                    label: l.syncDetailsAction,
                    onPressed: () => _showSyncSummary(
                      addedTitles,
                      updatedTitles,
                      deletedTitles,
                    ),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      // Only the passphrase-only path can fail purely on a wrong passphrase.
      // For a key-protected source a decryption failure may instead mean the
      // wrong key/PIN, so the "different passphrase" message would mislead.
      final isPassphraseMismatch =
          !isKeyProtected && msg.contains('decryption failed');
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.syncFailedTitle),
            content: Text(
              isPassphraseMismatch ? l.syncPassphraseMismatch : l.syncFailed(msg),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.dismiss),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Itemized "what changed" summary from a granular sync: entries grouped
  /// Added / Updated / Deleted. Each group shows only when it has entries.
  Future<void> _showSyncSummary(
    List<String> added,
    List<String> updated,
    List<String> deleted,
  ) {
    // Defensive: a Details tap that races in after this screen is gone must be a
    // no-op, not a null-check crash on the disposed State's context.
    if (!mounted) return Future.value();
    final l = AppLocalizations.of(context);
    Widget group(String heading, List<String> titles) {
      if (titles.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              '$heading (${titles.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final t in titles)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('- $t'),
            ),
        ],
      );
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true, // scroll title+content+actions together (ADR-016)
        title: Text(l.syncSummaryTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            group(l.syncSummaryAdded, added),
            group(l.syncSummaryUpdated, updated),
            group(l.syncSummaryDeleted, deleted),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'export':
        _openExportScreen();
      case 'import':
        _openImportScreen();
      case 'sync':
        _syncFromFile();
      case 'change_passphrase':
        final cpAppState = GabbroApp.of(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChangePassphraseScreen(
              vaultPath: widget.vaultPath,
              blockPassphraseCopyPaste:
                  cpAppState.settings.blockPassphraseCopyPaste,
              // Biometric stores the old passphrase; a change makes it stale, so
              // unenroll THIS vault (the screen informs the user).
              onDisableBiometric: (vaultPath) async {
                if (Platform.isAndroid) {
                  try {
                    await _biometricChannel.invokeMethod<void>('unenroll', {
                      'vaultPath': vaultPath,
                    });
                  } catch (_) {}
                }
              },
            ),
          ),
        );
      case 'appearance':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AppearanceScreen()),
        );
      case 'language':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const LanguageScreen()));
      case 'security':
        final appState = GabbroApp.of(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SecurityScreen(
              settings: appState.settings,
              onUpdate: (updated) => appState.updateSettings(updated),
              vaultPath: widget.vaultPath,
            ),
          ),
        );
      case 'yubikeys':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ManageYubiKeysScreen(
              vaultPath: widget.vaultPath,
              transport: _transport,
            ),
          ),
        );
      case 'manage_vaults':
        GabbroApp.maybeOf(context)?.navigateToManageVaults();
      case 'generator':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const GeneratorScreen()),
        );
      case 'manage_folders':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ManageFoldersScreen(
              listFolders: () async => listFolders(),
              createFolder: (name) async => createFolder(name: name),
              renameFolder: (oldName, newName) async =>
                  renameFolder(oldName: oldName, newName: newName),
              deleteFolder: (name, reassignTo) async =>
                  deleteFolder(name: name, reassignTo: reassignTo),
            ),
          ),
        );
        if (mounted) _loadEntries();
      case 'keyboard_shortcuts':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const KeyboardShortcutsListScreen(),
          ),
        );
      case 'help':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const HelpScreen()));
      case 'about':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const AboutScreen()));
      case 'quit':
        await _confirmQuit();
    }
  }

  // An accidental menu tap must not nuke a live session, so Quit from an
  // unlocked vault confirms first; on confirm it locks (wiping keys in Rust)
  // then exits. Cancel is the default focus, so a stray Enter is harmless.
  Future<void> _confirmQuit() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Flutter only supplies a default dialog name on Android, so on Linux
        // Orca announced "alert" and then the focused Cancel button — the
        // question itself was never read, leaving a screen-reader user
        // confirming something they were never told.
        semanticLabel: l.quitConfirmTitle,
        title: Text(l.quitConfirmTitle),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.quit),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.onLock();
    widget.onQuit?.call();
  }

  void _lockAndExit() {
    lockVault();
    final appState = GabbroApp.of(context);
    final settings = appState.settings;
    // pushAndRemoveUntil (not pushReplacement) so the entire back stack is
    // cleared on lock — no prior route (e.g. this now-locked vault's list) can
    // survive underneath to be revealed by a back-press. Mirrors auto-lock.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => UnlockScreen(
          vaultPath: widget.vaultPath,
          vaultAlias: widget.vaultAlias,
          blockPassphraseCopyPaste: settings.blockPassphraseCopyPaste,
          registry: appState.registry,
          onQuit: widget.onQuit,
        ),
      ),
      (_) => false,
    );
  }

  // Selection-mode checkbox labelled with the entry title, so a screen reader
  // announces "<title>, tick box, ticked" instead of a bare "tick box". The
  // checkbox role + checked state come from Checkbox; MergeSemantics folds the
  // label into that one node.
  Widget _selectionCheckbox(EntrySummaryData entry, String label) {
    return MergeSemantics(
      child: Semantics(
        label: label,
        child: scaledSelectionCheckbox(
          context,
          Checkbox(
            value: _selectedIds.contains(entry.id),
            onChanged: (_) => setState(() {
              if (_selectedIds.contains(entry.id)) {
                _selectedIds.remove(entry.id);
              } else {
                _selectedIds.add(entry.id);
              }
            }),
          ),
        ),
      ),
    );
  }

  // Shared by both layouts. On desktop the field's own outline is the focus
  // indicator (solid, or dashed + thicker in high-contrast). On Android there
  // is no keyboard navigation, so it never highlights: focused and unfocused
  // draw the same border, which also suppresses Material's own default.
  Widget _buildSearchField() {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hc = theme.extension<GabbroContrast>()?.highContrast ?? false;
    final focusSide =
        BorderSide(color: theme.colorScheme.primary, width: hc ? 3 : 2);
    final flat =
        OutlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.outline));
    final placeholder =
        _fullTextSearch ? l.searchAllFieldsHint : l.searchEntriesHint;
    // Two shortcuts reach this box and they differ in WHAT they search, which
    // a screen-reader user has no other way to discover. Only Linux is told:
    // there is no keyboard on Android to press them on.
    final searchOutcome = widget.isAndroid
        ? l.hintSearch
        : '${l.hintSearch}. Ctrl+F: ${l.kbFocusSearch}. '
              'Ctrl+Shift+F: ${l.kbSearchAllFields}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: _saysWhatItDoes(
        TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        decoration: InputDecoration(
          // Android keeps Flutter's own placeholder, styling and all. Linux
          // has to supply it as a WIDGET so its own name can be excluded from
          // the semantics and composed into the label first instead — and
          // Flutter does not style a placeholder it did not build, so the
          // grey is restated here. Pinned against Android in
          // a11y_region_net_test.dart.
          hintText: widget.isAndroid ? placeholder : null,
          hint: widget.isAndroid
              ? null
              : Text(
                  placeholder,
                  semanticsLabel: '',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          prefixIcon: IconButton(
            // semanticLabel as well as tooltip: Orca reads a control's name and
            // never its tooltip, so a tooltip alone leaves this saying "button".
            icon: Icon(
              _fullTextSearch ? Icons.manage_search : Icons.search,
              semanticLabel: _fullTextSearch
                  ? l.searchAllFieldsTooltip
                  : l.searchByTitleTooltip,
            ),
            tooltip: _fullTextSearch
                ? l.searchAllFieldsTooltip
                : l.searchByTitleTooltip,
            onPressed: () => setState(() => _fullTextSearch = !_fullTextSearch),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: l.tooltipClearSearch,
                  onPressed: () => setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                )
              : null,
          border: const OutlineInputBorder(),
          // The field's OWN outline is the focus indicator: it lights up solid
          // (normal) or dashed + thicker (high-contrast). One line that changes
          // — no overlay frame, so no fade-double on Tab-in. Android pins both
          // states to the same flat outline: nothing lights up.
          enabledBorder: widget.isAndroid ? flat : null,
          focusedBorder: widget.isAndroid
              ? flat
              : hc
              ? DashedOutlineInputBorder(borderSide: focusSide)
              : OutlineInputBorder(borderSide: focusSide),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
        ),
        name: placeholder,
        outcome: searchOutcome,
      ),
    );
  }

  // The focus frame comes from _region at the call sites, so it is absent on
  // Android along with the rest of the keyboard wiring.
  Widget _buildFilterChipRow() {
    final l = AppLocalizations.of(context);
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _updateChevrons();
            return false;
          },
          child: SingleChildScrollView(
            controller: _chipScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: _filters
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      // MergeSemantics: the chip builds its own container node,
                      // so a bare Semantics above it would sit in a separate
                      // node and never reach the chip.
                      child: MergeSemantics(
                        child: _saysWhatItDoes(
                          FilterChip(
                            label: Text(
                              _filterLabel(f, l),
                              semanticsLabel: _ownNameLabel(
                                outcome: l.hintFilterChip,
                              ),
                            ),
                            selected: _selectedFilter == f,
                            onSelected: (_) =>
                                setState(() => _selectedFilter = f),
                          ),
                          name: _filterLabel(f, l),
                          outcome: l.hintFilterChip,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (_showRightChevron)
          Positioned(
            right: 0,
            child: _ChipRowFadeEdge(
              alignment: Alignment.centerRight,
              label: l.tooltipNextPage,
              onTap: () => _scrollChips(true),
            ),
          ),
        if (_showLeftChevron)
          Positioned(
            left: 0,
            child: _ChipRowFadeEdge(
              alignment: Alignment.centerLeft,
              label: l.tooltipPreviousPage,
              onTap: () => _scrollChips(false),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_error != null) {
      return Scaffold(body: Center(child: Text(l.vaultLoadFailed(_error!))));
    }

    // Ctrl+F / Ctrl+Shift+F focus search via the global handler (main.dart) — see
    // focusVaultSearch above; no screen-local shortcut wrapper (it died once
    // focus left the screen).
    return Scaffold(
      // Search field sits at the top; let the keyboard overlay the scrollable
      // list rather than shrink the body (which overflowed the header). The
      // search field stays visible above the keyboard.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          _isSelecting
              ? l.selectedCount(_selectedIds.length)
              : _currentAlias(context) != null
              ? l.gabbroVaultTitle(_currentAlias(context)!)
              : l.gabbroTitle,
        ),
        actions: [
          if (_isImporting || _isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!_isSelecting) ...[
            IconButton(
              icon: Icon(
                Icons.checklist,
                semanticLabel: l.tooltipSelectEntries,
              ),
              iconSize: scaledIconSize(context),
              tooltip: l.tooltipSelectEntries,
              onPressed: () => setState(() => _selectionMode = true),
            ),
            IconButton(
              icon: Icon(Icons.lock_outline, semanticLabel: l.tooltipLockVault),
              iconSize: scaledIconSize(context),
              tooltip: l.tooltipLockVault,
              onPressed: _lockAndExit,
            ),
            PopupMenuButton<String>(
              key: _menuKey,
              icon: Icon(Icons.menu, semanticLabel: l.tooltipMenu),
              iconSize: scaledIconSize(context),
              tooltip: l.tooltipMenu,
              onSelected: _onMenuSelected,
              itemBuilder: (context) {
                final ml = AppLocalizations.of(context);
                return [
                  PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.upload_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuExportVault)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'import',
                    child: Row(
                      children: [
                        Icon(Icons.download_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuImportEntries)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sync',
                    child: Row(
                      children: [
                        Icon(Icons.sync, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuSyncFromFile)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'manage_vaults',
                    child: Row(
                      children: [
                        Icon(Icons.folder_special_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuManageVaults)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'change_passphrase',
                    child: Row(
                      children: [
                        Icon(Icons.key_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuChangePassphrase)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    enabled: _isYubikeyVault,
                    value: 'yubikeys',
                    child: Row(
                      children: [
                        Icon(Icons.security_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuManageYubiKeys)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'appearance',
                    child: Row(
                      children: [
                        Icon(Icons.palette_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuAppearance)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'language',
                    child: Row(
                      children: [
                        Icon(Icons.language_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.sectionLanguage)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'security',
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuSecurity)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'manage_folders',
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuManageFolders)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'generator',
                    child: Row(
                      children: [
                        Icon(Icons.casino_outlined, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuPasswordGenerator)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  // Desktop-only: a touch phone has no physical keyboard.
                  if (!widget.isAndroid)
                    PopupMenuItem(
                      value: 'keyboard_shortcuts',
                      child: Row(
                        children: [
                          Icon(Icons.keyboard_outlined,
                              size: scaledIconSize(context, 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(ml.keyboardShortcutsTitle)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'help',
                    child: Row(
                      children: [
                        Icon(Icons.help_outline, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuHelp)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'about',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: scaledIconSize(context, 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(ml.menuAbout)),
                      ],
                    ),
                  ),
                  // Quit is wired only on Linux; elsewhere onQuit is null and
                  // the item is absent.
                  if (widget.onQuit != null) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'quit',
                      child: Row(
                        children: [
                          Icon(Icons.power_settings_new,
                              size: scaledIconSize(context, 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(ml.quit)),
                        ],
                      ),
                    ),
                  ],
                ];
              },
            ),
          ],
          if (_isDeleting) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ] else if (_isSelecting) ...[
            IconButton(
              icon: Icon(
                _selectedIds.length == _filteredEntries.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: _selectedIds.length == _filteredEntries.length
                  ? l.tooltipDeselectAll
                  : l.tooltipSelectAll,
              onPressed: () => setState(() {
                if (_selectedIds.length == _filteredEntries.length) {
                  _selectedIds.clear();
                } else {
                  _selectedIds = _filteredEntries.map((e) => e.id).toSet();
                }
              }),
            ),
            if (_folders.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.folder_outlined),
                tooltip: l.tooltipAssignToFolder,
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _confirmAssignFolder(_selectedIds),
              ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: l.delete,
              onPressed: () => _confirmDelete(_selectedIds),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l.close,
              onPressed: () => setState(() {
                _selectedIds.clear();
                _selectionMode = false;
              }),
            ),
          ],
        ],
      ),
      // FAB stays at default bottom-right but the index bar column ends
      // above it via padding, so they never overlap.
      floatingActionButton: _isSelecting
          ? null
          : FloatingActionButton(
              onPressed: _showTypePicker,
              tooltip: l.newEntryTitle,
              child: Icon(
                Icons.add,
                size: scaledIconSize(context),
                semanticLabel: l.newEntryTitle,
              ),
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600) {
            return TabletVaultLayout(
              groupedEntries: _groupedEntries,
              filteredEntries: _filteredEntries,
              letterIndex: _letterIndex,
              barLetters: canonicalAlphabet(_locale),
              showIndexBar: isIndexableLocale(_locale),
              onLetterSelected: _scrollToLetter,
              displayTitle: (e) => _localizedDisplayTitle(e, l),
              displayType: (t) => _displayType(t, l),
              entryTypeIcon: _entryTypeIcon,
              // Region-wrap search / folder / chips here (VaultListScreen owns
              // these scopes); the list + detail scopes are passed in and wrapped
              // inside TabletVaultLayout. See reference two-layout-paths.
              searchBar: _region(
                _searchScope,
                _buildSearchField(),
                frame: false,
                label: l.regionSearch,
              ),
              filterChipRow: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_folders.isNotEmpty)
                    _region(
                      _folderScope,
                      Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: MergeSemantics(
                        child: _saysWhatItDoes(
                        DropdownButton<String>(
                        focusNode: _folderFocus,
                        isExpanded: true,
                        // Let open-menu items grow to their wrapped height
                        // instead of clipping at the default 48px (ADR-016).
                        itemHeight: null,
                        value: _selectedFolder,
                        // The button shows the selection on one line; ellipsize
                        // it so a long folder truncates cleanly instead of
                        // hard-clipping mid-glyph at large text (ADR-016).
                        selectedItemBuilder: (context) =>
                            [l.allFolders, ..._folders]
                                .map(
                                  // minHeight 48 so the collapsed button is a
                                  // 48dp tap target (a11y net); open menu items
                                  // still grow via itemHeight: null (ADR-016).
                                  (label) => Container(
                                    alignment: AlignmentDirectional.centerStart,
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      semanticsLabel: _ownNameLabel(
                                        outcome: l.hintFolderSelector,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedFolder = value ?? ''),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(l.allFolders),
                          ),
                          ..._folders.map(
                            (f) => DropdownMenuItem(value: f, child: Text(f)),
                          ),
                        ],
                      ),
                        name: _selectedFolder.isEmpty
                            ? l.allFolders
                            : _selectedFolder,
                        outcome: l.hintFolderSelector,
                      ),
                      ),
                    ),
                      label: l.regionFolders,
                    ),
                  _region(
                    _chipsScope,
                    _buildFilterChipRow(),
                    label: l.regionFilters,
                  ),
                ],
              ),
              searchActive: _searchQuery.isNotEmpty,
              onEntryTap: (_) {},
              onRefresh: widget.onRefreshFn ?? _loadEntries,
              getEntryFn: widget.getEntryFn,
              onDeleteEntryFn: widget.onDeleteEntryFn,
              selectionMode: _selectionMode,
              selectedIds: _selectedIds,
              onToggleSelection: (id) => setState(() {
                if (_selectedIds.contains(id)) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                  _selectionMode = true;
                }
              }),
              vaultPath: widget.vaultPath,
              clipboardClearTimeout:
                  GabbroApp.maybeOf(context)?.settings.clipboardClearTimeout ??
                  ClipboardClearTimeout.sixtySeconds,
              // The list + detail Tab regions (desktop only — null on Android so
              // the widget tree is unchanged there). Detail is wrapped by the
              // layout only when an entry is selected, which is how the cycle
              // knows to include it (see _stopOrder).
              listScope: widget.isAndroid ? null : _listScope,
              detailScope: widget.isAndroid ? null : _detailScope,
            );
          }
          final Widget body = SafeArea(
            child: Column(
              children: [
                _region(
                  _searchScope,
                  _buildSearchField(),
                  frame: false,
                  label: l.regionSearch,
                ),
                if (_folders.isNotEmpty)
                  _region(
                    _folderScope,
                    Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: MergeSemantics(
                      child: _saysWhatItDoes(
                    DropdownButton<String>(
                      focusNode: _folderFocus,
                      isExpanded: true,
                      // Let open-menu items grow to their wrapped height
                      // instead of clipping at the default 48px (ADR-016).
                      itemHeight: null,
                      value: _selectedFolder,
                      // Ellipsize the button's one-line selection so a long
                      // folder truncates cleanly instead of hard-clipping at
                      // large text (ADR-016).
                      selectedItemBuilder: (context) =>
                          [l.allFolders, ..._folders]
                              .map(
                                // minHeight 48 so the collapsed button is a
                                // 48dp tap target (a11y net); open menu items
                                // still grow via itemHeight: null (ADR-016).
                                (label) => Container(
                                  alignment: AlignmentDirectional.centerStart,
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    semanticsLabel: _ownNameLabel(
                                      outcome: l.hintFolderSelector,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedFolder = value ?? ''),
                      items: [
                        DropdownMenuItem(value: '', child: Text(l.allFolders)),
                        ..._folders.map(
                          (f) => DropdownMenuItem(value: f, child: Text(f)),
                        ),
                      ],
                    ),
                    name: _selectedFolder.isEmpty
                        ? l.allFolders
                        : _selectedFolder,
                    outcome: l.hintFolderSelector,
                    ),
                    ),
                  ),
                    label: l.regionFolders,
                  ),
                _region(
                  _chipsScope,
                  _buildFilterChipRow(),
                  label: l.regionFilters,
                ),
                Expanded(
                  child: _region(
                    _listScope,
                    _groupedEntries.isEmpty
                      ? Center(child: Text(l.noEntriesMatch))
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Index bar — fixed width column. Position (left or
                            // right) is read from settings or the test override.
                            if (_searchQuery.isEmpty &&
                                isIndexableLocale(_locale) &&
                                _alphabetBarPosition ==
                                    AlphabetBarPosition.left)
                              SizedBox(
                                width: 48,
                                child: AlphabetIndexBar(
                                  letters: canonicalAlphabet(_locale),
                                  presentLetters: _letterIndex.keys.toSet(),
                                  scrollUpLabel: l.tooltipPreviousPage,
                                  scrollDownLabel: l.tooltipNextPage,
                                  onLetterSelected: _scrollToLetter,
                                  highContrast:
                                      GabbroApp.maybeOf(context)
                                          ?.settings
                                          .highContrast ??
                                      false,
                                ),
                              ),
                            // List takes all remaining width.
                            Expanded(
                              child: ScrollConfiguration(
                                // Indexable locales hide the scrollbar (the bar
                                // navigates); ja/zh keep the platform default
                                // (desktop thumb, mobile flick).
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(
                                      scrollbars: isIndexableLocale(_locale)
                                          ? false
                                          : null,
                                    ),
                                child: ScrollablePositionedList.builder(
                                  itemScrollController: _itemScrollController,
                                  padding: const EdgeInsets.only(bottom: 80),
                                  itemCount: _groupedEntries.length,
                                  itemBuilder: (context, index) {
                                    final item = _groupedEntries[index];
                                    if (item is String) {
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          4,
                                        ),
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    }
                                    final entry = item as EntrySummaryData;
                                    final el = AppLocalizations.of(context);
                                    // Selection mode taps the row to tick it,
                                    // so "opens this entry" would then be a
                                    // lie.
                                    final rowOutcome = _isSelecting
                                        ? null
                                        : el.hintEntryRow;
                                    return _saysWhatItDoes(
                                      ListTile(
                                      dense: true,
                                      leading: _isSelecting
                                          ? _selectionCheckbox(
                                              entry,
                                              _localizedDisplayTitle(entry, el),
                                            )
                                          // No semanticLabel: the subtitle
                                          // below already says the type, and
                                          // labelling the icon too made a
                                          // reader announce it twice
                                          // ("card, amex, card").
                                          : Icon(
                                              _entryTypeIcon(entry.entryType),
                                              size: scaledIconSize(context, 20),
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                      title: Text(
                                        _localizedDisplayTitle(entry, el),
                                        semanticsLabel: _ownNameLabel(
                                          outcome: rowOutcome,
                                        ),
                                      ),
                                      subtitle: Text(
                                        _displayType(entry.entryType, el),
                                      ),
                                      onLongPress: () => setState(() {
                                        _selectionMode = true;
                                        _selectedIds.add(entry.id);
                                      }),
                                      onTap: () async {
                                        if (_isSelecting) {
                                          setState(() {
                                            if (_selectedIds.contains(
                                              entry.id,
                                            )) {
                                              _selectedIds.remove(entry.id);
                                            } else {
                                              _selectedIds.add(entry.id);
                                            }
                                          });
                                          return;
                                        }
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                EntryDetailScreen(
                                                  // Honour the injected fetch
                                                  // like the two-pane layout
                                                  // does: calling the FFI
                                                  // directly left this whole
                                                  // path untestable.
                                                  entry:
                                                      (widget.getEntryFn ??
                                                          (id) =>
                                                              getEntry(id: id))(
                                                        entry.id,
                                                      ),
                                                  // Honour the injected delete
                                                  // too — same reason as the
                                                  // fetch above: calling the
                                                  // FFI directly left deleting
                                                  // from here untestable.
                                                  onDeleteEntry:
                                                      widget.onDeleteEntryFn ??
                                                      (id) =>
                                                          deleteEntry(id: id),
                                                  clipboardClearTimeout:
                                                      GabbroApp.of(context)
                                                          .settings
                                                          .clipboardClearTimeout,
                                                ),
                                          ),
                                        );
                                        if (mounted) _loadEntries();
                                      },
                                      ),
                                      name: _localizedDisplayTitle(entry, el),
                                      outcome: rowOutcome,
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (_searchQuery.isEmpty &&
                                isIndexableLocale(_locale) &&
                                _alphabetBarPosition ==
                                    AlphabetBarPosition.right)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 80),
                                child: SizedBox(
                                  width: 48,
                                  child: AlphabetIndexBar(
                                    letters: canonicalAlphabet(_locale),
                                    presentLetters: _letterIndex.keys.toSet(),
                                    scrollUpLabel: l.tooltipPreviousPage,
                                    scrollDownLabel: l.tooltipNextPage,
                                    onLetterSelected: _scrollToLetter,
                                    highContrast:
                                        GabbroApp.maybeOf(context)
                                            ?.settings
                                            .highContrast ??
                                        false,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    label: l.regionEntries,
                  ),
                ),
              ],
            ),
          );
          // Tab traversal is driven globally (main.dart -> _handleRegionTab);
          // no body-scoped Actions override (it failed on hardware, round 10).
          return body;
        },
      ),
    );
  }
}

/// Passphrase dialog for "Sync from file".
///
/// Owns its TextEditingController so Flutter can dispose it safely during the
/// dialog exit animation via State.dispose(), avoiding use-after-dispose errors.
/// Returns the entered passphrase text on confirm, or null on cancel.
/// Credentials gathered by [SyncPassphraseDialog]. `pin` and `transport` are
/// only meaningful when the source is key-protected (ADR-013).
@visibleForTesting
class SyncCredentials {
  final String passphrase;
  final String pin;
  final String transport;
  // Tapped key material — non-null only for a key-protected source, where the
  // dialog runs the YubiKey tap itself (so it can show the inline tap note).
  final List<int>? hmac;
  final List<int>? credentialId;
  const SyncCredentials({
    required this.passphrase,
    this.pin = '',
    this.transport = 'usb',
    this.hmac,
    this.credentialId,
  });
}

@visibleForTesting
class SyncPassphraseDialog extends StatefulWidget {
  final String filePath;
  final bool isKeyProtected;
  final bool isAndroid;
  // For a key-protected source the dialog taps the key itself so the inline
  // "tap now" note can sit under the PIN field (mirroring the import screen).
  final List<YubikeyRecordData> sourceRecords;
  final Future<YubikeyHmacMatch> Function(
    List<YubikeyRecordData> records,
    String pin,
    String transport,
  )
  onGetYubikeyHmac;
  const SyncPassphraseDialog({
    super.key,
    required this.filePath,
    required this.sourceRecords,
    required this.onGetYubikeyHmac,
    this.isKeyProtected = false,
    this.isAndroid = false,
  });

  @override
  State<SyncPassphraseDialog> createState() => SyncPassphraseDialogState();
}

class SyncPassphraseDialogState extends State<SyncPassphraseDialog> {
  final _ctrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinFocus = FocusNode();
  bool _showPass = false;
  bool _pinObscured = true;
  String _transport = 'usb';
  String? _error;
  // True while the YubiKey tap is in flight (key-protected source only); drives
  // the inline tap note and disables the buttons.
  bool _tapping = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _pinCtrl.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Passphrase-only source: no key tap, return the passphrase straight away.
    if (!widget.isKeyProtected) {
      Navigator.of(context).pop(SyncCredentials(passphrase: _ctrl.text));
      return;
    }
    // A key-protected source needs a YubiKey PIN to run the CTAP2 assertion.
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).yubiKeyPinRequired);
      return;
    }
    // Tap the key while the dialog stays open, showing the inline note, then
    // return the tapped material with the creds for the merge. A failed tap
    // keeps the dialog open with the error rather than aborting the whole flow.
    setState(() {
      _tapping = true;
      _error = null;
    });
    try {
      final match = await widget.onGetYubikeyHmac(
        widget.sourceRecords,
        _pinCtrl.text,
        _transport,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        SyncCredentials(
          passphrase: _ctrl.text,
          pin: _pinCtrl.text,
          transport: _transport,
          hmac: match.hmac,
          credentialId: match.credentialId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(() {
        _tapping = false;
        _error = l.syncFailed(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      // scrollable scrolls title + content + actions together so neither the
      // soft keyboard nor large text strands the action buttons (ADR-016).
      scrollable: true,
      title: Text(l.syncFromFileTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.filePath,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: !_showPass,
            // A key-protected source needs a PIN, so advance to it; otherwise
            // Enter submits.
            onSubmitted: (_) =>
                widget.isKeyProtected ? _pinFocus.requestFocus() : _submit(),
            decoration: InputDecoration(
              labelText: l.vaultPassphraseLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                iconSize: scaledSuffixIconSize(context),
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                tooltip: _showPass ? l.tooltipHide : l.tooltipShow,
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.syncSafeToRetry,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (widget.isKeyProtected) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.usb,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.importSourceKeyProtected,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinCtrl,
              focusNode: _pinFocus,
              obscureText: _pinObscured,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l.yubiKeyPinLabel,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  iconSize: scaledSuffixIconSize(context),
                  icon: Icon(
                    _pinObscured ? Icons.visibility : Icons.visibility_off,
                  ),
                  tooltip: _pinObscured ? l.tooltipShowPin : l.tooltipHidePin,
                  onPressed: () => setState(() => _pinObscured = !_pinObscured),
                ),
              ),
            ),
            if (widget.isAndroid && nfcAvailable) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    l.transportLabel,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 12),
                  // Expanded so the segmented button fits the narrow dialog
                  // width instead of overflowing the Row.
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'usb',
                          label: Text(l.transportUsb),
                        ),
                        ButtonSegment(
                          value: 'nfc',
                          label: Text(l.transportNfc),
                        ),
                      ],
                      selected: {_transport},
                      onSelectionChanged: (s) =>
                          setState(() => _transport = s.first),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (_tapping) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.touch_app,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.tapYubiKeyNow,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _tapping ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        TextButton(onPressed: _tapping ? null : _submit, child: Text(l.sync)),
      ],
    );
  }
}

class _ChipRowFadeEdge extends StatelessWidget {
  final Alignment alignment;
  final String label;
  final VoidCallback onTap;
  const _ChipRowFadeEdge({
    required this.alignment,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRight = alignment == Alignment.centerRight;
    final color = Theme.of(context).scaffoldBackgroundColor;
    // Grow the chevron with the text scale (capped 1.5x — it lives in a fixed
    // 48px edge), matching the alphabet bar and breakdown sheet.
    final s = controlScaleFor(context).clamp(1.0, 1.5).toDouble();
    // Button semantics + a desktop hover tooltip, matching the alphabet index
    // bar. The Tooltip sits inside the excludeSemantics wrapper so the label is
    // announced once, not twice.
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
                end: isRight ? Alignment.centerRight : Alignment.centerLeft,
                colors: [color.withValues(alpha: 0), color],
              ),
            ),
            child: Center(
              child: Container(
                width: 28 * s,
                height: 28 * s,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRight ? Icons.chevron_right : Icons.chevron_left,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 20 * s,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
