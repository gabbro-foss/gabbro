use super::types::Language;

const MIN_LENGTH: u32 = 32;
const MAX_LENGTH: u32 = 256;

/// Configuration for classic password generation.
pub struct PasswordConfig {
    pub length: u32,
    pub use_uppercase: bool,
    pub use_lowercase: bool,
    pub use_digits: bool,
    pub use_symbols: bool,
    pub exclude_ambiguous: bool,
    /// Drives the character pool for uppercase/lowercase.
    /// Greek and Cyrillic scripts replace the Latin pool; Latin-script
    /// languages use the standard ASCII pool (exclude_ambiguous still applies).
    pub language: Language,
}

/// Generate a random password according to the given config.
/// Returns an error string if the config produces an empty character pool.
#[flutter_rust_bridge::frb(sync)]
pub fn generate_password(config: PasswordConfig) -> Result<String, String> {
    use rand::Rng;

    if config.length < MIN_LENGTH || config.length > MAX_LENGTH {
        return Err(format!(
            "Password length must be between {} and {} characters, got {}",
            MIN_LENGTH, MAX_LENGTH, config.length
        ));
    }

    let mut pool = String::new();

    match config.language {
        // CJK combined pools: uppercase/lowercase both map to a single unified pool.
        // Korean: 2350 Hangul syllables U+AC00–U+B52D.
        Language::Korean => {
            if config.use_uppercase || config.use_lowercase {
                pool.extend((0u32..2350).filter_map(|i| char::from_u32(0xAC00 + i)));
            }
        }
        // Chinese Simplified + Traditional share GB2312 Level 1: 3755 CJK chars U+4E00–U+5CAA.
        Language::ChineseSimplified | Language::ChineseTraditional => {
            if config.use_uppercase || config.use_lowercase {
                pool.extend((0u32..3755).filter_map(|i| char::from_u32(0x4E00 + i)));
            }
        }
        _ => {
            if config.use_uppercase {
                let chars = match config.language {
                    Language::Greek => "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ",
                    Language::Russian => "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ",
                    Language::Ukrainian => "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ",
                    Language::Bulgarian => "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЬЮЯ",
                    Language::Japanese => {
                        "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
                    }
                    _ => {
                        if config.exclude_ambiguous {
                            "ABCDEFGHJKLMNPQRSTUVWXYZ" // removed I, O
                        } else {
                            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                        }
                    }
                };
                pool.push_str(chars);
            }

            if config.use_lowercase {
                let chars = match config.language {
                    Language::Greek => "αβγδεζηθικλμνξοπρστυφχψω",
                    Language::Russian => "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
                    Language::Ukrainian => "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя",
                    Language::Bulgarian => "абвгдежзийклмнопрстуфхцчшщъьюя",
                    Language::Japanese => {
                        "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
                    }
                    _ => {
                        if config.exclude_ambiguous {
                            "abcdefghjkmnpqrstuvwxyz" // removed i, l, o
                        } else {
                            "abcdefghijklmnopqrstuvwxyz"
                        }
                    }
                };
                pool.push_str(chars);
            }
        }
    }

    if config.use_digits {
        let chars = if config.exclude_ambiguous {
            "23456789" // removed 0, 1
        } else {
            "0123456789"
        };
        pool.push_str(chars);
    }

    if config.use_symbols {
        pool.push_str("!@#$%^&*()-_=+[]{}|;:,.<>?");
    }

    if pool.is_empty() {
        return Err("No character sets selected.".to_string());
    }

    let pool_chars: Vec<char> = pool.chars().collect();
    let mut rng = rand::thread_rng();

    let password: String = (0..config.length)
        .map(|_| pool_chars[rng.gen_range(0..pool_chars.len())])
        .collect();

    Ok(password)
}

