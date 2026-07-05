//! Character -> X11 keysym planning for auto-type (ADR-017).
//!
//! Pure, host-testable logic with no X server involved: it maps each character
//! of a secret to the X11 keysym that the injection layer binds to a scratch
//! keycode and "presses". The mapping is the standard UCS rule used by libX11
//! and xdotool: the Latin-1 printable ranges map to the codepoint directly;
//! everything else uses the Unicode keysym `0x01000000 + codepoint`. Binding
//! the exact keysym at level 0 of a scratch keycode is why arbitrary scripts
//! (Greek, Cyrillic, CJK) inject uniformly, with no modifier juggling.

/// Map a single character to its X11 keysym (see module docs for the rule).
pub fn char_to_keysym(c: char) -> u32 {
    let cp = c as u32;
    // Latin-1 printable ranges: the keysym equals the codepoint.
    if (0x20..=0x7e).contains(&cp) || (0xa0..=0xff).contains(&cp) {
        cp
    } else {
        // Everything else: the X11 Unicode keysym.
        0x0100_0000 + cp
    }
}

/// Map a string to the ordered list of keysyms, one per character (Unicode
/// scalar value) -- never per byte.
pub fn plan_string(s: &str) -> Vec<u32> {
    s.chars().map(char_to_keysym).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ascii_letter_maps_to_codepoint() {
        assert_eq!(char_to_keysym('a'), 0x0061);
    }

    #[test]
    fn ascii_spread_maps_to_codepoints() {
        assert_eq!(char_to_keysym('A'), 0x41);
        assert_eq!(char_to_keysym('7'), 0x37);
        assert_eq!(char_to_keysym('@'), 0x40);
        assert_eq!(char_to_keysym(' '), 0x20);
        assert_eq!(char_to_keysym('~'), 0x7e);
    }

    #[test]
    fn latin1_high_maps_to_codepoint() {
        assert_eq!(char_to_keysym('\u{00e9}'), 0x00e9); // e-acute
        assert_eq!(char_to_keysym('\u{00a3}'), 0x00a3); // pound sign
    }

    #[test]
    fn boundary_above_latin1_uses_unicode_keysym() {
        assert_eq!(char_to_keysym('\u{0100}'), 0x0100_0100); // Latin A-macron
    }

    #[test]
    fn greek_uses_unicode_keysym() {
        assert_eq!(char_to_keysym('\u{03bb}'), 0x0100_03bb); // lambda
    }

    #[test]
    fn cyrillic_uses_unicode_keysym() {
        assert_eq!(char_to_keysym('\u{0434}'), 0x0100_0434); // de
    }

    #[test]
    fn euro_uses_unicode_keysym() {
        assert_eq!(char_to_keysym('\u{20ac}'), 0x0100_20ac); // euro sign
    }

    #[test]
    fn cjk_kana_hangul_use_unicode_keysym() {
        assert_eq!(char_to_keysym('\u{65e5}'), 0x0100_65e5); // CJK ri
        assert_eq!(char_to_keysym('\u{3042}'), 0x0100_3042); // hiragana a
        assert_eq!(char_to_keysym('\u{d55c}'), 0x0100_d55c); // hangul han
    }

    #[test]
    fn plan_empty_string_is_empty() {
        assert!(plan_string("").is_empty());
    }

    #[test]
    fn plan_mixed_string_preserves_order() {
        // 'a', 'E-acute', CJK-ri, euro
        assert_eq!(
            plan_string("a\u{00c9}\u{65e5}\u{20ac}"),
            vec![0x61, 0x00c9, 0x0100_65e5, 0x0100_20ac],
        );
    }

    #[test]
    fn plan_counts_chars_not_bytes() {
        // Mixed multi-byte scripts: keysym count must equal the character count,
        // not the (larger) UTF-8 byte length.
        let sample = "cafe\u{0301} \u{03bb}\u{0434} \u{65e5}\u{672c}\u{8a9e}";
        assert!(sample.len() > sample.chars().count());
        assert_eq!(plan_string(sample).len(), sample.chars().count());
    }
}
