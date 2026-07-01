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
use std::collections::HashMap;

/// Default folders applied to new vaults and legacy vaults on migration.
pub const DEFAULT_FOLDERS: [&str; 3] = ["Work", "Private", "Other"];

/// A record of an intentionally deleted entry.
///
/// Written to `VaultBody.deleted_ids` when an entry is removed so that sync
/// merge can distinguish "this entry was deleted" from "this entry never existed
/// on this device".
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DeletedEntry {
    pub id: String,
    /// ISO 8601 UTC timestamp of the deletion.
    pub deleted_at: String,
}

/// The complete decrypted vault body — folders list plus all entries.
///
/// `yubikey_aliases`, `vault_updated_at`, and `deleted_ids` are optional at
/// the JSON level (`#[serde(default)]`) so vaults written by older builds
/// deserialise cleanly with sensible defaults.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct VaultBody {
    pub folders: Vec<String>,
    pub entries: Vec<VaultEntry>,
    #[serde(default)]
    pub yubikey_aliases: HashMap<String, String>,
    /// ISO 8601 UTC timestamp set on every save.  Used by sync to detect
    /// whether two vaults are already identical.  Empty string on old vaults.
    #[serde(default)]
    pub vault_updated_at: String,
    /// Tombstones for intentionally deleted entries.  Used by sync merge to
    /// propagate deletions across devices.  Empty on old vaults.
    #[serde(default)]
    pub deleted_ids: Vec<DeletedEntry>,
}

impl VaultBody {
    /// Create a new empty vault body with default folders.
    pub fn empty() -> Self {
        VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries: vec![],
            yubikey_aliases: HashMap::new(),
            vault_updated_at: String::new(),
            deleted_ids: vec![],
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
        // Legacy bare array — migrate folders + fold previous_* into history.
        let mut value: serde_json::Value = serde_json::from_slice(bytes)
            .map_err(|e| format!("Failed to deserialize legacy entries: {e}"))?;
        if let Some(arr) = value.as_array_mut() {
            for entry in arr.iter_mut() {
                fold_previous_secrets(entry);
            }
        }
        let entries: Vec<VaultEntry> = serde_json::from_value(value)
            .map_err(|e| format!("Failed to deserialize legacy entries: {e}"))?;
        let entries = migrate_folders(entries);
        return Ok(VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries,
            yubikey_aliases: HashMap::new(),
            vault_updated_at: String::new(),
            deleted_ids: vec![],
        });
    }
    // Fold pre-v9 single-slot secrets into meta.history before typed decode.
    let mut value: serde_json::Value = serde_json::from_slice(bytes)
        .map_err(|e| format!("Failed to deserialize vault body: {e}"))?;
    if let Some(entries) = value.get_mut("entries").and_then(|e| e.as_array_mut()) {
        for entry in entries.iter_mut() {
            fold_previous_secrets(entry);
        }
    }
    serde_json::from_value(value).map_err(|e| format!("Failed to deserialize vault body: {e}"))
}

/// Fold the pre-v9 single-slot `previous_password`/`previous_cvv`/`previous_pin`
/// values of one externally-tagged entry (`{"Login": {...}}`) into its
/// `meta.history` as one-per-field records, then null out the old slots. Lossless
/// migration to the unified history model; a no-op for entries without them.
fn fold_previous_secrets(entry: &mut serde_json::Value) {
    if let Some(obj) = entry.as_object_mut() {
        for inner in obj.values_mut() {
            fold_inner_previous_secrets(inner);
        }
    }
}

