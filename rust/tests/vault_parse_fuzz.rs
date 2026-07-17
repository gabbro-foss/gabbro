//! `SealedVault::from_bytes` malformed-input fuzzer — proves the vault parser
//! rejects garbage with a clean `Err`, never a panic.
//!
//! # Why this exists
//!
//! `from_bytes` (`src/vault/file_format.rs`) is the first code to touch an
//! untrusted `.gabbro` file — a synced copy, an email attachment, anything a user
//! is handed. Every slice in it is guarded by a length check, so the parser *looks*
//! panic-free. But that safety was held only by inspection: the
//! `vault_backward_compat` gate only ever feeds it *valid* vaults, so a slice added
//! without its guard — or an integer-overflow in a guard expression — would ship a
//! crash-on-open and nothing would catch it. This is the negative test that locks
//! the good behaviour in.
//!
//! # Strategies
//!
//! 1. **Truncation** — every prefix `data[..n]` of a real golden vault. A vault cut
//!    short anywhere must be `Err`, never a panic.
//! 2. **Random garbage** — seeded-random byte strings of assorted lengths.
//! 3. **Oversized length fields** — a structurally valid header whose
//!    attacker-controlled 8-byte body-length is set huge (up to `u64::MAX`). This is
//!    the regression for the `pos + body_len` usize-overflow: in release the add
//!    wraps to a small number, the `data.len() < pos + body_len` guard passes, and
//!    `data[pos..pos + body_len]` becomes a reversed range -> panic. Must be `Err`.
//!
//! # Not `#[ignore]`'d (unlike `vault_state_machine_fuzz`)
//!
//! Parsing does no Argon2id / crypto work, so this is cheap and runs in the routine
//! `cargo test`. It is a permanent guard, not an opt-in exploratory run.
//!
//! # Determinism
//!
//! The RNG is seeded from a fixed constant: a guard must never flake.

use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};

use rust_lib_gabbro::vault::file_format::{SealedVault, MAGIC, VERSION};

const FIXED_SEED: u64 = 0x6761_6262_726f_5f70; // "gabbro_p"
const GARBAGE_CASES: usize = 4096;

/// Bytes of a committed golden vault, used as the "valid" base for truncation.
/// Must be a readable format (v11+): the truncation test needs the full file to
/// parse, and a pre-floor vault is refused on its version byte alone — which would
/// pass the "is_err" assertions for the wrong reason and test nothing.
fn golden_vault_bytes() -> Vec<u8> {
    let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/vaults/v11_passphrase.gabbro");
    std::fs::read(&path).expect("read golden fixture")
}

/// A structurally valid current-VERSION (v11) header (passphrase-only: no YubiKey
/// records, empty alias, empty passphrase_blob) with a chosen 8-byte `body_len` and
/// `body`. v11 dropped the ML-KEM ciphertext + X25519 ephemeral pubkey (ADR-018), so
/// this header omits them — matching the v11 parser's layout so the attacker-chosen
/// `body_len` lands exactly at the byte offset the body-length guard reads. The
/// crypto content is all-zero — `from_bytes` only slices, it does not validate it.
fn synthetic_header(body_len: u64, body: &[u8]) -> Vec<u8> {
    let mut v = Vec::new();
    v.extend_from_slice(MAGIC); // magic (6)
    v.push(VERSION); // version (1) — current: v11, no KEM fields
    v.extend_from_slice(&[0u8; 12]); // Argon2id params (3 x u32)
    v.extend_from_slice(&[0u8; 32]); // Argon2id salt
    v.extend_from_slice(&[0u8; 32]); // HKDF salt
    v.extend_from_slice(&[0u8; 12]); // nonce
    v.push(0); // YubiKey record count = 0
    v.extend_from_slice(&0u16.to_be_bytes()); // alias length = 0 (v5+)
    v.extend_from_slice(&0u16.to_be_bytes()); // passphrase_blob length = 0 (v4+)
    v.extend_from_slice(&body_len.to_be_bytes()); // body length (8)
    v.extend_from_slice(body); // body
    v
}

#[test]
fn truncations_of_a_valid_vault_return_err_never_panic() {
    let full = golden_vault_bytes();
    // The complete file parses; every strict prefix is truncated and must be Err.
    assert!(
        SealedVault::from_bytes(&full).is_ok(),
        "golden fixture should parse"
    );
    for n in 0..full.len() {
        let res = SealedVault::from_bytes(&full[..n]);
        assert!(
            res.is_err(),
            "truncation to {n}/{} bytes parsed as Ok",
            full.len()
        );
    }
}

#[test]
fn random_garbage_returns_err_or_ok_but_never_panics() {
    let mut rng = StdRng::seed_from_u64(FIXED_SEED);
    for _ in 0..GARBAGE_CASES {
        let len = rng.gen_range(0..4096);
        let bytes: Vec<u8> = (0..len).map(|_| rng.gen::<u8>()).collect();
        // The assertion is "does not panic" — reaching the next line is the pass.
        let _ = SealedVault::from_bytes(&bytes);
    }
}

#[test]
fn oversized_body_length_returns_err_never_panics() {
    // Regression for the pos + body_len usize-overflow at file_format.rs:373.
    // A valid header with body_len near usize::MAX must be rejected cleanly.
    for body_len in [
        u64::MAX,
        u64::MAX - 1,
        u64::MAX - 4095,
        1u64 << 63,
        1u64 << 60,
        1u64 << 40,
        u32::MAX as u64,
    ] {
        let bytes = synthetic_header(body_len, &[]);
        let res = SealedVault::from_bytes(&bytes);
        assert!(
            res.is_err(),
            "body_len {body_len:#x} should be rejected as truncated, got Ok"
        );
    }
}

#[test]
fn fuzzed_body_length_against_short_buffer_never_panics() {
    // Random body_len with a real (small) body present: exercises the guard across
    // the whole u64 range, including values that wrap pos + body_len.
    let mut rng = StdRng::seed_from_u64(FIXED_SEED ^ 0xABCD);
    for _ in 0..GARBAGE_CASES {
        let body_len: u64 = rng.gen();
        let body_present = rng.gen_range(0..64);
        let body: Vec<u8> = (0..body_present).map(|_| rng.gen::<u8>()).collect();
        let bytes = synthetic_header(body_len, &body);
        let _ = SealedVault::from_bytes(&bytes);
    }
}
