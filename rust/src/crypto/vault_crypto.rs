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
use crate::crypto::hkdf::{combine_yubikey, derive_vault_key, derive_vault_key_transcript_bound};
use crate::crypto::kdf::{derive_key, Argon2idParams};
use crate::crypto::keypair::X25519Keypair;
use crate::crypto::ml_kem::MlKemKeypair;
use crate::vault::file_format::{SealedVault, YubiKeyRecord, VERSION};

/// First file-format version that derives the ML-KEM keypair with FIPS 203
/// `ML-KEM.KeyGen(d, z)`. Vaults below this use the legacy `StdRng`-seeded
/// keygen and must keep doing so to remain readable (audit F-02).
const FIPS_KEYGEN_MIN_VERSION: u8 = 6;

/// First file-format version that binds the plaintext header to the encrypted
/// body via AES-256-GCM additional authenticated data (AAD).  Any modification
/// to the plaintext header of a VERSION 7+ vault causes body decryption to fail
/// with an authentication error.
const AAD_MIN_VERSION: u8 = 7;

/// First file-format version whose passphrase-only hybrid combiner folds the KEM
/// transcript (ct_M ‖ ephemeral_x25519_pub ‖ static_x25519_pub) into the HKDF
/// `info`, binding the vault key to the transcript from inside the KDF. Vaults
/// below this derive the passphrase-only key with the legacy combiner so older
/// vaults still open. YubiKey-mode derivation is unaffected at every version (F-03).
const TRANSCRIPT_BINDING_MIN_VERSION: u8 = 8;

/// First file-format version that derives the X25519 static secret directly from
/// KDF bytes [0..32] (clamp, no PRNG). Vaults below this route the derivation
/// through `rand::StdRng` (ChaCha12) and must keep doing so to remain readable
/// (RT-3). Removing the legacy path is a Release N+1 task once no <v10 vault
/// remains; see keypair.rs for the frozen-stream invariant.
const X25519_DIRECT_MIN_VERSION: u8 = 10;

/// Derives the ML-KEM keypair using the path that matches a vault's file
/// version: VERSION 6+ uses FIPS keygen, VERSION 2–5 use the legacy path so
/// vaults sealed by older builds still open. Seal paths pass [`VERSION`] (new
/// vaults are always current); open paths pass the parsed `sealed.version`.
fn ml_kem_keypair_for_version(version: u8, kdf_output: &[u8; 96]) -> MlKemKeypair {
    if version >= FIPS_KEYGEN_MIN_VERSION {
        MlKemKeypair::from_kdf_output_fips(kdf_output)
    } else {
        MlKemKeypair::from_kdf_output_legacy(kdf_output)
    }
}

/// Derives the X25519 keypair using the path that matches a vault's file version:
/// VERSION 10+ derives directly from KDF bytes [0..32] (no PRNG); VERSION 2–9 use
/// the legacy `StdRng` path so existing vaults still open. Seal paths pass
/// [`VERSION`]; open paths pass the parsed `sealed.version`.
fn x25519_keypair_for_version(version: u8, kdf_output: &[u8; 96]) -> X25519Keypair {
    if version >= X25519_DIRECT_MIN_VERSION {
        X25519Keypair::from_kdf_output_direct(kdf_output)
    } else {
        X25519Keypair::from_kdf_output_legacy(kdf_output)
    }
}

/// The version a body-only re-seal may tag a vault with (RT-3 "belt"). A body-only
/// re-seal (CRUD save with a cached `vault_key_master`) does NOT rebuild the
/// passphrase material, so it must never advance a vault ACROSS the X25519
/// derivation boundary — doing so would make the next open derive the new-style
/// key against old header material and brick the vault. It caps just below the
/// boundary until a full migration (on unlock) rebuilds the material. A vault
/// already at/past the boundary is safe to carry to the current [`VERSION`].
fn capped_reseal_version(material_version: u8) -> u8 {
    capped_reseal_version_for(material_version, VERSION)
}

fn capped_reseal_version_for(material_version: u8, current: u8) -> u8 {
    if material_version >= X25519_DIRECT_MIN_VERSION {
        current
    } else {
        current.min(X25519_DIRECT_MIN_VERSION - 1)
    }
}

