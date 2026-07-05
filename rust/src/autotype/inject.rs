//! X11 keystroke injection for auto-type (ADR-017), Linux-only.
//!
//! Synthesises key events with the XTEST extension. For each character it binds
//! a temporary "scratch" keycode (one with no keysyms mapped) to the target
//! keysym at every level, "presses" it, then restores the keycode -- the
//! xdotool technique. Binding at every level means no modifier state can alter
//! the produced character, so arbitrary Unicode (accented Latin, Greek,
//! Cyrillic, CJK) types uniformly regardless of the user's keyboard layout.
//! Events reach whatever window currently holds input focus.
//!
//! This is the raw injection primitive only. The ADR-017 safeguards that live
//! at a higher layer -- capturing the target window at trigger time and
//! aborting if focus moved, and the unlock-then-type flow -- are NOT here.

use std::{thread, time::Duration};

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{self, KEY_PRESS_EVENT, KEY_RELEASE_EVENT};
use x11rb::protocol::xtest;

use super::keysym::plan_string;

/// Errors from an injection attempt.
#[derive(Debug, thiserror::Error)]
pub enum InjectError {
    #[error("could not connect to the X server: {0}")]
    Connect(#[from] x11rb::errors::ConnectError),
    #[error("X11 request failed: {0}")]
    Connection(#[from] x11rb::errors::ConnectionError),
    #[error("X11 reply error: {0}")]
    Reply(#[from] x11rb::errors::ReplyError),
    #[error("the keyboard mapping reports zero levels per keycode")]
    NoKeyboardLevels,
    #[error("no unused keycode is available to remap for injection")]
    NoScratchKeycode,
}

/// Small pause between synthesised key events; some applications drop input
/// delivered faster than a human could plausibly type.
const KEY_DELAY: Duration = Duration::from_millis(12);

/// Type `text` into the currently focused window as synthesised key events.
///
/// Empty input is a no-op. The scratch keycode is always restored to its
/// unmapped state, even if injection fails partway.
pub fn type_text(text: &str) -> Result<(), InjectError> {
    let (conn, _screen) = x11rb::connect(None)?;
    type_keysyms(&conn, &plan_string(text))
}

/// Inject a prepared keysym sequence on an existing connection. Empty input is
/// a no-op. The scratch keycode is always restored, even if injection fails
/// partway. Callers that must verify window focus immediately before typing
/// should use the *same* `conn` for both, to minimise the race window.
pub fn type_keysyms(conn: &impl Connection, keysyms: &[u32]) -> Result<(), InjectError> {
    if keysyms.is_empty() {
        return Ok(());
    }
    let (scratch, per) = find_scratch_keycode(conn)?;
    let injected = inject_all(conn, scratch, per, keysyms);
    // Restore the scratch keycode to NoSymbol regardless of the outcome above.
    let restored = restore_keycode(conn, scratch, per);
    conn.flush()?;
    injected.and(restored)
}

fn inject_all(
    conn: &impl Connection,
    scratch: u8,
    per: u8,
    keysyms: &[u32],
) -> Result<(), InjectError> {
    for &ks in keysyms {
        // Same keysym at every level: modifier state cannot change the result.
        let levels = vec![ks; per as usize];
        xproto::change_keyboard_mapping(conn, 1, scratch, per, &levels)?.check()?;
        xtest::fake_input(conn, KEY_PRESS_EVENT, scratch, 0, x11rb::NONE, 0, 0, 0)?.check()?;
        xtest::fake_input(conn, KEY_RELEASE_EVENT, scratch, 0, x11rb::NONE, 0, 0, 0)?.check()?;
        thread::sleep(KEY_DELAY);
    }
    Ok(())
}

fn restore_keycode(conn: &impl Connection, scratch: u8, per: u8) -> Result<(), InjectError> {
    let empty = vec![0u32; per as usize];
    xproto::change_keyboard_mapping(conn, 1, scratch, per, &empty)?.check()?;
    Ok(())
}

/// Find a keycode whose every level is NoSymbol (0) -- safe to remap
/// temporarily -- and the mapping's levels-per-keycode.
fn find_scratch_keycode(conn: &impl Connection) -> Result<(u8, u8), InjectError> {
    let setup = conn.setup();
    let min = setup.min_keycode;
    let max = setup.max_keycode;
    let count = max - min + 1;

    let mapping = xproto::get_keyboard_mapping(conn, min, count)?.reply()?;
    let per = mapping.keysyms_per_keycode;
    if per == 0 {
        return Err(InjectError::NoKeyboardLevels);
    }

    for (i, chunk) in mapping.keysyms.chunks(per as usize).enumerate() {
        if chunk.iter().all(|&ks| ks == 0) {
            return Ok((min + i as u8, per));
        }
    }
    Err(InjectError::NoScratchKeycode)
}
