//! High-level vault seal and open operations.
//!
//! Orchestrates the full crypto stack per ADR-006:
//! passphrase → Argon2id → X25519 + ML-KEM → HKDF → AES-256-GCM

use ml_kem::kem::Decapsulate;
use ml_kem::kem::Encapsulate;
use ml_kem::Ciphertext;
use rand::rngs::OsRng;
use rand::RngCore;
use x25519_dalek::EphemeralSecret;
use x25519_dalek::PublicKey as X25519PublicKey;

use zeroize::Zeroizing;

use crate::crypto::aes_gcm;
use crate::crypto::hkdf::{combine_yubikey, derive_vault_key};
use crate::crypto::kdf::{derive_key, Argon2idParams};
use crate::crypto::keypair::X25519Keypair;
use crate::crypto::ml_kem::MlKemKeypair;
use crate::vault::file_format::{SealedVault, YubiKeyRecord};

/// Encrypts plaintext under the given passphrase.
pub fn seal_vault(passphrase: &[u8], plaintext: &[u8]) -> Result<SealedVault, String> {
    let params = Argon2idParams::default();

    // Step 1: random salt for Argon2id
    let mut argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut argon2_salt);

    // Step 2: derive keypairs from passphrase
    let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params)?);
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
    let ml_kem_secret_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
        (*ml_kem_secret)
            .try_into()
            .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?,
    );
    let x25519_secret_bytes = Zeroizing::new(x25519_secret.as_bytes().clone());
    let vault_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &hkdf_salt,
    ));

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
        yubikey_records: vec![],
    })
}

/// Decrypts a sealed vault using the given passphrase.
pub fn open_vault(passphrase: &[u8], sealed: &SealedVault) -> Result<Vec<u8>, String> {
    // Step 1: re-derive keypairs from passphrase
    let kdf_output = Zeroizing::new(derive_key(passphrase, &sealed.argon2_salt, &sealed.params)?);
    let x25519_keypair = X25519Keypair::from_kdf_output(&kdf_output);
    let ml_kem_keypair = MlKemKeypair::from_kdf_output(&kdf_output);

    // Step 2: ML-KEM decapsulate → shared secret A
    let ml_kem_ct_bytes: &[u8; 1568] = sealed
        .ml_kem_ciphertext
        .as_slice()
        .try_into()
        .map_err(|_| "ML-KEM ciphertext is not 1568 bytes".to_string())?;
    let ml_kem_ct = Ciphertext::<ml_kem::MlKem1024>::try_from(ml_kem_ct_bytes.as_ref())
        .map_err(|e| format!("ML-KEM ciphertext decode failed: {e:?}"))?;
    let ml_kem_secret = ml_kem_keypair
        .decapsulation_key
        .decapsulate(&ml_kem_ct)
        .map_err(|e| format!("ML-KEM decapsulation failed: {e:?}"))?;

    // Step 3: X25519 reverse exchange → shared secret B
    let ephemeral_public = X25519PublicKey::from(sealed.x25519_ephemeral_public);
    let x25519_secret = x25519_keypair.secret.diffie_hellman(&ephemeral_public);

    // Step 4: HKDF combine → vault key
    let ml_kem_secret_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
        (*ml_kem_secret)
            .try_into()
            .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?,
    );
    let x25519_secret_bytes = Zeroizing::new(x25519_secret.as_bytes().clone());
    let vault_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &sealed.hkdf_salt,
    ));

    // Step 5: AES-256-GCM decrypt
    aes_gcm::decrypt(&vault_key, &sealed.ciphertext, &sealed.nonce)
}