/// Derives the passphrase-only vault key using the combiner that matches a
/// vault's file version: VERSION 8+ folds the KEM transcript into the HKDF `info`
/// (transcript-bound); v2–7 use the legacy combiner so older vaults still open.
/// Seal paths pass [`VERSION`]; open paths pass the parsed `sealed.version`. Only
/// the passphrase-only path (`seal_vault` / `open_vault`) uses this; YubiKey paths
/// keep `derive_vault_key` unchanged at every version.
#[allow(clippy::too_many_arguments)]
fn derive_passphrase_vault_key_for_version(
    version: u8,
    ml_kem_secret: &[u8; 32],
    x25519_secret: &[u8; 32],
    salt: &[u8; 32],
    ml_kem_ciphertext: &[u8],
    ephemeral_x25519_pub: &[u8; 32],
    static_x25519_pub: &[u8; 32],
) -> [u8; 32] {
    if version >= TRANSCRIPT_BINDING_MIN_VERSION {
        derive_vault_key_transcript_bound(
            ml_kem_secret,
            x25519_secret,
            salt,
            ml_kem_ciphertext,
            ephemeral_x25519_pub,
            static_x25519_pub,
        )
    } else {
        derive_vault_key(ml_kem_secret, x25519_secret, salt)
    }
}

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

    // Step 2: derive keypairs from passphrase
    let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params)?);
    let x25519_keypair = x25519_keypair_for_version(VERSION, &kdf_output);
    let ml_kem_keypair = ml_kem_keypair_for_version(VERSION, &kdf_output);

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
    let vault_key = Zeroizing::new(derive_passphrase_vault_key_for_version(
        VERSION,
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &hkdf_salt,
        ml_kem_ciphertext.as_ref(),
        ephemeral_public.as_bytes(),
        x25519_keypair.public.as_bytes(),
    ));

    // Step 6: AES-256-GCM encrypt, binding the plaintext header as AAD for V7+.
    // Build the partial SealedVault first (empty ciphertext) so we can compute
    // header_aad() before the body is encrypted.
    let mut sealed = SealedVault {
        version: VERSION,
        params,
        argon2_salt,
        ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
        x25519_ephemeral_public: *ephemeral_public.as_bytes(),
        hkdf_salt,
        nonce: [0u8; 12],   // placeholder — updated below
        ciphertext: vec![], // placeholder — updated below
        yubikey_records: vec![],
        alias, // bound to body via AAD — must be the final alias
        passphrase_blob: vec![],
    };
    let (ciphertext, nonce) = if VERSION >= AAD_MIN_VERSION {
        aes_gcm::encrypt_with_aad(&vault_key, plaintext, &sealed.header_aad())?
    } else {
        aes_gcm::encrypt(&vault_key, plaintext)?
    };
    sealed.ciphertext = ciphertext;
    sealed.nonce = nonce;
    Ok(sealed)
}

