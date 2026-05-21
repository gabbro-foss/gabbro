//! Entropy estimation for user-typed passwords.
//!
//! # What this module does
//!
//! Given a password string, it detects which character classes are present,
//! computes a pool size, and returns an estimated entropy in bits using the
//! standard formula:
//!
//!     entropy = length × log₂(pool_size)
//!
//! # Important caveat
//!
//! This is a **lower-bound estimate**, not a true entropy value. It assumes
//! the password was drawn uniformly at random from the detected character
//! classes. User-chosen passwords are not random, so actual guessability is
//! often lower than the number reported here. The UI must label this clearly
//! as "estimated entropy" to avoid false precision.
//!
//! # References
//!
//! - Wikipedia — Password strength:
//!   https://en.wikipedia.org/wiki/Password_strength
//! - Red Kestrel — Random Password Strength (entropy formula and pool sizes):
//!   https://redkestrel.co.uk/articles/random-password-strength
//! - NIST — 8-character minimum threshold (~52 bits):
//!   https://www.passbolt.com/blog/show-me-your-entropy-and-ill-break-your-password-part1

// ── Character class pool sizes ────────────────────────────────────────────────
//
// Full pool sizes per class. We always use the full class size, never the
// reduced ambiguous-excluded variant, because `estimate_entropy` only sees
// the typed string — it has no way to know whether the user had
// `exclude_ambiguous` enabled in the generator. Using the full pool size
// is the conservative choice: it may slightly overestimate entropy for
// passwords generated with ambiguous chars excluded, but it avoids
// underestimating entropy for passwords typed manually or generated without
// that flag. This is consistent with the lower-bound framing of the estimate.
//
//   lowercase a-z        : 26  (vs 23 with exclude_ambiguous: removes i, l, o)
//   uppercase A-Z        : 26  (vs 24 with exclude_ambiguous: removes I, O)
//   digits    0-9        : 10  (vs  8 with exclude_ambiguous: removes 0, 1)
//   symbols (printable
//     ASCII non-alnum)   : 32  (no ambiguous symbols defined — unchanged)
//   non-ASCII            : 128 (conservative proxy for extended character sets)

const POOL_LOWERCASE: u32 = 26;
const POOL_UPPERCASE: u32 = 26;
const POOL_DIGITS: u32 = 10;
const POOL_SYMBOLS: u32 = 32;
const POOL_NON_ASCII: u32 = 128;

// ── Public types ──────────────────────────────────────────────────────────────

/// A coarse strength label for a password, derived from its estimated entropy.
///
/// Tier boundaries (in bits), anchored to published references:
///
///  <  28 bits → Terrible
///  <  36 bits → Weak
///  <  52 bits → Fair     (NIST 8-char minimum sits around 52 bits)
///  <  80 bits → Strong
///  < 128 bits → VeryStrong
///  ≥ 128 bits → Centuries (128-bit threshold = infeasible brute-force per NIST)
///
/// Display strings for these variants are intentionally kept in Flutter,
/// following the same pattern as the `Language` enum — Rust owns the
/// classification logic, Flutter owns the UI text.
#[derive(Debug, Clone, PartialEq)]
pub enum StrengthTier {
    Terrible,
    Weak,
    Fair,
    Strong,
    VeryStrong,
    Centuries,
}

