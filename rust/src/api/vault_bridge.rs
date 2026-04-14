//! Vault bridge — flutter_rust_bridge-facing wrappers for vault persistence.
//!
//! These functions are what Flutter actually calls. They translate between
//! bridge-friendly types (String paths, Vec<u8> passphrases, DTO enums) and
//! the internal Rust types used by the vault backend.
//!
//! The internal vault.rs functions are never called directly from Flutter.

use std::path::Path;

use crate::api::vault::{
    CardEntryData, CustomEntryData, CustomFieldData, FileEntryData, IdentityEntryData,
    LoginEntryData, NoteEntryData,
    load_vault, save_vault,
};
use crate::vault::entry::{
    CardEntry, CustomEntry, CustomField, EntryMeta, FileEntry, IdentityEntry, LoginEntry,
    NoteEntry, VaultEntry,
};

// ── Bridge-facing VaultEntry enum ────────────────────────────────────────────

/// A vault entry as seen by Flutter.
///
/// This is a bridge-facing enum that wraps the existing DTOs.
/// flutter_rust_bridge generates a Dart sealed class hierarchy from this,
/// which Flutter code can switch/match on — one case per entry type.
pub enum VaultEntryData {
    Login(LoginEntryData),
    Note(NoteEntryData),
    Identity(IdentityEntryData),
    Card(CardEntryData),
    File(FileEntryData),
    Custom(CustomEntryData),
}

// ── Conversion: internal VaultEntry → VaultEntryData DTO ─────────────────────

fn vault_entry_to_data(entry: VaultEntry) -> VaultEntryData {
    match entry {
        VaultEntry::Login(e) => VaultEntryData::Login(LoginEntryData {
            id: e.meta.id,
            created_at: e.meta.created_at,
            updated_at: e.meta.updated_at,
            folder: e.meta.folder,
            tags: e.meta.tags,
            favourite: e.meta.favourite,
            url: e.url,
            username: e.username,
            password: e.password,
            notes: e.notes,
            custom_fields: e.custom_fields
                .into_iter()
                .map(|f| CustomFieldData { label: f.label, value: f.value, hidden: f.hidden })
                .collect(),
        }),
        VaultEntry::Note(e) => VaultEntryData::Note(NoteEntryData {
            id: e.meta.id,
            created_at: e.meta.created_at,
            updated_at: e.meta.updated_at,
            folder: e.meta.folder,
            tags: e.meta.tags,
            favourite: e.meta.favourite,
            title: e.title,
            content: e.content,
        }),
        VaultEntry::Identity(e) => VaultEntryData::Identity(IdentityEntryData {
            id: e.meta.id,
            created_at: e.meta.created_at,
            updated_at: e.meta.updated_at,
            folder: e.meta.folder,
            tags: e.meta.tags,
            favourite: e.meta.favourite,
            first_name: e.first_name,
            last_name: e.last_name,
            email: e.email,
            phone: e.phone,
            address: e.address,
        }),
        VaultEntry::Card(e) => VaultEntryData::Card(CardEntryData {
            id: e.meta.id,
            created_at: e.meta.created_at,
            updated_at: e.meta.updated_at,
            folder: e.meta.folder,
            tags: e.meta.tags,
            favourite: e.meta.favourite,
            cardholder_name: e.cardholder_name,
            card_number: e.card_number,
            expiry: e.expiry,
            cvv: e.cvv,
            notes: e.notes,
        }),
        VaultEntry::File(e) => VaultEntryData::File(FileEntryData {
            id: e.meta.id,
            created_at: e.meta.created_at,
            updated_at: e.meta.updated_at,
            folder: e.meta.folder,
            tags: e.meta.tags,
            favourite: e.meta.favourite,
            filename: e.filename,
            data: e.data,
            notes: e.notes,
        }),
        VaultEntry::Custom(e) => VaultEntryData::Custom(CustomEntryData {
            id: e.meta.id,
            created_at: e.meta.created_at,
            updated_at: e.meta.updated_at,
            folder: e.meta.folder,
            tags: e.meta.tags,
            favourite: e.meta.favourite,
            title: e.title,
            fields: e.fields
                .into_values()
                .map(|f| CustomFieldData { label: f.label, value: f.value, hidden: f.hidden })
                .collect(),
        }),
    }
}

// ── Conversion: VaultEntryData DTO → internal VaultEntry ─────────────────────

