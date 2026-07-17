//! HKDF-SHA256 key derivation for the vault.
//!
//! Two derivations live here:
//! - `derive_vault_key_v11` — the vault key, straight from the Argon2id output (ADR-018).
//! - `combine_yubikey` — folds a YubiKey's hmac-secret response into a wrapping key.
//!
//! The v2–v10 hybrid combiners (ML-KEM + X25519, labels `gabbro-hybrid-kex-v1`/`-v2`)
//! were deleted at RT-3 with the hybrid layer itself; v11 is the oldest readable format.

use hkdf::Hkdf;
use sha2::Sha256;

const INFO_YUBIKEY: &[u8] = b"gabbro-yubikey-v1";
/// VERSION 11 vault-key label (ADR-018): the vault key is derived straight from the
/// Argon2id output. Frozen — changing it bricks every v11 vault.
const INFO_VAULT_KEY_V11: &[u8] = b"gabbro-vault-key-from-argon2id-v1";

/// Derives the 32-byte vault key for VERSION 11 vaults (ADR-018), directly from the
/// Argon2id output — no X25519 + ML-KEM hybrid layer.
///
/// `km` is the full Argon2id output (the same `derive_key` call as legacy formats,
/// byte-identical; only this post-Argon2id step changes). `salt` is the random
/// 32-byte `hkdf_salt` stored in the vault header.
///
/// `vault_key = HKDF-SHA256(salt = hkdf_salt, ikm = KM, info = INFO_VAULT_KEY_V11)`.
/// Used by the passphrase-only path (as the vault key) and the multi-key path (as
/// the `intermediate_key` that wraps the `wrapping_key`).
pub fn derive_vault_key_v11(km: &[u8; 96], salt: &[u8; 32]) -> [u8; 32] {
    let hkdf = Hkdf::<Sha256>::new(Some(salt), km);

    let mut okm = [0u8; 32];
    hkdf.expand(INFO_VAULT_KEY_V11, &mut okm)
        .expect("32 bytes is a valid HKDF output length");

    okm
}

/// Combines a passphrase-derived key with YubiKey hmac-secret output into a vault key.
///
/// `passphrase_key` is the Argon2id output. `yubikey_output` is the 32-byte
/// hmac-secret response from the YubiKey. `hkdf_salt` is a random 32-byte
/// value stored in the vault header.
pub fn combine_yubikey(
    passphrase_key: &[u8; 32],
    yubikey_output: &[u8; 32],
    hkdf_salt: &[u8; 32],
) -> [u8; 32] {
    let mut ikm = [0u8; 64];
    ikm[..32].copy_from_slice(passphrase_key);
    ikm[32..].copy_from_slice(yubikey_output);

    let hkdf = Hkdf::<Sha256>::new(Some(hkdf_salt), &ikm);

    let mut okm = [0u8; 32];
    hkdf.expand(INFO_YUBIKEY, &mut okm)
        .expect("32 bytes is a valid HKDF output length");

    okm
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn combine_yubikey_returns_32_bytes() {
        let key = combine_yubikey(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn combine_yubikey_is_deterministic() {
        let a = combine_yubikey(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = combine_yubikey(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        assert_eq!(a, b);
    }

    #[test]
    fn combine_yubikey_different_passphrase_key_produces_different_output() {
        let a = combine_yubikey(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = combine_yubikey(&[9u8; 32], &[2u8; 32], &[3u8; 32]);
        assert_ne!(a, b);
    }

    #[test]
    fn combine_yubikey_different_yubikey_output_produces_different_output() {
        let a = combine_yubikey(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = combine_yubikey(&[1u8; 32], &[9u8; 32], &[3u8; 32]);
        assert_ne!(a, b);
    }

    #[test]
    fn combine_yubikey_different_salt_produces_different_output() {
        let a = combine_yubikey(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = combine_yubikey(&[1u8; 32], &[2u8; 32], &[9u8; 32]);
        assert_ne!(a, b);
    }

    // ── derive_vault_key_v11 (VERSION 11, no KEM — ADR-018) ────────────────────
    // vault_key = HKDF-SHA256(salt = hkdf_salt, ikm = KM, info = v11 label),
    // where KM is the full Argon2id output. A representative KM is 96 bytes.

    /// A1 — known-answer test. Pins the exact VERSION 11 derivation forever: if the
    /// label, hash, or input ordering ever changes, every v11 vault becomes
    /// unopenable, so the output is frozen here as a tripwire.
    #[test]
    fn v11_vault_key_known_answer() {
        let km = [0x11u8; 96];
        let salt = [0x22u8; 32];
        let key = derive_vault_key_v11(&km, &salt);
        assert_eq!(
            key,
            [
                0xD6u8, 0x67, 0xAB, 0xE3, 0xEF, 0x37, 0xA4, 0x81, 0xC1, 0x5C, 0x63, 0x2D, 0x17,
                0xCA, 0x32, 0x7C, 0x90, 0xE1, 0xCA, 0x2B, 0xD9, 0x8B, 0x8A, 0x5A, 0xBB, 0x94, 0x07,
                0xD0, 0x77, 0xF6, 0x74, 0xA2,
            ],
            "v11 vault-key derivation must never change (frozen KAT)"
        );
    }

    #[test]
    fn v11_vault_key_is_deterministic() {
        let km = [0x33u8; 96];
        let salt = [0x44u8; 32];
        assert_eq!(
            derive_vault_key_v11(&km, &salt),
            derive_vault_key_v11(&km, &salt)
        );
    }

    #[test]
    fn v11_vault_key_changes_with_km() {
        let salt = [0x44u8; 32];
        let a = derive_vault_key_v11(&[0x33u8; 96], &salt);
        let mut km2 = [0x33u8; 96];
        km2[0] ^= 0x01;
        let b = derive_vault_key_v11(&km2, &salt);
        assert_ne!(a, b, "flipping a bit in KM must change the derived key");
    }

    #[test]
    fn v11_vault_key_changes_with_salt() {
        let km = [0x33u8; 96];
        let a = derive_vault_key_v11(&km, &[0x44u8; 32]);
        let b = derive_vault_key_v11(&km, &[0x55u8; 32]);
        assert_ne!(a, b, "a different HKDF salt must change the derived key");
    }

    /// A2 — domain separation: the v11 label must not collide with the YubiKey
    /// combiner even when fed the same 32-byte material and salt.
    #[test]
    fn v11_vault_key_differs_from_yubikey_combiner() {
        let salt = [0x66u8; 32];
        let v11 = derive_vault_key_v11(&[0x77u8; 96], &salt);
        let yk = combine_yubikey(&[0x77u8; 32], &[0x77u8; 32], &salt);
        assert_ne!(v11, yk, "distinct HKDF labels must yield distinct keys");
    }
}