/// Decrypts a sealed vault using the given passphrase.
pub fn open_vault(passphrase: &[u8], sealed: &SealedVault) -> Result<Vec<u8>, String> {
    // Step 1: re-derive keypairs from passphrase
    let kdf_output = Zeroizing::new(derive_key(passphrase, &sealed.argon2_salt, &sealed.params)?);
    let x25519_keypair = x25519_keypair_for_version(sealed.version, &kdf_output);
    let ml_kem_keypair = ml_kem_keypair_for_version(sealed.version, &kdf_output);

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
    let vault_key = Zeroizing::new(derive_passphrase_vault_key_for_version(
        sealed.version,
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &sealed.hkdf_salt,
        &sealed.ml_kem_ciphertext,
        &sealed.x25519_ephemeral_public,
        x25519_keypair.public.as_bytes(),
    ));

    // Step 5: AES-256-GCM decrypt — V7+ verifies header integrity via AAD.
    if sealed.version >= AAD_MIN_VERSION {
        aes_gcm::decrypt_with_aad(
            &vault_key,
            &sealed.ciphertext,
            &sealed.nonce,
            &sealed.header_aad(),
        )
    } else {
        aes_gcm::decrypt(&vault_key, &sealed.ciphertext, &sealed.nonce)
    }
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
    alias: Option<String>,
) -> Result<SealedVault, String> {
    let params = Argon2idParams::default();

    let mut argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut argon2_salt);

    let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params)?);
    let x25519_keypair = x25519_keypair_for_version(VERSION, &kdf_output);
    let ml_kem_keypair = ml_kem_keypair_for_version(VERSION, &kdf_output);

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

    let mut sealed = SealedVault {
        version: VERSION,
        params,
        argon2_salt,
        ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
        x25519_ephemeral_public: *ephemeral_public.as_bytes(),
        hkdf_salt,
        nonce: [0u8; 12],
        ciphertext: vec![],
        yubikey_records: vec![YubiKeyRecord {
            credential_id,
            salt: yubikey_salt,
            key_blob: vec![],
        }],
        alias,
        passphrase_blob: vec![],
    };
    let (ciphertext, nonce) = if VERSION >= AAD_MIN_VERSION {
        aes_gcm::encrypt_with_aad(&vault_key, plaintext, &sealed.header_aad())?
    } else {
        aes_gcm::encrypt(&vault_key, plaintext)?
    };
    sealed.ciphertext = ciphertext;
    sealed.nonce = nonce;
    Ok(sealed)
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
    let x25519_keypair = x25519_keypair_for_version(sealed.version, &kdf_output);
    let ml_kem_keypair = ml_kem_keypair_for_version(sealed.version, &kdf_output);

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

    if sealed.version >= AAD_MIN_VERSION {
        aes_gcm::decrypt_with_aad(
            &vault_key,
            &sealed.ciphertext,
            &sealed.nonce,
            &sealed.header_aad(),
        )
    } else {
        aes_gcm::decrypt(&vault_key, &sealed.ciphertext, &sealed.nonce)
    }
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
    let x25519_keypair = x25519_keypair_for_version(VERSION, &kdf_output);
    let ml_kem_keypair = ml_kem_keypair_for_version(VERSION, &kdf_output);

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
        ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
        x25519_ephemeral_public: *ephemeral_public.as_bytes(),
        ciphertext: vec![],
        yubikey_records,
        alias,
        passphrase_blob,
    };
    let (ciphertext, nonce) = if VERSION >= AAD_MIN_VERSION {
        aes_gcm::encrypt_with_aad(&vault_key_master, plaintext, &sealed.header_aad())?
    } else {
        aes_gcm::encrypt(&vault_key_master, plaintext)?
    };
    sealed.ciphertext = ciphertext;
    sealed.nonce = nonce;
    Ok(sealed)
}

