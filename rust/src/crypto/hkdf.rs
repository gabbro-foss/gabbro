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
}
