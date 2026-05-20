//! Vault entry serialization — converting between `VaultBody` and bytes.
//!
//! This is the glue between the domain model and the crypto stack:
//!   serialize_vault_body() → seal_vault()   → write_vault()
//!   read_vault()           → open_vault()   → deserialize_vault_body()
//!
//! Legacy vaults (bare JSON array) are migrated on first load:
//!   - Default folders are applied.
//!   - Entries with folder="Personal" are migrated to folder="".

use crate::vault::entry::VaultEntry;
use serde::{Deserialize, Serialize};

/// Default folders applied to new vaults and legacy vaults on migration.
pub const DEFAULT_FOLDERS: [&str; 3] = ["Work", "Private", "Other"];

/// The complete decrypted vault body — folders list plus all entries.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultBody {
    pub folders: Vec<String>,
    pub entries: Vec<VaultEntry>,
}

impl VaultBody {
    /// Create a new empty vault body with default folders.
    pub fn empty() -> Self {
        VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries: vec![],
        }
    }
}

/// Serialize a `VaultBody` to JSON bytes for encryption.
pub fn serialize_vault_body(body: &VaultBody) -> Result<Vec<u8>, String> {
    serde_json::to_vec(body).map_err(|e| format!("Failed to serialize vault body: {e}"))
}

/// Deserialize JSON bytes (from decryption) back into a `VaultBody`.
///
/// Handles two formats:
/// - New format: `{"folders":[...],"entries":[...]}` — deserialised directly.
/// - Legacy format: bare JSON array `[...]` — wrapped with default folders;
///   entries with `folder == "Personal"` are migrated to `folder == ""`.
pub fn deserialize_vault_body(bytes: &[u8]) -> Result<VaultBody, String> {
    // Detect legacy format by checking the first non-whitespace byte.
    let first = bytes.iter().find(|&&b| !b.is_ascii_whitespace());
    if first == Some(&b'[') {
        // Legacy bare array — migrate.
        let entries: Vec<VaultEntry> = serde_json::from_slice(bytes)
            .map_err(|e| format!("Failed to deserialize legacy entries: {e}"))?;
        let entries = migrate_folders(entries);
        return Ok(VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries,
        });
    }
    serde_json::from_slice(bytes).map_err(|e| format!("Failed to deserialize vault body: {e}"))
}

/// Migrate legacy `folder == "Personal"` entries to `folder == ""`.
fn migrate_folders(mut entries: Vec<VaultEntry>) -> Vec<VaultEntry> {
    for entry in &mut entries {
        let folder = match entry {
            VaultEntry::Login(e) => &mut e.meta.folder,
            VaultEntry::Note(e) => &mut e.meta.folder,
            VaultEntry::Identity(e) => &mut e.meta.folder,
            VaultEntry::Card(e) => &mut e.meta.folder,
            VaultEntry::File(e) => &mut e.meta.folder,
            VaultEntry::Custom(e) => &mut e.meta.folder,
        };
        if folder == "Personal" {
            *folder = String::new();
        }
    }
    entries
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, NoteEntry, VaultEntry};

    fn default_meta(id: &str) -> EntryMeta {
        EntryMeta {
            id: id.to_string(),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        }
    }

    // ── VaultBody tests ───────────────────────────────────────────────────────

    #[test]
    fn vault_body_roundtrips_with_folders() {
        let body = VaultBody {
            folders: vec![
                String::from("Work"),
                String::from("Private"),
                String::from("Other"),
            ],
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: default_meta("id-001"),
                title: String::from("Test"),
                content: String::from("Hello"),
                attachments: vec![],
            })],
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let recovered = deserialize_vault_body(&bytes).unwrap();
        assert_eq!(recovered.folders, vec!["Work", "Private", "Other"]);
        assert_eq!(recovered.entries.len(), 1);
    }

    #[test]
    fn deserialize_vault_body_migrates_legacy_array() {
        // Simulate an old vault: bare JSON array, entry with folder="Personal"
        let legacy_entry = VaultEntry::Login(LoginEntry {
            meta: default_meta("id-legacy"),
            title: String::from("Legacy"),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        });
        let legacy_bytes = serde_json::to_vec(&vec![legacy_entry]).unwrap();
        let body = deserialize_vault_body(&legacy_bytes).unwrap();
        // Default folders applied
        assert_eq!(body.folders, DEFAULT_FOLDERS.map(String::from).to_vec());
        // "Personal" migrated to ""
        match &body.entries[0] {
            VaultEntry::Login(e) => assert_eq!(e.meta.folder, ""),
            _ => panic!("Expected Login"),
        }
    }

    #[test]
    fn empty_vault_body_roundtrips() {
        let body = VaultBody::empty();
        let bytes = serialize_vault_body(&body).unwrap();
        let recovered = deserialize_vault_body(&bytes).unwrap();
        assert_eq!(recovered.entries.len(), 0);
        assert_eq!(
            recovered.folders,
            DEFAULT_FOLDERS.map(String::from).to_vec()
        );
    }

    #[test]
    fn single_login_entry_roundtrips() {
        let entry = VaultEntry::Login(LoginEntry {
            meta: default_meta("id-001"),
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("correct horst battery staple"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        });
        let body = VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries: vec![entry],
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let recovered = deserialize_vault_body(&bytes).unwrap();
        assert_eq!(recovered.entries.len(), 1);
        match &recovered.entries[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.username, "rob");
                assert_eq!(e.url, "https://github.com");
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn mixed_entry_types_roundtrip() {
        let entries = vec![
            VaultEntry::Login(LoginEntry {
                meta: default_meta("id-001"),
                title: String::from("Example"),
                url: String::from("https://example.com"),
                username: String::from("rob"),
                password: String::from("s3cr3t"),
                notes: None,
                custom_fields: vec![CustomField {
                    label: String::from("2FA backup"),
                    value: String::from("abc123"),
                    hidden: true,
                }],
                attachments: vec![],
                previous_password: None,
            }),
            VaultEntry::Note(NoteEntry {
                meta: default_meta("id-002"),
                title: String::from("Recovery codes"),
                content: String::from("code1\ncode2\ncode3"),
                attachments: vec![],
            }),
        ];
        let body = VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries,
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let recovered = deserialize_vault_body(&bytes).unwrap();
        assert_eq!(recovered.entries.len(), 2);
    }

    #[test]
    fn invalid_bytes_returns_error() {
        let result = deserialize_vault_body(b"this is not json");
        assert!(result.is_err());
    }

    #[test]
    fn serialized_bytes_are_valid_utf8_json() {
        let entry = VaultEntry::Note(NoteEntry {
            meta: default_meta("id-001"),
            title: String::from("Test"),
            content: String::from("Hello"),
            attachments: vec![],
        });
        let body = VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries: vec![entry],
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let json_str = std::str::from_utf8(&bytes).expect("bytes should be valid UTF-8");
        assert!(json_str.starts_with('{'));
        assert!(json_str.ends_with('}'));
    }
}
