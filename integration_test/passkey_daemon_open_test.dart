// Red-first for the daemon-failure status (F2, Current Focus item 5).
//
// `passkeyDaemonOpen()` must surface a device/lock failure as a catchable
// Dart error. The old shape (one stream fn doing flock + open + pump) lost
// its Err on an unawaited FRB future, so the app could never learn why the
// passkey provider was inactive and the vault-list banner stayed dead.
//
// Real seam: the compiled cdylib, the real flock path, an outside flock(1)
// holding the lock exactly as a second Gabbro instance would.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:gabbro/src/rust/api/passkey_daemon_bridge.dart';

import 'rust_lib_setup.dart';

void main() {
  setUpAll(initRustLib);

  test('a held instance lock makes passkeyDaemonOpen throw a catchable error',
      () async {
    // Same resolution order as Rust's take_instance_lock().
    final runtimeDir =
        Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path;
    final lockPath = '$runtimeDir/gabbro-passkey.lock';

    // Hold the exclusive flock from an outside process; "locked" on stdout
    // confirms it is taken before the bridge call runs.
    final holder = await Process.start(
      'flock',
      ['-x', lockPath, '-c', 'echo locked && sleep 30'],
    );
    await holder.stdout
        .transform(utf8.decoder)
        .firstWhere((chunk) => chunk.contains('locked'))
        .timeout(const Duration(seconds: 5));

    try {
      await expectLater(
        passkeyDaemonOpen(),
        throwsA(
          predicate(
            (e) => '$e'.contains('instance'),
            'names the second-instance cause',
          ),
        ),
      );
    } finally {
      holder.kill();
      await holder.exitCode;
    }
  });
}
