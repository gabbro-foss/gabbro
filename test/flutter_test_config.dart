// Flutter's test framework automatically runs this file's [testExecutable] around
// EVERY test in `test/`. We use it to root all of GabbroPaths' config/data I/O in a
// throwaway temp sandbox for the whole run, so no test can ever touch the user's
// real ~/.config/gabbro (settings + registry) or vault folders - even a test that
// forgets to isolate itself. Individual tests may still point sandboxRoot at their
// own temp dir for per-test isolation, as long as they restore the previous value
// (this global one) rather than null in tearDown.

import 'dart:async';
import 'dart:io';

import 'package:gabbro/app_paths.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = await Directory.systemTemp.createTemp('gabbro_test_sandbox_');
  GabbroPaths.sandboxRoot = sandbox.path;
  try {
    await testMain();
  } finally {
    GabbroPaths.sandboxRoot = null;
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  }
}
