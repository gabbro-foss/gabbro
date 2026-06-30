//! Crash-safety test helper — NOT shipped logic.
//!
//! Reads a vault once, then rewrites it through the real `write_vault` path in a
//! tight loop (no KDF: it re-writes the already-sealed bytes). The crash-safety
//! integration test (`tests/crash_safety.rs`) spawns this, `SIGKILL`s it at
//! varied moments, and confirms the vault on disk is never left torn.

use rust_lib_gabbro::vault::io::{read_vault, write_vault};
use std::path::PathBuf;

fn main() {
    let path = PathBuf::from(
        std::env::args()
            .nth(1)
            .expect("usage: crash_writer <vault-path>"),
    );
    let sealed = read_vault(&path).expect("read initial vault");
    loop {
        write_vault(&sealed, &path).expect("write vault");
    }
}
