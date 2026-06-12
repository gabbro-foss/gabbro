import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Single source of truth for the app's on-disk directories.
///
/// Two roots:
/// - **config** — user settings (`settings.jsonc`) and the vault registry
///   (`vaults.jsonc`). Linux/macOS: `$HOME/.config/gabbro` (resp. Application
///   Support); elsewhere the platform app-support dir.
/// - **data** — the default location for new vault files. The platform
///   app-support dir on every platform.
///
/// [sandboxRoot] is a test-only override. When set, BOTH roots resolve under it
/// (`<root>/config`, `<root>/data`) and the real folders are never touched. The
/// global net in `test/flutter_test_config.dart` sets it for the whole test run,
/// so no test can reach the user's real settings or vaults even if it forgets to.
class GabbroPaths {
  GabbroPaths._();

  /// Test-only: when non-null, every config/data path roots under this directory.
  /// Must never be left set in production code (it defaults to null).
  @visibleForTesting
  static String? sandboxRoot;

  /// Directory for `settings.jsonc` and `vaults.jsonc`. Created if absent.
  static Future<String> configDir() async {
    final root = sandboxRoot;
    final dir = root != null ? '$root/config' : await _realConfigDir();
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// Default directory for new vault files. Created if absent.
  static Future<String> dataDir() async {
    final root = sandboxRoot;
    final dir = root != null ? '$root/data' : await _realDataDir();
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// The Linux GTK application id, set as `APPLICATION_ID` in
  /// `linux/CMakeLists.txt` and as every `MethodChannel` prefix in `lib/`.
  /// path_provider reads this same id from the running GTK process at runtime;
  /// we only consult this constant in [linuxDataDirFallback], which runs solely
  /// when path_provider cannot resolve the directory at all.
  static const String _linuxApplicationId = 'app.gabbro.gabbro';

  // Real-folder resolution — must match the historical per-call-site logic so
  // production behaviour is unchanged when sandboxRoot is null.
  static Future<String> _realConfigDir() async {
    if (Platform.isLinux) {
      return linuxConfigDir(
        xdgConfigHome: Platform.environment['XDG_CONFIG_HOME'],
        home: Platform.environment['HOME'],
      );
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/Library/Application Support/gabbro';
    }
    return (await getApplicationSupportDirectory()).path;
  }

  static Future<String> _realDataDir() async {
    // path_provider returns whatever directory the install already uses, so on
    // every working machine this is unchanged. Only when it cannot resolve at
    // all (e.g. a bubblewrap sandbox with no ~/.local/share or GTK app-id) do
    // we reconstruct the same path it would have produced.
    try {
      return (await getApplicationSupportDirectory()).path;
    } catch (_) {
      if (Platform.isLinux) {
        return linuxDataDirFallback(
          xdgDataHome: Platform.environment['XDG_DATA_HOME'],
          home: Platform.environment['HOME'],
          dirExists: (p) => Directory(p).existsSync(),
        );
      }
      rethrow;
    }
  }

  /// Pure Linux config-dir resolution. Preserves the historical
  /// `$HOME/.config/gabbro` (so no existing install moves), and only when
  /// `HOME` is unset does it honour `XDG_CONFIG_HOME`. Throws when neither is
  /// available, so the caller can warn and let the user choose a path rather
  /// than silently writing somewhere wrong.
  @visibleForTesting
  static String linuxConfigDir({
    required String? xdgConfigHome,
    required String? home,
  }) {
    if (home != null && home.isNotEmpty) return '$home/.config/gabbro';
    if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
      return '$xdgConfigHome/gabbro';
    }
    throw Exception(
      'Cannot determine a config directory: neither HOME nor XDG_CONFIG_HOME '
      'is set.',
    );
  }

  /// Pure Linux data-dir fallback, used only when path_provider cannot resolve.
  /// Mirrors path_provider_linux's precedence so it lands on the SAME directory
  /// an existing install already uses: an existing app-id dir wins, then an
  /// existing legacy executable-name dir (`<base>/gabbro`), otherwise the app-id
  /// dir as the create target. Throws when no base directory can be determined.
  @visibleForTesting
  static String linuxDataDirFallback({
    required String? xdgDataHome,
    required String? home,
    required bool Function(String path) dirExists,
  }) {
    final String base;
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      base = xdgDataHome;
    } else if (home != null && home.isNotEmpty) {
      base = '$home/.local/share';
    } else {
      throw Exception(
        'Cannot determine a data directory: neither XDG_DATA_HOME nor HOME is '
        'set.',
      );
    }
    final appIdDir = '$base/$_linuxApplicationId';
    if (dirExists(appIdDir)) return appIdDir;
    final legacyDir = '$base/gabbro';
    if (dirExists(legacyDir)) return legacyDir;
    return appIdDir;
  }
}
