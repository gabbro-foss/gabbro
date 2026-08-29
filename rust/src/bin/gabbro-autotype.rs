//! The user-bound trigger client (ADR-017), e.g. qtile:
//!   Key([mod], "<key>", lazy.spawn("<path>/gabbro-autotype"))
//! Never opens a window; exits non-zero if Gabbro is not running.

#[cfg(target_os = "linux")]
fn main() {
    use rust_lib_gabbro::autotype::trigger;

    let path = trigger::default_socket_path();
    if let Err(e) = trigger::send(&path) {
        eprintln!("gabbro-autotype: no running Gabbro to trigger ({e}).");
        std::process::exit(1);
    }
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("gabbro-autotype is Linux-only (ADR-017).");
    std::process::exit(1);
}
