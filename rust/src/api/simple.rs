#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // R-04: harden the process before any secret can reach memory — disables
    // core dumps and ptrace/mem snooping on Linux. A failure here is logged,
    // not fatal: refusing to launch over an unexpected syscall failure is worse
    // than the residual risk. No-op on non-Linux targets.
    if let Err(e) = crate::hardening::harden_process() {
        eprintln!("warning: process hardening failed: {e}");
    }

    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
