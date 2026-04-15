//! Vault bridge — flutter_rust_bridge-facing wrappers for vault persistence.
//!
//! These functions are what Flutter actually calls. They translate between
//! bridge-friendly types (String paths, Vec<u8> passphrases, DTO enums) and
//! the internal Rust types used by the vault backend.
//!
//! The internal vault.rs functions are never called directly from Flutter.

use std::path::PathBuf;

use crate::api::vault::{
    CardEntryData, CustomEntryData, CustomFieldData, FileEntryData, IdentityEntryData,
    LoginEntryData, NoteEntryData,
};
use crate::vault::entry::{
    CardEntry, CustomEntry, CustomField, EntryMeta, FileEntry, IdentityEntry, LoginEntry,
    NoteEntry, VaultEntry,
};
use crate::vault::session;

/// Lightweight entry summary returned by `list_entry_summaries()`.
///
/// Contains just enough for Flutter to render a list row — no secrets.
pub struct EntrySummaryData {
    pub id: String,
    pub entry_type: String,
    pub title: String,
    pub folder: String,
    pub tags: Vec<String>,
    pub favourite: bool,
}

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

/// Decrypt the vault at `path` and store it in the session.
///
/// Async — Argon2id takes ~667ms on target hardware.
pub async fn unlock_vault(passphrase: Vec<u8>, path: String) -> Result<(), String> {
    session::unlock_vault(&passphrase, PathBuf::from(path))
}

/// Drop the session state, locking the vault.
///
/// Sync — instant, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn lock_vault() -> Result<(), String> {
    session::lock_vault()
}

/// Return lightweight summaries of all entries — no secrets.
///
/// Sync — reads from in-memory session, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn list_entry_summaries() -> Result<Vec<EntrySummaryData>, String> {
    session::list_entry_summaries()
}

/// Return one full entry DTO by UUID.
///
/// Sync — reads from in-memory session, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn get_entry(id: String) -> Result<VaultEntryData, String> {
    let entry = session::get_entry(&id)?;
    Ok(vault_entry_to_data(entry))
}

/// Add a new entry to the session and persist the vault to disk.
///
/// Async — triggers a full vault save (Argon2id + encryption).
pub async fn create_entry(entry: VaultEntryData) -> Result<EntrySummaryData, String> {
    let internal = vault_entry_from_data(entry)?;
    session::session_create_entry(internal)
}

/// Replace an existing entry by UUID and persist.
///
/// Async — triggers a full vault save.
pub async fn update_entry(entry: VaultEntryData) -> Result<(), String> {
    let internal = vault_entry_from_data(entry)?;
    session::session_update_entry(internal)
}

/// Remove an entry by UUID and persist.
///
/// Async — triggers a full vault save.
pub async fn delete_entry(id: String) -> Result<(), String> {
    session::session_delete_entry(&id)
}

/// Wipe the vault file from disk and drop the session.
///
/// Async — filesystem operation.
pub async fn delete_whole_vault() -> Result<(), String> {
    session::session_delete_whole_vault()
}

/// Re-seal the vault under a new passphrase. Session remains live.
///
/// Async — triggers a full vault save.
pub async fn change_passphrase(
    old_passphrase: Vec<u8>,
    new_passphrase: Vec<u8>,
) -> Result<(), String> {
    session::session_change_passphrase(&old_passphrase, &new_passphrase)
}

/// Write .gabbro + .gabbro.sha256 from current session state.
///
/// Async — filesystem operation.
pub async fn export_vault(path: String) -> Result<(), String> {
    session::session_export_vault(PathBuf::from(path))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;

    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(f)
    }

    #[test]
    #[serial]
    fn unlock_lock_roundtrip() {
        use std::env::temp_dir;
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use crate::api::vault::save_vault;

        let mut path = temp_dir();
        path.push("gabbro_bridge_v2_test.gabbro");
        let pass = b"bridge test passphrase";

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
            },
            title: String::from("Bridge v2 test"),
            content: String::from("bridge v2 content"),
        })];
        save_vault(&entries, pass, &path).unwrap();

        run(unlock_vault(pass.to_vec(), path.to_str().unwrap().to_string())).unwrap();
        let summaries = list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].entry_type, "Note");

        let entry = get_entry(String::from("id-001")).unwrap();
        match entry {
            VaultEntryData::Note(e) => assert_eq!(e.content, "bridge v2 content"),
            _ => panic!("Expected Note variant"),
        }

        lock_vault().unwrap();
        assert!(list_entry_summaries().is_err());

        let _ = std::fs::remove_file(&path);
    }

#[test]
#[ignore]
fn create_test_vault_on_disk() {
    use crate::vault::entry::{EntryMeta, NoteEntry, LoginEntry, VaultEntry};
    use crate::api::vault::save_vault;
    use std::path::PathBuf;

    let path = PathBuf::from("/tmp/gabbro_dev.gabbro");
    let pass = b"test passphrase";

    let entries = vec![
        VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: String::from("note-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
            },
            title: String::from("NAS recovery key"),
            content: String::from("secret content here"),
        }),
        VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Work"),
                tags: vec![],
                favourite: true,
            },
            url: String::from("https://github.com"),
            username: String::from("Zabamund"),
            password: String::from("hunter2"),
            notes: None,
            custom_fields: vec![],
        }),
    ];

    save_vault(&entries, pass, &path).unwrap();
    println!("Test vault written to {:?}", path);
}
}