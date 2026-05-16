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
}