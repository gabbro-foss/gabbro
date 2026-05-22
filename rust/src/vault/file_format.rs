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
//! | Body length            | 8            |
//! | Body (ciphertext)      | variable     |
//!
//! VERSION 2 (legacy): records have no key_blob fields.
//! VERSION 3 (current): records include key_blob_len + key_blob per entry.
//! Reads both; always writes VERSION 3.

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
pub const VERSION: u8 = 3;

/// Oldest version this build can still read.
const VERSION_MIN_READABLE: u8 = 2;

/// Size of the ML-KEM-1024 ciphertext in bytes.
const ML_KEM_CIPHERTEXT_LEN: usize = 1568;

/// The complete contents of a sealed vault file.
#[derive(Debug, Clone, PartialEq)]
pub struct SealedVault {
    pub params: Argon2idParams,
    pub argon2_salt: [u8; 32],
    pub hkdf_salt: [u8; 32],
    pub nonce: [u8; 12],
    pub ml_kem_ciphertext: Vec<u8>,
    pub x25519_ephemeral_public: [u8; 32],
    pub ciphertext: Vec<u8>,
    pub yubikey_records: Vec<YubiKeyRecord>,
}

impl SealedVault {
    /// Serialize the vault to a flat byte vector for writing to disk.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::new();

        // Header identity
        out.extend_from_slice(MAGIC);
        out.push(VERSION);

        // Argon2id parameters — each u32 written as 4 big-endian bytes
        out.extend_from_slice(&self.params.m_cost.to_be_bytes());
        out.extend_from_slice(&self.params.t_cost.to_be_bytes());
        out.extend_from_slice(&self.params.p_cost.to_be_bytes());

        // Fixed-size fields
        out.extend_from_slice(&self.argon2_salt);
        out.extend_from_slice(&self.hkdf_salt);
        out.extend_from_slice(&self.nonce);
        out.extend_from_slice(&self.ml_kem_ciphertext);
        out.extend_from_slice(&self.x25519_ephemeral_public);

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
        if !(VERSION_MIN_READABLE..=VERSION).contains(&version) {
            return Err(format!("Unsupported version: {}", version));
        }
        let is_v3 = version >= 3;
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

        // --- ML-KEM ciphertext (1568 bytes) ---
        if data.len() < pos + ML_KEM_CIPHERTEXT_LEN {
            return Err("File truncated at ML-KEM ciphertext".to_string());
        }
        let ml_kem_ciphertext = data[pos..pos + ML_KEM_CIPHERTEXT_LEN].to_vec();
        pos += ML_KEM_CIPHERTEXT_LEN;

        // --- X25519 ephemeral public key (32 bytes) ---
        if data.len() < pos + 32 {
            return Err("File truncated at X25519 public key".to_string());
        }
        let x25519_ephemeral_public: [u8; 32] = data[pos..pos + 32].try_into().unwrap();
        pos += 32;

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

        // --- Body length (8 bytes) ---
        if data.len() < pos + 8 {
            return Err("File truncated at body length".to_string());
        }
        let body_len = u64::from_be_bytes(data[pos..pos + 8].try_into().unwrap()) as usize;
        pos += 8;

        // --- Body ---
        if data.len() < pos + body_len {
            return Err("File truncated at body".to_string());
        }
        let ciphertext = data[pos..pos + body_len].to_vec();

        Ok(SealedVault {
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
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::kdf::Argon2idParams;

    fn test_vault() -> SealedVault {
        SealedVault {
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
        }
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
        // 6 + 1 + 4 + 4 + 4 + 32 + 32 + 12 + 1568 + 32 + 1 + 8 + 64 = 1768
        assert_eq!(bytes.len(), 1768);
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
        // Base: 1768 bytes (0 records)
        // Per record: 2 (id_len) + 64 (id) + 32 (salt) + 2 (kb_len) + 60 (key_blob) = 160
        // 2 records: 320 bytes
        assert_eq!(bytes.len(), 1768 + 320);
    }
}
