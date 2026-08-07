pub use super::types::Language;
use rand::Rng;

// ---------------------------------------------------------------------------
// Wordlists — embedded at compile time, one word per line
// ---------------------------------------------------------------------------

const WORDLIST_EN: &str = include_str!("../../assets/wordlist_en.txt");
const WORDLIST_FR: &str = include_str!("../../assets/wordlist_fr.txt");
const WORDLIST_DE: &str = include_str!("../../assets/wordlist_de.txt");
const WORDLIST_ES: &str = include_str!("../../assets/wordlist_es.txt");
const WORDLIST_IT: &str = include_str!("../../assets/wordlist_it.txt");
const WORDLIST_SV: &str = include_str!("../../assets/wordlist_sv.txt");
const WORDLIST_DA: &str = include_str!("../../assets/wordlist_da.txt");
const WORDLIST_NB: &str = include_str!("../../assets/wordlist_nb.txt");
const WORDLIST_FI: &str = include_str!("../../assets/wordlist_fi.txt");
const WORDLIST_SL: &str = include_str!("../../assets/wordlist_sl.txt");
const WORDLIST_PL: &str = include_str!("../../assets/wordlist_pl.txt");
const WORDLIST_RU: &str = include_str!("../../assets/wordlist_ru.txt");
const WORDLIST_HU: &str = include_str!("../../assets/wordlist_hu.txt");
const WORDLIST_CS: &str = include_str!("../../assets/wordlist_cs.txt");
const WORDLIST_EL: &str = include_str!("../../assets/wordlist_el.txt");
const WORDLIST_PT: &str = include_str!("../../assets/wordlist_pt.txt");
const WORDLIST_ET: &str = include_str!("../../assets/wordlist_et.txt");
const WORDLIST_SK: &str = include_str!("../../assets/wordlist_sk.txt");
const WORDLIST_BG: &str = include_str!("../../assets/wordlist_bg.txt");
const WORDLIST_UK: &str = include_str!("../../assets/wordlist_uk.txt");
const WORDLIST_JA: &str = include_str!("../../assets/wordlist_ja.txt");
const WORDLIST_KO: &str = include_str!("../../assets/wordlist_ko.txt");
const WORDLIST_ZH_CN: &str = include_str!("../../assets/wordlist_zh_cn.txt");
const WORDLIST_ZH_TW: &str = include_str!("../../assets/wordlist_zh_tw.txt");
const WORDLIST_NL: &str = include_str!("../../assets/wordlist_nl.txt");
const WORDLIST_HR: &str = include_str!("../../assets/wordlist_hr.txt");
const WORDLIST_LT: &str = include_str!("../../assets/wordlist_lt.txt");
const WORDLIST_LV: &str = include_str!("../../assets/wordlist_lv.txt");
const WORDLIST_KK: &str = include_str!("../../assets/wordlist_kk.txt");

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

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
        Language::French => WORDLIST_FR,
        Language::German => WORDLIST_DE,
        Language::Spanish => WORDLIST_ES,
        Language::Italian => WORDLIST_IT,
        Language::Swedish => WORDLIST_SV,
        Language::Danish => WORDLIST_DA,
        Language::Norwegian => WORDLIST_NB,
        Language::Finnish => WORDLIST_FI,
        Language::Slovenian => WORDLIST_SL,
        Language::Polish => WORDLIST_PL,
        Language::Russian => WORDLIST_RU,
        Language::Hungarian => WORDLIST_HU,
        Language::Czech => WORDLIST_CS,
        Language::Greek => WORDLIST_EL,
        Language::Portuguese => WORDLIST_PT,
        Language::Estonian => WORDLIST_ET,
        Language::Slovak => WORDLIST_SK,
        Language::Bulgarian => WORDLIST_BG,
        Language::Ukrainian => WORDLIST_UK,
        Language::Japanese => WORDLIST_JA,
        Language::Korean => WORDLIST_KO,
        Language::ChineseSimplified => WORDLIST_ZH_CN,
        Language::ChineseTraditional => WORDLIST_ZH_TW,
        Language::Dutch => WORDLIST_NL,
        Language::Croatian => WORDLIST_HR,
        Language::Lithuanian => WORDLIST_LT,
        Language::Latvian => WORDLIST_LV,
        Language::Kazakh => WORDLIST_KK,
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
                    Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
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
            // Collect valid char-boundary byte offsets so insert_str never
            // splits a multi-byte codepoint (e.g. accented letters in FR/DE/ES/IT).
            let boundaries: Vec<usize> = passphrase
                .char_indices()
                .map(|(i, _)| i)
                .chain(std::iter::once(passphrase.len()))
                .collect();
            let pos = boundaries[rng.gen_range(0..boundaries.len())];
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
        // Use a separator that cannot appear in any wordlist word.
        let config = PassphraseConfig {
            separator: "|".to_string(),
            ..default_config()
        };
        let result = generate_passphrase(config).unwrap();
        assert_eq!(result.split('|').count(), 4);
    }

    #[test]
    fn test_separator_applied() {
        // Use "|" (never in any wordlist word) so the absence-of-other-separators
        // check is reliable even for words like "t-shirt" or "drop-down".
        let config = PassphraseConfig {
            separator: "|".to_string(),
            ..default_config()
        };
        let result = generate_passphrase(config).unwrap();
        assert!(result.contains('|'));
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
        assert!(
            saw_upper,
            "Never saw a capitalised word with capitalise=true"
        );
        assert!(
            saw_lower,
            "Never saw a lowercase word with capitalise=true — not random"
        );
    }

    #[test]
    fn test_append_number() {
        for _ in 0..50 {
            let config = PassphraseConfig {
                word_count: 4,
                append_number: true,
                ..default_config()
            };
            let result = generate_passphrase(config).unwrap();
            let digit_count = result.chars().filter(|c| c.is_ascii_digit()).count();
            // word_count=4 → num_dig ∈ [4, 6]
            assert!(
                (4..=6).contains(&digit_count),
                "Expected 4–6 digits, got {} in \"{}\"",
                digit_count,
                result,
            );
            // Note: split('-').count() is intentionally not asserted here.
            // Some wordlist entries contain hyphens (e.g. "drop-down", "t-shirt"),
            // so the token count is not a reliable invariant.
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
    fn test_entropy_estonian() {
        // 4 words from 7052-word list: 4 * log2(7052) ≈ 51.1 bits
        let entropy = passphrase_entropy_bits(4, Language::Estonian);
        let expected = 4.0 * (7052_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_bulgarian() {
        // 4 words from 7527-word list: 4 * log2(7527) ≈ 51.5 bits
        let entropy = passphrase_entropy_bits(4, Language::Bulgarian);
        let expected = 4.0 * (7527_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_all_languages_generate() {
        let languages = [
            ("English", Language::English),
            ("French", Language::French),
            ("German", Language::German),
            ("Spanish", Language::Spanish),
            ("Italian", Language::Italian),
            ("Swedish", Language::Swedish),
            ("Danish", Language::Danish),
            ("Norwegian", Language::Norwegian),
            ("Finnish", Language::Finnish),
            ("Slovenian", Language::Slovenian),
            ("Polish", Language::Polish),
            ("Russian", Language::Russian),
            ("Hungarian", Language::Hungarian),
            ("Czech", Language::Czech),
            ("Greek", Language::Greek),
            ("Portuguese", Language::Portuguese),
            ("Estonian", Language::Estonian),
            ("Slovak", Language::Slovak),
            ("Bulgarian", Language::Bulgarian),
            ("Ukrainian", Language::Ukrainian),
            ("Japanese", Language::Japanese),
            ("Korean", Language::Korean),
            ("ChineseSimplified", Language::ChineseSimplified),
            ("ChineseTraditional", Language::ChineseTraditional),
            ("Dutch", Language::Dutch),
            ("Croatian", Language::Croatian),
            ("Lithuanian", Language::Lithuanian),
            ("Latvian", Language::Latvian),
            ("Kazakh", Language::Kazakh),
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
    fn test_entropy_dutch() {
        // 4 words from 7776-word list: 4 * log2(7776) ≈ 51.7 bits
        let entropy = passphrase_entropy_bits(4, Language::Dutch);
        let expected = 4.0 * (7776_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_japanese() {
        // 4 words from 2048-word BIP-39 list: 4 * log2(2048) = 44.0 bits
        let entropy = passphrase_entropy_bits(4, Language::Japanese);
        let expected = 4.0 * (2048_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_korean() {
        let entropy = passphrase_entropy_bits(4, Language::Korean);
        let expected = 4.0 * (2048_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_chinese_simplified() {
        // 4 words from 7775-word cfbao list: 4 * log2(7775) ≈ 51.7 bits
        // (7775, not 7776 — the entry containing a fullwidth Latin Q was dropped)
        let entropy = passphrase_entropy_bits(4, Language::ChineseSimplified);
        let expected = 4.0 * (7775_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_chinese_traditional() {
        // 4 words from 2048-word BIP-39 list: 4 * log2(2048) = 44.0 bits
        let entropy = passphrase_entropy_bits(4, Language::ChineseTraditional);
        let expected = 4.0 * (2048_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_croatian() {
        // 4 words from 7776-word list: 4 * log2(7776) ≈ 51.7 bits
        let entropy = passphrase_entropy_bits(4, Language::Croatian);
        let expected = 4.0 * (7776_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_lithuanian() {
        // 4 words from 7776-word list: 4 * log2(7776) ≈ 51.7 bits
        let entropy = passphrase_entropy_bits(4, Language::Lithuanian);
        let expected = 4.0 * (7776_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_latvian() {
        // 4 words from 7776-word list: 4 * log2(7776) ≈ 51.7 bits
        let entropy = passphrase_entropy_bits(4, Language::Latvian);
        let expected = 4.0 * (7776_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_entropy_kazakh() {
        // 4 words from 4311-word list (limited corpus): 4 * log2(4311) ≈ 48.3 bits
        let entropy = passphrase_entropy_bits(4, Language::Kazakh);
        let expected = 4.0 * (4311_f64).log2();
        assert!((entropy - expected).abs() < 0.1, "Got: {}", entropy);
    }

    #[test]
    fn test_word_count_above_maximum_returns_error() {
        let config = PassphraseConfig {
            word_count: 21,
            ..default_config()
        };
        assert!(generate_passphrase(config).is_err());
    }

    // -----------------------------------------------------------------
    // Wordlist integrity net
    //
    // Nothing else pins the embedded lists. A regenerate that introduces
    // duplicates or truncates a list would silently cut real entropy while
    // the UI keeps showing the old figure, and stray characters produce
    // passphrases that read as broken.
    // -----------------------------------------------------------------

    struct Spec {
        name: &'static str,
        raw: &'static str,
        size: usize,
        /// Allowed characters, explicit per language — never a blanket `a-z`,
        /// so a missing or foreign letter fails loudly. Empty for CJK, which
        /// is checked by script range instead.
        alphabet: &'static str,
        min: usize,
        max: usize,
        /// Unicode ranges the script occupies. Empty for alphabetic languages.
        ranges: &'static [(char, char)],
    }

    const fn alpha(
        name: &'static str,
        raw: &'static str,
        size: usize,
        alphabet: &'static str,
        min: usize,
        max: usize,
    ) -> Spec {
        Spec {
            name,
            raw,
            size,
            alphabet,
            min,
            max,
            ranges: &[],
        }
    }

    const fn cjk(
        name: &'static str,
        raw: &'static str,
        size: usize,
        min: usize,
        max: usize,
        ranges: &'static [(char, char)],
    ) -> Spec {
        Spec {
            name,
            raw,
            size,
            alphabet: "",
            min,
            max,
            ranges,
        }
    }

    #[rustfmt::skip]
    const SPECS: &[Spec] = &[
        alpha("en", WORDLIST_EN, 7776, "abcdefghijklmnopqrstuvwxyz-", 3, 9),
        alpha("fr", WORDLIST_FR, 7775, "abcdefghijklmnopqrstuvwxyz", 4, 8),
        alpha("de", WORDLIST_DE, 7776, "abcdefghijklmnopqrstuvwxyz", 5, 19),
        alpha("es", WORDLIST_ES, 8192, "abcdefghijklmnopqrstuvwxyz", 4, 8),
        alpha("it", WORDLIST_IT, 8192, "abcdefghijklmnopqrstuvxyz", 4, 8),
        alpha("nl", WORDLIST_NL, 7776, "abcdefghijklmnopqrstuvwxyz", 2, 7),
        alpha("et", WORDLIST_ET, 7052, "abcdefghijklmnopqrstuvwxyz", 3, 6),
        alpha("sv", WORDLIST_SV, 7776, "abcdefghijklmnopqrstuvwxyzåäö", 4, 12),
        alpha("da", WORDLIST_DA, 7776, "abcdefghijklmnopqrstuvwxyzåæø", 4, 12),
        alpha("nb", WORDLIST_NB, 7776, "abcdefghijklmnopqrstuvwxyzåæø", 4, 12),
        // The 24 letters of native Finnish — q w x z å appear only in loanwords.
        alpha("fi", WORDLIST_FI, 7776, "abcdefghijklmnoprstuvyäö", 4, 12),
        alpha("cs", WORDLIST_CS, 7776, "abcdefghijklmnopqrstuvwxyzáčďéěíňóřšťúůýž", 4, 12),
        alpha("sk", WORDLIST_SK, 6642, "abcdefghijklmnopqrstuvwxyzáäčďéíĺľňóôŕšťúýž", 3, 17),
        alpha("sl", WORDLIST_SL, 7776, "abcdefghijklmnoprstuvzčšž", 4, 12),
        alpha("pl", WORDLIST_PL, 7776, "abcdefghijklmnopqrstuvwxyząćęłńóśźż", 4, 12),
        alpha("hr", WORDLIST_HR, 7776, "abcdefghijklmnoprstuvzćčđšž", 4, 12),
        alpha("hu", WORDLIST_HU, 7776, "abcdefghijklmnopqrstuvwxyzáéíóöőúüű", 4, 12),
        alpha("lt", WORDLIST_LT, 7776, "abcdefghijklmnoprstuvyząčėęįšųūž", 4, 12),
        alpha("lv", WORDLIST_LV, 7776, "abcdefghijklmnoprstuvzāčēģīķļņšūž", 4, 12),
        alpha("pt", WORDLIST_PT, 7776, "abcdefghijklmnopqrstuvwxz", 4, 9),
        alpha("el", WORDLIST_EL, 7776, "αβγδεζηθικλμνξοπρσςτυφχψωάέήίόύώϊϋΐΰ", 4, 12),
        alpha("ru", WORDLIST_RU, 7776, "абвгдежзийклмнопрстуфхцчшщъыьэюя", 4, 12),
        alpha("uk", WORDLIST_UK, 7661, "абвгґдежзийклмнопрстуфхцчшщьюяєії", 2, 7),
        alpha("bg", WORDLIST_BG, 7527, "абвгдежзийклмнопрстуфхцчшщъьюя", 3, 5),
        alpha("kk", WORDLIST_KK, 4311, "абвгдежзийклмнопрстуфхцчшыьэюяәғіқңөүұһ", 4, 12),
        // Hiragana, plus the combining voiced-sound marks.
        cjk("ja", WORDLIST_JA, 2048, 3, 9, &[('\u{3041}', '\u{309F}')]),
        // Conjoining Hangul jamo and precomposed syllables.
        cjk("ko", WORDLIST_KO, 2048, 4, 11, &[('\u{1100}', '\u{11FF}'), ('\u{AC00}', '\u{D7A3}')]),
        cjk("zh_cn", WORDLIST_ZH_CN, 7775, 1, 3, &[('\u{4E00}', '\u{9FFF}')]),
        cjk("zh_tw", WORDLIST_ZH_TW, 2048, 1, 1, &[('\u{4E00}', '\u{9FFF}')]),
    ];

    fn words(raw: &str) -> Vec<&str> {
        raw.lines().filter(|l| !l.is_empty()).collect()
    }

    #[test]
    fn every_wordlist_covers_a_supported_language() {
        assert_eq!(
            SPECS.len(),
            29,
            "a language was added or removed without updating the integrity net"
        );
    }

    #[test]
    fn every_wordlist_is_duplicate_free() {
        for spec in SPECS {
            let all = words(spec.raw);
            let unique: std::collections::HashSet<&str> = all.iter().copied().collect();
            assert_eq!(
                all.len(),
                unique.len(),
                "{}: {} duplicate words — real entropy is below the displayed figure",
                spec.name,
                all.len() - unique.len()
            );
        }
    }

    #[test]
    fn every_wordlist_matches_its_declared_size() {
        for spec in SPECS {
            assert_eq!(
                words(spec.raw).len(),
                spec.size,
                "{}: wrong list size",
                spec.name
            );
        }
    }

    #[test]
    fn no_wordlist_entry_is_blank_or_padded() {
        for spec in SPECS {
            for (i, line) in spec.raw.lines().enumerate() {
                assert!(!line.is_empty(), "{}: blank line at {}", spec.name, i + 1);
                assert_eq!(
                    line,
                    line.trim(),
                    "{}: padded entry at {}",
                    spec.name,
                    i + 1
                );
            }
        }
    }

    /// Report every offending list in one go, with a sample. Aborting on the
    /// first bad word would hide how many lists are affected.
    fn report(offenders: Vec<(&str, usize, Vec<String>)>, what: &str) {
        if offenders.is_empty() {
            return;
        }
        let mut lines = vec![format!("{} in {} list(s):", what, offenders.len())];
        for (name, count, sample) in &offenders {
            lines.push(format!(
                "  {}: {} — e.g. {}",
                name,
                count,
                sample.join(", ")
            ));
        }
        panic!("{}", lines.join("\n"));
    }

    #[test]
    fn every_word_uses_only_its_language_script() {
        let mut offenders = Vec::new();
        for spec in SPECS {
            let allowed: std::collections::HashSet<char> = spec.alphabet.chars().collect();
            let bad: Vec<String> = words(spec.raw)
                .into_iter()
                .filter(|word| {
                    word.chars().any(|c| {
                        if spec.ranges.is_empty() {
                            !allowed.contains(&c)
                        } else {
                            !spec.ranges.iter().any(|(lo, hi)| c >= *lo && c <= *hi)
                        }
                    })
                })
                .map(|w| w.to_string())
                .collect();
            if !bad.is_empty() {
                offenders.push((spec.name, bad.len(), bad.into_iter().take(5).collect()));
            }
        }
        report(offenders, "foreign characters");
    }

    #[test]
    fn every_word_length_is_within_bounds() {
        let mut offenders = Vec::new();
        for spec in SPECS {
            let bad: Vec<String> = words(spec.raw)
                .into_iter()
                .filter(|w| {
                    let len = w.chars().count();
                    len < spec.min || len > spec.max
                })
                .map(|w| format!("'{}' ({})", w, w.chars().count()))
                .collect();
            if !bad.is_empty() {
                offenders.push((spec.name, bad.len(), bad.into_iter().take(5).collect()));
            }
        }
        report(offenders, "out-of-bounds lengths");
    }
}
