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
    let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
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
    let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
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
    let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
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
            key_blob: vec![],
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
    let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
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

// ── Multi-key vault (VERSION 3, minimum 2 keys) ───────────────────────────────

/// Key material supplied at vault creation for one YubiKey.
pub struct YubiKeyRegistration {
    pub credential_id: Vec<u8>,
    pub hmac_secret: [u8; 32],
    pub salt: [u8; 32],
}

/// Encrypts plaintext under the given passphrase and two or more YubiKeys.
///
/// Generates a random `vault_key_master`; wraps it independently for each
/// key so any single registered key can later unlock the vault.
/// Returns `Err` if fewer than 2 keys are supplied.
pub fn seal_vault_with_keys(
    passphrase: &[u8],
    keys: &[YubiKeyRegistration],
    plaintext: &[u8],
) -> Result<SealedVault, String> {
    if keys.len() < 2 {
        return Err(format!("at least 2 YubiKeys required; got {}", keys.len()));
    }

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
    let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
    let intermediate_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &hkdf_salt,
    ));

    // Random master key that encrypts the vault body.
    // Each registered key gets an independent encrypted copy (key_blob).
    let mut vault_key_master = Zeroizing::new([0u8; 32]);
    OsRng.fill_bytes(&mut *vault_key_master);

    let yubikey_records = keys
        .iter()
        .map(|k| {
            let wrap_key =
                Zeroizing::new(combine_yubikey(&intermediate_key, &k.hmac_secret, &k.salt));
            let (blob_ct, blob_nonce) = aes_gcm::encrypt(&wrap_key, &vault_key_master[..])?;
            // key_blob layout: nonce (12) || ciphertext+tag (48) = 60 bytes
            let mut key_blob = Vec::with_capacity(12 + blob_ct.len());
            key_blob.extend_from_slice(&blob_nonce);
            key_blob.extend_from_slice(&blob_ct);
            Ok(YubiKeyRecord {
                credential_id: k.credential_id.clone(),
                salt: k.salt,
                key_blob,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;

    let (ciphertext, nonce) = aes_gcm::encrypt(&vault_key_master, plaintext)?;

    Ok(SealedVault {
        params,
        argon2_salt,
        hkdf_salt,
        nonce,
        ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
        x25519_ephemeral_public: *ephemeral_public.as_bytes(),
        ciphertext,
        yubikey_records,
    })
}

/// Decrypts a multi-key vault using the passphrase and one registered YubiKey.
///
/// Finds the record matching `credential_id`, unwraps the `vault_key_master`
/// from its `key_blob`, and decrypts the body.  Falls back to the legacy
/// single-key path when `key_blob` is empty (VERSION 2 vaults).
///
/// Returns `(plaintext, vault_key_master)`.  The caller should cache
/// `vault_key_master` in the session for subsequent CRUD re-seals.
pub fn open_vault_with_key_record(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: &[u8],
    sealed: &SealedVault,
) -> Result<(Vec<u8>, Zeroizing<[u8; 32]>), String> {
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
    let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
    let intermediate_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &sealed.hkdf_salt,
    ));

    let record = sealed
        .yubikey_records
        .iter()
        .find(|r| r.credential_id == credential_id)
        .ok_or_else(|| "no YubiKey record found for this credential".to_string())?;

    let wrap_key = Zeroizing::new(combine_yubikey(
        &intermediate_key,
        hmac_secret,
        &record.salt,
    ));

    if record.key_blob.is_empty() {
        // Legacy VERSION 2 single-key: body encrypted directly with wrap_key.
        let plaintext = aes_gcm::decrypt(&wrap_key, &sealed.ciphertext, &sealed.nonce)?;
        return Ok((plaintext, wrap_key));
    }

    // VERSION 3: unwrap vault_key_master from key_blob (nonce || ciphertext+tag)
    if record.key_blob.len() != 60 {
        return Err(format!(
            "invalid key_blob length: {} (expected 60)",
            record.key_blob.len()
        ));
    }
    let blob_nonce: [u8; 12] = record.key_blob[..12].try_into().unwrap();
    let blob_ct = &record.key_blob[12..];

    let master_bytes = aes_gcm::decrypt(&wrap_key, blob_ct, &blob_nonce)?;
    let vault_key_master: Zeroizing<[u8; 32]> = Zeroizing::new(
        master_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "vault_key_master must be 32 bytes".to_string())?,
    );

    let plaintext = aes_gcm::decrypt(&vault_key_master, &sealed.ciphertext, &sealed.nonce)?;
    Ok((plaintext, vault_key_master))
}