fn vault_entry_from_data(data: VaultEntryData) -> Result<VaultEntry, String> {
    match data {
        VaultEntryData::Login(d) => Ok(VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
                tags: d.tags,
                favourite: d.favourite,
            },
            url: d.url,
            username: d.username,
            password: d.password,
            notes: d.notes,
            custom_fields: d.custom_fields
                .into_iter()
                .map(|f| CustomField { label: f.label, value: f.value, hidden: f.hidden })
                .collect(),
        })),
        VaultEntryData::Note(d) => Ok(VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
                tags: d.tags,
                favourite: d.favourite,
            },
            title: d.title,
            content: d.content,
        })),
        VaultEntryData::Identity(d) => Ok(VaultEntry::Identity(IdentityEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
                tags: d.tags,
                favourite: d.favourite,
            },
            first_name: d.first_name,
            last_name: d.last_name,
            email: d.email,
            phone: d.phone,
            address: d.address,
        })),
        VaultEntryData::Card(d) => {
            let meta = EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
                tags: d.tags,
                favourite: d.favourite,
            };
            let entry = CardEntry::new(
                meta,
                d.cardholder_name,
                d.card_number,
                d.expiry,
                d.cvv,
                d.notes,
            )?;
            Ok(VaultEntry::Card(entry))
        }
        VaultEntryData::File(d) => Ok(VaultEntry::File(FileEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
                tags: d.tags,
                favourite: d.favourite,
            },
            filename: d.filename,
            data: d.data,
            notes: d.notes,
        })),
        VaultEntryData::Custom(d) => Ok(VaultEntry::Custom(CustomEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
                tags: d.tags,
                favourite: d.favourite,
            },
            title: d.title,
            fields: d.fields
                .into_iter()
                .map(|f| (f.label.clone(), CustomField { label: f.label, value: f.value, hidden: f.hidden }))
                .collect(),
        })),
    }
}

// ── Bridge-facing API ─────────────────────────────────────────────────────────

/// Serialize, encrypt, and write a vault to disk.
///
/// Called by Flutter with a list of entries, the user's passphrase,
/// and the path to write to. The path is a String because `std::path::Path`
/// is not a bridge-friendly type.
///
/// This is an async function — Flutter awaits it without blocking the UI
/// during the Argon2id KDF (~667ms on target hardware).
pub async fn save_vault_to_disk(
    entries: Vec<VaultEntryData>,
    passphrase: Vec<u8>,
    path: String,
) -> Result<(), String> {
    let internal: Result<Vec<VaultEntry>, String> = entries
        .into_iter()
        .map(vault_entry_from_data)
        .collect();
    let internal = internal?;
    save_vault(&internal, &passphrase, Path::new(&path))
}

/// Read, decrypt, and deserialize a vault from disk.
///
/// Called by Flutter with the user's passphrase and the path to read from.
/// Returns all entries as bridge-facing DTOs.
///
/// This is an async function — Flutter awaits it without blocking the UI
/// during the Argon2id KDF (~667ms on target hardware).
pub async fn load_vault_from_disk(
    passphrase: Vec<u8>,
    path: String,
) -> Result<Vec<VaultEntryData>, String> {
    let entries = load_vault(&passphrase, Path::new(&path))?;
    Ok(entries.into_iter().map(vault_entry_to_data).collect())
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // Helper to run async functions in tests
    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(f)
    }

    #[test]
    fn save_and_load_roundtrip_via_bridge() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_roundtrip_test.gabbro");
        let path_str = path.to_str().unwrap().to_string();

        let entries = vec![
            VaultEntryData::Note(NoteEntryData {
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
                title: String::from("Bridge test note"),
                content: String::from("bridge secret content"),
            }),
        ];

        let passphrase = b"correct horst battery staple".to_vec();

        run(save_vault_to_disk(entries, passphrase.clone(), path_str.clone())).unwrap();
        let recovered = run(load_vault_from_disk(passphrase, path_str)).unwrap();

        assert_eq!(recovered.len(), 1);
        match &recovered[0] {
            VaultEntryData::Note(e) => assert_eq!(e.content, "bridge secret content"),
            _ => panic!("Expected Note variant"),
        }

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn load_wrong_passphrase_returns_error() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_wrong_pass_test.gabbro");
        let path_str = path.to_str().unwrap().to_string();

        let entries: Vec<VaultEntryData> = vec![];
        run(save_vault_to_disk(entries, b"correct".to_vec(), path_str.clone())).unwrap();

        let result = run(load_vault_from_disk(b"wrong".to_vec(), path_str));
        let _ = std::fs::remove_file(&path);

        assert!(result.is_err());
    }
}