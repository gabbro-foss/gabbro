//! Vault entry serialization — converting between `Vec<VaultEntry>` and bytes.
//!
//! This is the glue between the domain model and the crypto stack:
//!   serialize_entries() → seal_vault()   → write_vault()
//!   read_vault()        → open_vault()   → deserialize_entries()

use crate::vault::entry::VaultEntry;

/// Serialize a list of vault entries to JSON bytes for encryption.
pub fn serialize_entries(entries: &[VaultEntry]) -> Result<Vec<u8>, String> {
    serde_json::to_vec(entries)
        .map_err(|e| format!("Failed to serialize entries: {e}"))
}

/// Deserialize JSON bytes (from decryption) back into vault entries.
pub fn deserialize_entries(bytes: &[u8]) -> Result<Vec<VaultEntry>, String> {
    serde_json::from_slice(bytes)
        .map_err(|e| format!("Failed to deserialize entries: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::entry::{
        CustomField, EntryMeta, LoginEntry, NoteEntry, VaultEntry,
    };

    fn default_meta(id: &str) -> EntryMeta {
        EntryMeta {
            id: id.to_string(),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
            tags: vec![],
            favourite: false,
        }
    }

    #[test]
    fn empty_vault_roundtrips() {
        let entries: Vec<VaultEntry> = vec![];
        let bytes = serialize_entries(&entries).unwrap();
        let recovered = deserialize_entries(&bytes).unwrap();
        assert_eq!(recovered.len(), 0);
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
        });
        let bytes = serialize_entries(&[entry]).unwrap();
        let recovered = deserialize_entries(&bytes).unwrap();
        assert_eq!(recovered.len(), 1);
        match &recovered[0] {
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
            }),
            VaultEntry::Note(NoteEntry {
                meta: default_meta("id-002"),
                title: String::from("Recovery codes"),
                content: String::from("code1\ncode2\ncode3"),
                attachments: vec![],
            }),
        ];
        let bytes = serialize_entries(&entries).unwrap();
        let recovered = deserialize_entries(&bytes).unwrap();
        assert_eq!(recovered.len(), 2);
    }

    #[test]
    fn invalid_bytes_returns_error() {
        let result = deserialize_entries(b"this is not json");
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
        let bytes = serialize_entries(&[entry]).unwrap();
        let json_str = std::str::from_utf8(&bytes).expect("bytes should be valid UTF-8");
        assert!(json_str.starts_with('['));
        assert!(json_str.ends_with(']'));
    }
}
