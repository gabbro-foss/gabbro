//! Process-crash safety of the vault write path.
//!
//! Spawns `crash_writer`, which rewrites a vault in a tight loop, and `SIGKILL`s
//! it at varied moments so some kills land mid-write (temp written, rename or
//! `.bak` rotation in flight). After every kill the vault on disk must still
//! parse as a complete sealed vault — never torn.
//!
//! This proves crash safety against a *process* death (app killed, OOM,
//! force-quit). A real power cut also loses the OS page cache, which a kill does
//! not; that case is covered by `write_vault`'s `fsync`-before-`rename` ordering
//! (you get a complete old-or-new vault, never a torn one), resting on the
//! kernel's atomic `rename` — the same guarantee under every save.

use rust_lib_gabbro::api::vault::save_vault;
use rust_lib_gabbro::vault::io::read_vault;
use rust_lib_gabbro::vault::serialization::VaultBody;
use std::process::Command;
use std::time::Duration;

#[test]
#[ignore = "spawns a child process; run explicitly in release (fast Argon)"]
fn vault_survives_repeated_process_kills_mid_write() {
    let dir = std::env::temp_dir().join("gabbro_crash_safety");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("crash.gabbro");
    let bak = dir.join("crash.gabbro.bak");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(&bak);

    // One real seal so there is a valid vault on disk. The writer loop below does
    // no KDF — it rewrites these sealed bytes via the real write path.
    save_vault(&VaultBody::default(), b"crash-pass", &path).expect("seal initial vault");

    let exe = env!("CARGO_BIN_EXE_crash_writer");
    for i in 0..30 {
        let mut child = Command::new(exe).arg(&path).spawn().expect("spawn writer");
        // Vary the kill moment so some land while a write is in flight.
        std::thread::sleep(Duration::from_millis(2 + (i % 9)));
        let _ = child.kill();
        let _ = child.wait();

        // Whenever the process died, the vault must still be complete.
        read_vault(&path).unwrap_or_else(|e| panic!("vault torn after kill #{i}: {e}"));
    }

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(&bak);
}
