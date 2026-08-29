// Runs around every test in `test/`: roots all GabbroPaths I/O in a temp
// sandbox so even a test that forgets to isolate itself cannot reach the
// user's real settings or vaults. Tests that override sandboxRoot must
// restore this value, never null.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gabbro/app_paths.dart';
import 'package:gabbro/clipboard_clear.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = await Directory.systemTemp.createTemp('gabbro_test_sandbox_');
  GabbroPaths.sandboxRoot = sandbox.path;
  // The clipboard wipe deliberately outlives the screen that scheduled it
  // (RT-4), so any test that copies a secret without advancing time ends with a
  // pending timer - which the framework fails on. Drop it after every test.
  // Registered here (not a `finally`) so it applies to the whole run.
  tearDown(clipboardWiper.cancelPending);
  // Never reset the root or delete the dir here: `testMain()` returns when
  // the tests are declared, not run, so a teardown would fire before the
  // first body and a production save would hit the real registry. The OS
  // reclaims the temp dir. Pinned by test/sandbox_net_test.dart.
  await testMain();
}
