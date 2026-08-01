// The global test sandbox (test/flutter_test_config.dart) must hold DURING
// test execution, not just during declaration. It once did not: testMain()
// returns at declaration time, so a teardown that nulled the root ran before
// any test body — and a test driving a real production save overwrote the
// user's real ~/.config/gabbro/vaults.jsonc (2026-08-01). These pins make
// that regression impossible to miss.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/settings.dart';
import 'package:gabbro/vault_registry.dart';

/// The user's REAL config/data locations, resolved from the environment the
/// same way production does when no sandbox is set. Test-only observation —
/// nothing here may ever write them.
String? _realHome() => Platform.environment['HOME'];

/// Byte snapshot of a file, or null when absent.
List<int>? _bytes(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

/// name -> mtime for every file directly in [dir]; empty when absent.
Map<String, DateTime> _dirState(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return {};
  return {
    for (final f in d.listSync().whereType<File>())
      f.path: f.statSync().modified,
  };
}

void main() {
  testWidgets('sandbox root is set while a test body runs', (tester) async {
    expect(GabbroPaths.sandboxRoot, isNotNull,
        reason: 'a null root sends every config/data write to the real HOME');
  });

  testWidgets('sandbox root survives runAsync (real-async escape)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(GabbroPaths.sandboxRoot, isNotNull,
          reason: 'production saves driven via runAsync must stay sandboxed');
    });
  });

  testWidgets('config and data dirs resolve under the sandbox', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = GabbroPaths.sandboxRoot!;
      expect(await GabbroPaths.configDir(), startsWith(root));
      expect(await GabbroPaths.dataDir(), startsWith(root));
    });
  });

  // The canary: drive the two REAL production save paths (registry and
  // settings) end-to-end and prove the user's real ~/.config/gabbro and
  // ~/.local/share/app.gabbro.gabbro are byte-for-byte untouched. If the
  // sandbox ever regresses, the canary restores the bytes it captured BEFORE
  // failing — it can detect the escape without repeating the damage.
  testWidgets('production saves never touch the real config or vault dirs', (
    tester,
  ) async {
    final home = _realHome();
    if (home == null) return; // no HOME (CI container): nothing to protect
    final realRegistry = '$home/.config/gabbro/vaults.jsonc';
    final realSettings = '$home/.config/gabbro/settings.jsonc';
    final realVaultDir = '$home/.local/share/app.gabbro.gabbro';

    final registryBefore = _bytes(realRegistry);
    final settingsBefore = _bytes(realSettings);
    final vaultsBefore = _dirState(realVaultDir);

    late final String sandboxConfigDir;
    await tester.runAsync(() async {
      await VaultRegistry([
        VaultRecord(
          path: '/canary/never-a-real-vault.gabbro',
          alias: 'SandboxCanary',
          lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ]).save();
      await const AppSettings().save();
      sandboxConfigDir = await GabbroPaths.configDir();
    });

    // Restore FIRST on any mismatch, then fail: the canary must never leave
    // the user's files holding canary data.
    final registryAfter = _bytes(realRegistry);
    if (!_sameBytes(registryBefore, registryAfter)) {
      _restore(realRegistry, registryBefore);
    }
    final settingsAfter = _bytes(realSettings);
    if (!_sameBytes(settingsBefore, settingsAfter)) {
      _restore(realSettings, settingsBefore);
    }

    expect(_sameBytes(registryBefore, registryAfter), isTrue,
        reason: 'a production registry save reached the REAL vaults.jsonc — '
            'the test sandbox is broken (bytes restored)');
    expect(_sameBytes(settingsBefore, settingsAfter), isTrue,
        reason: 'a production settings save reached the REAL settings.jsonc — '
            'the test sandbox is broken (bytes restored)');
    expect(_dirState(realVaultDir), equals(vaultsBefore),
        reason: 'something under the REAL vault dir changed during the test');

    // And the saves must have actually happened — into the sandbox.
    expect(File('$sandboxConfigDir/vaults.jsonc').existsSync(), isTrue,
        reason: 'the canary save must land in the sandbox, not vanish');
  });
}

bool _sameBytes(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _restore(String path, List<int>? original) {
  if (original == null) {
    File(path).deleteSync();
  } else {
    File(path).writeAsBytesSync(original);
  }
}