/// Re-seals a vault body using a cached `vault_key_master` and the existing header.
///
/// Used for CRUD saves in a multi-key session: the header (including all
/// `key_blob`s) stays unchanged; only the body and nonce are refreshed.
pub fn reseal_vault_body(
    sealed: &mut SealedVault,
    vault_key_master: &[u8; 32],
    plaintext: &[u8],
) -> Result<(), String> {
    let (new_ciphertext, new_nonce) = aes_gcm::encrypt(vault_key_master, plaintext)?;
    sealed.ciphertext = new_ciphertext;
    sealed.nonce = new_nonce;
    Ok(())
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

    // ── Multi-key vault (minimum 2 keys) ─────────────────────────────────────

    fn two_test_keys() -> [YubiKeyRegistration; 2] {
        [
            YubiKeyRegistration {
                credential_id: vec![0x01u8; 64],
                hmac_secret: [0x11u8; 32],
                salt: [0x22u8; 32],
            },
            YubiKeyRegistration {
                credential_id: vec![0x02u8; 48],
                hmac_secret: [0x33u8; 32],
                salt: [0x44u8; 32],
            },
        ]
    }

    #[test]
    fn seal_with_zero_keys_fails() {
        let result = seal_vault_with_keys(b"pass", &[], b"data");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("at least 2"));
    }

    #[test]
    fn seal_with_one_key_fails() {
        let key = YubiKeyRegistration {
            credential_id: vec![0x01u8; 64],
            hmac_secret: [0x11u8; 32],
            salt: [0x22u8; 32],
        };
        let result = seal_vault_with_keys(b"pass", &[key], b"data");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("at least 2"));
    }

    #[test]
    fn seal_with_two_keys_stores_two_records_with_key_blobs() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"plaintext").unwrap();
        assert_eq!(sealed.yubikey_records.len(), 2);
        assert_eq!(sealed.yubikey_records[0].key_blob.len(), 60);
        assert_eq!(sealed.yubikey_records[1].key_blob.len(), 60);
        assert_eq!(
            sealed.yubikey_records[0].credential_id,
            keys[0].credential_id
        );
        assert_eq!(
            sealed.yubikey_records[1].credential_id,
            keys[1].credential_id
        );
    }

    #[test]
    fn open_with_first_key_succeeds() {
        let keys = two_test_keys();
        let plaintext = b"my secret vault data";
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext).unwrap();
        let (recovered, _master) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn open_with_second_key_succeeds() {
        let keys = two_test_keys();
        let plaintext = b"my secret vault data";
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext).unwrap();
        let (recovered, _master) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &sealed,
        )
        .unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn open_with_wrong_hmac_fails() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data").unwrap();
        let result = open_vault_with_key_record(
            b"passphrase",
            &[0xFFu8; 32],
            &keys[0].credential_id,
            &sealed,
        );
        assert!(result.is_err());
    }

    #[test]
    fn open_with_unknown_credential_fails() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data").unwrap();
        let result = open_vault_with_key_record(b"passphrase", &[0x11u8; 32], &[0xFF; 32], &sealed);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("no YubiKey record"));
    }

    #[test]
    fn open_with_wrong_passphrase_fails() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data").unwrap();
        let result = open_vault_with_key_record(
            b"wrong-passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        );
        assert!(result.is_err());
    }

    #[test]
    fn both_keys_produce_same_plaintext() {
        let keys = two_test_keys();
        let plaintext = b"consistent decryption";
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext).unwrap();
        let (pt1, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        let (pt2, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &sealed,
        )
        .unwrap();
        assert_eq!(pt1, plaintext);
        assert_eq!(pt2, plaintext);
    }

    #[test]
    fn multi_key_roundtrip_through_bytes() {
        let keys = two_test_keys();
        let plaintext = b"roundtrip with two keys";
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext).unwrap();
        let bytes = sealed.to_bytes();
        let recovered_sealed = SealedVault::from_bytes(&bytes).unwrap();
        let (pt, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &recovered_sealed,
        )
        .unwrap();
        assert_eq!(pt, plaintext);
    }

    #[test]
    fn reseal_body_produces_decryptable_ciphertext() {
        let keys = two_test_keys();
        let plaintext = b"initial body";
        let new_plaintext = b"updated body after CRUD";
        let mut sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext).unwrap();
        let (_, master) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        reseal_vault_body(&mut sealed, &master, new_plaintext).unwrap();
        let (recovered, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &sealed,
        )
        .unwrap();
        assert_eq!(recovered, new_plaintext);
    }
}
