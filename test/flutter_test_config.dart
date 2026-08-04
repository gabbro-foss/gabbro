// Flutter's test framework automatically runs this file's [testExecutable] around
// EVERY test in `test/`. We use it to root all of GabbroPaths' config/data I/O in a
// throwaway temp sandbox for the whole run, so no test can ever touch the user's
// real ~/.config/gabbro (settings + registry) or vault folders - even a test that
// forgets to isolate itself. Individual tests may still point sandboxRoot at their
// own temp dir for per-test isolation, as long as they restore the previous value
// (this global one) rather than null in tearDown.

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
  // pending timer — which the framework fails on. Drop it after every test.
  // Registered here (not a `finally`) so it applies to the whole run.
  tearDown(clipboardWiper.cancelPending);
  // NEVER reset the root or delete the dir here. `testMain()` completes when
  // the tests are DECLARED, not when they have run — a `finally` that nulled
  // the root here executed before the first test body did, so the "global
  // net" protected nothing, and the first test to drive a real production
  // save wrote the user's real ~/.config/gabbro/vaults.jsonc (2026-08-01).
  // The dir sits in the system temp and is reclaimed by the OS; leaking it
  // is the price of the guarantee. Pinned by test/sandbox_net_test.dart.
  await testMain();
}
