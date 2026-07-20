//! X11 keystroke injection for auto-type (ADR-017), Linux-only.
//!
//! Synthesises key events with the XTEST extension. It binds temporary "scratch"
//! keycodes (ones with no keysyms mapped) to the target keysyms at every level,
//! then "presses" them -- the xdotool technique. Binding at every level means no
//! modifier state can alter the produced character, so arbitrary Unicode
//! (accented Latin, Greek, Cyrillic, CJK) types uniformly regardless of the
//! user's keyboard layout. Events reach whatever window currently holds focus.
//!
//! Crucially, each *distinct* keysym gets its **own** scratch keycode, bound once
//! up front and never rebound while typing (see [`plan_batches`]). The earlier
//! approach reused one keycode, remapping it between every keystroke; the target
//! app could then resolve a keycode against a stale keymap, duplicating the
//! previous character and dropping the next (`abc.f` -> `abc..`). A secret with
//! more distinct characters than there are free keycodes is split into batches,
//! restored and settled at each seam.
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

/// Longer settle at a batch seam -- only reached when a secret has more distinct
/// characters than there are free keycodes. The previous batch's keycodes are
/// restored to NoSymbol first, so a tap the target hasn't drained yet resolves
/// to NoSymbol (a detectable drop) rather than a stale character once the same
/// keycodes are rebound for the next batch.
const BATCH_SETTLE: Duration = Duration::from_millis(100);

/// Function keysyms injected via their genuine keycodes (not a remapped scratch
/// key): apps like Chromium key Tab focus-navigation and Enter submission off
/// the real hardware keycode and ignore these on a made-up keycode.
const KEYSYM_TAB: u32 = 0xff09;
const KEYSYM_RETURN: u32 = 0xff0d;

/// Type `text` into the currently focused window as synthesised key events.
///
/// Empty input is a no-op. The scratch keycodes are always restored to their
/// unmapped state, even if injection fails partway.
pub fn type_text(text: &str) -> Result<(), InjectError> {
    let (conn, _screen) = x11rb::connect(None)?;
    type_keysyms(&conn, &plan_string(text))
}

