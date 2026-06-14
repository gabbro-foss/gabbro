import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/l10n/app_localizations.dart';
import 'package:gabbro/main.dart';
import 'package:gabbro/screens/language_screen.dart';
import 'package:gabbro/screens/vault_list_screen.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/src/rust/api/entropy.dart';
import 'package:gabbro/src/rust/api/fido_bridge.dart';
import 'package:gabbro/src/rust/api/vault_bridge.dart';
import 'package:gabbro/widgets/gabbro_logo.dart';
import 'package:gabbro/widgets/path_field.dart';
import 'package:gabbro/widgets/segmented_row.dart';

// ── Hex helpers ───────────────────────────────────────────────────────────────

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final result = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(result);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Turns a user-entered vault alias into a safe filename stem for the default
/// vault path. Lowercases, spaces -> `_`, and strips everything outside
/// `[a-z0-9_-]` so an alias can never inject a path separator or `..` traversal
/// into the generated vault path (the alias-path auto-sync feeds this straight
/// into `<dataDir>/<stem>_gabbro.gabbro`). Empty result falls back to `vault`.
@visibleForTesting
String sanitiseVaultAlias(String alias) {
  final s = alias.trim().toLowerCase().replaceAll(' ', '_');
  final cleaned = s.replaceAll(RegExp(r'[^a-z0-9_\-]'), '');
  return cleaned.isEmpty ? 'vault' : cleaned;
}

// ── Bridge defaults ───────────────────────────────────────────────────────────

Future<void> _defaultInitVault(
  List<int> passphrase,
  String path,
  String? alias,
) => initVault(passphrase: passphrase, path: path, alias: alias);

EntropyResult _defaultEstimateEntropy(String password) =>
    estimateEntropy(password: password);

const _yubikeyChannel = MethodChannel('app.gabbro.gabbro/yubikey');

Future<void> _linuxInitVaultWithYubikey(
  List<int> passphrase,
  List<String> pins,
  String path,
  void Function() onStep2,
  void Function() onStep3,
  Future<void> Function() onAwaitBackupKey,
  void Function() onStep4,
  String? alias,
) async {
  final primaryDevices = fidoListDevices();
  if (primaryDevices.isEmpty) {
    throw PlatformException(code: 'NO_FIDO2_DEVICE');
  }
  final primaryDevicePath = primaryDevices.first;

  // Tap 1: register primary key
  final cred1 = await fidoRegister(devicePath: primaryDevicePath, pin: pins[0]);
  onStep2();

  // Tap 2: activate primary key (get hmac-secret)
  final hmac1 = await fidoGetHmacSecret(
    devicePath: primaryDevicePath,
    credentialId: cred1.credentialId,
    salt: cred1.salt,
    pin: pins[0],
  );
  onStep3();

  // Wait for user to swap to a different physical key
  await onAwaitBackupKey();

  // Re-scan: user should have swapped to their backup key
  final backupDevices = fidoListDevices();
  if (backupDevices.isEmpty) {
    throw PlatformException(code: 'NO_BACKUP_FIDO2_DEVICE');
  }
  final backupDevicePath = backupDevices.first;

  // Tap 3: register backup key
  final cred2 = await fidoRegister(devicePath: backupDevicePath, pin: pins[1]);
  onStep4();

  // Tap 4: activate backup key (get hmac-secret)
  final hmac2 = await fidoGetHmacSecret(
    devicePath: backupDevicePath,
    credentialId: cred2.credentialId,
    salt: cred2.salt,
    pin: pins[1],
  );

  await initVaultWithKeys(
    passphrase: passphrase,
    keys: [
      YubiKeyInitData(
        credentialId: cred1.credentialId,
        hmacSecret: hmac1,
        hkdfSalt: cred1.salt,
      ),
      YubiKeyInitData(
        credentialId: cred2.credentialId,
        hmacSecret: hmac2,
        hkdfSalt: cred2.salt,
      ),
    ],
    path: path,
    alias: alias,
  );
}