fn fold_inner_previous_secrets(inner: &mut serde_json::Value) {
    use serde_json::{json, Value};
    let Some(map) = inner.as_object_mut() else {
        return;
    };
    const SLOTS: [(&str, &str); 3] = [
        ("previous_password", "password"),
        ("previous_cvv", "cvv"),
        ("previous_pin", "pin"),
    ];
    let mut records: Vec<Value> = Vec::new();
    for (key, field) in SLOTS {
        if let Some(Value::Object(prev)) = map.get(key).cloned() {
            let value = prev.get("value").cloned().unwrap_or_else(|| json!(""));
            let saved_at = prev.get("saved_at").cloned().unwrap_or_else(|| json!(""));
            let expires_at = prev.get("expires_at").cloned().unwrap_or(Value::Null);
            records.push(json!({
                "field": field,
                "value": value,
                "saved_at": saved_at,
                "expires_at": expires_at,
            }));
            map.insert(key.to_string(), Value::Null);
        }
    }
    if records.is_empty() {
        return;
    }
    let meta = map.entry("meta").or_insert_with(|| json!({}));
    let Some(meta_map) = meta.as_object_mut() else {
        return;
    };
    let history = meta_map.entry("history").or_insert_with(|| json!([]));
    let Some(hist) = history.as_array_mut() else {
        return;
    };
    for rec in records {
        let field = rec.get("field").and_then(|f| f.as_str());
        // One previous value per field: never duplicate an existing record.
        let exists = hist
            .iter()
            .any(|h| h.get("field").and_then(|f| f.as_str()) == field);
        if !exists {
            hist.push(rec);
        }
    }
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
            field_times: Default::default(),
            history: Vec::new(),
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
                custom_fields: vec![],
                attachments: vec![],
            })],
            ..Default::default()
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
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
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
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("correct horst battery staple"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let body = VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries: vec![entry],
            ..Default::default()
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let recovered = deserialize_vault_body(&bytes).unwrap();
        assert_eq!(recovered.entries.len(), 1);
        match &recovered.entries[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.username, "user");
                assert_eq!(e.url, "https://example.com");
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
                username: String::from("user"),
                password: String::from("s3cr3t"),
                notes: None,
                custom_fields: vec![CustomField {
                    label: String::from("2FA backup"),
                    value: String::from("abc123"),
                    hidden: true,
                }],
                attachments: vec![],
                app_id: None,
                email: None,
            }),
            VaultEntry::Note(NoteEntry {
                meta: default_meta("id-002"),
                title: String::from("Recovery codes"),
                content: String::from("code1\ncode2\ncode3"),
                custom_fields: vec![],
                attachments: vec![],
            }),
        ];
        let body = VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries,
            ..Default::default()
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
    fn deserialize_folds_previous_password_into_history() {
        // A v8-shaped Login carrying the old single-slot previous_password must
        // surface as a one-per-field meta.history record after load - lossless
        // migration for the unified history model.
        let v8 = br#"{
            "folders": ["Work"],
            "entries": [
                {"Login": {
                    "meta": {"id":"id-1","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-06-01T00:00:00Z","folder":""},
                    "title":"Example","url":"https://example.com","username":"user",
                    "password":"new_pw","notes":null,"custom_fields":[],"attachments":[],
                    "previous_password":{"value":"old_pw","saved_at":"2025-05-01T00:00:00Z","expires_at":null},
                    "app_id":null,"email":null
                }}
            ]
        }"#;
        let body = deserialize_vault_body(v8).unwrap();
        match &body.entries[0] {
            VaultEntry::Login(e) => {
                let rec = e
                    .meta
                    .history
                    .iter()
                    .find(|h| h.field == "password")
                    .expect("previous_password should fold into meta.history");
                assert_eq!(rec.value, "old_pw");
                assert_eq!(rec.saved_at, "2025-05-01T00:00:00Z");
            }
            _ => panic!("Expected Login"),
        }
    }

    #[test]
    fn yubikey_aliases_defaults_when_absent_from_json() {
        // Simulates an old vault body that predates the yubikey_aliases field.
        let legacy_json = br#"{"folders":["Work","Private"],"entries":[]}"#;
        let body = deserialize_vault_body(legacy_json).unwrap();
        assert!(
            body.yubikey_aliases.is_empty(),
            "missing yubikey_aliases must default to empty map"
        );
    }

    #[test]
    fn vault_updated_at_defaults_when_absent_from_json() {
        let legacy_json = br#"{"folders":[],"entries":[]}"#;
        let body = deserialize_vault_body(legacy_json).unwrap();
        assert_eq!(
            body.vault_updated_at, "",
            "missing vault_updated_at must default to empty string"
        );
    }

    #[test]
    fn deleted_ids_defaults_when_absent_from_json() {
        let legacy_json = br#"{"folders":[],"entries":[]}"#;
        let body = deserialize_vault_body(legacy_json).unwrap();
        assert!(
            body.deleted_ids.is_empty(),
            "missing deleted_ids must default to empty vec"
        );
    }

    #[test]
    fn deleted_entry_roundtrips() {
        use super::DeletedEntry;
        let body = VaultBody {
            folders: vec![],
            entries: vec![],
            deleted_ids: vec![DeletedEntry {
                id: String::from("uuid-abc"),
                deleted_at: String::from("2026-01-01T10:00:00Z"),
            }],
            vault_updated_at: String::from("2026-01-01T10:00:01Z"),
            ..Default::default()
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let recovered = deserialize_vault_body(&bytes).unwrap();
        assert_eq!(recovered.deleted_ids.len(), 1);
        assert_eq!(recovered.deleted_ids[0].id, "uuid-abc");
        assert_eq!(recovered.deleted_ids[0].deleted_at, "2026-01-01T10:00:00Z");
        assert_eq!(recovered.vault_updated_at, "2026-01-01T10:00:01Z");
    }

    #[test]
    fn yubikey_aliases_roundtrips() {
        let mut aliases = HashMap::new();
        aliases.insert(String::from("aabbcc"), String::from("main"));
        aliases.insert(String::from("ddeeff"), String::from("backup1"));
        let body = VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries: vec![],
            yubikey_aliases: aliases.clone(),
            ..Default::default()
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let recovered = deserialize_vault_body(&bytes).unwrap();
        assert_eq!(recovered.yubikey_aliases, aliases);
    }

    #[test]
    fn serialized_bytes_are_valid_utf8_json() {
        let entry = VaultEntry::Note(NoteEntry {
            meta: default_meta("id-001"),
            title: String::from("Test"),
            content: String::from("Hello"),
            custom_fields: vec![],
            attachments: vec![],
        });
        let body = VaultBody {
            folders: DEFAULT_FOLDERS.map(String::from).to_vec(),
            entries: vec![entry],
            ..Default::default()
        };
        let bytes = serialize_vault_body(&body).unwrap();
        let json_str = std::str::from_utf8(&bytes).expect("bytes should be valid UTF-8");
        assert!(json_str.starts_with('{'));
        assert!(json_str.ends_with('}'));
    }
}
