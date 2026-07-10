//! HKDF-SHA256 combiner for hybrid key exchange.
//!
//! Takes the shared secrets from ML-KEM and X25519 and derives a
//! single 32-byte vault encryption key per ADR-006 Decision 2.
//!
//! ikm  = ml_kem_shared_secret ∥ x25519_shared_secret
//! info = b"gabbro-hybrid-kex-v1"
//! salt = random 32 bytes (stored in vault header)

use hkdf::Hkdf;
use sha2::Sha256;

const INFO: &[u8] = b"gabbro-hybrid-kex-v1";
/// VERSION 8+ passphrase-only label. The combiner additionally folds the KEM
/// transcript into the HKDF info — see `derive_vault_key_transcript_bound`.
const INFO_V2: &[u8] = b"gabbro-hybrid-kex-v2";
const INFO_YUBIKEY: &[u8] = b"gabbro-yubikey-v1";
/// VERSION 11 vault-key label (ADR-018): the vault key is derived straight from the
/// Argon2id output, with no X25519 + ML-KEM layer. Distinct family name from the
/// hybrid-kex / yubikey labels above. Frozen — changing it bricks every v11 vault.
const INFO_VAULT_KEY_V11: &[u8] = b"gabbro-vault-key-from-argon2id-v1";

/// Derives a 32-byte vault encryption key from two shared secrets.
///
/// `ml_kem_secret` and `x25519_secret` are the shared secrets from
/// their respective key exchange operations. `salt` is a random
/// 32-byte value stored in the vault header.
pub fn derive_vault_key(
    ml_kem_secret: &[u8; 32],
    x25519_secret: &[u8; 32],
    salt: &[u8; 32],
) -> [u8; 32] {
    let mut ikm = [0u8; 64];
    ikm[..32].copy_from_slice(ml_kem_secret);
    ikm[32..].copy_from_slice(x25519_secret);

    let hkdf = Hkdf::<Sha256>::new(Some(salt), &ikm);

    let mut okm = [0u8; 32];
    hkdf.expand(INFO, &mut okm)
        .expect("32 bytes is a valid HKDF output length");

    okm
}

