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

use std::{
    thread,
    time::{Duration, Instant},
};

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

/// Function keysyms injected via their genuine keycodes (not a remapped scratch
/// key): apps like Chromium key Tab focus-navigation and Enter submission off
/// the real hardware keycode and ignore these on a made-up keycode.
const KEYSYM_TAB: u32 = 0xff09;
const KEYSYM_RETURN: u32 = 0xff0d;

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
    // Wait for the trigger combo (e.g. Super+Ctrl) to be physically released so
    // its release events don't interleave with -- and scramble -- the injected
    // keystrokes; then clear any still logically held, so injected characters
    // aren't turned into modified shortcuts.
    wait_for_modifiers_released(conn)?;
    release_held_modifiers(conn)?;
    let injected = inject_all(conn, scratch, per, keysyms);
    // Restore the scratch keycode to NoSymbol regardless of the outcome above.
    let restored = restore_keycode(conn, scratch, per);
    conn.flush()?;
    injected.and(restored)
}

/// How long to wait for the trigger modifiers to be released before giving up
/// and injecting anyway.
const MODIFIER_WAIT_TIMEOUT: Duration = Duration::from_millis(1000);
/// Poll interval while waiting for modifiers to clear.
const MODIFIER_POLL: Duration = Duration::from_millis(10);
/// Modifier bits that matter for shortcuts: Shift|Control|Mod1(Alt)|Mod4(Super)|
/// Mod5. Deliberately excludes Lock (CapsLock) and Mod2 (NumLock) -- those are
/// toggles that are commonly *always* set, so waiting on them would hang.
const SHORTCUT_MODIFIERS: u16 = 0x00cd;

/// Whether any shortcut modifier is currently held (per a `QueryPointer` mask).
fn shortcut_modifiers_held(mask: u16) -> bool {
    mask & SHORTCUT_MODIFIERS != 0
}

/// Block until no shortcut modifier is held, or the timeout elapses (then we
/// proceed anyway and rely on [`release_held_modifiers`]).
fn wait_for_modifiers_released(conn: &impl Connection) -> Result<(), InjectError> {
    let root = conn.setup().roots[0].root;
    let start = Instant::now();
    loop {
        let mask = u16::from(xproto::query_pointer(conn, root)?.reply()?.mask);
        if !shortcut_modifiers_held(mask) || start.elapsed() >= MODIFIER_WAIT_TIMEOUT {
            return Ok(());
        }
        thread::sleep(MODIFIER_POLL);
    }
}

/// Fake-release every modifier key so keys the user is physically holding (the
/// trigger combo) don't modify the injected characters. Releasing an already-up
/// key is harmless; a toggle (Caps/Num Lock) only flips on press, so releasing
/// it does nothing.
fn release_held_modifiers(conn: &impl Connection) -> Result<(), InjectError> {
    let mapping = xproto::get_modifier_mapping(conn)?.reply()?;
    for kc in modifier_keycodes(&mapping.keycodes) {
        xtest::fake_input(conn, KEY_RELEASE_EVENT, kc, 0, x11rb::NONE, 0, 0, 0)?.check()?;
    }
    Ok(())
}

/// The distinct non-zero keycodes in a `GetModifierMapping` table (8 modifiers
/// x keycodes-per-modifier; zero entries are unused slots).
fn modifier_keycodes(keycodes: &[u8]) -> Vec<u8> {
    let mut kcs: Vec<u8> = keycodes.iter().copied().filter(|&k| k != 0).collect();
    kcs.sort_unstable();
    kcs.dedup();
    kcs
}

