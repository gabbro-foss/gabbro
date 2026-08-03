//! The auto-type fill orchestration (ADR-017), Linux-only.
//!
//! Given the window captured at trigger time and an entry id: read the Login's
//! secret from the session, build the `username` Tab `password` Return keystroke
//! sequence, re-assert focus on the captured window and verify it actually holds
//! focus, and only then inject. The secret never leaves Rust. If focus is not on
//! the captured window, we abort rather than type it somewhere else.

use std::{thread, time::Duration};

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{ClientMessageEvent, ConnectionExt as _, EventMask, Window};
use zeroize::Zeroizing;

use crate::vault::entry::VaultEntry;
use crate::vault::session::{get_entry, is_vault_unlocked};

use super::inject;
use super::sequence::build_sequence;
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
    // Rendered via `redact_reply` so the value the server objected to never
    // reaches stdout -- it can come from the password (see that fn).
    #[error("{}", super::redact_reply(.0))]
    Reply(#[from] x11rb::errors::ReplyError),
    #[error(transparent)]
    Window(#[from] WindowError),
    #[error(transparent)]
    Inject(#[from] inject::InjectError),
}

/// The identifier to type into the login field: the `username` if it has one,
/// otherwise the `email` (which many sites accept as the login). Empty when
/// neither is set, so the sequence types nothing before Tab. Mirrors how web
/// autofill treats a login's email as an alternate identifier.
fn login_identifier<'a>(username: &'a str, email: Option<&'a str>) -> &'a str {
    if !username.is_empty() {
        username
    } else {
        email.unwrap_or_default()
    }
}

/// Whether the currently active window is the one we captured -- the
/// wrong-window safeguard. `None` (no active window) never matches, so we never
/// type a secret into nothing.
pub fn focus_matches(active: Option<Window>, target: Window) -> bool {
    active == Some(target)
}

/// Fill `entry_id` into `window_id`. See module docs.
pub fn fill(window_id: Window, entry_id: &str) -> Result<(), FillError> {
    if !is_vault_unlocked() {
        return Err(FillError::Locked);
    }

    // Read the secret from the in-memory session; it never crosses the bridge.
    // `entry` is a clone that zeroizes on drop (LoginEntry: ZeroizeOnDrop); we
    // borrow its fields (no extra copies) and scrub the built keysym list, which
    // also carries the secret, via Zeroizing.
    let entry = get_entry(entry_id).map_err(FillError::Session)?;
    let seq = match &entry {
        VaultEntry::Login(e) => {
            let user = login_identifier(&e.username, e.email.as_deref());
            Zeroizing::new(build_sequence(user, &e.password))
        }
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

    #[test]
    fn identifier_prefers_a_non_empty_username() {
        assert_eq!(login_identifier("alice", Some("a@example.com")), "alice");
    }

    #[test]
    fn identifier_falls_back_to_email_when_username_empty() {
        assert_eq!(login_identifier("", Some("a@example.com")), "a@example.com");
    }

    #[test]
    fn identifier_is_empty_when_username_empty_and_no_email() {
        assert_eq!(login_identifier("", None), "");
    }

    #[test]
    fn identifier_is_empty_when_username_and_email_both_empty() {
        assert_eq!(login_identifier("", Some("")), "");
    }

    // ── No fill error may carry secret material to stdout ────────────────────
    // `lib/main.dart` debugPrints this text, in release builds too, so every
    // variant's rendering is pinned here.

    #[test]
    fn locked_renders_fixed_text() {
        assert_eq!(FillError::Locked.to_string(), "vault is locked");
    }

    #[test]
    fn not_login_renders_fixed_text() {
        assert_eq!(FillError::NotLogin.to_string(), "entry is not a login");
    }

    #[test]
    fn focus_moved_renders_fixed_text() {
        assert_eq!(
            FillError::FocusMoved.to_string(),
            "focus did not return to the target window; aborted before typing",
        );
    }

    #[test]
    fn session_carries_only_the_entry_id() {
        let id = "3f2b1c7e-0a4d-4c8f-9b21-5e6d7a8c9f01";
        let rendered = FillError::Session(format!("No entry found with id: {id}")).to_string();
        assert_eq!(
            rendered,
            format!("session error: No entry found with id: {id}")
        );
    }

    /// What a rendered [`FillError`] can expose, worst case. Every variant must
    /// be classified: adding one without a classification fails to compile,
    /// which is the point -- the text reaches a terminal.
    #[derive(Debug, PartialEq)]
    enum Exposure {
        /// Fixed text only.
        Fixed,
        /// The entry UUID -- an internal identifier, never secret material.
        EntryId,
        /// X11 transport text (connect/parse/IO), no Gabbro data.
        X11Transport,
        /// A server-rejected request, redacted to kind + request name.
        X11Rejection,
    }

    fn exposure(e: &FillError) -> Exposure {
        match e {
            FillError::Locked | FillError::NotLogin | FillError::FocusMoved => Exposure::Fixed,
            FillError::Session(_) => Exposure::EntryId,
            FillError::Connect(_) | FillError::Connection(_) => Exposure::X11Transport,
            FillError::Reply(_) => Exposure::X11Rejection,
            FillError::Window(_) => Exposure::X11Rejection,
            FillError::Inject(_) => Exposure::X11Rejection,
        }
    }

    /// A server rejection of `ChangeKeyboardMapping` -- the one checked request
    /// whose payload is derived from the password (`inject.rs`) -- objecting to
    /// `bad_value`.
    fn rejected(bad_value: u32) -> x11rb::errors::ReplyError {
        x11rb::errors::ReplyError::X11Error(x11rb::x11_utils::X11Error {
            error_kind: x11rb::protocol::ErrorKind::Value,
            error_code: 2,
            sequence: 42,
            bad_value,
            minor_opcode: 0,
            major_opcode: 100,
            extension_name: None,
            request_name: Some("ChangeKeyboardMapping"),
        })
    }

    /// 0x79 is the keysym for `y`. x11rb's own Display Debug-prints the whole
    /// `X11Error`, so the value the server objected to would reach stdout --
    /// and for this request that value came from the password.
    fn assert_redacted(rendered: &str) {
        assert!(
            !rendered.contains("121"),
            "rendered the rejected value: {rendered}"
        );
        assert!(
            rendered.contains("Value"),
            "lost the error kind: {rendered}"
        );
        assert!(
            rendered.contains("ChangeKeyboardMapping"),
            "lost the request name: {rendered}",
        );
    }

    #[test]
    fn a_rejected_request_never_renders_the_rejected_value() {
        assert_redacted(&FillError::Reply(rejected(0x79)).to_string());
    }

    #[test]
    fn a_rejection_through_the_window_layer_is_redacted_too() {
        assert_redacted(&FillError::Window(WindowError::Reply(rejected(0x79))).to_string());
    }

    #[test]
    fn a_rejection_through_the_inject_layer_is_redacted_too() {
        assert_redacted(&FillError::Inject(inject::InjectError::Reply(rejected(0x79))).to_string());
    }

    #[test]
    fn every_constructible_variant_is_classified() {
        assert_eq!(exposure(&FillError::Locked), Exposure::Fixed);
        assert_eq!(exposure(&FillError::NotLogin), Exposure::Fixed);
        assert_eq!(exposure(&FillError::FocusMoved), Exposure::Fixed);
        assert_eq!(
            exposure(&FillError::Session(String::new())),
            Exposure::EntryId
        );
    }
}