/// Derives a 32-byte vault key, transcript-bound (VERSION 8+, passphrase-only).
///
/// Same `ikm = ml_kem_secret ‖ x25519_secret` as [`derive_vault_key`], but the
/// HKDF `info` additionally folds in the KEM transcript: the ML-KEM ciphertext
/// (`ct_M`), the ephemeral X25519 public key, and the static (passphrase-derived)
/// X25519 public key. This binds the derived key to the transcript from inside the
/// KDF, not only via the AES-GCM AAD. `ct_M` and the ephemeral pubkey are also
/// AAD-bound; the static pubkey is the field the AAD cannot bind (it is not stored
/// in the file).
///
/// Used only on the passphrase-only path (`seal_vault` / `open_vault`); the
/// YubiKey paths keep [`derive_vault_key`] unchanged.
pub fn derive_vault_key_transcript_bound(
    ml_kem_secret: &[u8; 32],
    x25519_secret: &[u8; 32],
    salt: &[u8; 32],
    ml_kem_ciphertext: &[u8],
    ephemeral_x25519_pub: &[u8; 32],
    static_x25519_pub: &[u8; 32],
) -> [u8; 32] {
    let mut ikm = [0u8; 64];
    ikm[..32].copy_from_slice(ml_kem_secret);
    ikm[32..].copy_from_slice(x25519_secret);

    // info = label ‖ ct_M ‖ ephemeral_pub ‖ static_pub. All fields are
    // fixed-length (ct_M is 1568 bytes for ML-KEM-1024, each pubkey is 32),
    // so plain concatenation is unambiguous.
    let mut info = Vec::with_capacity(INFO_V2.len() + ml_kem_ciphertext.len() + 64);
    info.extend_from_slice(INFO_V2);
    info.extend_from_slice(ml_kem_ciphertext);
    info.extend_from_slice(ephemeral_x25519_pub);
    info.extend_from_slice(static_x25519_pub);

    let hkdf = Hkdf::<Sha256>::new(Some(salt), &ikm);

    let mut okm = [0u8; 32];
    hkdf.expand(&info, &mut okm)
        .expect("32 bytes is a valid HKDF output length");

    okm
}

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
    fn derive_vault_key_returns_32_bytes() {
        let key = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn derive_vault_key_is_deterministic() {
        let a = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        assert_eq!(a, b);
    }

    #[test]
    fn different_ml_kem_secrets_produce_different_keys() {
        let a = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = derive_vault_key(&[9u8; 32], &[2u8; 32], &[3u8; 32]);
        assert_ne!(a, b);
    }

    #[test]
    fn different_x25519_secrets_produce_different_keys() {
        let a = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = derive_vault_key(&[1u8; 32], &[9u8; 32], &[3u8; 32]);
        assert_ne!(a, b);
    }

    #[test]
    fn different_salts_produce_different_keys() {
        let a = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = derive_vault_key(&[1u8; 32], &[2u8; 32], &[9u8; 32]);
        assert_ne!(a, b);
    }

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
    fn combine_yubikey_differs_from_derive_vault_key() {
        let a = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let b = combine_yubikey(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        assert_ne!(a, b);
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

    // ── derive_vault_key_transcript_bound (VERSION 8, passphrase-only) ─────────
    // Folds the KEM transcript (ct_M ‖ ephemeral_pub ‖ static_pub) into the HKDF
    // info so the derived key is transcript-bound from inside the KDF.

    /// Representative transcript: ct_M is 1568 bytes for ML-KEM-1024; the two
    /// X25519 public keys are 32 bytes each.
    fn sample_transcript() -> (Vec<u8>, [u8; 32], [u8; 32]) {
        (vec![0x55u8; 1568], [0x66u8; 32], [0x77u8; 32])
    }

    #[test]
    fn transcript_bound_differs_from_legacy() {
        let (ct_m, eph, stat) = sample_transcript();
        let legacy = derive_vault_key(&[1u8; 32], &[2u8; 32], &[3u8; 32]);
        let bound = derive_vault_key_transcript_bound(
            &[1u8; 32], &[2u8; 32], &[3u8; 32], &ct_m, &eph, &stat,
        );
        assert_ne!(
            legacy, bound,
            "transcript-bound recipe must differ from the legacy recipe for the same secrets+salt"
        );
    }

    #[test]
    fn transcript_binding_changes_with_ct_m() {
        let (ct_m, eph, stat) = sample_transcript();
        let a = derive_vault_key_transcript_bound(
            &[1u8; 32], &[2u8; 32], &[3u8; 32], &ct_m, &eph, &stat,
        );
        let mut ct_m2 = ct_m.clone();
        ct_m2[0] ^= 0x01;
        let b = derive_vault_key_transcript_bound(
            &[1u8; 32], &[2u8; 32], &[3u8; 32], &ct_m2, &eph, &stat,
        );
        assert_ne!(a, b, "flipping a bit in ct_M must change the derived key");
    }

    #[test]
    fn transcript_binding_changes_with_ephemeral_pub() {
        let (ct_m, eph, stat) = sample_transcript();
        let a = derive_vault_key_transcript_bound(
            &[1u8; 32], &[2u8; 32], &[3u8; 32], &ct_m, &eph, &stat,
        );
        let mut eph2 = eph;
        eph2[0] ^= 0x01;
        let b = derive_vault_key_transcript_bound(
            &[1u8; 32], &[2u8; 32], &[3u8; 32], &ct_m, &eph2, &stat,
        );
        assert_ne!(
            a, b,
            "flipping a bit in the ephemeral X25519 pubkey must change the derived key"
        );
    }

    #[test]
    fn transcript_binding_changes_with_static_pub() {
        let (ct_m, eph, stat) = sample_transcript();
        let a = derive_vault_key_transcript_bound(
            &[1u8; 32], &[2u8; 32], &[3u8; 32], &ct_m, &eph, &stat,
        );
        let mut stat2 = stat;
        stat2[0] ^= 0x01;
        let b = derive_vault_key_transcript_bound(
            &[1u8; 32], &[2u8; 32], &[3u8; 32], &ct_m, &eph, &stat2,
        );
        assert_ne!(
            a, b,
            "flipping a bit in the static X25519 pubkey must change the derived key"
        );
    }

    #[test]
    fn transcript_bound_is_deterministic() {
        let (ct_m, eph, stat) = sample_transcript();
        let a = derive_vault_key_transcript_bound(
            &[9u8; 32], &[8u8; 32], &[7u8; 32], &ct_m, &eph, &stat,
        );
        let b = derive_vault_key_transcript_bound(
            &[9u8; 32], &[8u8; 32], &[7u8; 32], &ct_m, &eph, &stat,
        );
        assert_eq!(a, b, "same inputs must derive the same key");
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
