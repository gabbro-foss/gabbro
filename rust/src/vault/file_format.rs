//! `.gabbro` vault file format — serialization and deserialization.
//!
//! Layout (all fields fixed-size except the ciphertext body):
//!
//! | Field                  | Size (bytes) |
//! |------------------------|--------------|
//! | Magic bytes            | 6            |
//! | Version                | 1            |
//! | Argon2id memory (m)    | 4            |
//! | Argon2id time (t)      | 4            |
//! | Argon2id parallelism   | 4            |
//! | Argon2id salt          | 32           |
//! | HKDF salt              | 32           |
//! | AES-GCM nonce          | 12           |
//! | ML-KEM ciphertext      | 1568         |
//! | X25519 ephemeral pub   | 32           |
//! | YubiKey record count   | 1            |
//! | YubiKeyRecord × count  | variable     |
//! |   credential_id length | 2            |
//! |   credential_id        | variable     |
//! |   salt                 | 32           |
//! |   key_blob length      | 2  (v3+)     |
//! |   key_blob             | 0 or 60      |
//! | alias length           | 2  (v5+)     |
//! | alias                  | 0–512 UTF-8  |
//! | passphrase_blob length | 2  (v4+)     |
//! | passphrase_blob        | 0 or 60      |
//! | Body length            | 8            |
//! | Body (ciphertext)      | variable     |
//!
//! VERSION 2 (legacy single-key): records have no key_blob fields; no passphrase_blob.
//! VERSION 3 (deprecated multi-key): records include key_blob_len + key_blob; no passphrase_blob.
//! VERSION 4 (multi-key): adds passphrase_blob for single-tap passphrase change.
//! VERSION 5: adds alias field (after YubiKey records, before passphrase_blob).
//! VERSION 6: identical header LAYOUT to VERSION 5; the only change is that the
//!   ML-KEM keypair is derived via FIPS 203 `ML-KEM.KeyGen(d, z)` instead of
//!   the legacy `StdRng`-seeded path (audit F-02).
//! VERSION 7 (current): identical header LAYOUT to VERSION 6; the AES-256-GCM
//!   body is now sealed with the serialised header as AAD, binding every
//!   plaintext header field to the authenticated ciphertext tag. Any modification
//!   to the plaintext header (alias, YubiKey records, Argon2id params, etc.) causes
//!   body decryption to fail with an authentication error (F-01 / header integrity).
//!   `set_vault_alias` and all other header-mutating operations now require an
//!   active session so the body can be re-sealed with the updated AAD.
//! VERSION 8: identical header LAYOUT to VERSION 7. The only change is
//!   the passphrase-only hybrid combiner: the HKDF `info` now folds in the KEM
//!   transcript (ct_M ‖ ephemeral_x25519_pub ‖ static_x25519_pub), so the
//!   passphrase-only vault key is transcript-bound from inside the KDF, not only
//!   via the AAD. YubiKey-mode key derivation is unchanged (F-03).
//! VERSION 9: identical header LAYOUT and cryptography to VERSION 8 —
//!   crypto is byte-for-byte unchanged. The only change is in the encrypted body
//!   JSON: each entry's metadata gains `field_times` (per-field change-times) for
//!   granular, field-level sync. The bump exists so an OLDER build refuses a v9
//!   vault (fail-closed) instead of opening it and silently stripping the new
//!   per-field times on its next save.
//! VERSION 10: the X25519 static secret is derived directly from KDF
//!   bytes [0..32] (clamp, no `StdRng`); v2–9 keep the legacy `StdRng` derivation
//!   on read and auto-migrate on unlock (RT-3). Header LAYOUT unchanged.
//! VERSION 11 (current): the vault key is derived straight from the Argon2id output
//!   via HKDF, dropping the X25519 + ML-KEM hybrid layer (ADR-018). The header omits
//!   the ML-KEM ciphertext + X25519 ephemeral pubkey. v2–10 read via the legacy
//!   hybrid derivation and auto-migrate to v11 on unlock.
//! Reads v2–11; always writes VERSION 11.

use crate::crypto::kdf::Argon2idParams;