/// Decrypts a multi-key vault using the passphrase and one registered YubiKey.
///
/// VERSION 4 path (passphrase_blob present):
///   intermediate_key → decrypt passphrase_blob → wrapping_key →
///   combine_yubikey(wrapping_key, hmac, salt) → decrypt key_blob → vault_key_master → body.
///
/// Legacy VERSION 2 path (key_blob empty, passphrase_blob empty):
///   intermediate_key → combine_yubikey(intermediate_key, hmac, salt) → body.
///
/// Returns `(plaintext, vault_key_master, wrapping_key)`.  The caller should cache
/// both in the session for CRUD re-seals and future key-add operations.
/// For VERSION 2 vaults `wrapping_key` is `None` — add/remove key is not supported.
#[allow(clippy::type_complexity)]
pub fn open_vault_with_key_record(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: &[u8],
    sealed: &SealedVault,
) -> Result<(Vec<u8>, Zeroizing<[u8; 32]>, Option<Zeroizing<[u8; 32]>>), String> {
    let kdf_output = Zeroizing::new(derive_key(passphrase, &sealed.argon2_salt, &sealed.params)?);
    let x25519_keypair = x25519_keypair_for_version(sealed.version, &kdf_output);
    let ml_kem_keypair = ml_kem_keypair_for_version(sealed.version, &kdf_output);

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

    if record.key_blob.is_empty() {
        // Legacy VERSION 2 single-key: body encrypted directly with combine_yubikey(intermediate_key, ...).
        let wrap_key = Zeroizing::new(combine_yubikey(
            &intermediate_key,
            hmac_secret,
            &record.salt,
        ));
        let plaintext = if sealed.version >= AAD_MIN_VERSION {
            aes_gcm::decrypt_with_aad(
                &wrap_key,
                &sealed.ciphertext,
                &sealed.nonce,
                &sealed.header_aad(),
            )?
        } else {
            aes_gcm::decrypt(&wrap_key, &sealed.ciphertext, &sealed.nonce)?
        };
        // V2 has no separate wrapping_key — key add/remove not supported on legacy vaults.
        return Ok((plaintext, wrap_key, None));
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

    let plaintext = if sealed.version >= AAD_MIN_VERSION {
        aes_gcm::decrypt_with_aad(
            &vault_key_master,
            &sealed.ciphertext,
            &sealed.nonce,
            &sealed.header_aad(),
        )?
    } else {
        aes_gcm::decrypt(&vault_key_master, &sealed.ciphertext, &sealed.nonce)?
    };
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
/// Migrates the vault to the current VERSION on every re-seal: old vaults
/// (V2–V6) are transparently upgraded to V7 (AAD-bound body) the first time
/// a CRUD save, YubiKey add/remove, alias change, or passphrase change runs.
pub fn reseal_vault_body(
    sealed: &mut SealedVault,
    vault_key_master: &[u8; 32],
    plaintext: &[u8],
) -> Result<(), String> {
    // Migrate toward the current version, but never across the X25519 derivation
    // boundary on a body-only re-seal (see capped_reseal_version — RT-3 belt).
    sealed.version = capped_reseal_version(sealed.version);
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
    // Step 1: Re-derive intermediate_key from old passphrase and stored PQ material.
    let old_kdf = Zeroizing::new(derive_key(
        old_passphrase,
        &sealed.argon2_salt,
        &sealed.params,
    )?);
    let old_x25519 = x25519_keypair_for_version(sealed.version, &old_kdf);
    let old_ml_kem = ml_kem_keypair_for_version(sealed.version, &old_kdf);

    let ml_kem_ct_bytes: &[u8; 1568] = sealed
        .ml_kem_ciphertext
        .as_slice()
        .try_into()
        .map_err(|_| "ML-KEM ciphertext is not 1568 bytes".to_string())?;
    let ml_kem_ct = Ciphertext::<ml_kem::MlKem1024>::try_from(ml_kem_ct_bytes.as_ref())
        .map_err(|e| format!("ML-KEM ciphertext decode failed: {e:?}"))?;
    let ml_kem_secret = old_ml_kem
        .decapsulation_key
        .decapsulate(&ml_kem_ct)
        .map_err(|e| format!("ML-KEM decapsulation failed: {e:?}"))?;

    let ephemeral_public = X25519PublicKey::from(sealed.x25519_ephemeral_public);
    let x25519_secret = old_x25519.secret.diffie_hellman(&ephemeral_public);

    let ml_kem_secret_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
        (*ml_kem_secret)
            .try_into()
            .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?,
    );
    let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
    let old_intermediate_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &sealed.hkdf_salt,
    ));

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

    // Step 3: Generate fresh PQ material for the new passphrase.
    let new_params = Argon2idParams::default();
    let mut new_argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut new_argon2_salt);

    let new_kdf = Zeroizing::new(derive_key(new_passphrase, &new_argon2_salt, &new_params)?);
    // Derive the NEW passphrase material at the CURRENT version: a passphrase change
    // regenerates the whole passphrase path, so it also migrates the vault to the
    // current format (RT-3). key_blobs (under the unchanged wrapping_key) and the
    // body are preserved. The OLD material above stays at sealed.version to decrypt
    // the existing passphrase_blob.
    let new_x25519 = x25519_keypair_for_version(VERSION, &new_kdf);
    let new_ml_kem = ml_kem_keypair_for_version(VERSION, &new_kdf);

    let mut encap_rng = OsRng;
    let (new_ml_kem_ct, new_ml_kem_secret) = new_ml_kem
        .encapsulation_key
        .encapsulate(&mut encap_rng)
        .map_err(|e| format!("ML-KEM encapsulation failed: {e:?}"))?;

    let new_ephemeral_secret = EphemeralSecret::random_from_rng(OsRng);
    let new_ephemeral_public = X25519PublicKey::from(&new_ephemeral_secret);
    let new_x25519_secret = new_ephemeral_secret.diffie_hellman(&new_x25519.public);

    let mut new_hkdf_salt = [0u8; 32];
    OsRng.fill_bytes(&mut new_hkdf_salt);

    let new_ml_kem_secret_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
        (*new_ml_kem_secret)
            .try_into()
            .map_err(|_| "ML-KEM shared secret is not 32 bytes".to_string())?,
    );
    let new_x25519_secret_bytes = Zeroizing::new(*new_x25519_secret.as_bytes());
    let new_intermediate_key = Zeroizing::new(derive_vault_key(
        &new_ml_kem_secret_bytes,
        &new_x25519_secret_bytes,
        &new_hkdf_salt,
    ));

    // Step 4: Re-encrypt wrapping_key under the new passphrase.
    let (new_pb_ct, new_pb_nonce) = aes_gcm::encrypt(&new_intermediate_key, &wrapping_key[..])?;
    let mut new_passphrase_blob = Vec::with_capacity(60);
    new_passphrase_blob.extend_from_slice(&new_pb_nonce);
    new_passphrase_blob.extend_from_slice(&new_pb_ct);

    // Step 5: Return new SealedVault with fresh PQ material and passphrase_blob.
    // key_blobs, body, and alias are unchanged — vault_key_master is stable.
    Ok(SealedVault {
        version: VERSION,
        params: new_params,
        argon2_salt: new_argon2_salt,
        hkdf_salt: new_hkdf_salt,
        nonce: sealed.nonce,
        ml_kem_ciphertext: new_ml_kem_ct.to_vec(),
        x25519_ephemeral_public: *new_ephemeral_public.as_bytes(),
        ciphertext: sealed.ciphertext.clone(),
        yubikey_records: sealed.yubikey_records.clone(),
        alias: sealed.alias.clone(),
        passphrase_blob: new_passphrase_blob,
    })
}

