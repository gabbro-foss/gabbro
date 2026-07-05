//! `gabbro-autotype` (ADR-017): the user-bound trigger client.
//!
//! Bind it to a key in your window manager / desktop shortcuts, e.g. qtile:
//!   Key([mod], "<key>", lazy.spawn("<path>/gabbro-autotype"))
//!
//! It connects to the running Gabbro's socket, sends the trigger, and exits.
//! It never opens a window. If Gabbro isn't running it prints a message and
//! exits non-zero.

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