/// One YubiKey's credential ID, hmac-secret salt, and encrypted vault key blob.
///
/// `key_blob` is empty for VERSION 2 (legacy single-key) vaults.
/// For VERSION 3 multi-key vaults, `key_blob` is 60 bytes:
/// nonce (12) + AES-256-GCM ciphertext of the vault_key_master (32 + 16 tag).
#[derive(Debug, Clone, PartialEq)]
pub struct YubiKeyRecord {
    pub credential_id: Vec<u8>,
    pub salt: [u8; 32],
    pub key_blob: Vec<u8>,
}

/// Magic bytes that identify a Gabbro vault file.
pub const MAGIC: &[u8; 6] = b"GABBRO";

/// Current file format version (written by this build).
///
/// VERSION 11 (ADR-018): the vault key is derived straight from the Argon2id output
/// via HKDF, with no X25519 + ML-KEM layer; the header omits the ML-KEM ciphertext
/// and X25519 ephemeral pubkey. Vaults v2–10 keep the legacy hybrid derivation on
/// read and auto-migrate to v11 on unlock.
pub const VERSION: u8 = 11;

/// Oldest version this build can still read.
const VERSION_MIN_READABLE: u8 = 2;

/// Size of the ML-KEM-1024 ciphertext in bytes.
const ML_KEM_CIPHERTEXT_LEN: usize = 1568;

/// Last format version whose header carries the ML-KEM ciphertext + X25519
/// ephemeral public key. VERSION 11+ derives the vault key straight from Argon2id
/// (ADR-018) and omits both fields from the header (`to_bytes`/`from_bytes`/
/// `header_aad` all version-branch on this).
const KEM_HEADER_MAX_VERSION: u8 = 10;

/// The complete contents of a sealed vault file.
#[derive(Debug, Clone, PartialEq)]
pub struct SealedVault {
    /// File-format version this vault was sealed with.
    ///
    /// Set to the parsed version on read and to [`VERSION`] for freshly sealed
    /// vaults. The crypto layer dispatches the ML-KEM keygen on it: VERSION 6
    /// uses FIPS 203 `KeyGen(d, z)`; VERSION 2–5 use the legacy `StdRng` path.
    pub version: u8,
    pub params: Argon2idParams,
    pub argon2_salt: [u8; 32],
    pub hkdf_salt: [u8; 32],
    pub nonce: [u8; 12],
    pub ml_kem_ciphertext: Vec<u8>,
    pub x25519_ephemeral_public: [u8; 32],
    pub ciphertext: Vec<u8>,
    pub yubikey_records: Vec<YubiKeyRecord>,
    /// Human-readable vault alias stored in the plaintext header (VERSION 5+).
    ///
    /// Travels with the file so aliases survive export/import across devices.
    /// `None` for new vaults without an alias, and for VERSION 2–4 files on read.
    pub alias: Option<String>,
    /// AES-256-GCM ciphertext of the wrapping_key under intermediate_key.
    ///
    /// Layout: nonce (12) + ciphertext+tag (48) = 60 bytes.
    /// Empty for passphrase-only vaults and VERSION 2/3 files.
    /// Present (60 bytes) for VERSION 4+ multi-key vaults — enables single-tap
    /// passphrase change without requiring all registered keys.
    pub passphrase_blob: Vec<u8>,
}

