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

/// Raise (`true`) or lower (`false`) the process `PR_SET_DUMPABLE` flag.
///
/// The Linux picker layer raises it only while a native file dialog is open so
/// `xdg-desktop-portal` can read `/proc/<pid>` to service the request, then
/// lowers it again. No-op on non-Linux targets. See
/// `crate::hardening::set_process_dumpable`.
pub fn set_process_dumpable(dumpable: bool) -> Result<(), String> {
    crate::hardening::set_process_dumpable(dumpable)
}