/// The result of an entropy estimate.
#[derive(Debug, Clone)]
pub struct EntropyResult {
    /// Estimated entropy in bits. This is a lower-bound estimate based on
    /// detected character classes. Label it "estimated entropy" in the UI.
    pub bits: f64,
    /// Coarse strength tier derived from `bits`.
    pub tier: StrengthTier,
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Estimate the entropy of a user-typed password.
///
/// Detects which character classes are present in `password`, builds a pool
/// size from those classes, then applies:
///
///     entropy = length × log₂(pool_size)
///
/// Returns `EntropyResult { bits: 0.0, tier: Terrible }` for an empty string.
#[flutter_rust_bridge::frb(sync)]
pub fn estimate_entropy(password: &str) -> EntropyResult {
    if password.is_empty() {
        return EntropyResult {
            bits: 0.0,
            tier: StrengthTier::Terrible,
        };
    }

    let pool = pool_size(password);
    let length = password.chars().count() as f64;
    let bits = if pool == 0 {
        0.0
    } else {
        length * (pool as f64).log2()
    };

    let tier = tier_for(bits);
    EntropyResult { bits, tier }
}

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Detect which character classes are present and sum their pool sizes.
fn pool_size(password: &str) -> u32 {
    let mut pool = 0u32;

    if password.chars().any(|c| c.is_ascii_lowercase()) {
        pool += POOL_LOWERCASE;
    }
    if password.chars().any(|c| c.is_ascii_uppercase()) {
        pool += POOL_UPPERCASE;
    }
    if password.chars().any(|c| c.is_ascii_digit()) {
        pool += POOL_DIGITS;
    }
    if password.chars().any(|c| c.is_ascii_punctuation()) {
        pool += POOL_SYMBOLS;
    }
    if !password.is_ascii() {
        pool += POOL_NON_ASCII;
    }

    pool
}

/// Map an entropy value in bits to a StrengthTier.
fn tier_for(bits: f64) -> StrengthTier {
    match bits {
        b if b < 28.0 => StrengthTier::Terrible,
        b if b < 36.0 => StrengthTier::Weak,
        b if b < 52.0 => StrengthTier::Fair,
        b if b < 80.0 => StrengthTier::Strong,
        b if b < 128.0 => StrengthTier::VeryStrong,
        _ => StrengthTier::Centuries,
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_password_returns_terrible() {
        let result = estimate_entropy("");
        assert_eq!(result.bits, 0.0);
        assert_eq!(result.tier, StrengthTier::Terrible);
    }

    #[test]
    fn digits_only_short_is_terrible() {
        // "1234" — pool=10, length=4 → 4 × 3.32 ≈ 13.3 bits
        let result = estimate_entropy("1234");
        assert!(result.bits < 28.0, "Got: {}", result.bits);
        assert_eq!(result.tier, StrengthTier::Terrible);
    }

    #[test]
    fn lowercase_only_short_is_weak() {
        // "abcdef" — pool=26, length=6 → 6 × 4.7 ≈ 28.2 bits
        let result = estimate_entropy("abcdef");
        assert!(
            result.bits >= 28.0 && result.bits < 36.0,
            "Got: {}",
            result.bits
        );
        assert_eq!(result.tier, StrengthTier::Weak);
    }

    #[test]
    fn mixed_case_digits_medium_is_fair() {
        // "Abcde1" — pool=62, length=6 → 6 × 5.95 ≈ 35.7 bits
        // just below Fair — bump length to 7 to land in Fair
        // "Abcde12" — pool=62, length=7 → 7 × 5.95 ≈ 41.7 bits
        let result = estimate_entropy("Abcde12");
        assert!(
            result.bits >= 36.0 && result.bits < 52.0,
            "Got: {}",
            result.bits
        );
        assert_eq!(result.tier, StrengthTier::Fair);
    }

    #[test]
    fn mixed_case_digits_symbols_longer_is_strong() {
        // "Abcde1!" — pool=94, length=7 → 7 × 6.55 ≈ 45.8 bits (Fair)
        // push to 10 chars: "Abcde12!@#" → 10 × 6.55 ≈ 65.5 bits (Strong)
        let result = estimate_entropy("Abcde12!@#");
        assert!(
            result.bits >= 52.0 && result.bits < 80.0,
            "Got: {}",
            result.bits
        );
        assert_eq!(result.tier, StrengthTier::Strong);
    }

    #[test]
    fn long_mixed_is_very_strong() {
        // 16 chars, pool=94 → 16 × 6.55 ≈ 104.8 bits
        let result = estimate_entropy("Abcde12!@#XyZ$%^");
        assert!(
            result.bits >= 80.0 && result.bits < 128.0,
            "Got: {}",
            result.bits
        );
        assert_eq!(result.tier, StrengthTier::VeryStrong);
    }

    #[test]
    fn very_long_password_is_centuries() {
        // 20 chars, pool=94 → 20 × 6.55 ≈ 131 bits
        let result = estimate_entropy("Abcde12!@#XyZ$%^&*()");
        assert!(result.bits >= 128.0, "Got: {}", result.bits);
        assert_eq!(result.tier, StrengthTier::Centuries);
    }

    #[test]
    fn non_ascii_increases_pool() {
        // Same length as a pure-lowercase password but with a non-ASCII char
        // should yield more bits
        let ascii_result = estimate_entropy("abcdef");
        let non_ascii_result = estimate_entropy("abcdéf");
        assert!(
            non_ascii_result.bits > ascii_result.bits,
            "Non-ASCII should increase entropy. ascii={}, non_ascii={}",
            ascii_result.bits,
            non_ascii_result.bits
        );
    }

    #[test]
    fn pool_size_detects_all_five_classes() {
        // Contains all five classes
        let p = pool_size("aA1!é");
        assert_eq!(
            p,
            POOL_LOWERCASE + POOL_UPPERCASE + POOL_DIGITS + POOL_SYMBOLS + POOL_NON_ASCII
        );
    }

    #[test]
    fn tier_boundaries_are_correct() {
        assert_eq!(tier_for(0.0), StrengthTier::Terrible);
        assert_eq!(tier_for(27.9), StrengthTier::Terrible);
        assert_eq!(tier_for(28.0), StrengthTier::Weak);
        assert_eq!(tier_for(35.9), StrengthTier::Weak);
        assert_eq!(tier_for(36.0), StrengthTier::Fair);
        assert_eq!(tier_for(51.9), StrengthTier::Fair);
        assert_eq!(tier_for(52.0), StrengthTier::Strong);
        assert_eq!(tier_for(79.9), StrengthTier::Strong);
        assert_eq!(tier_for(80.0), StrengthTier::VeryStrong);
        assert_eq!(tier_for(127.9), StrengthTier::VeryStrong);
        assert_eq!(tier_for(128.0), StrengthTier::Centuries);
    }
}
