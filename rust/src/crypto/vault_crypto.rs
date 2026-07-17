//! High-level vault seal and open operations.
//!
//! Orchestrates the full crypto stack (ADR-018):
//! passphrase → Argon2id → HKDF → AES-256-GCM
//!
//! The X25519 + ML-KEM hybrid layer that v2–v10 vaults used was deleted at RT-3,
//! along with the version dispatchers that selected between derivation eras. v11 is
//! the oldest readable format, so there is exactly one derivation path here.

use rand::rngs::OsRng;
use rand::RngCore;

use zeroize::Zeroizing;

use crate::crypto::aes_gcm;
use crate::crypto::hkdf::{combine_yubikey, derive_vault_key_v11};
use crate::crypto::kdf::{derive_key, Argon2idParams};
use crate::vault::file_format::{SealedVault, YubiKeyRecord, VERSION};

/// Encrypts plaintext under the given passphrase.
///
/// `alias` is stored in the plaintext header and bound to the body via AAD —
/// it must be the final alias so that the file written to disk is immediately
/// self-consistent.  Pass `None` if no alias is required.
pub fn seal_vault(
    passphrase: &[u8],
    plaintext: &[u8],
    alias: Option<String>,
) -> Result<SealedVault, String> {
    seal_vault_with_params(passphrase, plaintext, alias, Argon2idParams::default())
}

/// Like [`seal_vault`] but with caller-chosen Argon2id cost. Production sealing
/// always uses the default; this exists only to mint the cheap-param
/// sync-test corpus (`test_data/sync_test_vaults/`).
pub(crate) fn seal_vault_with_params(
    passphrase: &[u8],
    plaintext: &[u8],
    alias: Option<String>,
    params: Argon2idParams,
) -> Result<SealedVault, String> {
    // Step 1: random salt for Argon2id
    let mut argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut argon2_salt);

    // Step 2: KM = Argon2id output (byte-identical across formats); random hkdf_salt.
    let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params)?);
    let mut hkdf_salt = [0u8; 32];
    OsRng.fill_bytes(&mut hkdf_salt);

    // Step 3: derive the vault key straight from the Argon2id output (ADR-018).
    let vault_key = Zeroizing::new(derive_vault_key_v11(&kdf_output, &hkdf_salt));

    // Step 4: AES-256-GCM encrypt, binding the plaintext header as AAD.
    // Build the partial SealedVault first (empty ciphertext) so we can compute
    // header_aad() before the body is encrypted.
    let mut sealed = SealedVault {
        version: VERSION,
        params,
        argon2_salt,
        hkdf_salt,
        nonce: [0u8; 12],   // placeholder — updated below
        ciphertext: vec![], // placeholder — updated below
        yubikey_records: vec![],
        alias, // bound to body via AAD — must be the final alias
        passphrase_blob: vec![],
    };
    let (ciphertext, nonce) =
        aes_gcm::encrypt_with_aad(&vault_key, plaintext, &sealed.header_aad())?;
    sealed.ciphertext = ciphertext;
    sealed.nonce = nonce;
    Ok(sealed)
}

/// Decrypts a sealed vault using the given passphrase.
pub fn open_vault(passphrase: &[u8], sealed: &SealedVault) -> Result<Vec<u8>, String> {
    // Step 1: KM = Argon2id output.
    let kdf_output = Zeroizing::new(derive_key(passphrase, &sealed.argon2_salt, &sealed.params)?);

    // Step 2: re-derive the vault key straight from the Argon2id output (ADR-018).
    let vault_key = Zeroizing::new(derive_vault_key_v11(&kdf_output, &sealed.hkdf_salt));

    // Step 3: AES-256-GCM decrypt — the AAD verifies header integrity.
    aes_gcm::decrypt_with_aad(
        &vault_key,
        &sealed.ciphertext,
        &sealed.nonce,
        &sealed.header_aad(),
    )
}

// ── Multi-key vault (VERSION 3, minimum 2 keys) ───────────────────────────────

/// Key material supplied at vault creation for one YubiKey.
pub struct YubiKeyRegistration {
    pub credential_id: Vec<u8>,
    pub hmac_secret: [u8; 32],
    pub salt: [u8; 32],
}

