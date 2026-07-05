//! Login fill sequences for auto-type (ADR-017), Linux-only.
//!
//! Turns a login entry's `username`/`password` into the ordered list of X11
//! keysyms to inject: `username` Tab `password` Return. Character mapping is
//! delegated to [`super::keysym`]; the field separators are the function keysyms
//! `Tab` and `Return` -- inserted as explicit constants, *not* mapped from
//! `'\t'`/`'\n'` (those control codes would wrongly become Unicode keysyms). The
//! injection of the returned list is the hardware layer's job
//! ([`super::inject`]).

use super::keysym::plan_string;

/// X11 `XK_Tab` -- the field separator between username and password.
const KEYSYM_TAB: u32 = 0xff09;
/// X11 `XK_Return` -- submits the login.
const KEYSYM_RETURN: u32 = 0xff0d;

/// Build the ordered keysym list for a login: `username` Tab `password` Return.
pub fn build_sequence(username: &str, password: &str) -> Vec<u32> {
    let mut seq = plan_string(username);
    seq.push(KEYSYM_TAB);
    seq.extend(plan_string(password));
    seq.push(KEYSYM_RETURN);
    seq
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_username_tab_password_return() {
        assert_eq!(
            build_sequence("ab", "yz"),
            vec![0x61, 0x62, KEYSYM_TAB, 0x79, 0x7a, KEYSYM_RETURN],
        );
    }

    #[test]
    fn delegates_to_keysym_mapping_for_non_latin() {
        // 'e-acute' (U+00E9) -> 0xe9; lambda (U+03BB) -> unicode keysym.
        assert_eq!(
            build_sequence("\u{00e9}", "\u{03bb}"),
            vec![0x00e9, KEYSYM_TAB, 0x0100_03bb, KEYSYM_RETURN],
        );
    }

    #[test]
    fn empty_username_still_emits_separators() {
        assert_eq!(
            build_sequence("", "pw"),
            vec![KEYSYM_TAB, 0x70, 0x77, KEYSYM_RETURN],
        );
    }
}
