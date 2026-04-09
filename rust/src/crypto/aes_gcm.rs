//! AES-256-GCM authenticated encryption for the vault body.
//!
//! Encrypts and decrypts the vault body using a 32-byte key derived
//! from the HKDF combiner. The nonce is randomly generated per
//! encryption and stored in the vault header alongside the ciphertext.
//! The GCM authentication tag detects any tampering.

use aes_gcm::{Aes256Gcm, Key, Nonce};
use aes_gcm::aead::{Aead, KeyInit};
use rand::RngCore;
use rand::rngs::OsRng;

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
pub fn decrypt(
    key: &[u8; 32],
    ciphertext: &[u8],
    nonce: &[u8; 12],
) -> Result<Vec<u8>, String> {
    let key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(nonce);

    cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| "decryption failed: wrong key or tampered ciphertext".to_string())
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
}