/// Migrates a multi-key vault's passphrase-derivation material to `target_version`
/// and re-encrypts the body — WITHOUT re-tapping any YubiKey (RT-3 "braces").
///
/// Used on unlock to carry a p+YK vault across the X25519 derivation boundary. The
/// caller supplies the passphrase and the `wrapping_key`/`vault_key_master` already
/// recovered during unlock. The passphrase path (argon2 salt, X25519 at the target
/// version, ML-KEM, ephemeral, hkdf salt, `passphrase_blob`) is regenerated; the
/// `key_blob`s are preserved unchanged (they are bound to `wrapping_key`, not the PQ
/// header); the body is re-encrypted under `vault_key_master` with the new header AAD.
pub fn migrate_multikey_to_version(
    sealed: &SealedVault,
    passphrase: &[u8],
    wrapping_key: &[u8; 32],
    vault_key_master: &[u8; 32],
    plaintext: &[u8],
    target_version: u8,
) -> Result<SealedVault, String> {
    let params = Argon2idParams::default();
    let mut argon2_salt = [0u8; 32];
    OsRng.fill_bytes(&mut argon2_salt);

    let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params)?);
    let x25519_keypair = x25519_keypair_for_version(target_version, &kdf_output);
    let ml_kem_keypair = ml_kem_keypair_for_version(target_version, &kdf_output);

    let (ml_kem_ciphertext, ml_kem_secret) = ml_kem_keypair
        .encapsulation_key
        .encapsulate(&mut OsRng)
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
    // Multi-key mode uses the plain (non-transcript-bound) combiner at every
    // version, matching seal_vault_with_keys / open_vault_with_key_record.
    let intermediate_key = Zeroizing::new(derive_vault_key(
        &ml_kem_secret_bytes,
        &x25519_secret_bytes,
        &hkdf_salt,
    ));

    let (pb_ct, pb_nonce) = aes_gcm::encrypt(&intermediate_key, &wrapping_key[..])?;
    let mut passphrase_blob = Vec::with_capacity(12 + pb_ct.len());
    passphrase_blob.extend_from_slice(&pb_nonce);
    passphrase_blob.extend_from_slice(&pb_ct);

    let mut migrated = SealedVault {
        version: target_version,
        params,
        argon2_salt,
        hkdf_salt,
        nonce: [0u8; 12],
        ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
        x25519_ephemeral_public: *ephemeral_public.as_bytes(),
        ciphertext: vec![],
        yubikey_records: sealed.yubikey_records.clone(),
        alias: sealed.alias.clone(),
        passphrase_blob,
    };
    let (ciphertext, nonce) = if target_version >= AAD_MIN_VERSION {
        aes_gcm::encrypt_with_aad(vault_key_master, plaintext, &migrated.header_aad())?
    } else {
        aes_gcm::encrypt(vault_key_master, plaintext)?
    };
    migrated.ciphertext = ciphertext;
    migrated.nonce = nonce;
    Ok(migrated)
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
    fn seal_vault_produces_version_9() {
        let sealed = seal_vault(b"pass", b"data", None).unwrap();
        assert_eq!(
            sealed.version, 9,
            "new vaults are sealed as VERSION 9 (crypto identical to v8; body gains per-field change-times)"
        );
    }

    #[test]
    fn derive_passphrase_vault_key_dispatches_on_version() {
        let ml_kem = [1u8; 32];
        let x = [2u8; 32];
        let salt = [3u8; 32];
        let ct_m = vec![0x55u8; 1568];
        let eph = [0x66u8; 32];
        let stat = [0x77u8; 32];

        // v7 -> legacy combiner (transcript ignored).
        let v7 = derive_passphrase_vault_key_for_version(7, &ml_kem, &x, &salt, &ct_m, &eph, &stat);
        assert_eq!(
            v7,
            derive_vault_key(&ml_kem, &x, &salt),
            "v7 must use the legacy combiner"
        );

        // v8 -> transcript-bound combiner.
        let v8 = derive_passphrase_vault_key_for_version(8, &ml_kem, &x, &salt, &ct_m, &eph, &stat);
        assert_eq!(
            v8,
            derive_vault_key_transcript_bound(&ml_kem, &x, &salt, &ct_m, &eph, &stat),
            "v8 must use the transcript-bound combiner"
        );
        assert_ne!(
            v7, v8,
            "v7 and v8 must derive different keys from the same inputs"
        );
    }

    /// A vault sealed by a pre-FIPS build (legacy `StdRng` keygen, VERSION 5)
    /// must still open: `open_vault` dispatches the keygen on `sealed.version`.
    /// This is the backward-compatibility guarantee for existing on-disk vaults
    /// (audit F-02) — without it, every old vault would be bricked.
    #[test]
    fn legacy_version_5_vault_still_opens() {
        let passphrase = b"existing vault passphrase";
        let plaintext = b"data written by the old build";

        // Reproduce an old-build seal: legacy keygen, tagged VERSION 5.
        let params = Argon2idParams::default();
        let mut argon2_salt = [0u8; 32];
        OsRng.fill_bytes(&mut argon2_salt);
        let kdf_output = Zeroizing::new(derive_key(passphrase, &argon2_salt, &params).unwrap());
        let x25519_keypair = X25519Keypair::from_kdf_output_legacy(&kdf_output);
        let ml_kem_keypair = MlKemKeypair::from_kdf_output_legacy(&kdf_output);

        let mut encap_rng = OsRng;
        let (ml_kem_ciphertext, ml_kem_secret) = ml_kem_keypair
            .encapsulation_key
            .encapsulate(&mut encap_rng)
            .unwrap();
        let ephemeral_secret = EphemeralSecret::random_from_rng(OsRng);
        let ephemeral_public = X25519PublicKey::from(&ephemeral_secret);
        let x25519_secret = ephemeral_secret.diffie_hellman(&x25519_keypair.public);
        let mut hkdf_salt = [0u8; 32];
        OsRng.fill_bytes(&mut hkdf_salt);
        let ml_kem_secret_bytes: Zeroizing<[u8; 32]> =
            Zeroizing::new((*ml_kem_secret).try_into().unwrap());
        let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
        let vault_key = Zeroizing::new(derive_vault_key(
            &ml_kem_secret_bytes,
            &x25519_secret_bytes,
            &hkdf_salt,
        ));
        let (ciphertext, nonce) = aes_gcm::encrypt(&vault_key, plaintext).unwrap();

        let sealed = SealedVault {
            version: 5, // pre-FIPS on-disk vault
            params,
            argon2_salt,
            ml_kem_ciphertext: ml_kem_ciphertext.to_vec(),
            x25519_ephemeral_public: *ephemeral_public.as_bytes(),
            hkdf_salt,
            nonce,
            ciphertext,
            yubikey_records: vec![],
            alias: None,
            passphrase_blob: vec![],
        };

        // VERSION 5 → open_vault dispatches to the legacy keygen and decrypts.
        let recovered = open_vault(passphrase, &sealed).unwrap();
        assert_eq!(recovered, plaintext);

        // Proof the dispatch is what matters: the very same bytes tagged
        // VERSION 6 or 7 would use FIPS keygen → a different keypair → decapsulation
        // yields the wrong shared secret → decryption fails.
        let mut as_v6 = sealed.clone();
        as_v6.version = 6;
        assert!(open_vault(passphrase, &as_v6).is_err());
        let mut as_v7 = sealed.clone();
        as_v7.version = 7;
        assert!(open_vault(passphrase, &as_v7).is_err());
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
            None,
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
            None,
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
            None,
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
            None,
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
            None,
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
            None,
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
            None,
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

    /// S15 (belt): a body-only re-seal must never advance a vault across the v10
    /// X25519 boundary. Pure/version-independent so the boundary is pinned now.
    #[test]
    fn capped_reseal_version_never_crosses_the_x25519_boundary() {
        // Current build is v10.
        assert_eq!(capped_reseal_version_for(9, 10), 9, "v9 material must NOT jump to v10");
        assert_eq!(capped_reseal_version_for(6, 10), 9, "old material advances only to the boundary-1");
        assert_eq!(capped_reseal_version_for(10, 10), 10, "already-v10 material carries to current");
        assert_eq!(capped_reseal_version_for(11, 10), 10, "material ahead of current pins to current");
        // Current build is still v9 (today): behaviour is unchanged, always 9.
        assert_eq!(capped_reseal_version_for(9, 9), 9);
        assert_eq!(capped_reseal_version_for(6, 9), 9);
    }

    /// S10/S11/S12 (braces, unit level): a p+YK vault with legacy (v9 `StdRng`)
    /// material migrates ACROSS the boundary to v10 without a re-tap — key_blobs
    /// preserved, body intact, re-opens with EACH key under the v10 direct
    /// derivation. Version-independent (builds the v9 source via migration), so it
    /// holds whether the current build is v9 or v10.
    #[test]
    fn migrate_multikey_across_x25519_boundary_v9_to_v10_reopens_with_each_key() {
        let passphrase = b"multikey migration passphrase";
        let plaintext = b"multi-key body that must survive migration";
        let keys = two_test_keys();

        let sealed = seal_vault_with_keys(passphrase, &keys, plaintext, None).unwrap();
        let (_, master, wrapping) = open_vault_with_key_record(
            passphrase,
            &keys[0].hmac_secret,
            &keys[0].credential_id,
            &sealed,
        )
        .unwrap();
        let wrapping = wrapping.expect("multi-key vault yields a wrapping_key");

        // Build a legacy (v9, StdRng X25519) multi-key vault.
        let v9 =
            migrate_multikey_to_version(&sealed, passphrase, &wrapping, &master, plaintext, 9).unwrap();
        assert_eq!(v9.version, 9);
        // It opens as a genuine v9 vault (legacy derivation) with each key.
        for k in &keys {
            let (pt, _, _) =
                open_vault_with_key_record(passphrase, &k.hmac_secret, &k.credential_id, &v9).unwrap();
            assert_eq!(pt, plaintext);
        }

        // Migrate across the boundary to v10 (direct X25519) — no re-tap.
        let v10 =
            migrate_multikey_to_version(&v9, passphrase, &wrapping, &master, plaintext, 10).unwrap();
        assert_eq!(v10.version, 10);
        assert_eq!(v10.yubikey_records.len(), 2, "both key_blobs preserved");

        for k in &keys {
            let (pt, _, _) =
                open_vault_with_key_record(passphrase, &k.hmac_secret, &k.credential_id, &v10).unwrap();
            assert_eq!(pt, plaintext, "v10-migrated vault must open with each registered key");
        }
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
    fn open_vault_v6_no_aad_still_opens() {
        // Build a V6 sealed vault (legacy path, no AAD).
        use crate::crypto::hkdf::derive_vault_key;
        use crate::crypto::kdf::Argon2idParams;
        use crate::crypto::ml_kem::MlKemKeypair;
        use crate::vault::file_format::SealedVault;
        use zeroize::Zeroizing;

        let passphrase = b"v6 passphrase";
        let plaintext = b"v6 vault body";
        let params = Argon2idParams::default();
        let mut argon2_salt = [0u8; 32];
        OsRng.fill_bytes(&mut argon2_salt);
        let kdf_output = Zeroizing::new(
            crate::crypto::kdf::derive_key(passphrase, &argon2_salt, &params).unwrap(),
        );
        let x25519_keypair =
            crate::crypto::keypair::X25519Keypair::from_kdf_output_legacy(&kdf_output);
        let ml_kem_keypair = MlKemKeypair::from_kdf_output_fips(&kdf_output);
        let (ml_kem_ct, ml_kem_secret) = ml_kem_keypair
            .encapsulation_key
            .encapsulate(&mut OsRng)
            .unwrap();
        let ephemeral_secret = x25519_dalek::EphemeralSecret::random_from_rng(OsRng);
        let ephemeral_public = x25519_dalek::PublicKey::from(&ephemeral_secret);
        let x25519_secret = ephemeral_secret.diffie_hellman(&x25519_keypair.public);
        let mut hkdf_salt = [0u8; 32];
        OsRng.fill_bytes(&mut hkdf_salt);
        let ml_kem_secret_bytes: Zeroizing<[u8; 32]> =
            Zeroizing::new((*ml_kem_secret).try_into().unwrap());
        let x25519_secret_bytes = Zeroizing::new(*x25519_secret.as_bytes());
        let vault_key = Zeroizing::new(derive_vault_key(
            &ml_kem_secret_bytes,
            &x25519_secret_bytes,
            &hkdf_salt,
        ));
        let (ciphertext, nonce) = aes_gcm::encrypt(&vault_key, plaintext).unwrap();

        let sealed = SealedVault {
            version: 6,
            params,
            argon2_salt,
            ml_kem_ciphertext: ml_kem_ct.to_vec(),
            x25519_ephemeral_public: *ephemeral_public.as_bytes(),
            hkdf_salt,
            nonce,
            ciphertext,
            yubikey_records: vec![],
            alias: None,
            passphrase_blob: vec![],
        };
        let recovered = open_vault(passphrase, &sealed).unwrap();
        assert_eq!(recovered, plaintext, "V6 vault must open without AAD");
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

    #[test]
    fn truncated_ml_kem_ciphertext_returns_error_not_panic() {
        // A corrupt or truncated ML-KEM ciphertext must produce Err, not panic.
        let passphrase = b"truncated kem";
        let mut sealed = seal_vault(passphrase, b"data", None).unwrap();
        sealed.ml_kem_ciphertext.truncate(16); // was 1568 bytes; now obviously wrong
        let result = open_vault(passphrase, &sealed);
        assert!(result.is_err());
        assert!(
            result.unwrap_err().contains("1568"),
            "error should name the expected length"
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
    fn mutated_alias_breaks_v7_aad_binding() {
        // In VERSION 7+, the alias is part of the AAD.  Changing it after sealing
        // must cause decryption to fail, proving the header is cryptographically
        // bound to the body.
        let passphrase = b"pass";
        let mut sealed = seal_vault(passphrase, b"body", Some("vault-a".to_string())).unwrap();
        assert!(sealed.version >= AAD_MIN_VERSION);
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
        // In V7+ the entire plaintext header is bound as AES-GCM AAD.
        // Modifying ANY header byte (including an individual key_blob) makes
        // the body unreadable to ALL keys — not just the one whose blob was
        // changed.  This prevents a partial header-substitution attack.
        let keys = two_test_keys();
        let mut sealed =
            seal_vault_with_keys(b"passphrase", &keys, b"protected body", None).unwrap();
        assert!(sealed.version >= AAD_MIN_VERSION, "test assumes V7+");

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