fn inject_all(
    conn: &impl Connection,
    scratch: u8,
    per: u8,
    keysyms: &[u32],
) -> Result<(), InjectError> {
    // Fetch the mapping once so Tab/Return can use their real keycodes.
    let setup = conn.setup();
    let min = setup.min_keycode;
    let count = setup.max_keycode - min + 1;
    let mapping = xproto::get_keyboard_mapping(conn, min, count)?.reply()?;
    let kb_per = mapping.keysyms_per_keycode as usize;

    for &ks in keysyms {
        let real = if ks == KEYSYM_TAB || ks == KEYSYM_RETURN {
            keycode_for_keysym(&mapping.keysyms, kb_per, min, ks)
        } else {
            None
        };
        match real {
            // Tap the genuine key (Tab/Return) so apps recognise it.
            Some(keycode) => tap_keycode(conn, keycode)?,
            // Remap a scratch keycode to the target keysym at every level (so no
            // modifier state can alter it), then tap it. Handles arbitrary
            // Unicode; the char path proven on hardware.
            None => {
                let levels = vec![ks; per as usize];
                xproto::change_keyboard_mapping(conn, 1, scratch, per, &levels)?.check()?;
                tap_keycode(conn, scratch)?;
            }
        }
        thread::sleep(KEY_DELAY);
    }
    Ok(())
}

/// Synthesise a press+release of `keycode`.
fn tap_keycode(conn: &impl Connection, keycode: u8) -> Result<(), InjectError> {
    xtest::fake_input(conn, KEY_PRESS_EVENT, keycode, 0, x11rb::NONE, 0, 0, 0)?.check()?;
    xtest::fake_input(conn, KEY_RELEASE_EVENT, keycode, 0, x11rb::NONE, 0, 0, 0)?.check()?;
    Ok(())
}

/// The keycode whose level-0 keysym is `target`, if any -- a pure scan of a
/// `GetKeyboardMapping` keysyms table (`per` keysyms per keycode, starting at
/// keycode `min`).
fn keycode_for_keysym(keysyms: &[u32], per: usize, min: u8, target: u32) -> Option<u8> {
    if per == 0 {
        return None;
    }
    for (i, chunk) in keysyms.chunks(per).enumerate() {
        if chunk.first() == Some(&target) {
            return Some(min + i as u8);
        }
    }
    None
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

#[cfg(test)]
mod tests {
    use super::{keycode_for_keysym, modifier_keycodes, shortcut_modifiers_held, KEYSYM_TAB};

    #[test]
    fn finds_level0_keycode_for_keysym() {
        // keycode 8 -> [a, A]; keycode 9 -> [Tab, 0]. per=2, min=8.
        let keysyms = [0x61, 0x41, KEYSYM_TAB, 0];
        assert_eq!(keycode_for_keysym(&keysyms, 2, 8, KEYSYM_TAB), Some(9));
    }

    #[test]
    fn only_matches_level0_not_shifted() {
        // 0x41 ('A') sits at level 1 of keycode 8; it must not match.
        let keysyms = [0x61, 0x41];
        assert_eq!(keycode_for_keysym(&keysyms, 2, 8, 0x41), None);
    }

    #[test]
    fn returns_none_when_absent() {
        assert_eq!(keycode_for_keysym(&[0x61, 0x62], 1, 8, KEYSYM_TAB), None);
    }

    #[test]
    fn control_is_a_held_shortcut_modifier() {
        assert!(shortcut_modifiers_held(0x04)); // Control
    }

    #[test]
    fn super_is_a_held_shortcut_modifier() {
        assert!(shortcut_modifiers_held(0x40)); // Mod4 (Super)
    }

    #[test]
    fn caps_and_num_lock_are_ignored() {
        assert!(!shortcut_modifiers_held(0x02 | 0x10)); // Lock (Caps) + Mod2 (Num)
    }

    #[test]
    fn no_modifiers_is_not_held() {
        assert!(!shortcut_modifiers_held(0x00));
    }

    #[test]
    fn filters_zero_placeholders() {
        assert_eq!(modifier_keycodes(&[0, 0, 37, 0, 0, 0]), vec![37]);
    }

    #[test]
    fn dedups_and_sorts() {
        assert_eq!(
            modifier_keycodes(&[133, 37, 37, 0, 133, 64]),
            vec![37, 64, 133]
        );
    }

    #[test]
    fn all_zero_is_empty() {
        assert!(modifier_keycodes(&[0, 0, 0, 0]).is_empty());
    }
}
