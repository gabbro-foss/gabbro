//! Rewrites an already-sealed vault through `write_vault` in a tight loop (no
//! KDF) for `tests/crash_safety.rs` to `SIGKILL`. Not shipped.

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
