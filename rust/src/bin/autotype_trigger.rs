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

    use rust_lib_gabbro::autotype::trigger;

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

    eprintln!("listening at {} (Ctrl-C to stop)", path.display());
    let mut count = 0u64;
    let result = trigger::serve(&path, || {
        count += 1;
        println!("triggered! ({count})");
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
