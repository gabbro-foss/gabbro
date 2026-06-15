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

/// Raise or lower the process `PR_SET_DUMPABLE` flag.
///
/// `harden_process` clears it (0) so a same-uid process cannot `ptrace` us or
/// read `/proc/<pid>/mem`. That same flag, however, makes the kernel reassign
/// `/proc/<pid>/{root,cwd,exe}` to a `ptrace`-gated state: a same-uid peer
/// without `CAP_SYS_PTRACE` gets `EACCES` reading them. `xdg-desktop-portal`
/// reads exactly those entries to build the caller's app-info when servicing a
/// FileChooser request, so a non-dumpable process cannot open a native file
/// dialog at all (it fails as "portal unreachable").
///
/// The picker layer therefore raises the flag (`true`) only for the brief,
/// user-initiated window a file dialog is open, then lowers it (`false`) again.
/// During that window the kernel's yama `ptrace_scope` (>= 1 on Debian/Mint and
/// Arch defaults) still blocks any non-ancestor same-uid tracer, so the
/// exposure is negligible. `RLIMIT_CORE` stays 0 throughout — the no-core-dump
/// guarantee is independent of this flag.
#[cfg(target_os = "linux")]
pub fn set_process_dumpable(dumpable: bool) -> Result<(), String> {
    let arg = if dumpable { 1 } else { 0 } as libc::c_ulong;
    // SAFETY: PR_SET_DUMPABLE takes an integer arg (0 or 1), no pointers.
    let rc = unsafe { libc::prctl(libc::PR_SET_DUMPABLE, arg) };
    if rc != 0 {
        return Err(format!(
            "prctl(PR_SET_DUMPABLE, {arg}) failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

/// No-op on non-Linux targets.
#[cfg(not(target_os = "linux"))]
pub fn set_process_dumpable(_dumpable: bool) -> Result<(), String> {
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

    #[test]
    #[serial]
    fn set_process_dumpable_toggles_flag() {
        set_process_dumpable(true).expect("raise failed");
        assert_eq!(current_dumpable(), 1, "flag should be raised");
        set_process_dumpable(false).expect("lower failed");
        assert_eq!(current_dumpable(), 0, "flag should be lowered");
    }

    #[test]
    #[serial]
    fn raising_dumpable_leaves_core_rlimit_zero() {
        // The no-core-dump guarantee must be independent of the picker-window
        // dumpable toggle: raising the flag for a file dialog must not reopen
        // the core-dump path.
        harden_process().expect("harden failed");
        set_process_dumpable(true).expect("raise failed");
        let lim = current_core_rlimit();
        assert_eq!(lim.rlim_cur, 0, "core rlimit soft must stay 0 while dumpable");
        assert_eq!(lim.rlim_max, 0, "core rlimit hard must stay 0 while dumpable");
        set_process_dumpable(false).expect("restore failed");
    }

    /// Fork a child that sets its own dumpable flag to `child_dumpable`, signal
    /// readiness over a pipe, then probe whether this (same-uid, parent) process
    /// can dereference the child's `/proc/<pid>/root` — the exact access
    /// `xdg-desktop-portal` performs to read a caller's app-info. Returns true
    /// iff the `read_link` succeeds.
    fn child_proc_root_accessible(child_dumpable: bool) -> bool {
        let mut fds: [libc::c_int; 2] = [0; 2];
        // SAFETY: `fds` is a valid two-int array for pipe(2).
        assert_eq!(unsafe { libc::pipe(fds.as_mut_ptr()) }, 0, "pipe failed");
        let (read_fd, write_fd) = (fds[0], fds[1]);

        // SAFETY: fork(2). The child runs only direct syscalls below (no heap
        // allocation on the success path) before pause()/_exit.
        let pid = unsafe { libc::fork() };
        assert!(pid >= 0, "fork failed");
        if pid == 0 {
            let arg = if child_dumpable { 1 } else { 0 } as libc::c_ulong;
            // SAFETY: set the flag, signal one byte, then sleep until killed.
            unsafe {
                libc::prctl(libc::PR_SET_DUMPABLE, arg);
                let byte = [0u8; 1];
                libc::write(write_fd, byte.as_ptr() as *const libc::c_void, 1);
                libc::pause();
                libc::_exit(0);
            }
        }

        // SAFETY: close our copy of the write end; block until the child's byte.
        unsafe { libc::close(write_fd) };
        let mut buf = [0u8; 1];
        // SAFETY: `buf` is a valid one-byte destination.
        let n = unsafe { libc::read(read_fd, buf.as_mut_ptr() as *mut libc::c_void, 1) };
        assert_eq!(n, 1, "child never signalled readiness");

        let accessible = std::fs::read_link(format!("/proc/{pid}/root")).is_ok();

        // SAFETY: reap the child and release the read end.
        unsafe {
            libc::kill(pid, libc::SIGKILL);
            let mut status = 0;
            libc::waitpid(pid, &mut status, 0);
            libc::close(read_fd);
        }
        accessible
    }

    // The regression guard for the v0.1.0-alpha.7 portal breakage: a hardened
    // (non-dumpable) process is NOT reachable by a same-uid peer at
    // /proc/<pid>/root, which is exactly why xdg-desktop-portal could not open
    // a file dialog. Raising the flag restores that access.
    #[test]
    #[serial]
    fn proc_root_access_tracks_dumpable_flag() {
        assert!(
            !child_proc_root_accessible(false),
            "a non-dumpable process must NOT be same-uid /proc/<pid>/root \
             accessible (this is exactly why the XDG portal fails while hardened)"
        );
        assert!(
            child_proc_root_accessible(true),
            "a dumpable process must be same-uid /proc/<pid>/root accessible so \
             xdg-desktop-portal can service a FileChooser request"
        );
    }
}
