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

  // Real-folder resolution — must match the historical per-call-site logic so
  // production behaviour is unchanged when sandboxRoot is null.
  static Future<String> _realConfigDir() async {
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return Platform.isLinux
          ? '$home/.config/gabbro'
          : '$home/Library/Application Support/gabbro';
    }
    return (await getApplicationSupportDirectory()).path;
  }

  static Future<String> _realDataDir() async =>
      (await getApplicationSupportDirectory()).path;
}