/// Encrypts plaintext under the given passphrase and two or more YubiKeys (VERSION 4).
///
/// Generates a random `wrapping_key` and a random `vault_key_master`.
/// `passphrase_blob` = AES-GCM(wrapping_key, intermediate_key) — enables
/// passphrase change without requiring all registered keys.
/// Each key's `key_blob` = AES-GCM(vault_key_master, combine_yubikey(wrapping_key, hmac_i, salt_i)).
/// Returns `Err` if fewer than 2 keys are supplied.
pub fn seal_vault_with_keys(
    passphrase: &[u8],
    keys: &[YubiKeyRegistration],
    plaintext: &[u8],
    alias: Option<String>,
) -> Result<SealedVault, String> {
    if keys.len() < 2 {
        return Err(format!("at least 2 YubiKeys required; got {}", keys.len()));
    }

    let params = Argon2idParams::default();
    let mut argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut argon2_salt);

    let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params)?);
    let mut hkdf_salt = [0u8; 32];
    OsRng.fill_bytes(&mut hkdf_salt);

    // intermediate_key is derived straight from Argon2id (ADR-018).
    let intermediate_key = Zeroizing::new(derive_vault_key_v11(&kdf_output, &hkdf_salt));

    // wrapping_key: stable random key that mediates between passphrase and YubiKeys.
    // Encrypted under intermediate_key → passphrase_blob (enables single-tap passphrase change).
    // Used in combine_yubikey instead of intermediate_key → key_blobs survive passphrase changes.
    let mut wrapping_key = Zeroizing::new([0u8; 32]);
    OsRng.fill_bytes(&mut *wrapping_key);

    let (pb_ct, pb_nonce) = aes_gcm::encrypt(&intermediate_key, &wrapping_key[..])?;
    let mut passphrase_blob = Vec::with_capacity(12 + pb_ct.len());
    passphrase_blob.extend_from_slice(&pb_nonce);
    passphrase_blob.extend_from_slice(&pb_ct);

    // vault_key_master: random key that encrypts the vault body.
    // Each registered key gets an independent encrypted copy (key_blob).
    let mut vault_key_master = Zeroizing::new([0u8; 32]);
    OsRng.fill_bytes(&mut *vault_key_master);

    let yubikey_records = keys
        .iter()
        .map(|k| {
            // wrap_key uses wrapping_key (not intermediate_key) so key_blobs are
            // independent of the passphrase and survive passphrase changes.
            let wrap_key = Zeroizing::new(combine_yubikey(&wrapping_key, &k.hmac_secret, &k.salt));
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

    let mut sealed = SealedVault {
        version: VERSION,
        params,
        argon2_salt,
        hkdf_salt,
        nonce: [0u8; 12],
        ciphertext: vec![],
        yubikey_records,
        alias,
        passphrase_blob,
    };
    let (ciphertext, nonce) =
        aes_gcm::encrypt_with_aad(&vault_key_master, plaintext, &sealed.header_aad())?;
    sealed.ciphertext = ciphertext;
    sealed.nonce = nonce;
    Ok(sealed)
}

/// Decrypts a multi-key vault (VERSION 4+, passphrase_blob present) using the
/// passphrase and one registered YubiKey:
///   intermediate_key → decrypt passphrase_blob → wrapping_key →
///   combine_yubikey(wrapping_key, hmac, salt) → decrypt key_blob → vault_key_master → body.
///
/// Returns `(plaintext, vault_key_master, wrapping_key)`.  The caller should cache
/// both in the session for CRUD re-seals and future key-add operations.
#[allow(clippy::type_complexity)]
pub fn open_vault_with_key_record(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: &[u8],
    sealed: &SealedVault,
) -> Result<(Vec<u8>, Zeroizing<[u8; 32]>, Option<Zeroizing<[u8; 32]>>), String> {
    let kdf_output = Zeroizing::new(derive_key(passphrase, &sealed.argon2_salt, &sealed.params)?);

    // intermediate_key is derived straight from Argon2id (ADR-018).
    let intermediate_key = Zeroizing::new(derive_vault_key_v11(&kdf_output, &sealed.hkdf_salt));

    let record = sealed
        .yubikey_records
        .iter()
        .find(|r| r.credential_id == credential_id)
        .ok_or_else(|| "no YubiKey record found for this credential".to_string())?;

    if record.key_blob.is_empty() {
        // Legacy VERSION 2 single-key vaults are no longer supported: no seal path
        // can produce an empty-key_blob record, so fail closed rather than open one.
        return Err("unsupported legacy single-key vault (empty key_blob)".to_string());
    }

    // VERSION 4: decrypt passphrase_blob → wrapping_key, then unwrap key_blob.
    if sealed.passphrase_blob.len() != 60 {
        return Err(format!(
            "invalid passphrase_blob length: {} (expected 60 for VERSION 4 multi-key vault)",
            sealed.passphrase_blob.len()
        ));
    }
    let pb_nonce: [u8; 12] = sealed.passphrase_blob[..12]
        .try_into()
        .expect("length checked above");
    let pb_ct = &sealed.passphrase_blob[12..];
    let wrapping_key_bytes = aes_gcm::decrypt(&intermediate_key, pb_ct, &pb_nonce)
        .map_err(|_| "decryption failed: wrong passphrase or corrupted vault".to_string())?;
    let wrapping_key: Zeroizing<[u8; 32]> = Zeroizing::new(
        wrapping_key_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "wrapping_key must be 32 bytes".to_string())?,
    );

    if record.key_blob.len() != 60 {
        return Err(format!(
            "invalid key_blob length: {} (expected 60)",
            record.key_blob.len()
        ));
    }
    let blob_nonce: [u8; 12] = record.key_blob[..12]
        .try_into()
        .expect("length checked above");
    let blob_ct = &record.key_blob[12..];

    let wrap_key = Zeroizing::new(combine_yubikey(&wrapping_key, hmac_secret, &record.salt));
    let master_bytes = aes_gcm::decrypt(&wrap_key, blob_ct, &blob_nonce)?;
    let vault_key_master: Zeroizing<[u8; 32]> = Zeroizing::new(
        master_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "vault_key_master must be 32 bytes".to_string())?,
    );

    let plaintext = aes_gcm::decrypt_with_aad(
        &vault_key_master,
        &sealed.ciphertext,
        &sealed.nonce,
        &sealed.header_aad(),
    )?;
    Ok((plaintext, vault_key_master, Some(wrapping_key)))
}

