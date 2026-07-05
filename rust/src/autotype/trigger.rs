//! Single-instance trigger IPC for auto-type (ADR-017), Linux-only.
//!
//! The running Gabbro listens on a unix-domain socket; the user-bound
//! `gabbro --autotype` command (wired in a later phase) connects and sends a
//! fixed token, which tells the running instance to capture the active window
//! and show the picker. There is no key grab -- the user binds the command in
//! their window manager. Plain sockets, so this whole module is host-testable
//! with no X server involved.

use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};

/// Errors from the trigger IPC.
#[derive(Debug, thiserror::Error)]
pub enum TriggerError {
    #[error("trigger socket I/O failed: {0}")]
    Io(#[from] std::io::Error),
}

/// The exact token a trigger client sends; a connection carrying anything else
/// is ignored, so a stray connection can't fire a fill. Exposed via
/// [`trigger_token`] so the Dart listener matches it without duplicating the
/// literal.
const TRIGGER_TOKEN: &str = "gabbro-autotype-trigger";

/// The trigger token the client sends and any listener must match.
pub fn trigger_token() -> &'static str {
    TRIGGER_TOKEN
}

/// The socket path: `<XDG_RUNTIME_DIR>/gabbro/autotype.sock` when the runtime
/// dir is known, otherwise under `fallback_dir` (e.g. the temp dir).
pub fn socket_path(xdg_runtime_dir: Option<&Path>, fallback_dir: &Path) -> PathBuf {
    let base = xdg_runtime_dir.unwrap_or(fallback_dir);
    base.join("gabbro").join("autotype.sock")
}

/// The socket path resolved from the environment (`XDG_RUNTIME_DIR`, falling
/// back to the temp dir).
pub fn default_socket_path() -> PathBuf {
    let xdg = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from);
    socket_path(xdg.as_deref(), &std::env::temp_dir())
}

/// Bind the listener, clearing any stale socket file first and creating the
/// parent directory as needed.
pub fn bind(path: &Path) -> Result<UnixListener, TriggerError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // A leftover socket file from a previous run would make bind fail with
    // "address already in use"; remove it (ignore "not found").
    match std::fs::remove_file(path) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.into()),
    }
    Ok(UnixListener::bind(path)?)
}

/// Send a trigger to a listening instance. Errors (e.g. connection refused)
/// mean no instance is running -- the signal `gabbro --autotype` uses to report
/// that Gabbro isn't open.
pub fn send(path: &Path) -> Result<(), TriggerError> {
    let mut stream = UnixStream::connect(path)?;
    stream.write_all(TRIGGER_TOKEN.as_bytes())?;
    stream.flush()?;
    Ok(())
}

/// Accept connections forever, invoking `on_trigger` for each valid trigger.
/// A connection carrying anything other than the token is ignored; a single
/// bad or errored connection never stops the loop.
pub fn serve<F: FnMut()>(path: &Path, mut on_trigger: F) -> Result<(), TriggerError> {
    let listener = bind(path)?;
    loop {
        match accept_one(&listener) {
            Ok(true) => on_trigger(),
            Ok(false) => {}
            Err(_) => {} // one bad connection must not kill the listener
        }
    }
}

/// Accept one connection and report whether it carried the trigger token.
fn accept_one(listener: &UnixListener) -> Result<bool, TriggerError> {
    let (mut stream, _addr) = listener.accept()?;
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf)?;
    Ok(buf == TRIGGER_TOKEN.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::os::unix::net::UnixStream;
    use std::thread;

    // A unique socket path per test (distinct name + pid), so parallel tests
    // never collide and stale files from a prior run are harmless (bind clears
    // them).
    fn unique_sock(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("gabbro-2b-{}-{}.sock", name, std::process::id()))
    }

    #[test]
    fn socket_path_uses_runtime_dir_when_present() {
        assert_eq!(
            socket_path(Some(Path::new("/run/user/1000")), Path::new("/tmp")),
            PathBuf::from("/run/user/1000/gabbro/autotype.sock"),
        );
    }

    #[test]
    fn socket_path_falls_back_when_runtime_dir_absent() {
        assert_eq!(
            socket_path(None, Path::new("/tmp")),
            PathBuf::from("/tmp/gabbro/autotype.sock"),
        );
    }

    #[test]
    fn send_is_received_once() {
        let path = unique_sock("once");
        let listener = bind(&path).unwrap();
        let p = path.clone();
        let sender = thread::spawn(move || send(&p).unwrap());
        let got = accept_one(&listener).unwrap();
        sender.join().unwrap();
        assert!(got);
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn two_sends_are_both_received() {
        let path = unique_sock("twice");
        let listener = bind(&path).unwrap();
        let p = path.clone();
        let sender = thread::spawn(move || {
            send(&p).unwrap();
            send(&p).unwrap();
        });
        let first = accept_one(&listener).unwrap();
        let second = accept_one(&listener).unwrap();
        sender.join().unwrap();
        assert!(first && second);
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn send_without_listener_errors() {
        let path = unique_sock("nolistener");
        std::fs::remove_file(&path).ok();
        assert!(send(&path).is_err());
    }

    #[test]
    fn wrong_bytes_are_not_a_trigger() {
        let path = unique_sock("wrong");
        let listener = bind(&path).unwrap();
        let p = path.clone();
        let sender = thread::spawn(move || {
            let mut stream = UnixStream::connect(&p).unwrap();
            stream.write_all(b"garbage").unwrap();
        });
        let got = accept_one(&listener).unwrap();
        sender.join().unwrap();
        assert!(!got);
        std::fs::remove_file(&path).ok();
    }
}