/// Inject a prepared keysym sequence on an existing connection. Empty input is
/// a no-op. The scratch keycodes are always restored, even if injection fails
/// partway. Callers that must verify window focus immediately before typing
/// should use the *same* `conn` for both, to minimise the race window.
pub fn type_keysyms(conn: &impl Connection, keysyms: &[u32]) -> Result<(), InjectError> {
    if keysyms.is_empty() {
        return Ok(());
    }
    let (pool, per) = find_all_scratch_keycodes(conn)?;
    // Wait for the trigger combo (e.g. Super+Ctrl) to be physically released so
    // its release events don't interleave with -- and scramble -- the injected
    // keystrokes; then clear any still logically held, so injected characters
    // aren't turned into modified shortcuts.
    wait_for_modifiers_released(conn)?;
    release_held_modifiers(conn)?;
    let injected = inject_planned(conn, &pool, per, keysyms);
    // Restore every scratch keycode to NoSymbol regardless of the outcome above.
    let restored = restore_all(conn, &pool, per);
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

fn inject_planned(
    conn: &impl Connection,
    pool: &[u8],
    per: u8,
    keysyms: &[u32],
) -> Result<(), InjectError> {
    // Fetch the mapping once so Tab/Return can use their real keycodes.
    let setup = conn.setup();
    let min = setup.min_keycode;
    let count = setup.max_keycode - min + 1;
    let mapping = xproto::get_keyboard_mapping(conn, min, count)?.reply()?;
    let kb_per = mapping.keysyms_per_keycode as usize;

    // Tab/Return tap their genuine keycode (apps key focus/submit off it and
    // ignore a made-up keycode); every other character needs a scratch keycode.
    let slots: Vec<Slot> = keysyms
        .iter()
        .map(|&ks| {
            if ks == KEYSYM_TAB || ks == KEYSYM_RETURN {
                match keycode_for_keysym(&mapping.keysyms, kb_per, min, ks) {
                    Some(kc) => Slot::Real(kc),
                    None => Slot::Scratch(ks),
                }
            } else {
                Slot::Scratch(ks)
            }
        })
        .collect();

    let batches = plan_batches(&slots, pool);
    let last = batches.len().saturating_sub(1);
    for (i, batch) in batches.iter().enumerate() {
        // Bind every keycode this batch uses -- at every level, so no modifier
        // state can alter the produced character -- BEFORE tapping any of them.
        // Nothing is rebound while tapping, so the target never resolves a
        // keycode against a stale keymap (the race this fixes).
        for &(kc, ks) in &batch.bindings {
            let levels = vec![ks; per as usize];
            xproto::change_keyboard_mapping(conn, 1, kc, per, &levels)?.check()?;
        }
        for &kc in &batch.taps {
            tap_keycode(conn, kc)?;
            thread::sleep(KEY_DELAY);
        }
        // Restore this batch's keycodes and settle before the next batch reuses
        // them (only when a secret overflows the free-keycode pool). The final
        // batch is restored by the caller's restore_all.
        if i != last {
            for &(kc, _) in &batch.bindings {
                restore_keycode(conn, kc, per)?;
            }
            thread::sleep(BATCH_SETTLE);
        }
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

/// Restore every keycode in `pool` to NoSymbol, attempting all even if one
/// fails, and return the first error (if any). Ensures no scratch keycode is
/// left bound after injection, whatever went wrong partway.
fn restore_all(conn: &impl Connection, pool: &[u8], per: u8) -> Result<(), InjectError> {
    let mut result = Ok(());
    for &kc in pool {
        let r = restore_keycode(conn, kc, per);
        if result.is_ok() {
            result = r;
        }
    }
    result
}

/// Find every keycode whose levels are all NoSymbol (0) -- each safe to remap
/// temporarily -- and the mapping's levels-per-keycode. Ordered ascending;
/// errs if none exist. A larger pool means fewer secrets overflow into batches.
fn find_all_scratch_keycodes(conn: &impl Connection) -> Result<(Vec<u8>, u8), InjectError> {
    let setup = conn.setup();
    let min = setup.min_keycode;
    let max = setup.max_keycode;
    let count = max - min + 1;

    let mapping = xproto::get_keyboard_mapping(conn, min, count)?.reply()?;
    let per = mapping.keysyms_per_keycode;
    if per == 0 {
        return Err(InjectError::NoKeyboardLevels);
    }

    let pool: Vec<u8> = mapping
        .keysyms
        .chunks(per as usize)
        .enumerate()
        .filter(|(_, chunk)| chunk.iter().all(|&ks| ks == 0))
        .map(|(i, _)| min + i as u8)
        .collect();
    if pool.is_empty() {
        return Err(InjectError::NoScratchKeycode);
    }
    Ok((pool, per))
}

// ── Stable-keycode planner ──────────────────────────────────────────────────
// The remap-one-scratch-keycode-per-keystroke technique lets the target app
// resolve a keycode against a stale keymap between taps, duplicating the
// previous character and dropping the next. The planner assigns each *distinct*
// keysym its own keycode, bound once per batch and never rebound mid-batch, so
// no keystroke depends on the app refreshing its keymap.

/// One position in the tap stream: a real keycode tapped as-is (Tab/Return,
/// which apps key off their genuine keycode), or a keysym that must be bound to
/// a scratch keycode before it can be tapped.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Slot {
    Real(u8),
    Scratch(u32),
}

/// A batch: bind each `(keycode, keysym)` in `bindings` once (at every level),
/// tap `taps` in order, then the caller restores. No keycode is rebound within
/// a batch, so the app never resolves a keycode against a stale keymap mid-batch.
#[derive(Debug, PartialEq, Eq)]
struct Batch {
    bindings: Vec<(u8, u32)>,
    taps: Vec<u8>,
}

/// Partition `slots` into batches over `pool` free scratch keycodes. Each batch
/// binds at most `pool.len()` distinct scratch keysyms (one keycode each) and
/// taps them in order; `Real` slots pass through and consume no pool slot.
/// Contiguous batching preserves the overall tap order. `pool` must be non-empty
/// when any `Scratch` slot is present (the caller guards with `NoScratchKeycode`).
fn plan_batches(slots: &[Slot], pool: &[u8]) -> Vec<Batch> {
    let mut batches = Vec::new();
    let mut bindings: Vec<(u8, u32)> = Vec::new();
    let mut taps: Vec<u8> = Vec::new();
    let mut assigned: std::collections::HashMap<u32, u8> = std::collections::HashMap::new();

    for &slot in slots {
        match slot {
            // Real keycodes (Tab/Return) tap as-is and need no pool slot.
            Slot::Real(kc) => taps.push(kc),
            Slot::Scratch(ks) => {
                if let Some(&kc) = assigned.get(&ks) {
                    taps.push(kc); // already bound in this batch — reuse it
                } else {
                    if assigned.len() == pool.len() {
                        // No free pool slot left: close this batch and start a
                        // fresh one (the caller restores + settles between them).
                        batches.push(Batch {
                            bindings: std::mem::take(&mut bindings),
                            taps: std::mem::take(&mut taps),
                        });
                        assigned.clear();
                    }
                    let kc = pool[assigned.len()];
                    assigned.insert(ks, kc);
                    bindings.push((kc, ks));
                    taps.push(kc);
                }
            }
        }
    }
    if !bindings.is_empty() || !taps.is_empty() {
        batches.push(Batch { bindings, taps });
    }
    batches
}

#[cfg(test)]
mod tests {
    use super::{
        keycode_for_keysym, modifier_keycodes, plan_batches, shortcut_modifiers_held, Slot,
        KEYSYM_TAB,
    };
    use std::collections::{HashMap, HashSet};

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

    // ── Stable-keycode planner ──────────────────────────────────────────────

    #[test]
    fn single_batch_when_distinct_fits_pool() {
        // 'a','b','a' over pool [50,51,52]: a->50, b->51; the repeat reuses 50.
        let slots = [
            Slot::Scratch(0x61),
            Slot::Scratch(0x62),
            Slot::Scratch(0x61),
        ];
        let plan = plan_batches(&slots, &[50, 51, 52]);
        assert_eq!(plan.len(), 1);
        assert_eq!(plan[0].bindings, vec![(50, 0x61), (51, 0x62)]);
        assert_eq!(plan[0].taps, vec![50, 51, 50]);
    }

    #[test]
    fn real_slots_pass_through_and_consume_no_pool() {
        // 'a' Tab 'b', with Tab as a real keycode (23).
        let slots = [Slot::Scratch(0x61), Slot::Real(23), Slot::Scratch(0x62)];
        let plan = plan_batches(&slots, &[50, 51]);
        assert_eq!(plan.len(), 1);
        assert_eq!(plan[0].bindings, vec![(50, 0x61), (51, 0x62)]);
        assert_eq!(plan[0].taps, vec![50, 23, 51]);
    }

    #[test]
    fn splits_into_batches_when_distinct_exceeds_pool() {
        // Pool of 1, two distinct keysyms -> two batches, order preserved.
        let slots = [Slot::Scratch(0x61), Slot::Scratch(0x62)];
        let plan = plan_batches(&slots, &[50]);
        assert_eq!(plan.len(), 2);
        assert_eq!(plan[0].bindings, vec![(50, 0x61)]);
        assert_eq!(plan[0].taps, vec![50]);
        assert_eq!(plan[1].bindings, vec![(50, 0x62)]);
        assert_eq!(plan[1].taps, vec![50]);
    }

    #[test]
    fn concatenated_taps_reproduce_keysym_order() {
        // Across a batch split (pool 2), the typed keysyms must equal the input.
        let slots = [
            Slot::Scratch(0x61),
            Slot::Scratch(0x62),
            Slot::Scratch(0x63),
            Slot::Scratch(0x61),
            Slot::Scratch(0x64),
        ];
        let plan = plan_batches(&slots, &[50, 51]);
        let mut typed = Vec::new();
        for batch in &plan {
            let map: HashMap<u8, u32> = batch.bindings.iter().copied().collect();
            for &kc in &batch.taps {
                typed.push(map[&kc]);
            }
        }
        assert_eq!(typed, vec![0x61, 0x62, 0x63, 0x61, 0x64]);
    }

    #[test]
    fn no_keycode_rebound_within_a_batch() {
        // The race-killing invariant: within each batch every keycode is bound at
        // most once, and every scratch tap references a keycode bound in it.
        let slots = [
            Slot::Scratch(0x61),
            Slot::Scratch(0x62),
            Slot::Real(23),
            Slot::Scratch(0x63),
            Slot::Scratch(0x61),
            Slot::Scratch(0x64),
        ];
        let real: HashSet<u8> = [23].into_iter().collect();
        for batch in plan_batches(&slots, &[50, 51, 52]) {
            let mut bound = HashSet::new();
            for &(kc, _) in &batch.bindings {
                assert!(bound.insert(kc), "keycode {kc} bound twice in one batch");
            }
            for &kc in &batch.taps {
                assert!(
                    real.contains(&kc) || bound.contains(&kc),
                    "tapped keycode {kc} was not bound in its batch"
                );
            }
        }
    }

    #[test]
    fn empty_sequence_is_empty_plan() {
        assert!(plan_batches(&[], &[50, 51]).is_empty());
    }
}
