//! Login fill sequences for auto-type (ADR-017), Linux-only.
//!
//! Turns a login entry's `username`/`password` into the ordered list of X11
//! keysyms to inject. Character mapping is delegated to [`super::keysym`]; the
//! field separators are the function keysyms `Tab` and `Return` -- inserted as
//! explicit constants, *not* mapped from `'\t'`/`'\n'` (those control codes
//! would wrongly become Unicode keysyms). The injection of the returned list is
//! the hardware layer's job ([`super::inject`]).

use super::keysym::plan_string;

/// X11 `XK_Tab` -- the field separator in a full login sequence.
const KEYSYM_TAB: u32 = 0xff09;
/// X11 `XK_Return` -- submits a full login sequence.
const KEYSYM_RETURN: u32 = 0xff0d;

/// Which part(s) of a login to type. `Full` drives a single-page form; the
/// single-field variants drive two-step forms (identifier page, then password).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SequenceKind {
    /// `username` Tab `password` Return.
    Full,
    /// Just the username.
    UsernameOnly,
    /// Just the password.
    PasswordOnly,
}

/// Build the ordered keysym list for the requested part(s) of a login.
pub fn build_sequence(username: &str, password: &str, kind: SequenceKind) -> Vec<u32> {
    match kind {
        SequenceKind::UsernameOnly => plan_string(username),
        SequenceKind::PasswordOnly => plan_string(password),
        SequenceKind::Full => {
            let mut seq = plan_string(username);
            seq.push(KEYSYM_TAB);
            seq.extend(plan_string(password));
            seq.push(KEYSYM_RETURN);
            seq
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_is_username_tab_password_return() {
        assert_eq!(
            build_sequence("ab", "yz", SequenceKind::Full),
            vec![0x61, 0x62, KEYSYM_TAB, 0x79, 0x7a, KEYSYM_RETURN],
        );
    }

    #[test]
    fn username_only_ignores_password_and_separators() {
        assert_eq!(
            build_sequence("ab", "yz", SequenceKind::UsernameOnly),
            vec![0x61, 0x62],
        );
    }

    #[test]
    fn password_only_ignores_username_and_separators() {
        assert_eq!(
            build_sequence("ab", "yz", SequenceKind::PasswordOnly),
            vec![0x79, 0x7a],
        );
    }

    #[test]
    fn full_delegates_to_keysym_mapping_for_non_latin() {
        // 'e-acute' (U+00E9) -> 0xe9; lambda (U+03BB) -> unicode keysym.
        assert_eq!(
            build_sequence("\u{00e9}", "\u{03bb}", SequenceKind::Full),
            vec![0x00e9, KEYSYM_TAB, 0x0100_03bb, KEYSYM_RETURN],
        );
    }

    #[test]
    fn full_with_empty_username_still_emits_separators() {
        assert_eq!(
            build_sequence("", "pw", SequenceKind::Full),
            vec![KEYSYM_TAB, 0x70, 0x77, KEYSYM_RETURN],
        );
    }
}
