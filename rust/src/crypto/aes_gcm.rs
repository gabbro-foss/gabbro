//! AES-256-GCM authenticated encryption for the vault body.
//!
//! Encrypts and decrypts the vault body using a 32-byte key derived
//! from the HKDF combiner. The nonce is randomly generated per
//! encryption and stored in the vault header alongside the ciphertext.
//! The GCM authentication tag detects any tampering.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use rand::rngs::OsRng;
use rand::RngCore;

/// Encrypts plaintext with AES-256-GCM.
///
/// Returns `(ciphertext, nonce)`. The nonce is 12 bytes and must be
/// stored in the vault header — it is required for decryption.
/// A fresh random nonce is generated for every encryption operation.
pub fn encrypt(key: &[u8; 32], plaintext: &[u8]) -> Result<(Vec<u8>, [u8; 12]), String> {
    let key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(key);

    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| format!("AES-256-GCM encryption failed: {e}"))?;

    Ok((ciphertext, nonce_bytes))
}

/// Decrypts ciphertext with AES-256-GCM.
///
/// Returns the plaintext if the key and nonce are correct and the
/// authentication tag is valid. Returns `Err` if the tag fails —
/// this means either the wrong key or tampered ciphertext.
pub fn decrypt(key: &[u8; 32], ciphertext: &[u8], nonce: &[u8; 12]) -> Result<Vec<u8>, String> {
    let key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(nonce);

    cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| "decryption failed: wrong key or tampered ciphertext".to_string())
}

/// Encrypts plaintext with AES-256-GCM and additional authenticated data (AAD).
///
/// Returns `(ciphertext, nonce)`. The AAD is authenticated but not encrypted —
/// any modification to the AAD causes decryption to fail. Used for VERSION 7+
/// vaults to bind the plaintext header to the encrypted body.
pub fn encrypt_with_aad(
    key: &[u8; 32],
    plaintext: &[u8],
    aad: &[u8],
) -> Result<(Vec<u8>, [u8; 12]), String> {
    let key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(key);

    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(
            nonce,
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|e| format!("AES-256-GCM encryption failed: {e}"))?;

    Ok((ciphertext, nonce_bytes))
}

/// Decrypts ciphertext with AES-256-GCM and additional authenticated data (AAD).
///
/// Returns the plaintext only if the key, nonce, AAD, and authentication tag
/// all match. Any mismatch — wrong key, tampered ciphertext, or modified AAD —
/// returns `Err`. Used for VERSION 7+ vaults to detect plaintext-header tampering.
pub fn decrypt_with_aad(
    key: &[u8; 32],
    ciphertext: &[u8],
    nonce: &[u8; 12],
    aad: &[u8],
) -> Result<Vec<u8>, String> {
    let key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(nonce);

    cipher
        .decrypt(
            nonce,
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|_| {
            "decryption failed: wrong key, tampered ciphertext, or modified header".to_string()
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypt_and_decrypt_roundtrip() {
        let key = [1u8; 32];
        let plaintext = b"hello gabbro vault";
        let (ciphertext, nonce) = encrypt(&key, plaintext).unwrap();
        let recovered = decrypt(&key, &ciphertext, &nonce).unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn ciphertext_is_different_from_plaintext() {
        let key = [2u8; 32];
        let plaintext = b"sensitive vault data";
        let (ciphertext, _nonce) = encrypt(&key, plaintext).unwrap();
        assert_ne!(ciphertext, plaintext.to_vec());
    }

    #[test]
    fn wrong_key_fails_decryption() {
        let key = [3u8; 32];
        let wrong_key = [4u8; 32];
        let (ciphertext, nonce) = encrypt(&key, b"secret").unwrap();
        let result = decrypt(&wrong_key, &ciphertext, &nonce);
        assert!(result.is_err());
    }

    #[test]
    fn tampered_ciphertext_fails_decryption() {
        let key = [5u8; 32];
        let (mut ciphertext, nonce) = encrypt(&key, b"secret data").unwrap();
        ciphertext[0] ^= 0xff; // flip bits in first byte
        let result = decrypt(&key, &ciphertext, &nonce);
        assert!(result.is_err());
    }

    #[test]
    fn fresh_nonce_per_encryption() {
        let key = [6u8; 32];
        let (_ct1, nonce1) = encrypt(&key, b"same plaintext").unwrap();
        let (_ct2, nonce2) = encrypt(&key, b"same plaintext").unwrap();
        assert_ne!(nonce1, nonce2);
    }

    // ── AAD variants ──────────────────────────────────────────────────────────

    #[test]
    fn encrypt_with_aad_decrypt_with_aad_roundtrip() {
        let key = [7u8; 32];
        let plaintext = b"vault body with aad";
        let aad = b"vault header bytes";
        let (ciphertext, nonce) = encrypt_with_aad(&key, plaintext, aad).unwrap();
        let recovered = decrypt_with_aad(&key, &ciphertext, &nonce, aad).unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn wrong_aad_fails_decryption() {
        let key = [8u8; 32];
        let (ciphertext, nonce) = encrypt_with_aad(&key, b"secret", b"correct aad").unwrap();
        let result = decrypt_with_aad(&key, &ciphertext, &nonce, b"wrong aad");
        assert!(result.is_err());
    }

    #[test]
    fn tampered_ciphertext_fails_with_aad() {
        let key = [9u8; 32];
        let aad = b"header";
        let (mut ciphertext, nonce) = encrypt_with_aad(&key, b"plaintext", aad).unwrap();
        ciphertext[0] ^= 0xff;
        assert!(decrypt_with_aad(&key, &ciphertext, &nonce, aad).is_err());
    }

    #[test]
    fn empty_aad_behaves_like_no_aad_when_matched() {
        let key = [10u8; 32];
        let (ciphertext, nonce) = encrypt_with_aad(&key, b"data", b"").unwrap();
        let recovered = decrypt_with_aad(&key, &ciphertext, &nonce, b"").unwrap();
        assert_eq!(recovered, b"data");
    }
}
