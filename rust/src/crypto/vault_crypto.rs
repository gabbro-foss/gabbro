//! High-level vault seal and open operations.
//!
//! Orchestrates the full crypto stack per ADR-006:
//! passphrase → Argon2id → X25519 + ML-KEM → HKDF → AES-256-GCM

use ml_kem::Ciphertext;
use ml_kem::kem::Encapsulate;
use ml_kem::kem::Decapsulate;
use rand::RngCore;
use rand::rngs::OsRng;
use x25519_dalek::EphemeralSecret;
use x25519_dalek::PublicKey as X25519PublicKey;

use crate::crypto::aes_gcm;
use crate::crypto::hkdf::derive_vault_key;
use crate::crypto::kdf::{derive_key, Argon2idParams};
use crate::crypto::keypair::X25519Keypair;
use crate::crypto::ml_kem::MlKemKeypair;
use crate::vault::file_format::SealedVault;

/// Encrypts plaintext under the given passphrase.
pub fn seal_vault(
    passphrase: &[u8],
    plaintext: &[u8],
) -> Result<SealedVault, String> {
    let params = Argon2idParams::default();

    // Step 1: random salt for Argon2id
    let mut argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut argon2_salt);

    // Step 2: derive keypairs from passphrase
    let kdf_output = derive_key(passphrase, &argon2_salt, &params)?;
    let x25519_keypair = X25519Keypair::from_kdf_output(&kdf_output);
    let ml_kem_keypair = MlKemKeypair::from_kdf_output(&kdf_output);

    // Step 3: ML-KEM encapsulate → shared secret A
    let mut encap_rng = OsRng;
    let (ml_kem_ciphertext, ml_kem_secret) = ml_kem_keypair
        .encapsulation_key
        .encapsulate(&mut encap_rng)
        .map_err(|e| format!("ML-KEM encapsulation failed: {e:?}"))?;

    // Step 4: X25519 ephemeral key exchange → shared secret B
    let ephemeral_secret = EphemeralSecret::random_from_rng(OsRng);
    let ephemeral_public = X25519PublicKey::from(&ephemeral_secret);
    let x25519_secret = ephemeral_secret.diffie_hellman(&x25519_keypair.public);

    // Step 5: HKDF combine → vault key
    let mut hkdf_salt = [0u8; 32];
    OsRng.fill_bytes(&mut hkdf_salt);
    let ml_kem_secret_bytes: [u8; 32] = (*ml_kem_secret)
        .try_into()
        .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?;
    let x25519_secret_bytes: [u8; 32] = x25519_secret.as_bytes().clone();
    let vault_key = derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &hkdf_salt,
    );

    // Step 6: AES-256-GCM encrypt
    let (ciphertext, nonce) = aes_gcm::encrypt(&vault_key, plaintext)?;

    Ok(SealedVault {
        params,
        argon2_salt,
        ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
        x25519_ephemeral_public: *ephemeral_public.as_bytes(),
        hkdf_salt,
        nonce,
        ciphertext,
    })
}

/// Decrypts a sealed vault using the given passphrase.
pub fn open_vault(
    passphrase: &[u8],
    sealed: &SealedVault,
) -> Result<Vec<u8>, String> {
    // Step 1: re-derive keypairs from passphrase
    let kdf_output = derive_key(passphrase, &sealed.argon2_salt, &sealed.params)?;
    let x25519_keypair = X25519Keypair::from_kdf_output(&kdf_output);
    let ml_kem_keypair = MlKemKeypair::from_kdf_output(&kdf_output);

    // Step 2: ML-KEM decapsulate → shared secret A
    let ml_kem_ct_bytes: &[u8; 1568] = sealed.ml_kem_ciphertext
        .as_slice()
        .try_into()
        .map_err(|_| "ML-KEM ciphertext is not 1568 bytes".to_string())?;
    let ml_kem_ct = Ciphertext::<ml_kem::MlKem1024>::try_from(
        ml_kem_ct_bytes.as_ref()
    ).map_err(|e| format!("ML-KEM ciphertext decode failed: {e:?}"))?;
    let ml_kem_secret = ml_kem_keypair
        .decapsulation_key
        .decapsulate(&ml_kem_ct)
        .map_err(|e| format!("ML-KEM decapsulation failed: {e:?}"))?;

    // Step 3: X25519 reverse exchange → shared secret B
    let ephemeral_public = X25519PublicKey::from(sealed.x25519_ephemeral_public);
    let x25519_secret = x25519_keypair.secret.diffie_hellman(&ephemeral_public);

    // Step 4: HKDF combine → vault key
    let ml_kem_secret_bytes: [u8; 32] = (*ml_kem_secret)
        .try_into()
        .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?;
    let x25519_secret_bytes: [u8; 32] = x25519_secret.as_bytes().clone();
    let vault_key = derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &sealed.hkdf_salt,
    );

    // Step 5: AES-256-GCM decrypt
    aes_gcm::decrypt(&vault_key, &sealed.ciphertext, &sealed.nonce)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_and_open_roundtrip() {
        let passphrase = b"correct horse battery staple";
        let plaintext = b"my secret vault contents";
        let sealed = seal_vault(passphrase, plaintext).unwrap();
        let recovered = open_vault(passphrase, &sealed).unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn wrong_passphrase_fails_to_open() {
        let sealed = seal_vault(b"correct passphrase", b"secret").unwrap();
        let result = open_vault(b"wrong passphrase", &sealed);
        assert!(result.is_err());
    }

    #[test]
    fn seal_produces_different_ciphertext_each_time() {
        let passphrase = b"passphrase";
        let plaintext = b"same plaintext";
        let a = seal_vault(passphrase, plaintext).unwrap();
        let b = seal_vault(passphrase, plaintext).unwrap();
        assert_ne!(a.ciphertext, b.ciphertext);
    }
}