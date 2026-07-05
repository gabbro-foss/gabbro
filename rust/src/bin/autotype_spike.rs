//! Hardware spike for ADR-017 Linux auto-type: prove arbitrary-Unicode
//! keystroke injection into the currently focused X11 window.
//!
//! Usage:
//!   cargo run --bin autotype_spike -- ["text to type"]
//!
//! Run it, then focus a text field (browser, editor, terminal) during the
//! countdown; the text is synthesised into that window. The default sample
//! exercises Latin, accented Latin, Greek, Cyrillic, CJK, digits and symbols
//! -- the arbitrary-Unicode case the ADR must prove on real hardware.

#[cfg(target_os = "linux")]
fn main() {
    use std::{env, thread, time::Duration};

    let text = env::args().nth(1).unwrap_or_else(|| {
        "Gabbro-1 caf\u{00e9} \u{03bb}\u{0434} \u{65e5}\u{672c}\u{8a9e} @#%".to_string()
    });

    eprintln!("autotype spike: focus a text field NOW.");
    for n in (1..=3).rev() {
        eprintln!("  typing in {n}...");
        thread::sleep(Duration::from_secs(1));
    }

    match rust_lib_gabbro::autotype::inject::type_text(&text) {
        Ok(()) => eprintln!("done: injected {} characters.", text.chars().count()),
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    }
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("autotype_spike is Linux-only (ADR-017).");
    std::process::exit(1);
}
