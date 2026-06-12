// GabbroPaths is the single source of truth for the app's config + data
// directories, with a test-only `sandboxRoot` override. When the override is set,
// every settings / registry / vault-default read and write is rooted under it, so
// no test can ever touch the user's real ~/.config/gabbro or vault folders.
//
// The global net lives in test/flutter_test_config.dart, which sets sandboxRoot for
// the whole `flutter test` run. These tests point it at a per-test temp dir and
// restore the previous (global) value in tearDown - never leaving it null, which
// would re-expose the real folders to subsequent test files.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_paths.dart';

void main() {
  late Directory tmp;
  late String? previousRoot;

  setUp(() async {
    previousRoot = GabbroPaths.sandboxRoot; // the global sandbox from flutter_test_config
    tmp = await Directory.systemTemp.createTemp('gabbro_paths_test_');
    GabbroPaths.sandboxRoot = tmp.path;
  });

  tearDown(() async {
    GabbroPaths.sandboxRoot = previousRoot; // restore the global net, never null
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('configDir roots under the sandbox and is created', () async {
    final dir = await GabbroPaths.configDir();
    expect(dir, '${tmp.path}/config');
    expect(Directory(dir).existsSync(), isTrue,
        reason: 'configDir must create the directory it returns');
  });

  test('dataDir roots under the sandbox and is created', () async {
    final dir = await GabbroPaths.dataDir();
    expect(dir, '${tmp.path}/data');
    expect(Directory(dir).existsSync(), isTrue,
        reason: 'dataDir must create the directory it returns');
  });

  test('config and data are distinct dirs under the same sandbox root', () async {
    final config = await GabbroPaths.configDir();
    final data = await GabbroPaths.dataDir();
    expect(config, isNot(equals(data)));
    expect(config, startsWith(tmp.path));
    expect(data, startsWith(tmp.path));
  });

  // Linux real-folder resolution. These are pure functions: the production
  // _realDataDir wraps path_provider's getApplicationSupportDirectory and only
  // falls back to linuxDataDirFallback when that throws (e.g. under a bubblewrap
  // sandbox where ~/.local/share is absent or the GTK app-id FFI is unavailable).
  // The fallback must mirror path_provider_linux's own precedence so it lands on
  // the SAME directory an existing install already uses - never moving a vault.
  group('Linux real-folder resolution (pure)', () {
    test('linuxDataDirFallback: XDG_DATA_HOME set and the app-id dir exists '
        'returns the app-id dir under XDG_DATA_HOME', () {
      final dir = GabbroPaths.linuxDataDirFallback(
        xdgDataHome: '/xdg/data',
        home: '/home/u',
        dirExists: (p) => p == '/xdg/data/app.gabbro.gabbro',
      );
      expect(dir, '/xdg/data/app.gabbro.gabbro');
    });

    test('linuxDataDirFallback: XDG_DATA_HOME empty, HOME set, nothing exists '
        'yet returns the create-target under ~/.local/share', () {
      final dir = GabbroPaths.linuxDataDirFallback(
        xdgDataHome: '',
        home: '/home/u',
        dirExists: (_) => false,
      );
      expect(dir, '/home/u/.local/share/app.gabbro.gabbro');
    });

    test('linuxDataDirFallback: only the legacy <base>/gabbro dir exists '
        'returns the legacy dir (matches path_provider, protects old installs)',
        () {
      final dir = GabbroPaths.linuxDataDirFallback(
        xdgDataHome: '',
        home: '/home/u',
        dirExists: (p) => p == '/home/u/.local/share/gabbro',
      );
      expect(dir, '/home/u/.local/share/gabbro');
    });

    test('linuxDataDirFallback: both the app-id and legacy dirs exist '
        'prefers the app-id dir', () {
      final dir = GabbroPaths.linuxDataDirFallback(
        xdgDataHome: '',
        home: '/home/u',
        dirExists: (_) => true,
      );
      expect(dir, '/home/u/.local/share/app.gabbro.gabbro');
    });

    test('linuxDataDirFallback: neither XDG_DATA_HOME nor HOME is set throws',
        () {
      expect(
        () => GabbroPaths.linuxDataDirFallback(
          xdgDataHome: null,
          home: null,
          dirExists: (_) => false,
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => GabbroPaths.linuxDataDirFallback(
          xdgDataHome: '',
          home: '',
          dirExists: (_) => false,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('linuxConfigDir: HOME set returns ~/.config/gabbro and ignores '
        'XDG_CONFIG_HOME (no-move guard for existing installs)', () {
      final dir = GabbroPaths.linuxConfigDir(
        xdgConfigHome: '/xdg/config',
        home: '/home/u',
      );
      expect(dir, '/home/u/.config/gabbro');
    });

    test('linuxConfigDir: HOME empty but XDG_CONFIG_HOME set returns '
        '<XDG_CONFIG_HOME>/gabbro', () {
      final dir = GabbroPaths.linuxConfigDir(
        xdgConfigHome: '/xdg/config',
        home: '',
      );
      expect(dir, '/xdg/config/gabbro');
    });

    test('linuxConfigDir: neither HOME nor XDG_CONFIG_HOME is set throws', () {
      expect(
        () => GabbroPaths.linuxConfigDir(xdgConfigHome: null, home: null),
        throwsA(isA<Exception>()),
      );
    });
  });
}
