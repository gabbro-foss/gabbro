use flutter_rust_bridge::frb;

/// Passphrase / password generator language.
///
/// Each variant maps to an embedded wordlist (passphrase mode) and to a
/// script-specific character pool (classic mode).  `nb` covers both Bokmål
/// and Nynorsk; `pt` covers both pt-PT and pt-BR; `nl` covers Dutch and Flemish.
#[frb(dart_metadata = ("freezed"))]
pub enum Language {
    English,
    French,
    German,
    Spanish,
    Italian,
    Swedish,
    Danish,
    Norwegian,
    Finnish,
    Slovenian,
    Polish,
    Russian,
    Hungarian,
    Czech,
    Greek,
    Portuguese,
    Estonian,
    Slovak,
    Bulgarian,
    Ukrainian,
    Japanese,
    Korean,
    ChineseSimplified,
    ChineseTraditional,
    Dutch,
    Croatian,
    Lithuanian,
    Latvian,
    Kazakh,
}