/// Add a new YubiKey record to a VERSION 4 vault without re-sealing the body.
///
/// Requires `wrapping_key` and `vault_key_master` from the active session — both
/// are cached at unlock time so the user needs only one existing-key tap to authorise.
/// Returns `Err` if the vault already has 4 keys or the credential_id is already
/// registered.
pub fn add_key_to_sealed(
    sealed: &SealedVault,
    new_cred_id: Vec<u8>,
    new_hmac: &[u8; 32],
    new_salt: [u8; 32],
    wrapping_key: &[u8; 32],
    vault_key_master: &[u8; 32],
) -> Result<SealedVault, String> {
    if sealed.yubikey_records.len() >= 4 {
        return Err(format!(
            "maximum 4 YubiKeys; vault already has {}",
            sealed.yubikey_records.len()
        ));
    }
    if sealed
        .yubikey_records
        .iter()
        .any(|r| r.credential_id == new_cred_id)
    {
        return Err("credential_id already registered in this vault".to_string());
    }
    let wrap_key = Zeroizing::new(combine_yubikey(wrapping_key, new_hmac, &new_salt));
    let (blob_ct, blob_nonce) = aes_gcm::encrypt(&wrap_key, vault_key_master)?;
    let mut key_blob = Vec::with_capacity(60);
    key_blob.extend_from_slice(&blob_nonce);
    key_blob.extend_from_slice(&blob_ct);
    let mut new_records = sealed.yubikey_records.clone();
    new_records.push(YubiKeyRecord {
        credential_id: new_cred_id,
        salt: new_salt,
        key_blob,
    });
    Ok(SealedVault {
        yubikey_records: new_records,
        ..sealed.clone()
    })
}

/// Remove a YubiKey record from a vault.
///
/// Enforces a minimum of 1 remaining record — callers that wish to enforce
/// the ADR-010 minimum-2 invariant at vault creation should do so before calling
/// this.  Returns `Err` if the credential_id is not found or only one record
/// remains.
pub fn remove_key_from_sealed(sealed: &SealedVault, cred_id: &[u8]) -> Result<SealedVault, String> {
    let pos = sealed
        .yubikey_records
        .iter()
        .position(|r| r.credential_id == cred_id)
        .ok_or_else(|| "credential_id not found in vault".to_string())?;
    if sealed.yubikey_records.len() <= 1 {
        return Err("cannot remove the last YubiKey from the vault".to_string());
    }
    let mut new_records = sealed.yubikey_records.clone();
    new_records.remove(pos);
    Ok(SealedVault {
        yubikey_records: new_records,
        ..sealed.clone()
    })
}

/// Re-seals a vault body using a cached `vault_key_master` and the existing header.
///
/// Tags the vault at the current VERSION. Safe unconditionally at floor v11: every
/// readable vault is v11+, a single derivation era, so a body-only re-seal (which
/// does not rebuild the passphrase material) can never strand the header on a
/// derivation the next open will not use.
pub fn reseal_vault_body(
    sealed: &mut SealedVault,
    vault_key_master: &[u8; 32],
    plaintext: &[u8],
) -> Result<(), String> {
    sealed.version = VERSION;
    let aad = sealed.header_aad();
    let (new_ciphertext, new_nonce) = aes_gcm::encrypt_with_aad(vault_key_master, plaintext, &aad)?;
    sealed.ciphertext = new_ciphertext;
    sealed.nonce = new_nonce;
    Ok(())
}

