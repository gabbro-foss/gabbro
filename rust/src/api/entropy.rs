//! `entropy = length x log2(pool_size)` over the detected character classes.
//! A lower bound that assumes uniform random choice; user-chosen passwords are
//! weaker, so the UI must label it "estimated". References:
//! https://en.wikipedia.org/wiki/Password_strength,
//! https://redkestrel.co.uk/articles/random-password-strength.

// Full class sizes, never the ambiguous-excluded ones: this only sees the
// typed string and cannot know whether `exclude_ambiguous` was on. Non-ASCII
// is a conservative proxy for extended character sets.
const POOL_LOWERCASE: u32 = 26;
const POOL_UPPERCASE: u32 = 26;
const POOL_DIGITS: u32 = 10;
const POOL_SYMBOLS: u32 = 32;
const POOL_NON_ASCII: u32 = 128;

/// Boundaries: 28, 36, 52 (NIST 8-char minimum), 80, 128 bits (infeasible
/// brute force). Display strings live in Flutter, as for `Language`.
#[derive(Debug, Clone, PartialEq)]
pub enum StrengthTier {
    Terrible,
    Weak,
    Fair,
    Strong,
    VeryStrong,
    Centuries,
}

#[derive(Debug, Clone)]
pub struct EntropyResult {
    /// A lower bound; label it "estimated" in the UI.
    pub bits: f64,
    pub tier: StrengthTier,
}

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
        // "1234" - pool=10, length=4 -> 4 x 3.32 ~ 13.3 bits
        let result = estimate_entropy("1234");
        assert!(result.bits < 28.0, "Got: {}", result.bits);
        assert_eq!(result.tier, StrengthTier::Terrible);
    }

    #[test]
    fn lowercase_only_short_is_weak() {
        // "abcdef" - pool=26, length=6 -> 6 x 4.7 ~ 28.2 bits
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
        // "Abcde1" - pool=62, length=6 -> 6 x 5.95 ~ 35.7 bits
        // just below Fair - bump length to 7 to land in Fair
        // "Abcde12" - pool=62, length=7 -> 7 x 5.95 ~ 41.7 bits
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
        // "Abcde1!" - pool=94, length=7 -> 7 x 6.55 ~ 45.8 bits (Fair)
        // push to 10 chars: "Abcde12!@#" -> 10 x 6.55 ~ 65.5 bits (Strong)
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
        // 16 chars, pool=94 -> 16 x 6.55 ~ 104.8 bits
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
        // 20 chars, pool=94 -> 20 x 6.55 ~ 131 bits
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
