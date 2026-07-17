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
//! | YubiKey record count   | 1            |
//! | YubiKeyRecord × count  | variable     |
//! |   credential_id length | 2            |
//! |   credential_id        | variable     |
//! |   salt                 | 32           |
//! |   key_blob length      | 2            |
//! |   key_blob             | 0 or 60      |
//! | alias length           | 2            |
//! | alias                  | 0–512 UTF-8  |
//! | passphrase_blob length | 2            |
//! | passphrase_blob        | 0 or 60      |
//! | Body length            | 8            |
//! | Body (ciphertext)      | variable     |
//!
//! VERSION 11 is the only readable format: the vault key is derived straight from the
//! Argon2id output via HKDF (ADR-018), and the AES-256-GCM body is sealed with the
//! serialised header as AAD, so any change to a plaintext header field (alias, YubiKey
//! records, Argon2id params) fails body decryption with an authentication error.
//!
//! RT-3 raised the floor from v2 to v11 and deleted the X25519 + ML-KEM hybrid layer
//! those older formats derived their keys through; their headers also carried an ML-KEM
//! ciphertext (1568 bytes) and an X25519 ephemeral pubkey (32) between the nonce and the
//! YubiKey records. A v2–v10 file is now refused intact, with a pointer to the upgrade
//! path — see [`VERSION_MIN_READABLE`] and docs/VAULT_UPGRADE_PATH.md. The per-version
//! history lives in git and CHANGELOG.md.
//!
//! Reads v11 only; always writes VERSION 11.

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
///
/// RT-3 raised this 2 -> 11: the X25519 + ML-KEM derivation that opened v2–v10 is
/// gone, so those vaults are refused (never damaged) and the user is pointed at the
/// upgrade path — install alpha.14, open each vault once to migrate it to v11, then
/// return. See docs/VAULT_UPGRADE_PATH.md.
const VERSION_MIN_READABLE: u8 = 11;

/// Where a user with a pre-v11 vault is sent to recover it. Carried in the refusal
/// error itself: the file is intact, and this documents the way back.
const UPGRADE_PATH_URL: &str =
    "https://github.com/gabbro-foss/gabbro/blob/master/docs/VAULT_UPGRADE_PATH.md";

/// Read the format version from a vault file's first bytes, with **no floor check**.
///
/// [`SealedVault::from_bytes`] refuses anything below [`VERSION_MIN_READABLE`] before
/// it returns a header, so a caller cannot learn a pre-v11 vault's version from it.
/// Without this, the app treats "too old to open" as "corrupt" and offers to delete a
/// perfectly intact vault. Reads magic + the version byte only; decrypts nothing.
///
/// `Err` means the file is not a Gabbro vault (bad magic) or is too short to have a
/// version — i.e. genuinely unreadable rather than merely old.
pub fn peek_version(data: &[u8]) -> Result<u8, String> {
    if data.len() < 7 {
        return Err("File too short to be a Gabbro vault".to_string());
    }
    if &data[..6] != MAGIC {
        return Err("Not a Gabbro vault file".to_string());
    }
    Ok(data[6])
}

/// Whether the vault file at `data` is readable by this build, or predates the floor.
///
/// `Ok(true)` = intact Gabbro vault, too old to open (the user must migrate it with an
/// older release first — see [`UPGRADE_PATH_URL`]). `Ok(false)` = current enough to try.
/// `Err` = not a Gabbro vault at all.
pub fn is_format_too_old(data: &[u8]) -> Result<bool, String> {
    Ok(peek_version(data)? < VERSION_MIN_READABLE)
}

/// The complete contents of a sealed vault file.
#[derive(Debug, Clone, PartialEq)]
pub struct SealedVault {
    /// File-format version this vault was sealed with.
    ///
    /// Set to the parsed version on read and to [`VERSION`] for freshly sealed
    /// vaults. At floor v11 every readable vault shares one key derivation, so
    /// nothing dispatches on it; it remains the fail-closed check against a file
    /// written by a newer or older build.
    pub version: u8,
    pub params: Argon2idParams,
    pub argon2_salt: [u8; 32],
    pub hkdf_salt: [u8; 32],
    pub nonce: [u8; 12],
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
    /// magic, version, Argon2id parameters, salts, YubiKey records, alias, and
    /// passphrase_blob.
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

