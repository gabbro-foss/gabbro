//! The auto-type fill orchestration (ADR-017), Linux-only.
//!
//! Given the window captured at trigger time, an entry id and a sequence kind:
//! read the Login's secret from the session, build the keystroke sequence,
//! ask the window manager to re-activate the target window (the picker stole
//! focus), verify focus actually landed on the target, and only then inject.
//! The secret never leaves Rust. If focus did not return to the captured
//! window, we abort rather than type it somewhere else.

use std::{thread, time::Duration};

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{ClientMessageEvent, ConnectionExt as _, EventMask, Window};
use zeroize::Zeroizing;

use crate::vault::entry::VaultEntry;
use crate::vault::session::{get_entry, is_vault_unlocked};

use super::inject;
use super::sequence::{build_sequence, SequenceKind};
use super::window::{active_window, WindowError};

/// Time allowed for the window manager to action the activate request before we
/// re-check focus. Provisional -- tune on hardware (ADR-017 3.4b).
const FOCUS_SETTLE: Duration = Duration::from_millis(40);

/// Errors from a fill attempt.
#[derive(Debug, thiserror::Error)]
pub enum FillError {
    #[error("vault is locked")]
    Locked,
    #[error("entry is not a login")]
    NotLogin,
    #[error("session error: {0}")]
    Session(String),
    #[error("focus did not return to the target window; aborted before typing")]
    FocusMoved,
    #[error("could not connect to the X server: {0}")]
    Connect(#[from] x11rb::errors::ConnectError),
    #[error("X11 request failed: {0}")]
    Connection(#[from] x11rb::errors::ConnectionError),
    #[error("X11 reply error: {0}")]
    Reply(#[from] x11rb::errors::ReplyError),
    #[error(transparent)]
    Window(#[from] WindowError),
    #[error(transparent)]
    Inject(#[from] inject::InjectError),
}

/// Whether the currently active window is the one we captured -- the
/// wrong-window safeguard. `None` (no active window) never matches, so we never
/// type a secret into nothing.
pub fn focus_matches(active: Option<Window>, target: Window) -> bool {
    active == Some(target)
}

/// Fill `entry_id` into `window_id` using `kind`. See module docs.
pub fn fill(window_id: Window, entry_id: &str, kind: SequenceKind) -> Result<(), FillError> {
    if !is_vault_unlocked() {
        return Err(FillError::Locked);
    }

    // Read the secret from the in-memory session; it never crosses the bridge.
    // `entry` is a clone that zeroizes on drop (LoginEntry: ZeroizeOnDrop); we
    // borrow its fields (no extra copies) and scrub the built keysym list, which
    // also carries the secret, via Zeroizing.
    let entry = get_entry(entry_id).map_err(FillError::Session)?;
    let seq = match &entry {
        VaultEntry::Login(e) => Zeroizing::new(build_sequence(&e.username, &e.password, kind)),
        _ => return Err(FillError::NotLogin),
    };

    let (conn, screen) = x11rb::connect(None)?;
    let root = conn.setup().roots[screen].root;

    request_activate(&conn, root, window_id)?;
    conn.flush()?;
    thread::sleep(FOCUS_SETTLE);

    if !focus_matches(active_window(&conn, root)?, window_id) {
        return Err(FillError::FocusMoved);
    }

    inject::type_keysyms(&conn, seq.as_slice())?;
    Ok(())
}

/// Ask the window manager (EWMH) to activate `target`. Source indication 2
/// ("pager"/direct user action) tells the WM to honour it over focus-stealing
/// prevention; qtile and other EWMH WMs respect this.
fn request_activate(conn: &impl Connection, root: Window, target: Window) -> Result<(), FillError> {
    let atom = conn.intern_atom(true, b"_NET_ACTIVE_WINDOW")?.reply()?.atom;
    if atom == x11rb::NONE {
        // No EWMH support: nothing to ask; leave focus as-is (verify will catch).
        return Ok(());
    }
    let event = ClientMessageEvent::new(32, target, atom, [2u32, 0, 0, 0, 0]);
    conn.send_event(
        false,
        root,
        EventMask::SUBSTRUCTURE_REDIRECT | EventMask::SUBSTRUCTURE_NOTIFY,
        event,
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn active_equals_target_matches() {
        assert!(focus_matches(Some(0x1a0_000f), 0x1a0_000f));
    }

    #[test]
    fn active_differs_does_not_match() {
        assert!(!focus_matches(Some(0xabc), 0xdef));
    }

    #[test]
    fn no_active_window_does_not_match() {
        assert!(!focus_matches(None, 0x1a0_000f));
    }
}