Future<void> _defaultInitVaultWithYubikey(
  List<int> passphrase,
  List<String> pins,
  String path,
  void Function() onStep2,
  void Function() onStep3,
  Future<void> Function() onAwaitBackupKey,
  void Function() onStep4,
  String transport,
  String? alias,
) async {
  if (Platform.isLinux) {
    return _linuxInitVaultWithYubikey(
      passphrase,
      pins,
      path,
      onStep2,
      onStep3,
      onAwaitBackupKey,
      onStep4,
      alias,
    );
  }

  // Android: register and activate 2 keys via platform channel.
  // Each MethodChannel call starts fresh discovery, so it accepts whatever
  // key is physically presented at that moment.

  // Tap 1: register primary key
  final credId1Hex = await _yubikeyChannel.invokeMethod<String>('register', {
    'pin': pins[0],
    'transport': transport,
  });
  if (credId1Hex == null) {
    throw Exception('YubiKey registration returned no credential');
  }

  final salt1 = Uint8List.fromList(
    List.generate(32, (_) => Random.secure().nextInt(256)),
  );
  onStep2();

  // Tap 2: activate primary key
  final hmac1Hex = await _yubikeyChannel
      .invokeMethod<String>('get_hmac_secret', {
        'credentialId': credId1Hex,
        'salt': _toHex(salt1),
        'pin': pins[0],
        'transport': transport,
      });
  if (hmac1Hex == null) {
    throw Exception('YubiKey activation returned no secret');
  }
  onStep3();

  // Wait for user to swap to a different physical key before backup registration
  await onAwaitBackupKey();

  // Tap 3: register backup key (fresh discovery — accepts the backup key now presented)
  final credId2Hex = await _yubikeyChannel.invokeMethod<String>('register', {
    'pin': pins[1],
    'transport': transport,
  });
  if (credId2Hex == null) {
    throw Exception('YubiKey registration returned no credential');
  }

  final salt2 = Uint8List.fromList(
    List.generate(32, (_) => Random.secure().nextInt(256)),
  );
  onStep4();

  // Tap 4: activate backup key
  final hmac2Hex = await _yubikeyChannel
      .invokeMethod<String>('get_hmac_secret', {
        'credentialId': credId2Hex,
        'salt': _toHex(salt2),
        'pin': pins[1],
        'transport': transport,
      });
  if (hmac2Hex == null) {
    throw Exception('YubiKey activation returned no secret');
  }

  await initVaultWithKeys(
    passphrase: passphrase,
    keys: [
      YubiKeyInitData(
        credentialId: _fromHex(credId1Hex),
        hmacSecret: _fromHex(hmac1Hex),
        hkdfSalt: salt1,
      ),
      YubiKeyInitData(
        credentialId: _fromHex(credId2Hex),
        hmacSecret: _fromHex(hmac2Hex),
        hkdfSalt: salt2,
      ),
    ],
    path: path,
    alias: alias,
  );
}

