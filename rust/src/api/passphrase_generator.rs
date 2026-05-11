use flutter_rust_bridge::frb;
use rand::Rng;

// ---------------------------------------------------------------------------
// Wordlists — embedded at compile time, one word per line
// ---------------------------------------------------------------------------

const WORDLIST_EN: &str = include_str!("../../assets/wordlist_en.txt");
const WORDLIST_FR: &str = include_str!("../../assets/wordlist_fr.txt");
const WORDLIST_DE: &str = include_str!("../../assets/wordlist_de.txt");
const WORDLIST_ES: &str = include_str!("../../assets/wordlist_es.txt");
const WORDLIST_IT: &str = include_str!("../../assets/wordlist_it.txt");

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

#[frb(dart_metadata=("freezed"))]
pub enum Language {
    English,
    French,
    German,
    Spanish,
    Italian,
}

pub struct PassphraseConfig {
    pub word_count: u32,
    pub separator: String,
    pub capitalise: bool,
    pub append_number: bool,
    pub language: Language,
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn wordlist_for(language: &Language) -> Vec<&'static str> {
    let raw = match language {
        Language::English => WORDLIST_EN,
        Language::French  => WORDLIST_FR,
        Language::German  => WORDLIST_DE,
        Language::Spanish => WORDLIST_ES,
        Language::Italian => WORDLIST_IT,
    };
    raw.lines().filter(|l| !l.is_empty()).collect()
}

// ---------------------------------------------------------------------------
// Public API (exposed to Flutter via flutter_rust_bridge)
// ---------------------------------------------------------------------------

/// Generate a passphrase from the given config.
/// Returns Err if word_count is 0 or the wordlist is empty.
pub fn generate_passphrase(config: PassphraseConfig) -> Result<String, String> {
    const MIN_WORD_COUNT: u32 = 4;
    const MAX_WORD_COUNT: u32 = 20;

    if config.word_count < MIN_WORD_COUNT {
        return Err(format!("word_count must be at least {}", MIN_WORD_COUNT));
    }
    if config.word_count > MAX_WORD_COUNT {
        return Err(format!("word_count must be at most {}", MAX_WORD_COUNT));
    }

    let words = wordlist_for(&config.language);
    if words.is_empty() {
        return Err("wordlist is empty".into());
    }

    let mut rng = rand::thread_rng();
    let chosen: Vec<String> = (0..config.word_count)
        .map(|_| {
            let word = words[rng.gen_range(0..words.len())];
            if config.capitalise && rng.gen_bool(0.5) {
                let mut chars = word.chars();
                match chars.next() {
                    None => String::new(),
                    Some(first) => {
                        first.to_uppercase().collect::<String>() + chars.as_str()
                    }
                }
            } else {
                word.to_string()
            }
        })
        .collect();

    let mut passphrase = chosen.join(&config.separator);

    if config.append_number {
        let num_dig = rng.gen_range(config.word_count..=(config.word_count * 3 / 2));
        for _ in 0..num_dig {
            let pos = rng.gen_range(0..=passphrase.len());
            let digit = rng.gen_range(0u8..=9u8).to_string();
            passphrase.insert_str(pos, &digit);
        }
    }

    Ok(passphrase)
}

/// Calculate entropy in bits for a passphrase.
/// Uses the actual wordlist size for the given language.
pub fn passphrase_entropy_bits(word_count: u32, language: Language) -> f64 {
    let list_size = wordlist_for(&language).len() as f64;
    (word_count as f64) * list_size.log2()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> PassphraseConfig {
        PassphraseConfig {
            word_count: 4,
            separator: "-".to_string(),
            capitalise: false,
            append_number: false,
            language: Language::English,
        }
    }

    #[test]
    fn test_correct_word_count() {
        let result = generate_passphrase(default_config()).unwrap();
        assert_eq!(result.split('-').count(), 4);
    }

    #[test]
    fn test_separator_applied() {
        let config = PassphraseConfig {
            separator: ".".to_string(),
            ..default_config()
        };
        let result = generate_passphrase(config).unwrap();
        assert!(result.contains('.'));
        assert!(!result.contains('-'));
    }

    #[test]
    fn test_capitalise() {
        // Over many runs, we must see at least one capitalised word and at
        // least one lowercase word — proving it is random, not all-or-nothing.
        let mut saw_upper = false;
        let mut saw_lower = false;
        for _ in 0..200 {
            let config = PassphraseConfig {
                word_count: 6,
                capitalise: true,
                ..default_config()
            };
            let result = generate_passphrase(config).unwrap();
            for word in result.split('-') {
                let first = word.chars().next().unwrap();
                if first.is_alphabetic() {
                    if first.is_uppercase() {
                        saw_upper = true;
                    } else {
                        saw_lower = true;
                    }
                }
            }
            if saw_upper && saw_lower {
                break;
            }
        }
        assert!(saw_upper, "Never saw a capitalised word with capitalise=true");
        assert!(saw_lower, "Never saw a lowercase word with capitalise=true — not random");
    }

    #[test]
    fn test_append_number() {
        // Run many times to reduce flakiness from randomness.
        for _ in 0..50 {
            let config = PassphraseConfig {
                word_count: 4,
                append_number: true,
                ..default_config()
            };
            let result = generate_passphrase(config).unwrap();
            let digit_count = result.chars().filter(|c| c.is_ascii_digit()).count();
            // 4 words → num_dig in [4, 6]
            assert!(
                (4..=6).contains(&digit_count),
                "Expected 4–6 digits, got {} in \"{}\"",
                digit_count,
                result,
            );
            // Word count unchanged — still 4 separator-delimited tokens
            assert_eq!(result.split('-').count(), 4);
        }
    }

    #[test]
    fn test_zero_word_count_returns_error() {
        for bad_count in [0, 1, 2, 3] {
            let config = PassphraseConfig {
                word_count: bad_count,
                ..default_config()
            };
            assert!(
                generate_passphrase(config).is_err(),
                "Expected error for word_count = {}",
                bad_count
            );
        }
    }

    #[test]
    fn test_entropy_english() {
        // 4 words from 7776-word list: 4 * log2(7776) ≈ 51.7 bits
        let entropy = passphrase_entropy_bits(4, Language::English);
        assert!((entropy - 51.7).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_spanish() {
        // 4 words from 8192-word list: 4 * 13.0 = 52.0 bits
        let entropy = passphrase_entropy_bits(4, Language::Spanish);
        assert!((entropy - 52.0).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_all_languages_generate() {
        let languages = [
            ("English", Language::English),
            ("French", Language::French),
            ("German", Language::German),
            ("Spanish", Language::Spanish),
            ("Italian", Language::Italian),
        ];
        for (name, lang) in languages {
            let config = PassphraseConfig {
                word_count: 4,
                separator: "-".to_string(),
                capitalise: false,
                append_number: false,
                language: lang,
            };
            let result = generate_passphrase(config);
            assert!(result.is_ok(), "Failed for language: {}", name);
        }
    }

    #[test]
    fn test_word_count_above_maximum_returns_error() {
        let config = PassphraseConfig {
            word_count: 21,
            ..default_config()
        };
        assert!(generate_passphrase(config).is_err());
    }

}