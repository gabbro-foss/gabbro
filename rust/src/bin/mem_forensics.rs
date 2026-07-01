//! Memory-forensics self-test harness (audit L-6 / Appendix C item 6).
//!
//! Validates empirically that the master passphrase is scrubbed from process
//! memory when a vault is locked — i.e. that `VaultSession`'s `Zeroizing` fields
//! and `lock_vault()` actually work against a real core dump, not just in theory.
//!
//! NOT part of normal builds. Build and run via the driver script:
//!
//! ```text
//! cargo build --release --features forensics --bin mem_forensics
//! scripts/mem_forensics.sh
//! ```
//!
//! The driver uses two distinct high-entropy **canaries**: one as the vault
//! passphrase (validates `Zeroizing` + `lock_vault`), one as a Login entry's
//! password (validates `ZeroizeOnDrop` on `VaultEntry` via `entries.clear()`).
//! The passphrase canary is never written to disk; the entry canary lives only
//! inside the encrypted vault and, once unlocked, the in-memory session — so
//! neither has disk/argv false positives. Canaries reach the harness via
//! **stdin** (never argv) so they cannot leak through `/proc/<pid>/cmdline`.
//!
//! Subcommands:
//!   create <path>   seal a passphrase vault (line 1) containing one Login entry
//!                   whose password is the entry canary (line 2), then exit —
//!                   this process's plaintext dies with it, polluting nothing.
//!   test   <path>   unlock (passphrase canary on stdin) → print "UNLOCKED <pid>"
//!                   → wait → lock → print "LOCKED" → wait → exit. The driver runs
//!                   `gcore` at each wait and greps the dumps for both canaries.

use rust_lib_gabbro::api::vault::LoginEntryData;
use rust_lib_gabbro::api::vault_bridge::VaultEntryData;
use std::io::{BufRead, Write};
use std::path::PathBuf;

/// `prctl(2)` option: nominate which process may `ptrace` us. Passing
/// `PR_SET_PTRACER_ANY` (-1) lets an unrelated `gcore` attach even under
/// `yama` `ptrace_scope=1`, so the self-test needs no sudo.
const PR_SET_PTRACER: libc::c_int = 0x59616d61;

fn main() {
    let mut args = std::env::args().skip(1);
    let cmd = args.next().unwrap_or_default();

    match cmd.as_str() {
        "create" => {
            let path = args.next().expect("usage: mem_forensics create <path>");
            let pass_canary = read_canary_from_stdin(); // stdin line 1 = passphrase
            let entry_canary = read_canary_from_stdin(); // stdin line 2 = entry password
            block_on(rust_lib_gabbro::api::vault_bridge::init_vault(
                pass_canary.to_vec(),
                path,
                Some("forensics-self-test".to_string()),
            ))
            .expect("init_vault failed");
            // Add a Login entry whose password is the (distinct) entry canary, then
            // persist. This exercises the entries `ZeroizeOnDrop` path on
            // `VaultEntry`, which is separate from the passphrase's `Zeroizing`.
            // init_vault left this process's session unlocked.
            let login = VaultEntryData::Login(LoginEntryData {
                id: String::new(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
                title: "forensics-canary".to_string(),
                url: String::new(),
                username: String::new(),
                password: String::from_utf8_lossy(&entry_canary).into_owned(),
                notes: None,
                custom_fields: Vec::new(),
                app_id: None,
                email: None,
            });
            block_on(rust_lib_gabbro::api::vault_bridge::create_entry(login))
                .expect("create_entry failed");
            // The OS reclaims this process's memory on exit; lock for tidiness.
            let _ = rust_lib_gabbro::vault::session::lock_vault();
        }

        "test" => {
            let path = PathBuf::from(args.next().expect("usage: mem_forensics test <path>"));

            // Allow any same-uid process (the driver's gcore) to ptrace us,
            // despite yama ptrace_scope=1 — no sudo required.
            unsafe {
                libc::prctl(PR_SET_PTRACER, -1i64 as libc::c_ulong, 0, 0, 0);
            }

            let canary = read_canary_from_stdin();
            rust_lib_gabbro::vault::session::unlock_vault(&canary, path).expect("unlock failed");
            // Drop our local copy now (Zeroizing → zeroized on drop). From here the
            // canary should live ONLY inside the global VaultSession — the thing
            // under test.
            drop(canary);

            announce(&format!("UNLOCKED {}", std::process::id()));
            wait_for_driver(); // gcore #1 (expect canary FOUND)

            rust_lib_gabbro::vault::session::lock_vault().expect("lock failed");
            announce("LOCKED");
            wait_for_driver(); // gcore #2 (expect canary ABSENT)

            announce("EXIT");
        }

        other => {
            eprintln!("mem_forensics: unknown subcommand {other:?} (expected create|test)");
            std::process::exit(2);
        }
    }
}

/// Reads the first stdin line as the canary, trimming the newline, into a
/// zeroizing buffer pre-sized so `read_until` does not reallocate (which could
/// leave a stray plaintext copy behind).
fn read_canary_from_stdin() -> zeroize::Zeroizing<Vec<u8>> {
    let mut buf: Vec<u8> = Vec::with_capacity(512);
    std::io::stdin()
        .lock()
        .read_until(b'\n', &mut buf)
        .expect("read canary from stdin");
    while matches!(buf.last(), Some(b'\n') | Some(b'\r')) {
        buf.pop();
    }
    zeroize::Zeroizing::new(buf)
}

/// Prints a protocol line to stdout and flushes so the driver sees it promptly.
fn announce(msg: &str) {
    let mut out = std::io::stdout();
    writeln!(out, "{msg}").expect("write stdout");
    out.flush().expect("flush stdout");
}

/// Blocks until the driver writes a line to stdin (its "proceed" signal, sent
/// after it has finished a `gcore` dump).
fn wait_for_driver() {
    let mut s = String::new();
    std::io::stdin().read_line(&mut s).ok();
}

/// Minimal executor for the one immediately-ready future we need (`init_vault`
/// performs synchronous std file I/O, so it never parks). Avoids pulling a full
/// async runtime into the harness.
fn block_on<F: std::future::Future>(fut: F) -> F::Output {
    use std::pin::pin;
    use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};
    const VTABLE: RawWakerVTable = RawWakerVTable::new(
        |_| RawWaker::new(std::ptr::null(), &VTABLE),
        |_| {},
        |_| {},
        |_| {},
    );
    let waker = unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) };
    let mut cx = Context::from_waker(&waker);
    let mut fut = pin!(fut);
    loop {
        match fut.as_mut().poll(&mut cx) {
            Poll::Ready(v) => return v,
            Poll::Pending => std::thread::yield_now(),
        }
    }
}
