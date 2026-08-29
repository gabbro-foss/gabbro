// The real-FFI suites run under plain `dart test` (no window needed) against
// the release cdylib; debug Argon2id blows the timeouts:
//   cd rust && cargo build --release --lib && cd ..
//   dart test integration_test/ -j 1

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
