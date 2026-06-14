//! Process hardening (R-04 — Linux core-dump hardening).
//!
//! While a vault is unlocked, decrypted secrets (the master key, plaintext
//! entries) live in process RAM. Two escape routes for that material are
//! closed here:
//!   * a crash core dump would snapshot the whole address space to disk
//!     -> `RLIMIT_CORE = 0` tells the kernel never to write one;
//!   * a same-uid process could `ptrace` / read `/proc/<pid>/mem` to scrape
//!     it from the live process -> `PR_SET_DUMPABLE(0)` blocks both.
//!
//! Belt and suspenders: the two cover different escape routes.
//!
//! Linux-only syscalls; a no-op on other targets (production Android processes
//! are already non-dumpable). Must be called once, early, before any secret is
//! in memory — wired into the flutter_rust_bridge `init_app()` hook so every
//! Dart entrypoint (`main.dart`, `autofill_unlock_main.dart`) reaches it before
//! `runApp` / any unlock work.

/// Harden the current process against in-memory secret disclosure.
///
/// Returns `Ok(())` on success, and on non-Linux targets where it is a no-op.
#[cfg(target_os = "linux")]
pub fn harden_process() -> Result<(), String> {
    // Block ptrace attach and /proc/<pid>/mem reads by same-uid processes.
    // SAFETY: PR_SET_DUMPABLE takes an integer arg (0), no pointers.
    let rc = unsafe { libc::prctl(libc::PR_SET_DUMPABLE, 0 as libc::c_ulong) };
    if rc != 0 {
        return Err(format!(
            "prctl(PR_SET_DUMPABLE, 0) failed: {}",
            std::io::Error::last_os_error()
        ));
    }

    // Stop the kernel from writing a core dump of this process — both the soft
    // and hard limit to 0 so it cannot be raised again.
    let limit = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    // SAFETY: `limit` is a valid, fully-initialised rlimit passed by const ptr.
    let rc = unsafe { libc::setrlimit(libc::RLIMIT_CORE, &limit) };
    if rc != 0 {
        return Err(format!(
            "setrlimit(RLIMIT_CORE, 0) failed: {}",
            std::io::Error::last_os_error()
        ));
    }

    Ok(())
}

/// No-op on non-Linux targets (Android production processes are already
/// non-dumpable; these are Linux syscalls).
#[cfg(not(target_os = "linux"))]
pub fn harden_process() -> Result<(), String> {
    Ok(())
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use serial_test::serial;

    fn current_dumpable() -> libc::c_int {
        // SAFETY: PR_GET_DUMPABLE takes no further arguments and returns the
        // dumpable flag (0, 1 or 2) as the prctl return value.
        unsafe { libc::prctl(libc::PR_GET_DUMPABLE) }
    }

    fn current_core_rlimit() -> libc::rlimit {
        let mut lim = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        // SAFETY: `lim` is a valid, fully-initialised rlimit we hand to the
        // kernel to fill in.
        let rc = unsafe { libc::getrlimit(libc::RLIMIT_CORE, &mut lim) };
        assert_eq!(rc, 0, "getrlimit(RLIMIT_CORE) failed");
        lim
    }

    #[test]
    #[serial]
    fn harden_process_returns_ok() {
        assert!(harden_process().is_ok());
    }

    #[test]
    #[serial]
    fn harden_process_makes_process_non_dumpable() {
        harden_process().expect("harden_process failed");
        assert_eq!(
            current_dumpable(),
            0,
            "process should be non-dumpable after hardening"
        );
    }

    #[test]
    #[serial]
    fn harden_process_zeroes_core_rlimit_soft_and_hard() {
        harden_process().expect("harden_process failed");
        let lim = current_core_rlimit();
        assert_eq!(lim.rlim_cur, 0, "core rlimit soft should be 0");
        assert_eq!(lim.rlim_max, 0, "core rlimit hard should be 0");
    }

    #[test]
    #[serial]
    fn harden_process_is_idempotent() {
        harden_process().expect("first call failed");
        harden_process().expect("second call failed");
        assert_eq!(current_dumpable(), 0);
        let lim = current_core_rlimit();
        assert_eq!(lim.rlim_cur, 0);
        assert_eq!(lim.rlim_max, 0);
    }
}
