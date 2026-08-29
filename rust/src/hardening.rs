//! R-04. Two routes out of RAM for an unlocked vault's secrets are closed:
//! `RLIMIT_CORE = 0` so a crash never writes a core dump, and
//! `PR_SET_DUMPABLE(0)` so a same-uid process cannot `ptrace` or read
//! `/proc/<pid>/mem`. Wired into the frb `init_app()` hook so every Dart
//! entrypoint runs it before any secret exists. No-op off Linux (Android
//! processes are already non-dumpable).

#[cfg(target_os = "linux")]
pub fn harden_process() -> Result<(), String> {
    // SAFETY: PR_SET_DUMPABLE takes an integer arg (0), no pointers.
    let rc = unsafe { libc::prctl(libc::PR_SET_DUMPABLE, 0 as libc::c_ulong) };
    if rc != 0 {
        return Err(format!(
            "prctl(PR_SET_DUMPABLE, 0) failed: {}",
            std::io::Error::last_os_error()
        ));
    }

    // Hard limit 0 too, so it cannot be raised again.
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

#[cfg(not(target_os = "linux"))]
pub fn harden_process() -> Result<(), String> {
    Ok(())
}

/// A non-dumpable process has `/proc/<pid>/{root,cwd,exe}` gated behind
/// ptrace, and `xdg-desktop-portal` reads those to service a FileChooser, so
/// the native file dialog fails as "portal unreachable". The picker raises the
/// flag only while a dialog is open; yama `ptrace_scope >= 1` still blocks
/// non-ancestor tracers in that window, and `RLIMIT_CORE` stays 0 throughout.
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

    /// True when the caller is (effectively) root. A privileged caller holds
    /// `CAP_SYS_PTRACE` and so bypasses the dumpable-based `/proc/<pid>` access
    /// gate the kernel enforces only against unprivileged same-uid peers. The
    /// offline release gate runs the Rust leg under `unshare -r` (caller uid
    /// mapped to 0 to obtain a network namespace), so this is true there.
    fn caller_is_privileged() -> bool {
        // SAFETY: geteuid takes no arguments and cannot fail.
        let euid = unsafe { libc::geteuid() };
        euid == 0
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
        assert_eq!(
            lim.rlim_cur, 0,
            "core rlimit soft must stay 0 while dumpable"
        );
        assert_eq!(
            lim.rlim_max, 0,
            "core rlimit hard must stay 0 while dumpable"
        );
        set_process_dumpable(false).expect("restore failed");
    }

    /// Fork a child that sets its own dumpable flag to `child_dumpable`, signal
    /// readiness over a pipe, then probe whether this (same-uid, parent) process
    /// can dereference the child's `/proc/<pid>/root` - the exact access
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
        // CAP_SYS_PTRACE bypasses the dumpable gate, so the negative half
        // would fail spuriously under the offline gate's `unshare -r`.
        if caller_is_privileged() {
            eprintln!(
                "skipping the non-dumpable denial assertion: caller is root \
                 (CAP_SYS_PTRACE bypasses the /proc dumpable gate)"
            );
        } else {
            assert!(
                !child_proc_root_accessible(false),
                "a non-dumpable process must NOT be same-uid /proc/<pid>/root \
                 accessible (this is exactly why the XDG portal fails while hardened)"
            );
        }
        assert!(
            child_proc_root_accessible(true),
            "a dumpable process must be same-uid /proc/<pid>/root accessible so \
             xdg-desktop-portal can service a FileChooser request"
        );
    }
}