/// Encrypts plaintext under the given passphrase and YubiKey hmac-secret.
///
/// `yubikey_salt` is stored in the vault header (`YubiKeyRecord.salt`); it is
/// also the salt used in `combine_yubikey`, so the caller must pass the same
/// value to `open_vault_with_yubikey`.
pub fn seal_vault_with_yubikey(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: Vec<u8>,
    yubikey_salt: [u8; 32],
    plaintext: &[u8],
) -> Result<SealedVault, String> {
    let params = Argon2idParams::default();

    let mut argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut argon2_salt);

    let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params)?);
    let x25519_keypair = X25519Keypair::from_kdf_output(&kdf_output);
    let ml_kem_keypair = MlKemKeypair::from_kdf_output(&kdf_output);

    let mut encap_rng = OsRng;
    let (ml_kem_ciphertext, ml_kem_secret) = ml_kem_keypair
        .encapsulation_key
        .encapsulate(&mut encap_rng)
        .map_err(|e| format!("ML-KEM encapsulation failed: {e:?}"))?;

    let ephemeral_secret = EphemeralSecret::random_from_rng(OsRng);
    let ephemeral_public = X25519PublicKey::from(&ephemeral_secret);
    let x25519_secret = ephemeral_secret.diffie_hellman(&x25519_keypair.public);

    let mut hkdf_salt = [0u8; 32];
    OsRng.fill_bytes(&mut hkdf_salt);
    let ml_kem_secret_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
        (*ml_kem_secret)
            .try_into()
            .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?,
    );
    let x25519_secret_bytes = Zeroizing::new(x25519_secret.as_bytes().clone());
    let intermediate_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &hkdf_salt,
    ));
    let vault_key = Zeroizing::new(combine_yubikey(
        &intermediate_key,
        hmac_secret,
        &yubikey_salt,
    ));

    let (ciphertext, nonce) = aes_gcm::encrypt(&vault_key, plaintext)?;

    Ok(SealedVault {
        params,
        argon2_salt,
        ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
        x25519_ephemeral_public: *ephemeral_public.as_bytes(),
        hkdf_salt,
        nonce,
        ciphertext,
        yubikey_records: vec![YubiKeyRecord {
            credential_id,
            salt: yubikey_salt,
        }],
    })
}