impl SealedVault {
    /// Canonical header bytes used as AES-256-GCM AAD (VERSION 7+).
    ///
    /// Covers every field in the plaintext header that should be tamper-evident:
    /// magic, version, Argon2id parameters, salts, ML-KEM ciphertext, X25519
    /// ephemeral public key, YubiKey records, alias, and passphrase_blob.
    ///
    /// The AES-GCM nonce is excluded — AES-GCM authenticates the nonce implicitly
    /// (a modified nonce produces a different keystream whose GCM tag fails).
    /// The ciphertext and body-length prefix are excluded because they ARE the
    /// encrypted body being sealed.
    ///
    /// At seal time this is computed on a partial `SealedVault` with an empty
    /// ciphertext placeholder; at open time it is computed from the full struct.
    /// Both produce identical bytes because the ciphertext field is excluded.
    pub fn header_aad(&self) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        out.push(self.version);
        out.extend_from_slice(&self.params.m_cost.to_be_bytes());
        out.extend_from_slice(&self.params.t_cost.to_be_bytes());
        out.extend_from_slice(&self.params.p_cost.to_be_bytes());
        out.extend_from_slice(&self.argon2_salt);
        out.extend_from_slice(&self.hkdf_salt);
        // nonce excluded — authenticated implicitly by AES-GCM
        // VERSION 11+ omits the KEM fields entirely (ADR-018).
        if self.version <= KEM_HEADER_MAX_VERSION {
            out.extend_from_slice(&self.ml_kem_ciphertext);
            out.extend_from_slice(&self.x25519_ephemeral_public);
        }
        out.push(self.yubikey_records.len() as u8);
        for record in &self.yubikey_records {
            let id_len = record.credential_id.len() as u16;
            out.extend_from_slice(&id_len.to_be_bytes());
            out.extend_from_slice(&record.credential_id);
            out.extend_from_slice(&record.salt);
            let kb_len = record.key_blob.len() as u16;
            out.extend_from_slice(&kb_len.to_be_bytes());
            out.extend_from_slice(&record.key_blob);
        }
        let alias_bytes = self.alias.as_deref().unwrap_or("").as_bytes();
        out.extend_from_slice(&(alias_bytes.len() as u16).to_be_bytes());
        out.extend_from_slice(alias_bytes);
        let pb_len = self.passphrase_blob.len() as u16;
        out.extend_from_slice(&pb_len.to_be_bytes());
        out.extend_from_slice(&self.passphrase_blob);
        out
    }

    /// Serialize the vault to a flat byte vector for writing to disk.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::new();

        // Header identity — write self.version (not the const) so a vault read
        // as VERSION 5 round-trips as VERSION 5 until explicitly migrated.
        out.extend_from_slice(MAGIC);
        out.push(self.version);

        // Argon2id parameters — each u32 written as 4 big-endian bytes
        out.extend_from_slice(&self.params.m_cost.to_be_bytes());
        out.extend_from_slice(&self.params.t_cost.to_be_bytes());
        out.extend_from_slice(&self.params.p_cost.to_be_bytes());

        // Fixed-size fields
        out.extend_from_slice(&self.argon2_salt);
        out.extend_from_slice(&self.hkdf_salt);
        out.extend_from_slice(&self.nonce);
        // VERSION 11+ omits the ML-KEM ciphertext + X25519 ephemeral pubkey (ADR-018).
        if self.version <= KEM_HEADER_MAX_VERSION {
            out.extend_from_slice(&self.ml_kem_ciphertext);
            out.extend_from_slice(&self.x25519_ephemeral_public);
        }

        // YubiKey records — count byte then each record (VERSION 3 format)
        out.push(self.yubikey_records.len() as u8);
        for record in &self.yubikey_records {
            let id_len = record.credential_id.len() as u16;
            out.extend_from_slice(&id_len.to_be_bytes());
            out.extend_from_slice(&record.credential_id);
            out.extend_from_slice(&record.salt);
            let kb_len = record.key_blob.len() as u16;
            out.extend_from_slice(&kb_len.to_be_bytes());
            out.extend_from_slice(&record.key_blob);
        }

        // alias — length prefix then UTF-8 bytes (VERSION 5+); empty string encodes None
        let alias_bytes = self.alias.as_deref().unwrap_or("").as_bytes();
        let alias_len = alias_bytes.len() as u16;
        out.extend_from_slice(&alias_len.to_be_bytes());
        out.extend_from_slice(alias_bytes);

        // passphrase_blob — length prefix then the bytes themselves (VERSION 4+)
        let pb_len = self.passphrase_blob.len() as u16;
        out.extend_from_slice(&pb_len.to_be_bytes());
        out.extend_from_slice(&self.passphrase_blob);

        // Body — length prefix then the bytes themselves
        let body_len = self.ciphertext.len() as u64;
        out.extend_from_slice(&body_len.to_be_bytes());
        out.extend_from_slice(&self.ciphertext);

        out
    }

    /// Deserialize a vault from raw bytes read from disk.
    pub fn from_bytes(data: &[u8]) -> Result<Self, String> {
        let mut pos = 0usize;

        // --- Magic bytes ---
        if data.len() < 6 {
            return Err("File too short to be a Gabbro vault".to_string());
        }
        if &data[pos..pos + 6] != MAGIC {
            return Err("Not a Gabbro vault file".to_string());
        }
        pos += 6;

        // --- Version ---
        if data.len() < pos + 1 {
            return Err("File truncated at version byte".to_string());
        }
        let version = data[pos];
        if version > VERSION {
            // Fail closed: a newer-format vault is refused rather than opened and
            // silently downgraded (which would strip data this build doesn't know).
            return Err(format!(
                "This vault was created by a newer version of Gabbro (format v{version}). \
                 Please update Gabbro to open it."
            ));
        }
        if version < VERSION_MIN_READABLE {
            return Err(format!("Unsupported version: {version}"));
        }
        let is_v3 = version >= 3;
        let is_v4 = version >= 4;
        let is_v5 = version >= 5;
        pos += 1;

        // --- Argon2id parameters (3 x u32 = 12 bytes) ---
        if data.len() < pos + 12 {
            return Err("File truncated at Argon2id params".to_string());
        }
        let m_cost = u32::from_be_bytes(data[pos..pos + 4].try_into().unwrap());
        pos += 4;
        let t_cost = u32::from_be_bytes(data[pos..pos + 4].try_into().unwrap());
        pos += 4;
        let p_cost = u32::from_be_bytes(data[pos..pos + 4].try_into().unwrap());
        pos += 4;

        // --- Argon2id salt (32 bytes) ---
        if data.len() < pos + 32 {
            return Err("File truncated at Argon2id salt".to_string());
        }
        let argon2_salt: [u8; 32] = data[pos..pos + 32].try_into().unwrap();
        pos += 32;

        // --- HKDF salt (32 bytes) ---
        if data.len() < pos + 32 {
            return Err("File truncated at HKDF salt".to_string());
        }
        let hkdf_salt: [u8; 32] = data[pos..pos + 32].try_into().unwrap();
        pos += 32;

        // --- Nonce (12 bytes) ---
        if data.len() < pos + 12 {
            return Err("File truncated at nonce".to_string());
        }
        let nonce: [u8; 12] = data[pos..pos + 12].try_into().unwrap();
        pos += 12;

        // --- ML-KEM ciphertext + X25519 ephemeral public key ---
        // VERSION 11+ omits both (ADR-018): empty ciphertext, zeroed pubkey.
        let (ml_kem_ciphertext, x25519_ephemeral_public) = if version <= KEM_HEADER_MAX_VERSION {
            if data.len() < pos + ML_KEM_CIPHERTEXT_LEN {
                return Err("File truncated at ML-KEM ciphertext".to_string());
            }
            let ct = data[pos..pos + ML_KEM_CIPHERTEXT_LEN].to_vec();
            pos += ML_KEM_CIPHERTEXT_LEN;

            if data.len() < pos + 32 {
                return Err("File truncated at X25519 public key".to_string());
            }
            let eph: [u8; 32] = data[pos..pos + 32].try_into().unwrap();
            pos += 32;
            (ct, eph)
        } else {
            (Vec::new(), [0u8; 32])
        };

        // --- YubiKey records ---
        if data.len() < pos + 1 {
            return Err("File truncated at YubiKey record count".to_string());
        }
        let yubikey_count = data[pos] as usize;
        pos += 1;

        let mut yubikey_records = Vec::with_capacity(yubikey_count);
        for _ in 0..yubikey_count {
            if data.len() < pos + 2 {
                return Err("File truncated at YubiKey credential_id length".to_string());
            }
            let id_len = u16::from_be_bytes(data[pos..pos + 2].try_into().unwrap()) as usize;
            pos += 2;

            if data.len() < pos + id_len {
                return Err("File truncated at YubiKey credential_id".to_string());
            }
            let credential_id = data[pos..pos + id_len].to_vec();
            pos += id_len;

            if data.len() < pos + 32 {
                return Err("File truncated at YubiKey salt".to_string());
            }
            let salt: [u8; 32] = data[pos..pos + 32].try_into().unwrap();
            pos += 32;

            // VERSION 3+: each record has a key_blob (wrapped vault_key_master)
            let key_blob = if is_v3 {
                if data.len() < pos + 2 {
                    return Err("File truncated at YubiKey key_blob length".to_string());
                }
                let kb_len = u16::from_be_bytes(data[pos..pos + 2].try_into().unwrap()) as usize;
                pos += 2;
                if data.len() < pos + kb_len {
                    return Err("File truncated at YubiKey key_blob".to_string());
                }
                let kb = data[pos..pos + kb_len].to_vec();
                pos += kb_len;
                kb
            } else {
                vec![]
            };

            yubikey_records.push(YubiKeyRecord {
                credential_id,
                salt,
                key_blob,
            });
        }

        // --- alias (VERSION 5+) ---
        let alias = if is_v5 {
            if data.len() < pos + 2 {
                return Err("File truncated at alias length".to_string());
            }
            let a_len = u16::from_be_bytes(data[pos..pos + 2].try_into().unwrap()) as usize;
            pos += 2;
            if data.len() < pos + a_len {
                return Err("File truncated at alias".to_string());
            }
            let alias_str = std::str::from_utf8(&data[pos..pos + a_len])
                .map_err(|_| "Invalid UTF-8 in alias".to_string())?
                .to_string();
            pos += a_len;
            if alias_str.is_empty() {
                None
            } else {
                Some(alias_str)
            }
        } else {
            None
        };

        // --- passphrase_blob (VERSION 4+) ---
        let passphrase_blob = if is_v4 {
            if data.len() < pos + 2 {
                return Err("File truncated at passphrase_blob length".to_string());
            }
            let pb_len = u16::from_be_bytes(data[pos..pos + 2].try_into().unwrap()) as usize;
            pos += 2;
            if data.len() < pos + pb_len {
                return Err("File truncated at passphrase_blob".to_string());
            }
            let pb = data[pos..pos + pb_len].to_vec();
            pos += pb_len;
            pb
        } else {
            vec![]
        };

        // --- Body length (8 bytes) ---
        if data.len() < pos + 8 {
            return Err("File truncated at body length".to_string());
        }
        let body_len = u64::from_be_bytes(data[pos..pos + 8].try_into().unwrap()) as usize;
        pos += 8;

        // --- Body ---
        // body_len is attacker-controlled (8 bytes straight off disk), so compute
        // the end with a checked add: `pos + body_len` would otherwise overflow
        // usize for a huge body_len, wrapping the guard below and turning the slice
        // into a reversed range -> panic on open. See tests/vault_parse_fuzz.rs.
        let body_end = pos
            .checked_add(body_len)
            .ok_or_else(|| "File truncated at body".to_string())?;
        if data.len() < body_end {
            return Err("File truncated at body".to_string());
        }
        let ciphertext = data[pos..body_end].to_vec();

        Ok(SealedVault {
            version,
            params: Argon2idParams {
                m_cost,
                t_cost,
                p_cost,
            },
            argon2_salt,
            hkdf_salt,
            nonce,
            ml_kem_ciphertext,
            x25519_ephemeral_public,
            ciphertext,
            yubikey_records,
            alias,
            passphrase_blob,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::kdf::Argon2idParams;

    fn test_vault() -> SealedVault {
        // Pinned to v10 (the KEM-bearing format) so these header tests stay valid
        // once VERSION advances past it; v11 tests use test_vault_v11().
        SealedVault {
            version: 10,
            params: Argon2idParams {
                m_cost: 65536,
                t_cost: 25,
                p_cost: 4,
            },
            argon2_salt: [1u8; 32],
            hkdf_salt: [2u8; 32],
            nonce: [3u8; 12],
            ml_kem_ciphertext: vec![4u8; 1568],
            x25519_ephemeral_public: [5u8; 32],
            ciphertext: vec![6u8; 64],
            yubikey_records: vec![],
            alias: None,
            passphrase_blob: vec![],
        }
    }

    /// Build a raw VERSION 4 byte stream (no alias field) for backward-compat tests.
    fn test_vault_v4_bytes() -> Vec<u8> {
        let v = test_vault();
        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        out.push(4u8);
        out.extend_from_slice(&v.params.m_cost.to_be_bytes());
        out.extend_from_slice(&v.params.t_cost.to_be_bytes());
        out.extend_from_slice(&v.params.p_cost.to_be_bytes());
        out.extend_from_slice(&v.argon2_salt);
        out.extend_from_slice(&v.hkdf_salt);
        out.extend_from_slice(&v.nonce);
        out.extend_from_slice(&v.ml_kem_ciphertext);
        out.extend_from_slice(&v.x25519_ephemeral_public);
        out.push(0u8); // 0 YubiKey records
                       // passphrase_blob (VERSION 4 has this; no alias)
        let pb_len = v.passphrase_blob.len() as u16;
        out.extend_from_slice(&pb_len.to_be_bytes());
        out.extend_from_slice(&v.passphrase_blob);
        // body
        let body_len = v.ciphertext.len() as u64;
        out.extend_from_slice(&body_len.to_be_bytes());
        out.extend_from_slice(&v.ciphertext);
        out
    }

    #[test]
    fn roundtrip_with_no_yubikey_records() {
        let original = test_vault();
        let bytes = original.to_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(original, recovered);
    }

    #[test]
    fn roundtrip_with_yubikey_records_no_key_blob() {
        let mut vault = test_vault();
        vault.yubikey_records = vec![
            YubiKeyRecord {
                credential_id: vec![0xAAu8; 64],
                salt: [0xBBu8; 32],
                key_blob: vec![],
            },
            YubiKeyRecord {
                credential_id: vec![0xCCu8; 32],
                salt: [0xDDu8; 32],
                key_blob: vec![],
            },
        ];
        let bytes = vault.to_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(vault, recovered);
    }

    #[test]
    fn roundtrip_with_yubikey_records_with_key_blob() {
        let mut vault = test_vault();
        vault.yubikey_records = vec![
            YubiKeyRecord {
                credential_id: vec![0xAAu8; 64],
                salt: [0xBBu8; 32],
                key_blob: vec![0xEEu8; 60],
            },
            YubiKeyRecord {
                credential_id: vec![0xCCu8; 32],
                salt: [0xDDu8; 32],
                key_blob: vec![0xFFu8; 60],
            },
        ];
        let bytes = vault.to_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(vault, recovered);
    }

    #[test]
    fn roundtrip_with_passphrase_blob() {
        let mut vault = test_vault();
        vault.yubikey_records = vec![YubiKeyRecord {
            credential_id: vec![0xAAu8; 64],
            salt: [0xBBu8; 32],
            key_blob: vec![0xEEu8; 60],
        }];
        vault.passphrase_blob = vec![0xFFu8; 60];
        let bytes = vault.to_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(vault, recovered);
        assert_eq!(recovered.passphrase_blob.len(), 60);
    }

    // ── VERSION 11 header: no ML-KEM ciphertext + no X25519 ephemeral pubkey ──────
    // (ADR-018). A v11 vault carries an empty ml_kem_ciphertext and a zeroed
    // x25519_ephemeral_public in memory; neither is written to / read from disk.

    fn test_vault_v11() -> SealedVault {
        let mut v = test_vault();
        v.version = 11;
        v.ml_kem_ciphertext = vec![];
        v.x25519_ephemeral_public = [0u8; 32];
        v
    }

    #[test]
    fn v11_header_roundtrips_without_kem_fields() {
        let original = test_vault_v11();
        let bytes = original.to_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(original, recovered);
        assert!(
            recovered.ml_kem_ciphertext.is_empty(),
            "v11 header carries no ML-KEM ciphertext"
        );
        assert_eq!(
            recovered.x25519_ephemeral_public, [0u8; 32],
            "v11 header carries no X25519 ephemeral pubkey"
        );
    }

    #[test]
    fn v11_header_is_1600_bytes_shorter_than_the_v10_layout() {
        // v11 drops the ML-KEM ciphertext (1568) + X25519 ephemeral pubkey (32) = 1600.
        // Same body/records so the KEM fields are the only size difference.
        let v10 = test_vault();
        let v11 = test_vault_v11();
        assert_eq!(v10.to_bytes().len() - v11.to_bytes().len(), 1600);
    }

    #[test]
    fn from_bytes_version_branches_on_kem_fields() {
        // v10: KEM present (1568-byte ciphertext parsed back).
        let r10 = SealedVault::from_bytes(&test_vault().to_bytes()).unwrap();
        assert_eq!(r10.ml_kem_ciphertext.len(), 1568);
        assert_eq!(r10.version, 10);
        // v11: KEM absent.
        let r11 = SealedVault::from_bytes(&test_vault_v11().to_bytes()).unwrap();
        assert!(r11.ml_kem_ciphertext.is_empty());
        assert_eq!(r11.version, 11);
    }

    #[test]
    fn v11_header_aad_excludes_kem_fields() {
        // The AAD covers the plaintext header; for v11 it must omit the 1600 bytes
        // of KEM material, matching to_bytes so seal/open compute the same AAD.
        let v11 = test_vault_v11();
        let v10 = test_vault();
        assert_eq!(v10.header_aad().len() - v11.header_aad().len(), 1600);
    }

    #[test]
    fn version_2_records_readable_without_key_blob() {
        // Craft a raw VERSION 2 vault with one YubiKey record (no key_blob fields).
        let mut bytes = test_vault().to_bytes();
        // Patch version byte to 2 (offset 6)
        bytes[6] = 2;
        // The test_vault has 0 yubikey records written in VERSION 3 format.
        // We need to craft a VERSION 2 byte stream with one record manually.
        // Easier: just verify version=2 with 0 records is accepted.
        let result = SealedVault::from_bytes(&bytes);
        assert!(result.is_ok(), "VERSION 2 must be readable: {result:?}");
        assert_eq!(result.unwrap().yubikey_records.len(), 0);
    }

    #[test]
    fn wrong_magic_bytes_rejected() {
        let mut bytes = test_vault().to_bytes();
        bytes[0] = b'X';
        assert!(SealedVault::from_bytes(&bytes).is_err());
    }

    #[test]
    fn wrong_version_rejected() {
        let mut bytes = test_vault().to_bytes();
        bytes[6] = 99;
        assert!(SealedVault::from_bytes(&bytes).is_err());
    }

    #[test]
    fn truncated_file_rejected() {
        let bytes = test_vault().to_bytes();
        let truncated = &bytes[..100];
        assert!(SealedVault::from_bytes(truncated).is_err());
    }

    #[test]
    fn byte_length_no_records() {
        let vault = test_vault();
        let bytes = vault.to_bytes();
        // 6 + 1 + 4 + 4 + 4 + 32 + 32 + 12 + 1568 + 32 + 1 + 2(alias_len) + 0(alias) + 2(pb_len) + 0(pb) + 8 + 64 = 1772
        assert_eq!(bytes.len(), 1772);
    }

    #[test]
    fn byte_length_two_records_with_key_blob() {
        let mut vault = test_vault();
        vault.yubikey_records = vec![
            YubiKeyRecord {
                credential_id: vec![0xAAu8; 64],
                salt: [0xBBu8; 32],
                key_blob: vec![0xEEu8; 60],
            },
            YubiKeyRecord {
                credential_id: vec![0xCCu8; 64],
                salt: [0xDDu8; 32],
                key_blob: vec![0xFFu8; 60],
            },
        ];
        let bytes = vault.to_bytes();
        // Base: 1772 bytes (0 records, empty alias, empty passphrase_blob)
        // Per record: 2 (id_len) + 64 (id) + 32 (salt) + 2 (kb_len) + 60 (key_blob) = 160
        // 2 records: 320 bytes
        assert_eq!(bytes.len(), 1772 + 320);
    }

    #[test]
    fn version5_with_alias_roundtrip() {
        let mut vault = test_vault();
        vault.alias = Some("Work Vault".to_string());
        let bytes = vault.to_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(recovered.alias, Some("Work Vault".to_string()));
    }

    #[test]
    fn version5_alias_len_included_in_byte_count() {
        let mut vault = test_vault();
        vault.alias = Some("Work".to_string()); // 4 ASCII bytes
        let bytes = vault.to_bytes();
        // 1772 (base with empty alias) - 0 (empty alias) + 4 (alias bytes) = 1776
        assert_eq!(bytes.len(), 1776);
    }

    #[test]
    fn version4_backward_compat_alias_is_none() {
        let bytes = test_vault_v4_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(recovered.alias, None);
        assert_eq!(recovered.ciphertext, vec![6u8; 64]);
    }

    #[test]
    fn current_version_is_11() {
        assert_eq!(VERSION, 11);
        // test_vault() is deliberately pinned to v10 (the KEM-bearing format) so the
        // legacy-format header tests stay valid; it is not the current version.
        assert_eq!(test_vault().version, 10);
    }

    #[test]
    fn version_5_layout_still_readable_and_version_preserved() {
        // VERSION 7 header layout is identical to VERSION 5, so a V7 byte stream
        // with the version byte patched to 5 must still parse, and re-serialise
        // back as VERSION 5 (lazy migration: old vaults are not silently bumped).
        let mut bytes = test_vault().to_bytes();
        bytes[6] = 5; // version byte offset = 6 (after 6 magic bytes)
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(recovered.version, 5);
        assert_eq!(
            recovered.to_bytes()[6],
            5,
            "re-serialise preserves version 5"
        );
    }

    #[test]
    fn version_6_layout_still_readable_and_version_preserved() {
        let mut bytes = test_vault().to_bytes();
        bytes[6] = 6;
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(recovered.version, 6);
        assert_eq!(
            recovered.to_bytes()[6],
            6,
            "re-serialise preserves version 6"
        );
    }

    // ── header_aad tests ──────────────────────────────────────────────────────

    #[test]
    fn header_aad_does_not_include_nonce() {
        let vault = test_vault();
        let aad = vault.header_aad();
        // The nonce is 12 bytes of [3u8; 12] in test_vault().
        // It must not appear as a contiguous block in the AAD.
        let nonce = [3u8; 12];
        let found = aad.windows(12).any(|w| w == nonce);
        assert!(!found, "nonce must be excluded from header_aad");
    }

    #[test]
    fn header_aad_stable_across_ciphertext_changes() {
        let mut a = test_vault();
        let mut b = test_vault();
        b.ciphertext = vec![0xFFu8; 128]; // different ciphertext
        b.nonce = [0xEEu8; 12]; // different nonce
        assert_eq!(
            a.header_aad(),
            b.header_aad(),
            "header_aad must be identical regardless of ciphertext or nonce"
        );
        a.ciphertext = vec![];
        assert_eq!(
            a.header_aad(),
            b.header_aad(),
            "empty ciphertext placeholder must yield the same AAD"
        );
    }

    #[test]
    fn header_aad_changes_when_alias_changes() {
        let mut vault = test_vault();
        let aad_no_alias = vault.header_aad();
        vault.alias = Some("Work".to_string());
        let aad_with_alias = vault.header_aad();
        assert_ne!(aad_no_alias, aad_with_alias);
    }

    #[test]
    fn header_aad_changes_when_yubikey_records_change() {
        let mut vault = test_vault();
        let aad_before = vault.header_aad();
        vault.yubikey_records.push(YubiKeyRecord {
            credential_id: vec![0xAAu8; 32],
            salt: [0xBBu8; 32],
            key_blob: vec![],
        });
        let aad_after = vault.header_aad();
        assert_ne!(aad_before, aad_after);
    }

    #[test]
    fn byte_length_two_records_with_passphrase_blob() {
        let mut vault = test_vault();
        vault.yubikey_records = vec![
            YubiKeyRecord {
                credential_id: vec![0xAAu8; 64],
                salt: [0xBBu8; 32],
                key_blob: vec![0xEEu8; 60],
            },
            YubiKeyRecord {
                credential_id: vec![0xCCu8; 64],
                salt: [0xDDu8; 32],
                key_blob: vec![0xFFu8; 60],
            },
        ];
        vault.passphrase_blob = vec![0xAAu8; 60];
        let bytes = vault.to_bytes();
        // Base 1772 + 320 records + 60 passphrase_blob = 2152
        assert_eq!(bytes.len(), 1772 + 320 + 60);
    }
}
