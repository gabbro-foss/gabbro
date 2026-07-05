//! Diagnostic for ADR-017 Phase 2b: the single-instance trigger IPC.
//!
//! Two terminals:
//!   cargo run --bin autotype_trigger            # listen; prints "triggered!" per hit
//!   cargo run --bin autotype_trigger -- --send  # send one trigger to the listener
//!
//! The unit tests already prove the round-trip deterministically; this is just
//! a manual sanity check.

#[cfg(target_os = "linux")]
fn main() {
    use std::env;

    use x11rb::connection::Connection;

    use rust_lib_gabbro::autotype::{trigger, window};

    let path = trigger::default_socket_path();

    if env::args().any(|a| a == "--send") {
        match trigger::send(&path) {
            Ok(()) => eprintln!("sent trigger to {}", path.display()),
            Err(e) => {
                eprintln!("send failed ({e}) -- is a listener running?");
                std::process::exit(1);
            }
        }
        return;
    }

    // Listen mode: on each trigger, capture the window that was focused at that
    // instant (the whole point of the Rust-side listener) and print it.
    let (conn, screen_num) = match x11rb::connect(None) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("could not connect to the X server: {e}");
            std::process::exit(1);
        }
    };
    let root = conn.setup().roots[screen_num].root;

    eprintln!("listening at {} (Ctrl-C to stop)", path.display());
    let mut count = 0u64;
    let result = trigger::serve(&path, || {
        count += 1;
        match window::capture_active(&conn, root) {
            Ok(Some(w)) => println!(
                "triggered ({count}): active=0x{:08x} class={:?} title={:?}",
                w.id, w.class, w.title
            ),
            Ok(None) => println!("triggered ({count}): active=<none>"),
            Err(e) => println!("triggered ({count}): capture error: {e}"),
        }
    });
    if let Err(e) = result {
        eprintln!("listener failed: {e}");
        std::process::exit(1);
    }
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("autotype_trigger is Linux-only (ADR-017).");
    std::process::exit(1);
}