/// Decrypts a sealed vault using the given passphrase and YubiKey hmac-secret.
///
/// `yubikey_salt` must match `YubiKeyRecord.salt` that was used when sealing.
pub fn open_vault_with_yubikey(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    yubikey_salt: &[u8; 32],
    sealed: &SealedVault,
) -> Result<Vec<u8>, String> {
    let kdf_output = Zeroizing::new(derive_key(passphrase, &sealed.argon2_salt, &sealed.params)?);
    let x25519_keypair = X25519Keypair::from_kdf_output(&kdf_output);
    let ml_kem_keypair = MlKemKeypair::from_kdf_output(&kdf_output);

    let ml_kem_ct_bytes: &[u8; 1568] = sealed
        .ml_kem_ciphertext
        .as_slice()
        .try_into()
        .map_err(|_| "ML-KEM ciphertext is not 1568 bytes".to_string())?;
    let ml_kem_ct = Ciphertext::<ml_kem::MlKem1024>::try_from(ml_kem_ct_bytes.as_ref())
        .map_err(|e| format!("ML-KEM ciphertext decode failed: {e:?}"))?;
    let ml_kem_secret = ml_kem_keypair
        .decapsulation_key
        .decapsulate(&ml_kem_ct)
        .map_err(|e| format!("ML-KEM decapsulation failed: {e:?}"))?;

    let ephemeral_public = X25519PublicKey::from(sealed.x25519_ephemeral_public);
    let x25519_secret = x25519_keypair.secret.diffie_hellman(&ephemeral_public);

    let ml_kem_secret_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
        (*ml_kem_secret)
            .try_into()
            .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?,
    );
    let x25519_secret_bytes = Zeroizing::new(x25519_secret.as_bytes().clone());
    let intermediate_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &sealed.hkdf_salt,
    ));
    let vault_key = Zeroizing::new(combine_yubikey(
        &intermediate_key,
        hmac_secret,
        yubikey_salt,
    ));

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

    #[test]
    fn seal_serialize_deserialize_open_roundtrip() {
        let passphrase = b"correct horst battery staple";
        let plaintext = b"end-to-end vault file roundtrip";

        // Seal -> real crypto, real ciphertext
        let sealed = seal_vault(passphrase, plaintext).unwrap();

        // Serialize -> flat bytes, as written to disk
        let bytes = sealed.to_bytes();

        // Deserialize -> reconstruct SealedVault from bytes
        let recovered_sealed = SealedVault::from_bytes(&bytes)
            .expect("from_bytes should succeed on valid sealed vault");

        // Open -> decrypt with the same passphrase
        let recovered_plaintext = open_vault(passphrase, &recovered_sealed)
            .expect("open_vault should succeed after roundtrip through bytes");

        assert_eq!(recovered_plaintext, plaintext);
    }

    // ── YubiKey variants ──────────────────────────────────────────────────────

    #[test]
    fn seal_with_yubikey_open_with_yubikey_roundtrip() {
        let passphrase = b"correct horse battery staple";
        let plaintext = b"my secret vault contents";
        let hmac_secret = [0xAAu8; 32];
        let credential_id = vec![0xBBu8; 64];
        let yubikey_salt = [0xCCu8; 32];

        let sealed = seal_vault_with_yubikey(
            passphrase,
            &hmac_secret,
            credential_id,
            yubikey_salt,
            plaintext,
        )
        .unwrap();
        let recovered =
            open_vault_with_yubikey(passphrase, &hmac_secret, &yubikey_salt, &sealed).unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn wrong_hmac_secret_fails_to_open() {
        let passphrase = b"correct horse battery staple";
        let plaintext = b"secret";
        let hmac_secret = [0xAAu8; 32];
        let wrong_hmac = [0x00u8; 32];
        let credential_id = vec![0xBBu8; 64];
        let yubikey_salt = [0xCCu8; 32];

        let sealed = seal_vault_with_yubikey(
            passphrase,
            &hmac_secret,
            credential_id,
            yubikey_salt,
            plaintext,
        )
        .unwrap();
        let result = open_vault_with_yubikey(passphrase, &wrong_hmac, &yubikey_salt, &sealed);
        assert!(result.is_err());
    }

    #[test]
    fn wrong_passphrase_with_yubikey_fails() {
        let plaintext = b"secret";
        let hmac_secret = [0xAAu8; 32];
        let credential_id = vec![0xBBu8; 64];
        let yubikey_salt = [0xCCu8; 32];

        let sealed = seal_vault_with_yubikey(
            b"correct",
            &hmac_secret,
            credential_id,
            yubikey_salt,
            plaintext,
        )
        .unwrap();
        let result = open_vault_with_yubikey(b"wrong", &hmac_secret, &yubikey_salt, &sealed);
        assert!(result.is_err());
    }

    #[test]
    fn wrong_yubikey_salt_fails_to_open() {
        let passphrase = b"passphrase";
        let plaintext = b"secret";
        let hmac_secret = [0xAAu8; 32];
        let credential_id = vec![0xBBu8; 64];
        let yubikey_salt = [0xCCu8; 32];
        let wrong_salt = [0xDDu8; 32];

        let sealed = seal_vault_with_yubikey(
            passphrase,
            &hmac_secret,
            credential_id,
            yubikey_salt,
            plaintext,
        )
        .unwrap();
        let result = open_vault_with_yubikey(passphrase, &hmac_secret, &wrong_salt, &sealed);
        assert!(result.is_err());
    }

    #[test]
    fn seal_with_yubikey_stores_record_in_header() {
        let credential_id = vec![0xBBu8; 64];
        let yubikey_salt = [0xCCu8; 32];

        let sealed = seal_vault_with_yubikey(
            b"pass",
            &[0xAAu8; 32],
            credential_id.clone(),
            yubikey_salt,
            b"data",
        )
        .unwrap();

        assert_eq!(sealed.yubikey_records.len(), 1);
        assert_eq!(sealed.yubikey_records[0].credential_id, credential_id);
        assert_eq!(sealed.yubikey_records[0].salt, yubikey_salt);
    }

    #[test]
    fn seal_with_yubikey_serialize_deserialize_open_roundtrip() {
        let passphrase = b"roundtrip passphrase";
        let plaintext = b"roundtrip secret";
        let hmac_secret = [0x11u8; 32];
        let credential_id = vec![0x22u8; 64];
        let yubikey_salt = [0x33u8; 32];

        let sealed = seal_vault_with_yubikey(
            passphrase,
            &hmac_secret,
            credential_id,
            yubikey_salt,
            plaintext,
        )
        .unwrap();
        let bytes = sealed.to_bytes();
        let recovered_sealed = SealedVault::from_bytes(&bytes).unwrap();
        let recovered =
            open_vault_with_yubikey(passphrase, &hmac_secret, &yubikey_salt, &recovered_sealed)
                .unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn yubikey_vault_cannot_be_opened_without_yubikey() {
        let passphrase = b"passphrase";
        let plaintext = b"secret";
        let hmac_secret = [0xAAu8; 32];
        let credential_id = vec![0xBBu8; 64];
        let yubikey_salt = [0xCCu8; 32];

        let sealed = seal_vault_with_yubikey(
            passphrase,
            &hmac_secret,
            credential_id,
            yubikey_salt,
            plaintext,
        )
        .unwrap();
        let result = open_vault(passphrase, &sealed);
        assert!(result.is_err());
    }
}