// ── Widget ────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  final String? initialPath;
  final String? postDeletionMessage;
  final Future<void> Function(List<int> passphrase, String path, String? alias) onInitVault;
  final EntropyResult Function(String password) onEstimateEntropy;
  final bool blockPassphraseCopyPaste;

  /// Controls YubiKey opt-in section visibility. Defaults to Android or Linux.
  /// Tests can pass `showYubikey: true` to exercise the YubiKey UI.
  final bool showYubikey;

  /// True only on Android — controls NFC transport selector visibility.
  /// Tests simulating Android can pass `isAndroid: true`.
  final bool isAndroid;

  final Future<void> Function(
    List<int> passphrase,
    List<String> pins,
    String path,
    void Function() onStep2,
    void Function() onStep3,
    Future<void> Function() onAwaitBackupKey,
    void Function() onStep4,
    String transport,
    String? alias,
  )
  onInitVaultWithYubikey;

  /// Called after successful vault creation with the vault path and alias.
  /// Use this to add the new vault to the registry.
  final Future<void> Function(String path, String alias)? onVaultCreated;

  /// Aliases that are already in use by other vaults. The alias form field
  /// will reject any value present in this set.
  final Set<String> existingAliases;

  /// Resolves the default directory for new vault files. Seam for tests; in
  /// production it is [GabbroPaths.dataDir], which can throw when no data
  /// directory can be determined (e.g. a Wayland bubblewrap sandbox with no
  /// `~/.local/share`). On failure the path field is left empty and editable.
  final Future<String> Function() resolveDataDir;

  OnboardingScreen({
    super.key,
    this.initialPath,
    this.postDeletionMessage,
    this.onInitVault = _defaultInitVault,
    this.onEstimateEntropy = _defaultEstimateEntropy,
    this.blockPassphraseCopyPaste = true,
    bool? showYubikey,
    bool? isAndroid,
    this.onInitVaultWithYubikey = _defaultInitVaultWithYubikey,
    this.onVaultCreated,
    this.existingAliases = const {},
    this.resolveDataDir = GabbroPaths.dataDir,
  }) : showYubikey = showYubikey ?? (Platform.isAndroid || Platform.isLinux),
       isAndroid = isAndroid ?? Platform.isAndroid;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aliasController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  // One controller per key (index 0 = primary, 1 = backup, …)
  final List<TextEditingController> _pinControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  String _vaultPath = '';
  String? _defaultDir;
  bool _pathManuallySet = false;

  bool _passphraseObscured = true;
  bool _confirmObscured = true;
  final List<bool> _pinObscured = [true, true];
  bool _isCreating = false;
  String? _error;
  EntropyResult? _entropy;
  bool? _confirmMatches;
  bool _useYubikey = false;
  String _transport = 'usb';
  // 0 = idle, 1 = tap 1 (register key 1), 2 = tap 2 (activate key 1),
  // 3 = swap key (user presses Continue), 4 = tap 3 (register key 2),
  // 5 = tap 4 (activate key 2)
  int _yubikeyStep = 0;
  Completer<void>? _backupKeyCompleter;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      _vaultPath = widget.initialPath!;
      _pathManuallySet = true;
    } else {
      _initDefaultPath();
    }
    _aliasController.addListener(_onAliasChanged);
  }

  void _onAliasChanged() {
    if (_pathManuallySet) return;
    final dir = _defaultDir;
    if (dir == null) return;
    final alias = _aliasController.text.trim();
    final newPath = alias.isEmpty
        ? _firstFreeVaultPath(dir)
        : _aliasBasedPath(dir, alias);
    if (newPath != _vaultPath) {
      setState(() => _vaultPath = newPath);
    }
  }

  Future<void> _initDefaultPath() async {
    String? dirPath;
    try {
      dirPath = await widget.resolveDataDir();
    } catch (_) {
      // No data directory could be determined (e.g. a sandbox with no
      // ~/.local/share). Leave the path empty so the editable field lets the
      // user type or paste their own location instead of crashing.
      dirPath = null;
    }
    if (!mounted) return;
    final alias = _aliasController.text.trim();
    setState(() {
      _defaultDir = dirPath;
      _vaultPath = dirPath == null
          ? ''
          : (alias.isEmpty
              ? _firstFreeVaultPath(dirPath)
              : _aliasBasedPath(dirPath, alias));
    });
  }

  String _firstFreeVaultPath(String dirPath) {
    if (!File('$dirPath/gabbro.gabbro').existsSync()) {
      return '$dirPath/gabbro.gabbro';
    }
    for (var i = 2; ; i++) {
      final p = '$dirPath/gabbro_$i.gabbro';
      if (!File(p).existsSync()) return p;
    }
  }

  String _aliasBasedPath(String dirPath, String alias) {
    final base = sanitiseVaultAlias(alias);
    final primary = '$dirPath/${base}_gabbro.gabbro';
    if (!File(primary).existsSync()) return primary;
    for (var i = 2; ; i++) {
      final p = '$dirPath/${base}_${i}_gabbro.gabbro';
      if (!File(p).existsSync()) return p;
    }
  }

  @override
  void dispose() {
    _aliasController.removeListener(_onAliasChanged);
    _aliasController.dispose();
    _passphraseController.dispose();
    _confirmController.dispose();
    for (final c in _pinControllers) {
      c.dispose();
    }
    final c = _backupKeyCompleter;
    if (c != null && !c.isCompleted) {
      c.completeError(Exception('Widget disposed'));
    }
    super.dispose();
  }

  Future<void> _awaitBackupKey() {
    _backupKeyCompleter = Completer<void>();
    return _backupKeyCompleter!.future;
  }

  void _onContinueWithBackupKey() {
    final c = _backupKeyCompleter;
    if (c == null || c.isCompleted) return;
    if (mounted) setState(() => _yubikeyStep = 4);
    c.complete();
  }

  String _pinLabel(int index, AppLocalizations l) => switch (index) {
    0 => l.onboardingPrimaryKeyPin,
    1 => l.onboardingBackupKeyPin,
    _ => l.onboardingKeyNPin(index + 1),
  };

  void _onPassphraseChanged(String value) {
    final result = widget.onEstimateEntropy(value);
    setState(() => _entropy = result);
  }

  Future<void> _createVault() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isCreating = true;
      _error = null;
      if (_useYubikey) _yubikeyStep = 1;
    });
    try {
      final file = File(_vaultPath);
      await file.parent.create(recursive: true);
      final alias = _aliasController.text.trim();
      if (_useYubikey) {
        await widget.onInitVaultWithYubikey(
          _passphraseController.text.codeUnits,
          _pinControllers.map((c) => c.text).toList(),
          _vaultPath,
          () {
            if (mounted) setState(() => _yubikeyStep = 2);
          },
          () {
            if (mounted) setState(() => _yubikeyStep = 3);
          },
          _awaitBackupKey,
          () {
            if (mounted) setState(() => _yubikeyStep = 5);
          },
          _transport,
          alias.isEmpty ? null : alias,
        );
      } else {
        await widget.onInitVault(
          _passphraseController.text.codeUnits,
          _vaultPath,
          alias.isEmpty ? null : alias,
        );
      }
      await widget.onVaultCreated?.call(_vaultPath, _aliasController.text.trim());
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VaultListScreen(
              vaultPath: _vaultPath,
              vaultAlias: _aliasController.text.trim(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        setState(() {
          _error = switch (e) {
            PlatformException(code: 'NO_FIDO2_DEVICE') => l.noFidoDeviceFound,
            PlatformException(code: 'NO_BACKUP_FIDO2_DEVICE') =>
              l.noBackupFidoDeviceFound,
            PlatformException() => e.message ?? l.yubikeyOperationFailed,
            _ => e.toString(),
          };
          _yubikeyStep = 0;
        });
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Color _tierColor(StrengthTier tier) => switch (tier) {
    StrengthTier.terrible => Colors.red,
    StrengthTier.weak => Colors.orange,
    StrengthTier.fair => Colors.yellow.shade700,
    StrengthTier.strong => Colors.lightGreen,
    StrengthTier.veryStrong => Colors.green,
    StrengthTier.centuries => Colors.green.shade800,
  };

  String _tierLabel(StrengthTier tier, AppLocalizations l) => switch (tier) {
    StrengthTier.terrible => l.strengthTierTerrible,
    StrengthTier.weak => l.strengthTierWeak,
    StrengthTier.fair => l.strengthTierFair,
    StrengthTier.strong => l.strengthTierStrong,
    StrengthTier.veryStrong => l.strengthTierVeryStrong,
    StrengthTier.centuries => l.strengthTierExcellent,
  };

  /// A passphrase may create a vault once it reaches the `Fair` tier. Anything
  /// weaker (Weak / Terrible) is blocked with a visible explanation; a `Fair`
  /// passphrase is allowed but its strength warning stays in plain sight.
  bool get _meetsMinimum =>
      _entropy != null &&
      _entropy!.tier != StrengthTier.terrible &&
      _entropy!.tier != StrengthTier.weak;

  Future<void> _toggleAccessibility() async {
    final app = GabbroApp.maybeOf(context);
    if (app == null) return;
    final current = app.settings;
    final isOn =
        current.highContrast && current.textSize == TextSizeChoice.xxLarge;
    await app.updateSettings(
      current.copyWith(
        highContrast: !isOn,
        textSize: isOn ? TextSizeChoice.regular : TextSizeChoice.xxLarge,
      ),
    );
  }

  void _showLanguagePicker() {
    final app = GabbroApp.maybeOf(context);
    if (app == null) return;
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: ListView(
            children: [
              for (final lang in sortedLanguageChoices(l))
                ListTile(
                  title: Text(languageChoiceLabel(lang, l)),
                  selected: app.settings.language == lang,
                  onTap: () {
                    app.updateSettings(app.settings.copyWith(language: lang));
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(
    BuildContext context, {
    required int number,
    required String label,
    required String hint,
    required bool done,
    required bool active,
  }) {
    final cs = Theme.of(context).colorScheme;
    final circleColor = done
        ? Colors.green.shade600
        : active
        ? cs.primary
        : cs.outlineVariant;
    final labelColor = done
        ? Colors.green.shade600
        : active
        ? cs.onSurface
        : cs.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(shape: BoxShape.circle, color: circleColor),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '$number',
                    style: TextStyle(
                      color: active ? Colors.white : cs.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              if (active)
                Text(
                  hint,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildYubikeyCreationSteps(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    Widget connector(bool done) => Padding(
      padding: const EdgeInsets.only(left: 13, top: 4, bottom: 4),
      child: Container(
        width: 2,
        height: 14,
        color: done ? Colors.green.shade600 : cs.outlineVariant,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepRow(
            context,
            number: 1,
            label: l.onboardingStep1Label,
            hint: l.onboardingStep1Hint,
            done: _yubikeyStep >= 2,
            active: _yubikeyStep == 1,
          ),
          connector(_yubikeyStep >= 2),
          _buildStepRow(
            context,
            number: 2,
            label: l.onboardingStep2Label,
            hint: l.onboardingStep2Hint,
            done: _yubikeyStep >= 3,
            active: _yubikeyStep == 2,
          ),
          connector(_yubikeyStep >= 3),
          _buildStepRow(
            context,
            number: 3,
            label: l.onboardingStep3Label,
            hint: l.onboardingStep3Hint,
            done: _yubikeyStep >= 4,
            active: _yubikeyStep == 3,
          ),
          if (_yubikeyStep == 3) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: _onContinueWithBackupKey,
                  child: Text(AppLocalizations.of(context).continueLabel),
                ),
              ),
            ),
          ],
          connector(_yubikeyStep >= 4),
          _buildStepRow(
            context,
            number: 4,
            label: l.onboardingStep4Label,
            hint: l.onboardingStep4Hint,
            done: _yubikeyStep >= 5,
            active: _yubikeyStep == 4,
          ),
          connector(_yubikeyStep >= 5),
          _buildStepRow(
            context,
            number: 5,
            label: l.onboardingStep5Label,
            hint: l.onboardingStep5Hint,
            done: false,
            active: _yubikeyStep == 5,
          ),
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = GabbroApp.maybeOf(context);
    final isAccessibilityOn =
        app != null &&
        app.settings.highContrast &&
        app.settings.textSize == TextSizeChoice.xxLarge;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top row: cancel (left, if nested) + accessibility (right) ──
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  if (Navigator.canPop(context))
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l.tooltipCancel,
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.language),
                      tooltip: AppLocalizations.of(context).sectionLanguage,
                      onPressed: _showLanguagePicker,
                    ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: MediaQuery.of(context).viewInsets.bottom > 0
                        ? 0.0
                        : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.accessibility_new,
                          color: isAccessibilityOn
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        label: Text(AppLocalizations.of(context).accessibilityButton),
                        onPressed: _toggleAccessibility,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Main content ────────────────────────────────────────────
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      32,
                      16,
                      32,
                      32 + MediaQuery.of(context).viewPadding.bottom,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: GabbroLogo(withText: true, width: 200)),
                          const SizedBox(height: 8),
                          if (widget.postDeletionMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      widget.postDeletionMessage!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Text(
                              l.onboardingGetStarted,
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 40),
                          Text(
                            l.onboardingVaultName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _aliasController,
                            decoration: InputDecoration(
                              labelText: l.aliasLabel,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return l.onboardingAliasRequired;
                              }
                              final alias = v.trim();
                              if (widget.existingAliases.contains(alias)) {
                                return l.vaultNameAlreadyExists(alias);
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          Text(
                            widget.postDeletionMessage != null
                                ? l.onboardingNewVaultLocation
                                : l.onboardingVaultLocation,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          if (widget.isAndroid)
                            Text(
                              _vaultPath.isEmpty ? l.onboardingLoadingPath : _vaultPath,
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          else
                            PathField(
                              mode: PathFieldMode.save,
                              hint: l.onboardingPathHint,
                              initialPath: _vaultPath.isEmpty
                                  ? null
                                  : _vaultPath,
                              allowedExtensions: const ['gabbro'],
                              saveFileName: _vaultPath.isEmpty
                                  ? 'gabbro.gabbro'
                                  : _vaultPath.split('/').last,
                              onPathSelected: (path) => setState(() {
                                _pathManuallySet = true;
                                _vaultPath = path;
                              }),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? l.onboardingPathRequired
                                  : null,
                            ),
                          if (widget.postDeletionMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              l.onboardingReusePassphraseHint,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _passphraseController,
                            obscureText: _passphraseObscured,
                            enableInteractiveSelection:
                                !widget.blockPassphraseCopyPaste,
                            onChanged: _onPassphraseChanged,
                            decoration: InputDecoration(
                              labelText: l.masterPassphraseLabel,
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _passphraseObscured
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _passphraseObscured =
                                      !_passphraseObscured,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l.onboardingPassphraseRequired;
                              }
                              if (!_meetsMinimum) {
                                return l.passphraseTooWeak;
                              }
                              return null;
                            },
                          ),
                          if (_entropy != null) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: switch (_entropy!.tier) {
                                StrengthTier.terrible => 0.1,
                                StrengthTier.weak => 0.25,
                                StrengthTier.fair => 0.5,
                                StrengthTier.strong => 0.75,
                                StrengthTier.veryStrong => 0.9,
                                StrengthTier.centuries => 1.0,
                              },
                              color: _tierColor(_entropy!.tier),
                              backgroundColor: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.unlockEntropyDisplay(
                                _tierLabel(_entropy!.tier, l),
                                _entropy!.bits.toStringAsFixed(1),
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: _tierColor(_entropy!.tier),
                              ),
                            ),
                            // Below the minimum: make the disabled button's
                            // reason explicit rather than leaving it greyed out
                            // with no explanation.
                            if (!_meetsMinimum) ...[
                              const SizedBox(height: 4),
                              Text(
                                l.passphraseTooWeak,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: _confirmObscured,
                            enableInteractiveSelection:
                                !widget.blockPassphraseCopyPaste,
                            onFieldSubmitted: (_) => _createVault(),
                            onChanged: (v) {
                              setState(
                                () => _confirmMatches = v.isEmpty
                                    ? null
                                    : v == _passphraseController.text,
                              );
                            },
                            decoration: InputDecoration(
                              labelText: l.confirmPassphraseLabelShort,
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _confirmObscured
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _confirmObscured = !_confirmObscured,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l.onboardingConfirmRequired;
                              }
                              if (v != _passphraseController.text) {
                                return l.passphrasesDoNotMatch;
                              }
                              return null;
                            },
                          ),
                          if (_confirmMatches != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _confirmMatches!
                                  ? l.passphrasesMatch
                                  : l.passphrasesNoMatch,
                              style: TextStyle(
                                fontSize: 12,
                                color: _confirmMatches!
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          // ── YubiKey opt-in (Android and Linux) ─────────────
                          if (widget.showYubikey) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            SwitchListTile(
                              title: Text(AppLocalizations.of(context).protectWithYubiKey),
                              subtitle: Text(
                                AppLocalizations.of(context).yubiKeySubtitle,
                              ),
                              value: _useYubikey,
                              onChanged: (v) => setState(() => _useYubikey = v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (_useYubikey) ...[
                              for (
                                var i = 0;
                                i < _pinControllers.length;
                                i++
                              ) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _pinControllers[i],
                                  obscureText: _pinObscured[i],
                                  decoration: InputDecoration(
                                    labelText: _pinLabel(i, l),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _pinObscured[i]
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () => setState(
                                        () =>
                                            _pinObscured[i] = !_pinObscured[i],
                                      ),
                                    ),
                                  ),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? l.yubiKeyPinRequired
                                      : null,
                                ),
                              ],
                              if (widget.isAndroid) ...[
                                const SizedBox(height: 12),
                                SegmentedRow<String>(
                                  values: const ['usb', 'nfc'],
                                  selected: _transport,
                                  label: (v) => v.toUpperCase(),
                                  onSelected: (v) =>
                                      setState(() => _transport = v),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if (_isCreating)
                                _buildYubikeyCreationSteps(context)
                              else ...[
                                Text(
                                  l.onboardingYubikeyTapInstruction,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    l.onboardingYubikeySlowNote,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ],
                          ],
                          const SizedBox(height: 24),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          FilledButton(
                            onPressed: (_isCreating || !_meetsMinimum)
                                ? null
                                : _createVault,
                            child: _isCreating
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(AppLocalizations.of(context).createVault),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