/// Changes the passphrase for a VERSION 4 multi-key vault.
///
/// Verifies the old passphrase by decrypting `passphrase_blob` → `wrapping_key`.
/// Generates fresh PQ material for the new passphrase, re-encrypts `wrapping_key`
/// as the new `passphrase_blob`. All `key_blob`s and the vault body are unchanged —
/// any single registered key continues to work with the new passphrase.
pub fn change_vault_passphrase_with_keys(
    sealed: &SealedVault,
    old_passphrase: &[u8],
    new_passphrase: &[u8],
) -> Result<SealedVault, String> {
    // Step 1: Re-derive the OLD intermediate_key to decrypt the existing
    // passphrase_blob — straight from Argon2id (ADR-018).
    let old_kdf = Zeroizing::new(derive_key(
        old_passphrase,
        &sealed.argon2_salt,
        &sealed.params,
    )?);
    let old_intermediate_key = Zeroizing::new(derive_vault_key_v11(&old_kdf, &sealed.hkdf_salt));

    // Step 2: Decrypt passphrase_blob → wrapping_key (verifies old passphrase).
    if sealed.passphrase_blob.len() != 60 {
        return Err(
            "vault does not support single-key passphrase change — not a VERSION 4 multi-key vault"
                .to_string(),
        );
    }
    let pb_nonce: [u8; 12] = sealed.passphrase_blob[..12]
        .try_into()
        .expect("length checked above");
    let pb_ct = &sealed.passphrase_blob[12..];
    let wrapping_key_bytes = aes_gcm::decrypt(&old_intermediate_key, pb_ct, &pb_nonce)
        .map_err(|_| "wrong passphrase".to_string())?;
    let wrapping_key: Zeroizing<[u8; 32]> = Zeroizing::new(
        wrapping_key_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "wrapping_key must be 32 bytes".to_string())?,
    );

    // Step 3: Generate fresh passphrase material.
    let new_params = Argon2idParams::default();
    let mut new_argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut new_argon2_salt);

    let new_kdf = Zeroizing::new(derive_key(new_passphrase, &new_argon2_salt, &new_params)?);
    let mut new_hkdf_salt = [0u8; 32];
    OsRng.fill_bytes(&mut new_hkdf_salt);

    // Derive the NEW passphrase material at the CURRENT version: a passphrase change
    // regenerates the whole passphrase path, so it also migrates the vault to the
    // current format. key_blobs (under the unchanged wrapping_key) and the body are
    // preserved. Derived straight from Argon2id (ADR-018).
    let new_intermediate_key = Zeroizing::new(derive_vault_key_v11(&new_kdf, &new_hkdf_salt));

    // Step 4: Re-encrypt wrapping_key under the new passphrase.
    let (new_pb_ct, new_pb_nonce) = aes_gcm::encrypt(&new_intermediate_key, &wrapping_key[..])?;
    let mut new_passphrase_blob = Vec::with_capacity(60);
    new_passphrase_blob.extend_from_slice(&new_pb_nonce);
    new_passphrase_blob.extend_from_slice(&new_pb_ct);

    // Step 5: Return new SealedVault with fresh passphrase material and passphrase_blob.
    // key_blobs, body, and alias are unchanged — vault_key_master is stable.
    Ok(SealedVault {
        version: VERSION,
        params: new_params,
        argon2_salt: new_argon2_salt,
        hkdf_salt: new_hkdf_salt,
        nonce: sealed.nonce,
        ciphertext: sealed.ciphertext.clone(),
        yubikey_records: sealed.yubikey_records.clone(),
        alias: sealed.alias.clone(),
        passphrase_blob: new_passphrase_blob,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_and_open_roundtrip() {
        let passphrase = b"correct horse battery staple";
        let plaintext = b"my secret vault contents";
        let sealed = seal_vault(passphrase, plaintext, None).unwrap();
        let recovered = open_vault(passphrase, &sealed).unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn wrong_passphrase_fails_to_open() {
        let sealed = seal_vault(b"correct passphrase", b"secret", None).unwrap();
        let result = open_vault(b"wrong passphrase", &sealed);
        assert!(result.is_err());
    }

    #[test]
    fn seal_produces_different_ciphertext_each_time() {
        let passphrase = b"passphrase";
        let plaintext = b"same plaintext";
        let a = seal_vault(passphrase, plaintext, None).unwrap();
        let b = seal_vault(passphrase, plaintext, None).unwrap();
        assert_ne!(a.ciphertext, b.ciphertext);
    }

    #[test]
    fn seal_serialize_deserialize_open_roundtrip() {
        let passphrase = b"correct horst battery staple";
        let plaintext = b"end-to-end vault file roundtrip";

        // Seal -> real crypto, real ciphertext
        let sealed = seal_vault(passphrase, plaintext, None).unwrap();

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

    #[test]
    fn seal_vault_produces_version_11() {
        let sealed = seal_vault(b"pass", b"data", None).unwrap();
        assert_eq!(
            sealed.version, 11,
            "new vaults are sealed as VERSION 11 (vault key derived straight from Argon2id)"
        );
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

    /// N5 (RT-3 net), as observable behaviour: a body-only re-seal tags the current
    /// VERSION and never invents one. This replaces the old `capped_reseal_version_for`
    /// unit test — the era cap it pinned died with the multi-era derivation, but the
    /// guarantee it protected (a re-seal never strands the header on a version the next
    /// open cannot derive) still has to hold, so it is pinned through the public API.
    #[test]
    fn reseal_body_keeps_the_vault_at_the_current_version() {
        let keys = two_test_keys();
        let plaintext = b"body re-sealed after a CRUD save";
        let mut sealed = seal_vault_with_keys(b"passphrase", &keys, b"initial", None).unwrap();
        let (_, master, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();

        reseal_vault_body(&mut sealed, &master, plaintext).unwrap();

        assert_eq!(
            sealed.version, VERSION,
            "a body-only re-seal tags the current VERSION"
        );
        let (recovered, _, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &sealed,
        )
        .unwrap();
        assert_eq!(
            recovered, plaintext,
            "the re-sealed vault still opens with every registered key"
        );
    }

    #[test]
    fn seal_with_zero_keys_fails() {
        let result = seal_vault_with_keys(b"pass", &[], b"data", None);
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
        let result = seal_vault_with_keys(b"pass", &[key], b"data", None);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("at least 2"));
    }

    #[test]
    fn seal_vault_with_keys_produces_version_11() {
        // C2: the multi-key seal path is at VERSION 11 too, not just passphrase-only
        // (seal_vault_produces_version_11).
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
        assert_eq!(
            sealed.version, 11,
            "new multi-key vaults are sealed as VERSION 11"
        );
    }

    #[test]
    fn seal_with_two_keys_stores_two_records_with_key_blobs() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"plaintext", None).unwrap();
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
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();
        let (recovered, _master, _wk) = open_vault_with_key_record(
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
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();
        let (recovered, _master, _wk) = open_vault_with_key_record(
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
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
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
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
        let result = open_vault_with_key_record(b"passphrase", &[0x11u8; 32], &[0xFF; 32], &sealed);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("no YubiKey record"));
    }

    #[test]
    fn open_with_wrong_passphrase_fails() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
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
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();
        let (pt1, _, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        let (pt2, _, _) = open_vault_with_key_record(
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
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();
        let bytes = sealed.to_bytes();
        let recovered_sealed = SealedVault::from_bytes(&bytes).unwrap();
        let (pt, _, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &recovered_sealed,
        )
        .unwrap();
        assert_eq!(pt, plaintext);
    }

    #[test]
    fn seal_with_keys_produces_passphrase_blob() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
        assert_eq!(sealed.passphrase_blob.len(), 60);
    }

    #[test]
    fn reseal_body_produces_decryptable_ciphertext() {
        let keys = two_test_keys();
        let plaintext = b"initial body";
        let new_plaintext = b"updated body after CRUD";
        let mut sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();
        let (_, master, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        reseal_vault_body(&mut sealed, &master, new_plaintext).unwrap();
        let (recovered, _, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &sealed,
        )
        .unwrap();
        assert_eq!(recovered, new_plaintext);
    }

    // ── change_vault_passphrase_with_keys ─────────────────────────────────────

    #[test]
    fn change_passphrase_with_keys_key_blobs_unchanged() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"old-pass", &keys, b"data", None).unwrap();
        let old_blobs: Vec<_> = sealed
            .yubikey_records
            .iter()
            .map(|r| r.key_blob.clone())
            .collect();

        let new_sealed =
            change_vault_passphrase_with_keys(&sealed, b"old-pass", b"new-pass").unwrap();
        let new_blobs: Vec<_> = new_sealed
            .yubikey_records
            .iter()
            .map(|r| r.key_blob.clone())
            .collect();

        assert_eq!(
            old_blobs, new_blobs,
            "key_blobs must be unchanged after passphrase change"
        );
        assert_ne!(
            sealed.passphrase_blob, new_sealed.passphrase_blob,
            "passphrase_blob must be refreshed"
        );
    }

    #[test]
    fn change_passphrase_with_keys_old_passphrase_no_longer_opens() {
        let keys = two_test_keys();
        let plaintext = b"secret";
        let sealed = seal_vault_with_keys(b"old-pass", &keys, plaintext, None).unwrap();
        let new_sealed =
            change_vault_passphrase_with_keys(&sealed, b"old-pass", b"new-pass").unwrap();

        let result = open_vault_with_key_record(
            b"old-pass",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &new_sealed,
        );
        assert!(
            result.is_err(),
            "old passphrase must no longer work after change"
        );
    }

    #[test]
    fn change_passphrase_with_keys_new_passphrase_opens_with_any_key() {
        let keys = two_test_keys();
        let plaintext = b"my vault data";
        let sealed = seal_vault_with_keys(b"old-pass", &keys, plaintext, None).unwrap();

        // Extract vault_key_master so we can re-seal the body after rotating PQ material.
        let (_, master, _) = open_vault_with_key_record(
            b"old-pass",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();

        let mut new_sealed =
            change_vault_passphrase_with_keys(&sealed, b"old-pass", b"new-pass").unwrap();

        // Re-seal body so the new header (new argon2_salt, hkdf_salt, etc.) is
        // committed as AAD — mirrors what api::vault::change_passphrase_with_keys does.
        reseal_vault_body(&mut new_sealed, &master, plaintext).unwrap();

        let (pt0, _, _) = open_vault_with_key_record(
            b"new-pass",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &new_sealed,
        )
        .unwrap();
        assert_eq!(pt0, plaintext);

        let (pt1, _, _) = open_vault_with_key_record(
            b"new-pass",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &new_sealed,
        )
        .unwrap();
        assert_eq!(pt1, plaintext);
    }

    #[test]
    fn change_passphrase_wrong_old_passphrase_fails() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"correct", &keys, b"data", None).unwrap();
        let result = change_vault_passphrase_with_keys(&sealed, b"wrong", b"new-pass");
        assert!(result.is_err());
    }

    #[test]
    fn change_passphrase_roundtrip_through_bytes() {
        let keys = two_test_keys();
        let plaintext = b"roundtrip after passphrase change";
        let sealed = seal_vault_with_keys(b"old", &keys, plaintext, None).unwrap();

        let (_, master, _) = open_vault_with_key_record(
            b"old",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();

        let mut new_sealed = change_vault_passphrase_with_keys(&sealed, b"old", b"new").unwrap();
        reseal_vault_body(&mut new_sealed, &master, plaintext).unwrap();

        // Serialize and deserialize the new sealed vault
        let bytes = new_sealed.to_bytes();
        let restored = SealedVault::from_bytes(&bytes).unwrap();

        let (pt, _, _) = open_vault_with_key_record(
            b"new",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &restored,
        )
        .unwrap();
        assert_eq!(pt, plaintext);
    }

    // ── add_key_to_sealed / remove_key_from_sealed ────────────────────────────

    #[test]
    fn add_key_to_sealed_adds_third_record() {
        let keys = two_test_keys();
        let plaintext = b"vault body";
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();

        let (_, master, wk) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        let wrapping_key = wk.unwrap();

        let new_cred_id = vec![0x03u8; 64];
        let new_hmac = [0x55u8; 32];
        let new_salt = [0x66u8; 32];

        let new_sealed = add_key_to_sealed(
            &sealed,
            new_cred_id.clone(),
            &new_hmac,
            new_salt,
            &wrapping_key,
            &master,
        )
        .unwrap();

        assert_eq!(new_sealed.yubikey_records.len(), 3);
        assert_eq!(new_sealed.yubikey_records[2].credential_id, new_cred_id);
        assert_eq!(new_sealed.yubikey_records[2].key_blob.len(), 60);
    }

    #[test]
    fn added_key_can_decrypt_vault_body() {
        let keys = two_test_keys();
        let plaintext = b"decryptable by new key";
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();

        let (_, master, wk) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        let wrapping_key = wk.unwrap();

        let new_cred_id = vec![0x03u8; 64];
        let new_hmac = [0x77u8; 32];
        let new_salt = [0x88u8; 32];

        let mut new_sealed = add_key_to_sealed(
            &sealed,
            new_cred_id.clone(),
            &new_hmac,
            new_salt,
            &wrapping_key,
            &master,
        )
        .unwrap();

        // The header changed (3 records now); re-seal so the new AAD matches.
        reseal_vault_body(&mut new_sealed, &master, plaintext).unwrap();

        let (recovered, _, _) =
            open_vault_with_key_record(b"passphrase", &new_hmac, &new_cred_id, &new_sealed)
                .unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn add_key_rejects_duplicate_credential_id() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
        let (_, master, wk) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        let wrapping_key = wk.unwrap();

        let result = add_key_to_sealed(
            &sealed,
            keys[0].credential_id.clone(),
            &keys[0].hmac_secret,
            keys[0].salt,
            &wrapping_key,
            &master,
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("already registered"));
    }

    #[test]
    fn add_key_rejects_when_at_max_four() {
        // Build a vault with 4 keys by adding them one at a time.
        let keys = two_test_keys();
        let sealed0 = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
        let (_, master, wk) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed0,
        )
        .unwrap();
        let wrapping_key = wk.unwrap();

        let sealed1 = add_key_to_sealed(
            &sealed0,
            vec![0x03u8; 64],
            &[0x33u8; 32],
            [0x44u8; 32],
            &wrapping_key,
            &master,
        )
        .unwrap();
        let sealed2 = add_key_to_sealed(
            &sealed1,
            vec![0x04u8; 64],
            &[0x55u8; 32],
            [0x66u8; 32],
            &wrapping_key,
            &master,
        )
        .unwrap();
        assert_eq!(sealed2.yubikey_records.len(), 4);

        let result = add_key_to_sealed(
            &sealed2,
            vec![0x05u8; 64],
            &[0x77u8; 32],
            [0x88u8; 32],
            &wrapping_key,
            &master,
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("maximum 4"));
    }

    #[test]
    fn remove_key_from_sealed_removes_correct_record() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();

        let new_sealed = remove_key_from_sealed(&sealed, &keys[0].credential_id).unwrap();

        assert_eq!(new_sealed.yubikey_records.len(), 1);
        assert_eq!(
            new_sealed.yubikey_records[0].credential_id,
            keys[1].credential_id
        );
    }

    #[test]
    fn remove_key_rejects_last_key() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();
        let one_key = remove_key_from_sealed(&sealed, &keys[0].credential_id).unwrap();

        let result = remove_key_from_sealed(&one_key, &keys[1].credential_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("last YubiKey"));
    }

    #[test]
    fn remove_key_rejects_unknown_credential_id() {
        let keys = two_test_keys();
        let sealed = seal_vault_with_keys(b"passphrase", &keys, b"data", None).unwrap();

        let result = remove_key_from_sealed(&sealed, &[0xFFu8; 32]);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }

    // ── VERSION 7 AAD / header-integrity tests ────────────────────────────────

    #[test]
    fn seal_vault_v7_header_tamper_detected() {
        let passphrase = b"integrity test";
        let plaintext = b"secret vault body";
        let sealed = seal_vault(passphrase, plaintext, None).unwrap();
        assert_eq!(
            sealed.version,
            crate::vault::file_format::VERSION,
            "new vaults are written at the current VERSION"
        );

        // Tamper with the alias in the serialised vault bytes.
        let mut bytes = sealed.to_bytes();
        // Find the alias length prefix (2 bytes of 0x0000 for None alias) after the
        // passphrase_blob section and flip its length to inject a fake alias byte.
        // Easier: just flip a bit in the argon2_salt (bytes 7..39).
        bytes[10] ^= 0x01;
        let tampered = crate::vault::file_format::SealedVault::from_bytes(&bytes).unwrap();
        assert!(
            open_vault(passphrase, &tampered).is_err(),
            "tampered argon2_salt must cause decryption failure via AAD mismatch"
        );
    }

    #[test]
    fn remaining_key_still_decrypts_after_removal() {
        let keys = two_test_keys();
        let plaintext = b"still readable after removal";
        let sealed = seal_vault_with_keys(b"passphrase", &keys, plaintext, None).unwrap();

        // Unlock first to obtain vault_key_master needed for re-sealing.
        let (_, master, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();

        let mut new_sealed = remove_key_from_sealed(&sealed, &keys[0].credential_id).unwrap();

        // The header changed (1 record now); re-seal so the new AAD matches.
        reseal_vault_body(&mut new_sealed, &master, plaintext).unwrap();

        let (recovered, _, _) = open_vault_with_key_record(
            b"passphrase",
            &keys[1].hmac_secret,
            &keys[1].credential_id,
            &new_sealed,
        )
        .unwrap();
        assert_eq!(recovered, plaintext);
    }

    // ── Body integrity and tamper detection ───────────────────────────────────

    #[test]
    fn tampered_ciphertext_body_is_rejected() {
        // AES-GCM auth tag must catch any modification to the encrypted body,
        // even when the plaintext header (AAD) is intact.
        let passphrase = b"integrity-check passphrase";
        let mut sealed = seal_vault(passphrase, b"secret body", None).unwrap();
        sealed.ciphertext[0] ^= 0x01;
        assert!(
            open_vault(passphrase, &sealed).is_err(),
            "bit flip in ciphertext body must be rejected by AES-GCM auth tag"
        );
    }

    // ── Alias field: storage, retrieval, and AAD binding ─────────────────────

    #[test]
    fn seal_with_alias_preserves_alias_in_header() {
        let sealed = seal_vault(b"pass", b"body", Some("my-vault".to_string())).unwrap();
        assert_eq!(sealed.alias.as_deref(), Some("my-vault"));
    }

    #[test]
    fn seal_with_alias_roundtrip_opens_correctly() {
        let passphrase = b"pass";
        let plaintext = b"aliased vault data";
        let sealed = seal_vault(passphrase, plaintext, Some("my-vault".to_string())).unwrap();
        let recovered = open_vault(passphrase, &sealed).unwrap();
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn mutated_alias_breaks_aad_binding() {
        // The alias is part of the AAD. Changing it after sealing must cause
        // decryption to fail, proving the header is cryptographically bound to
        // the body.
        let passphrase = b"pass";
        let mut sealed = seal_vault(passphrase, b"body", Some("vault-a".to_string())).unwrap();
        sealed.alias = Some("vault-b".to_string()); // tamper: change alias without resealing
        assert!(
            open_vault(passphrase, &sealed).is_err(),
            "alias mutation must break body decryption via AAD mismatch"
        );
    }

    // ── Edge cases ────────────────────────────────────────────────────────────

    #[test]
    fn empty_plaintext_roundtrip() {
        // An empty body (e.g., freshly created vault with no entries) must
        // seal and reopen without error.
        let passphrase = b"empty vault passphrase";
        let sealed = seal_vault(passphrase, b"", None).unwrap();
        let recovered = open_vault(passphrase, &sealed).unwrap();
        assert!(recovered.is_empty());
    }

    #[test]
    fn empty_passphrase_is_accepted() {
        // An empty passphrase is a user choice (weak but not forbidden).
        // The vault must seal and open without error.
        let sealed = seal_vault(b"", b"data", None).unwrap();
        let recovered = open_vault(b"", &sealed).unwrap();
        assert_eq!(recovered, b"data");
    }

    // ── Multi-key: tampered key_blob ─────────────────────────────────────────

    #[test]
    fn tampered_key_blob_fails_gracefully() {
        // A corrupt key_blob (e.g., storage error) must return Err, not
        // partial data or a panic.
        let keys = two_test_keys();
        let mut sealed = seal_vault_with_keys(b"passphrase", &keys, b"vault", None).unwrap();
        sealed.yubikey_records[0].key_blob[0] ^= 0xFF;

        let result = open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        );
        assert!(result.is_err(), "corrupted key_blob must return Err");
    }

    #[test]
    fn any_header_modification_breaks_body_decryption_for_all_keys() {
        // The entire plaintext header is bound as AES-GCM AAD. Modifying ANY
        // header byte (including an individual key_blob) makes the body unreadable
        // to ALL keys — not just the one whose blob was changed. This prevents a
        // partial header-substitution attack.
        let keys = two_test_keys();
        let mut sealed =
            seal_vault_with_keys(b"passphrase", &keys, b"protected body", None).unwrap();

        sealed.yubikey_records[0].key_blob[0] ^= 0xFF; // header changed → AAD broken

        assert!(open_vault_with_key_record(
            b"passphrase",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .is_err());
        assert!(
            open_vault_with_key_record(
                b"passphrase",
                &keys[1].hmac_secret,
                &keys[1].credential_id,
                &sealed,
            )
            .is_err(),
            "second key must also be locked out when header is modified"
        );
    }

    #[test]
    fn reseal_body_with_empty_plaintext_roundtrip() {
        let keys = two_test_keys();
        let mut sealed = seal_vault_with_keys(b"pass", &keys, b"initial", None).unwrap();
        let (_, master, _) = open_vault_with_key_record(
            b"pass",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        reseal_vault_body(&mut sealed, &master, b"").unwrap();
        let (recovered, _, _) = open_vault_with_key_record(
            b"pass",
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        assert!(recovered.is_empty());
    }
}