/// Calculate entropy in bits for a password of given length drawn from a pool of given size.
/// Formula: entropy = length × log₂(pool_size)
#[flutter_rust_bridge::frb(sync)]
pub fn entropy_bits(pool_size: u32, length: u32) -> f64 {
    if pool_size == 0 || length == 0 {
        return 0.0;
    }
    (length as f64) * (pool_size as f64).log2()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> PasswordConfig {
        PasswordConfig {
            length: 32,
            use_uppercase: true,
            use_lowercase: true,
            use_digits: true,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::English,
        }
    }

    #[test]
    fn test_correct_length() {
        let pwd = generate_password(default_config()).unwrap();
        assert_eq!(pwd.len(), 32);
    }

    #[test]
    fn test_empty_pool_returns_error() {
        let config = PasswordConfig {
            length: 32,
            use_uppercase: false,
            use_lowercase: false,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::English,
        };
        assert!(generate_password(config).is_err());
    }

    #[test]
    fn test_digits_only() {
        let config = PasswordConfig {
            length: 32,
            use_uppercase: false,
            use_lowercase: false,
            use_digits: true,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::English,
        };
        let pwd = generate_password(config).unwrap();
        assert!(pwd.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn test_exclude_ambiguous_removes_banned_chars() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: true,
            use_lowercase: true,
            use_digits: true,
            use_symbols: false,
            exclude_ambiguous: true,
            language: Language::English,
        };
        let pwd = generate_password(config).unwrap();
        let banned = ['0', '1', 'I', 'O', 'i', 'l', 'o'];
        for ch in banned {
            assert!(!pwd.contains(ch), "Found banned char '{}' in password", ch);
        }
    }

    #[test]
    fn test_entropy_bits_reasonable() {
        // 16 chars from pool of 62 (a-z, A-Z, 0-9) ≈ 95 bits
        let e = entropy_bits(62, 16);
        assert!(e > 90.0 && e < 100.0, "Entropy was {}", e);
    }

    #[test]
    fn test_entropy_zero_inputs() {
        assert_eq!(entropy_bits(0, 16), 0.0);
        assert_eq!(entropy_bits(62, 0), 0.0);
    }

    #[test]
    fn test_length_below_minimum_returns_error() {
        let config = PasswordConfig {
            length: 8,
            ..default_config()
        };
        assert!(generate_password(config).is_err());
    }

    #[test]
    fn test_length_above_maximum_returns_error() {
        let config = PasswordConfig {
            length: 512,
            ..default_config()
        };
        assert!(generate_password(config).is_err());
    }

    #[test]
    fn test_greek_uppercase_lowercase_are_greek() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: true,
            use_lowercase: true,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::Greek,
        };
        let pwd = generate_password(config).unwrap();
        assert!(
            pwd.chars()
                .all(|c| "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρστυφχψω".contains(c)),
            "Non-Greek char found in Greek password"
        );
    }

    #[test]
    fn test_japanese_katakana_uppercase() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: true,
            use_lowercase: false,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::Japanese,
        };
        let pwd = generate_password(config).unwrap();
        let katakana: std::collections::HashSet<char> =
            "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
                .chars()
                .collect();
        assert!(
            pwd.chars().all(|c| katakana.contains(&c)),
            "Non-Katakana char found in Japanese uppercase password"
        );
    }

    #[test]
    fn test_japanese_hiragana_lowercase() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: false,
            use_lowercase: true,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::Japanese,
        };
        let pwd = generate_password(config).unwrap();
        let hiragana: std::collections::HashSet<char> =
            "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
                .chars()
                .collect();
        assert!(
            pwd.chars().all(|c| hiragana.contains(&c)),
            "Non-Hiragana char found in Japanese lowercase password"
        );
    }

    #[test]
    fn test_korean_uses_hangul_syllables() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: true,
            use_lowercase: false,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::Korean,
        };
        let pwd = generate_password(config).unwrap();
        assert!(
            pwd.chars().all(|c| ('\u{AC00}'..='\u{B52D}').contains(&c)),
            "Non-Hangul char found in Korean password"
        );
    }

    #[test]
    fn test_korean_combined_pool_not_doubled() {
        // Both uppercase AND lowercase selected: pool is 2350, not 4700.
        let config = PasswordConfig {
            length: 200,
            use_uppercase: true,
            use_lowercase: true,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::Korean,
        };
        let pwd = generate_password(config).unwrap();
        assert!(
            pwd.chars().all(|c| ('\u{AC00}'..='\u{B52D}').contains(&c)),
            "Non-Hangul char found when both uppercase and lowercase selected for Korean"
        );
    }

    #[test]
    fn test_chinese_simplified_uses_cjk() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: false,
            use_lowercase: true,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::ChineseSimplified,
        };
        let pwd = generate_password(config).unwrap();
        assert!(
            pwd.chars().all(|c| ('\u{4E00}'..='\u{5CAA}').contains(&c)),
            "Non-CJK char found in Chinese Simplified password"
        );
    }

    #[test]
    fn test_chinese_traditional_same_pool() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: true,
            use_lowercase: false,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::ChineseTraditional,
        };
        let pwd = generate_password(config).unwrap();
        assert!(
            pwd.chars().all(|c| ('\u{4E00}'..='\u{5CAA}').contains(&c)),
            "Non-CJK char found in Chinese Traditional password"
        );
    }

    #[test]
    fn test_cyrillic_russian_no_latin() {
        let config = PasswordConfig {
            length: 200,
            use_uppercase: true,
            use_lowercase: true,
            use_digits: false,
            use_symbols: false,
            exclude_ambiguous: false,
            language: Language::Russian,
        };
        let pwd = generate_password(config).unwrap();
        assert!(
            pwd.chars()
                .all(|c| c.is_alphabetic() && !c.is_ascii_alphabetic()),
            "Latin char found in Russian password"
        );
    }
}
