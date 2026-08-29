//! S-08: every import parser takes attacker-suppliable files and must answer
//! garbage and byte mutations with `Err`, never a panic; S-01 (a
//! non-char-boundary slice in the Enpass expiry parser) proved inspection is
//! not enough. Fixed seed, no crypto, so it runs in the routine suite.

use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};

use super::csv::{import_csv, CsvImportConfig};
use super::{bitwarden, dashlane, enpass, google_pm};

const FIXED_SEED: u64 = 0x6761_6262_726f_5f69; // "gabbro_i"
const CASES: usize = 2048;

// A minimal valid sample per format, used as the base for byte mutation.
const BITWARDEN_SAMPLE: &[u8] = br#"{"folders":[],"items":[{"type":1,"name":"x","login":{"username":"u","password":"p","uris":[{"uri":"https://example.com"}]}}]}"#;
const ENPASS_SAMPLE: &[u8] = br#"{"items":[{"uuid":"1","title":"t","category":"creditcard","note":"","favorite":0,"archived":0,"trashed":0,"fields":[{"label":"N","type":"ccNumber","value":"4111111111111111","sensitive":1,"deleted":0},{"label":"E","type":"ccExpiry","value":"12/2028","sensitive":0,"deleted":0}]}]}"#;
const DASHLANE_SAMPLE: &[u8] =
    b"username,username2,username3,url,category,note,password,title\nu,,,https://example.com,,n,p,t\n";
const GOOGLE_SAMPLE: &[u8] = b"name,url,username,password,note\nt,https://example.com,u,p,n\n";

/// Feed `parser` random garbage and byte-mutations of `base`. Any return value is
/// fine; the assertion is implicit - reaching the end means it never panicked.
fn fuzz_bytes(seed_salt: u64, base: &[u8], parser: impl Fn(&[u8])) {
    let mut rng = StdRng::seed_from_u64(FIXED_SEED ^ seed_salt);
    // Random garbage of assorted lengths.
    for _ in 0..CASES {
        let len = rng.gen_range(0..512);
        let bytes: Vec<u8> = (0..len).map(|_| rng.gen::<u8>()).collect();
        parser(&bytes);
    }
    // Byte mutations of a valid sample (1-7 flips each).
    for _ in 0..CASES {
        let mut bytes = base.to_vec();
        let muts = rng.gen_range(1..8);
        for _ in 0..muts {
            let i = rng.gen_range(0..bytes.len());
            bytes[i] = rng.gen::<u8>();
        }
        parser(&bytes);
    }
}

#[test]
fn bitwarden_parse_never_panics() {
    fuzz_bytes(1, BITWARDEN_SAMPLE, |b| {
        let _ = bitwarden::parse(b);
    });
}

#[test]
fn enpass_parse_never_panics() {
    fuzz_bytes(2, ENPASS_SAMPLE, |b| {
        let _ = enpass::parse(b);
    });
}

#[test]
fn dashlane_parse_never_panics() {
    fuzz_bytes(3, DASHLANE_SAMPLE, |b| {
        let _ = dashlane::parse(b);
    });
}

#[test]
fn google_pm_parse_never_panics() {
    fuzz_bytes(4, GOOGLE_SAMPLE, |b| {
        let _ = google_pm::parse(b);
    });
}

#[test]
fn csv_import_never_panics() {
    // CSV takes &str, so fuzz with random Unicode strings + mutated valid CSV.
    let config = CsvImportConfig {
        title_col: Some("name".to_string()),
        url_col: Some("url".to_string()),
        username_col: Some("username".to_string()),
        password_col: Some("password".to_string()),
        notes_col: Some("note".to_string()),
    };
    let mut rng = StdRng::seed_from_u64(FIXED_SEED ^ 5);
    for _ in 0..CASES {
        let len = rng.gen_range(0..512);
        let s: String = (0..len).map(|_| rng.gen::<char>()).collect();
        let _ = import_csv(&s, &config);
    }
    let base = b"name,url,username,password,note\nt,https://example.com,u,p,n\n";
    for _ in 0..CASES {
        let mut bytes = base.to_vec();
        let muts = rng.gen_range(1..8);
        for _ in 0..muts {
            let i = rng.gen_range(0..bytes.len());
            bytes[i] = rng.gen::<u8>();
        }
        let s = String::from_utf8_lossy(&bytes);
        let _ = import_csv(&s, &config);
    }
}