        // YubiKey records — count byte then each record
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
            // Refuse, never touch: the file stays intact so the user can migrate it
            // with an older release and come back. Names no other cause (a passphrase,
            // corruption) so the message can't send them chasing the wrong thing.
            return Err(format!(
                "file version not supported: v{version} (this build opens v{VERSION_MIN_READABLE} and later) - {UPGRADE_PATH_URL}"
            ));
        }
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

            // Each record carries a key_blob (the wrapped vault_key_master).
            if data.len() < pos + 2 {
                return Err("File truncated at YubiKey key_blob length".to_string());
            }
            let kb_len = u16::from_be_bytes(data[pos..pos + 2].try_into().unwrap()) as usize;
            pos += 2;
            if data.len() < pos + kb_len {
                return Err("File truncated at YubiKey key_blob".to_string());
            }
            let key_blob = data[pos..pos + kb_len].to_vec();
            pos += kb_len;

            yubikey_records.push(YubiKeyRecord {
                credential_id,
                salt,
                key_blob,
            });
        }

        // --- alias ---
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
        // An empty alias encodes None.
        let alias = if alias_str.is_empty() {
            None
        } else {
            Some(alias_str)
        };

        // --- passphrase_blob ---
        if data.len() < pos + 2 {
            return Err("File truncated at passphrase_blob length".to_string());
        }
        let pb_len = u16::from_be_bytes(data[pos..pos + 2].try_into().unwrap()) as usize;
        pos += 2;
        if data.len() < pos + pb_len {
            return Err("File truncated at passphrase_blob".to_string());
        }
        let passphrase_blob = data[pos..pos + pb_len].to_vec();
        pos += pb_len;

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
        // v11 — the only readable format. RT-3 re-pinned this from v10 when the
        // KEM-bearing formats stopped being readable.
        SealedVault {
            version: 11,
            params: Argon2idParams {
                m_cost: 65536,
                t_cost: 25,
                p_cost: 4,
            },
            argon2_salt: [1u8; 32],
            hkdf_salt: [2u8; 32],
            nonce: [3u8; 12],
            ciphertext: vec![6u8; 64],
            yubikey_records: vec![],
            alias: None,
            passphrase_blob: vec![],
        }
    }

    /// A byte stream that is a well-formed vault except for a pre-floor version byte.
    /// `from_bytes` refuses on the version alone, before parsing any field after it,
    /// so patching the byte is enough to exercise the refusal.
    fn too_old_vault_bytes(version: u8) -> Vec<u8> {
        let mut bytes = test_vault().to_bytes();
        bytes[6] = version; // version byte: immediately after the 6 magic bytes
        bytes
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

    // ── N4 (RT-3 net): absolute pin of the VERSION 11 layout ──────────────────
    // The expected streams are rebuilt field by field from the format spec at the
    // top of this file rather than copied from `to_bytes` output — so a change to
    // `to_bytes` cannot quietly redefine v11. Self-contained on purpose: they must
    // not inherit from `test_vault()`, so re-pinning that fixture (as RT-3 did,
    // v10 -> v11) can never silently move the pin.

    fn pinned_v11_vault() -> SealedVault {
        SealedVault {
            version: 11,
            params: Argon2idParams {
                m_cost: 65536,
                t_cost: 25,
                p_cost: 4,
            },
            argon2_salt: [1u8; 32],
            hkdf_salt: [2u8; 32],
            nonce: [3u8; 12],
            ciphertext: vec![6u8; 64],
            yubikey_records: vec![],
            alias: None,
            passphrase_blob: vec![],
        }
    }

    // ── peek_version: tell "too old" apart from "corrupt" ────────────────────
    // `from_bytes` refuses a pre-v11 vault before it returns anything, so the app
    // cannot learn the version from it and would report an old vault as corrupt —
    // then offer to delete it. `peek_version` reads magic + the version byte only,
    // with no floor check, so the refusal can be explained instead.

    #[test]
    fn peek_version_reads_a_version_from_bytes_refuses() {
        // The exact case that matters: from_bytes says no, peek_version says v10.
        let bytes = too_old_vault_bytes(10);
        assert!(
            SealedVault::from_bytes(&bytes).is_err(),
            "v10 must be refused at floor v11"
        );
        assert_eq!(peek_version(&bytes).unwrap(), 10);

        // ...and a current vault reports its own version just the same.
        assert_eq!(peek_version(&test_vault().to_bytes()).unwrap(), 11);
    }

    #[test]
    fn peek_version_rejects_a_non_gabbro_file() {
        let mut bytes = test_vault().to_bytes();
        bytes[0] = b'X';
        assert!(
            peek_version(&bytes).is_err(),
            "a file that is not a Gabbro vault has no version to report"
        );
    }

    #[test]
    fn peek_version_rejects_a_truncated_file() {
        assert!(
            peek_version(b"GABBR").is_err(),
            "too short to hold magic + version"
        );
        assert!(
            peek_version(MAGIC).is_err(),
            "magic present but the version byte is missing"
        );
    }

    #[test]
    fn v11_on_disk_layout_is_pinned_absolutely() {
        let mut expected = Vec::new();
        expected.extend_from_slice(MAGIC); // 6
        expected.push(11); // version 1
        expected.extend_from_slice(&65536u32.to_be_bytes()); // m_cost 4
        expected.extend_from_slice(&25u32.to_be_bytes()); // t_cost 4
        expected.extend_from_slice(&4u32.to_be_bytes()); // p_cost 4
        expected.extend_from_slice(&[1u8; 32]); // argon2_salt 32
        expected.extend_from_slice(&[2u8; 32]); // hkdf_salt 32
        expected.extend_from_slice(&[3u8; 12]); // nonce 12
                                                // v11 carries NO ML-KEM ciphertext and NO X25519 ephemeral pubkey
        expected.push(0); // yubikey record count 1
        expected.extend_from_slice(&0u16.to_be_bytes()); // alias_len 2
        expected.extend_from_slice(&0u16.to_be_bytes()); // passphrase_blob_len 2
        expected.extend_from_slice(&64u64.to_be_bytes()); // body_len 8
        expected.extend_from_slice(&[6u8; 64]); // body 64

        assert_eq!(
            pinned_v11_vault().to_bytes(),
            expected,
            "the v11 on-disk layout is frozen — changing it makes every v11 vault unopenable"
        );
        assert_eq!(expected.len(), 172, "6+1+12+32+32+12+1+2+2+8+64 = 172");
    }

    #[test]
    fn v11_header_aad_is_pinned_absolutely() {
        let mut expected = Vec::new();
        expected.extend_from_slice(MAGIC);
        expected.push(11);
        expected.extend_from_slice(&65536u32.to_be_bytes());
        expected.extend_from_slice(&25u32.to_be_bytes());
        expected.extend_from_slice(&4u32.to_be_bytes());
        expected.extend_from_slice(&[1u8; 32]); // argon2_salt
        expected.extend_from_slice(&[2u8; 32]); // hkdf_salt
                                                // nonce excluded (AES-GCM authenticates it implicitly); no KEM fields at v11
        expected.push(0); // yubikey record count
        expected.extend_from_slice(&0u16.to_be_bytes()); // alias_len
        expected.extend_from_slice(&0u16.to_be_bytes()); // passphrase_blob_len

        assert_eq!(
            pinned_v11_vault().header_aad(),
            expected,
            "the v11 AAD recipe is frozen — changing it makes every v11 vault unopenable"
        );
        assert_eq!(expected.len(), 88, "6+1+12+32+32+1+2+2 = 88");
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
        // 6 + 1 + 4 + 4 + 4 + 32 + 32 + 12 + 1 + 2(alias_len) + 0(alias) + 2(pb_len) + 0(pb) + 8 + 64 = 172
        assert_eq!(bytes.len(), 172);
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
        // Base: 172 bytes (0 records, empty alias, empty passphrase_blob)
        // Per record: 2 (id_len) + 64 (id) + 32 (salt) + 2 (kb_len) + 60 (key_blob) = 160
        // 2 records: 320 bytes
        assert_eq!(bytes.len(), 172 + 320);
    }

    #[test]
    fn alias_roundtrips() {
        let mut vault = test_vault();
        vault.alias = Some("Work Vault".to_string());
        let bytes = vault.to_bytes();
        let recovered = SealedVault::from_bytes(&bytes).unwrap();
        assert_eq!(recovered.alias, Some("Work Vault".to_string()));
    }

    #[test]
    fn alias_len_included_in_byte_count() {
        let mut vault = test_vault();
        vault.alias = Some("Work".to_string()); // 4 ASCII bytes
        let bytes = vault.to_bytes();
        // 172 (base with empty alias) - 0 (empty alias) + 4 (alias bytes) = 176
        assert_eq!(bytes.len(), 176);
    }

    #[test]
    fn current_version_is_11() {
        assert_eq!(VERSION, 11);
        assert_eq!(
            test_vault().version,
            VERSION,
            "the fixture must track the current format"
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
        // Base 172 + 320 records + 60 passphrase_blob = 552
        assert_eq!(bytes.len(), 172 + 320 + 60);
    }
}
