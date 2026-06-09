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
}
