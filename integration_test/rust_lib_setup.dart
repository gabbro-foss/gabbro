// Shared setup for the real-FFI suites.
//
// These suites run under plain `dart test` (no Flutter, no window, no GL).
// They load the compiled Rust cdylib directly, so every bridge call goes
// through real FFI -> crypto -> disk, exactly as it does in the app.
//
// The library must be built in release first:
//   cd rust && cargo build --release --lib
// Release matters: debug Argon2id is slow enough to blow the test timeouts.

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:gabbro/src/rust/frb_generated.dart';

/// Repo-relative path to the release cdylib, resolved from the current
/// directory (`dart test` runs from the package root).
const soPath = 'rust/target/release/librust_lib_gabbro.so';

/// Load the real Rust library into this isolate. Safe to call once per suite.
Future<void> initRustLib() async {
  final so = File(soPath);
  if (!so.existsSync()) {
    throw StateError(
      'Rust library not found at $soPath - build it first:\n'
      '  cd rust && cargo build --release --lib',
    );
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(so.absolute.path));
}
