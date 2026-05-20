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

    if config.use_uppercase {
        let chars = if config.exclude_ambiguous {
            "ABCDEFGHJKLMNPQRSTUVWXYZ" // removed I, O
        } else {
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        };
        pool.push_str(chars);
    }

    if config.use_lowercase {
        let chars = if config.exclude_ambiguous {
            "abcdefghjkmnpqrstuvwxyz" // removed i, l, o
        } else {
            "abcdefghijklmnopqrstuvwxyz"
        };
        pool.push_str(chars);
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
}
