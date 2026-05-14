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
    LoginEntryData, NoteEntryData, PreviousSecretData,
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

// Takes a reference to avoid moving out of a type that implements Drop
// (via ZeroizeOnDrop). All fields are cloned explicitly.
fn vault_entry_to_data(entry: &VaultEntry) -> VaultEntryData {
    match entry {
        VaultEntry::Login(e) => VaultEntryData::Login(LoginEntryData {
            id: e.meta.id.clone(),
            created_at: e.meta.created_at.clone(),
            updated_at: e.meta.updated_at.clone(),
            folder: e.meta.folder.clone(),
            title: e.title.clone(),
            url: e.url.clone(),
            username: e.username.clone(),
            password: e.password.clone(),
            notes: e.notes.clone(),
            custom_fields: e.custom_fields
                .iter()
                .map(|f| CustomFieldData { label: f.label.clone(), value: f.value.clone(), hidden: f.hidden })
                .collect(),
            previous_password: e.previous_password.as_ref().map(|p| PreviousSecretData {
                value: p.value.clone(),
                saved_at: p.saved_at.clone(),
                expires_at: p.expires_at.clone(),
            }),
        }),
        VaultEntry::Note(e) => VaultEntryData::Note(NoteEntryData {
            id: e.meta.id.clone(),
            created_at: e.meta.created_at.clone(),
            updated_at: e.meta.updated_at.clone(),
            folder: e.meta.folder.clone(),
            title: e.title.clone(),
            content: e.content.clone(),
        }),
        VaultEntry::Identity(e) => VaultEntryData::Identity(IdentityEntryData {
            id: e.meta.id.clone(),
            created_at: e.meta.created_at.clone(),
            updated_at: e.meta.updated_at.clone(),
            folder: e.meta.folder.clone(),
            first_name: e.first_name.clone(),
            last_name: e.last_name.clone(),
            email: e.email.clone(),
            phone: e.phone.clone(),
            address: e.address.clone(),
            custom_fields: e.custom_fields
                .iter()
                .map(|f| CustomFieldData { label: f.label.clone(), value: f.value.clone(), hidden: f.hidden })
                .collect(),
        }),
        VaultEntry::Card(e) => VaultEntryData::Card(CardEntryData {
            id: e.meta.id.clone(),
            created_at: e.meta.created_at.clone(),
            updated_at: e.meta.updated_at.clone(),
            folder: e.meta.folder.clone(),
            card_name: e.card_name.clone(),
            status: e.status.clone(),
            cardholder_name: e.cardholder_name.clone(),
            card_number: e.card_number.clone(),
            expiry: e.expiry.clone(),
            cvv: e.cvv.clone(),
            credit_limit: e.credit_limit.clone(),
            card_account_number: e.card_account_number.clone(),
            payment_network: e.payment_network.clone(),
            pin: e.pin.clone(),
            bank_name: e.bank_name.clone(),
            transaction_password: e.transaction_password.clone(),
            notes: e.notes.clone(),
            custom_fields: e.custom_fields.iter().map(|f| CustomFieldData {
                label: f.label.clone(),
                value: f.value.clone(),
                hidden: f.hidden,
            }).collect(),
            previous_cvv: e.previous_cvv.as_ref().map(|p| PreviousSecretData {
                value: crate::api::vault::MASKED_VALUE.to_string(),
                saved_at: p.saved_at.clone(),
                expires_at: p.expires_at.clone(),
            }),
            previous_pin: e.previous_pin.as_ref().map(|p| PreviousSecretData {
                value: crate::api::vault::MASKED_VALUE.to_string(),
                saved_at: p.saved_at.clone(),
                expires_at: p.expires_at.clone(),
            }),
        }),
        VaultEntry::File(e) => VaultEntryData::File(FileEntryData {
            id: e.meta.id.clone(),
            created_at: e.meta.created_at.clone(),
            updated_at: e.meta.updated_at.clone(),
            folder: e.meta.folder.clone(),
            filename: e.filename.clone(),
            data: e.data.clone(),
            notes: e.notes.clone(),
        }),
        VaultEntry::Custom(e) => VaultEntryData::Custom(CustomEntryData {
            id: e.meta.id.clone(),
            created_at: e.meta.created_at.clone(),
            updated_at: e.meta.updated_at.clone(),
            folder: e.meta.folder.clone(),
            title: e.title.clone(),
            fields: e.fields
                .values()
                .map(|f| CustomFieldData { label: f.label.clone(), value: f.value.clone(), hidden: f.hidden })
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
            },
            title: d.title,
            url: d.url,
            username: d.username,
            password: d.password,
            notes: d.notes,
            custom_fields: d.custom_fields
                .into_iter()
                .map(|f| CustomField { label: f.label, value: f.value, hidden: f.hidden })
                .collect(),
            attachments: vec![],
            previous_password: d.previous_password.map(|p| crate::vault::entry::PreviousSecret {
                value: p.value,
                saved_at: p.saved_at,
                expires_at: p.expires_at,
            }),
        })),
        VaultEntryData::Note(d) => Ok(VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
            },
            title: d.title,
            content: d.content,
            attachments: vec![],
        })),
        VaultEntryData::Identity(d) => Ok(VaultEntry::Identity(IdentityEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
            },
            first_name: d.first_name,
            last_name: d.last_name,
            email: d.email,
            phone: d.phone,
            address: d.address,
            custom_fields: d.custom_fields
                .into_iter()
                .map(|f| CustomField { label: f.label, value: f.value, hidden: f.hidden })
                .collect(),
            attachments: vec![],
        })),
        VaultEntryData::Card(d) => {
            let meta = EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
            };
            let entry = CardEntry::new(
                meta,
                d.card_name,
                d.status,
                d.cardholder_name,
                d.card_number,
                d.expiry,
                d.cvv,
                d.credit_limit,
                d.card_account_number,
                d.payment_network,
                d.pin,
                d.bank_name,
                d.transaction_password,
                d.notes,
                vec![],
                vec![],
                None,
                None,
            )?;
            Ok(VaultEntry::Card(entry))
        }
        VaultEntryData::File(d) => Ok(VaultEntry::File(FileEntry {
            meta: EntryMeta {
                id: d.id,
                created_at: d.created_at,
                updated_at: d.updated_at,
                folder: d.folder,
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
            },
            title: d.title,
            fields: d.fields
                .into_iter()
                .map(|f| (f.label.clone(), CustomField { label: f.label, value: f.value, hidden: f.hidden }))
                .collect(),
            attachments: vec![],
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

/// Return the list of folder names from the current session.
///
/// Sync — reads from in-memory session, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn list_folders() -> Result<Vec<String>, String> {
    session::session_list_folders()
}

/// Rename an existing folder and update all entries that reference it.
///
/// Returns `Err` if `old_name` does not exist, `new_name` is empty,
/// or `new_name` already exists.
/// Async — triggers a full vault save.
pub async fn rename_folder(old_name: String, new_name: String) -> Result<(), String> {
    session::session_rename_folder(old_name, new_name)
}

/// Delete a folder and either reassign its entries to another folder or
/// clear them to unfoldered (`""`).
///
/// Returns `Err` if `name` does not exist, or if `reassign_to` names a
/// folder that does not exist.
/// Async — triggers a full vault save.
pub async fn delete_folder(name: String, reassign_to: Option<String>) -> Result<(), String> {
    session::session_delete_folder(name, reassign_to)
}

/// Add a new folder to the session and persist the vault to disk.
///
/// Returns `Err` if the name is empty or already exists.
/// Async — triggers a full vault save.
pub async fn create_folder(name: String) -> Result<(), String> {
    session::session_create_folder(name)
}

/// Return one full entry DTO by UUID.
///
/// Sync — reads from in-memory session, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn get_entry(id: String) -> Result<VaultEntryData, String> {
    let entry = session::get_entry(&id)?;
    Ok(vault_entry_to_data(&entry))
}

/// Add a new entry to the session and persist the vault to disk.
///
/// Async — triggers a full vault save (Argon2id + encryption).
pub async fn create_entry(entry: VaultEntryData) -> Result<EntrySummaryData, String> {
    use uuid::Uuid;
    use crate::api::vault::chrono_now;
    let mut internal = vault_entry_from_data(entry)?;
    let now = chrono_now();
    let id = Uuid::new_v4().to_string();
    // `ref mut e` borrows the inner value rather than moving it — required
    // because VaultEntry now implements Drop via ZeroizeOnDrop.
    match &mut internal {
        VaultEntry::Login(ref mut e)    => { e.meta.id = id; e.meta.created_at = now.clone(); e.meta.updated_at = now; }
        VaultEntry::Note(ref mut e)     => { e.meta.id = id; e.meta.created_at = now.clone(); e.meta.updated_at = now; }
        VaultEntry::Identity(ref mut e) => { e.meta.id = id; e.meta.created_at = now.clone(); e.meta.updated_at = now; }
        VaultEntry::Card(ref mut e)     => { e.meta.id = id; e.meta.created_at = now.clone(); e.meta.updated_at = now; }
        VaultEntry::File(ref mut e)     => { e.meta.id = id; e.meta.created_at = now.clone(); e.meta.updated_at = now; }
        VaultEntry::Custom(ref mut e)   => { e.meta.id = id; e.meta.created_at = now.clone(); e.meta.updated_at = now; }
    }
    session::session_create_entry(internal)
}

/// Replace an existing entry by UUID and persist.
///
/// `expiry_days`: how long to retain the previous sensitive value.
/// `None` = keep until manually deleted. `Some(n)` = purge after n days.
/// Async — triggers a full vault save.
pub async fn update_entry(entry: VaultEntryData, expiry_days: Option<u32>) -> Result<(), String> {
    let internal = vault_entry_from_data(entry)?;
    session::session_update_entry(internal, expiry_days)
}

/// Remove an entry by UUID and persist.
///
/// Async — triggers a full vault save.
pub async fn delete_entry(id: String) -> Result<(), String> {
    session::session_delete_entry(&id)
}

/// Remove multiple entries by UUID in one pass and persist once.
///
/// Async — triggers a single vault save regardless of how many entries
/// are deleted. Use this instead of calling delete_entry in a loop.
pub async fn delete_entries(ids: Vec<String>) -> Result<(), String> {
    session::session_delete_entries_no_save(&ids)?;
    session::session_save()
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

/// Clear the previous password history for a Login entry and persist.
///
/// Async — triggers a full vault save.
pub async fn session_clear_password_history(id: String) -> Result<(), String> {
    session::session_clear_password_history(&id)
}

/// Revert the current password to the previous password for a Login entry and persist.
///
/// Async — triggers a full vault save.
pub async fn session_revert_password(id: String) -> Result<(), String> {
    session::session_revert_password(&id)
}

/// Write .gabbro + .gabbro.sha256 from current session state.
///
/// Async — filesystem operation.
pub async fn export_vault(path: String) -> Result<(), String> {
    session::session_export_vault(PathBuf::from(path))
}

/// Create a new empty vault at `path`, sealed with `passphrase`.
///
/// Called during onboarding. Async — runs Argon2id + encryption.
pub async fn init_vault(passphrase: Vec<u8>, path: String) -> Result<(), String> {
    use crate::api::vault::save_vault;
    use crate::vault::serialization::VaultBody;
    let vault_path = PathBuf::from(&path);
    save_vault(&VaultBody::empty(), &passphrase, &vault_path)?;
    // Unlock into session immediately so the user lands on the list screen
    session::unlock_vault(&passphrase, vault_path)
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use crate::vault::serialization::VaultBody;

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
            },
            title: String::from("Bridge v2 test"),
            content: String::from("bridge v2 content"),
            attachments: vec![],
        })];
        save_vault(&VaultBody { folders: vec![], entries }, pass, &path).unwrap();

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
    #[serial]
    fn list_folders_returns_folders_via_bridge() {
        use std::env::temp_dir;
        use crate::api::vault::save_vault;

        let mut path = temp_dir();
        path.push("gabbro_bridge_list_folders_test.gabbro");
        let pass = b"bridge-folder-test";
        let folders = vec![
            String::from("Work"),
            String::from("Private"),
        ];

        save_vault(&VaultBody { folders: folders.clone(), entries: vec![] }, pass, &path).unwrap();
        run(unlock_vault(pass.to_vec(), path.to_str().unwrap().to_string())).unwrap();

        let result = list_folders().unwrap();
        assert_eq!(result, folders);

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn create_folder_adds_folder_via_bridge() {
        use std::env::temp_dir;
        use crate::api::vault::save_vault;

        let mut path = temp_dir();
        path.push("gabbro_bridge_create_folder_test.gabbro");
        let pass = b"bridge-folder-test";

        save_vault(&VaultBody { folders: vec![String::from("Work")], entries: vec![] }, pass, &path).unwrap();
        run(unlock_vault(pass.to_vec(), path.to_str().unwrap().to_string())).unwrap();

        run(create_folder(String::from("Private"))).unwrap();

        let folders = list_folders().unwrap();
        assert!(folders.contains(&String::from("Work")));
        assert!(folders.contains(&String::from("Private")));

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn rename_folder_updates_name_via_bridge() {
        use std::env::temp_dir;
        use crate::api::vault::save_vault;

        let mut path = temp_dir();
        path.push("gabbro_bridge_rename_folder_test.gabbro");
        let pass = b"bridge-folder-test";

        save_vault(&VaultBody { folders: vec![String::from("Work")], entries: vec![] }, pass, &path).unwrap();
        run(unlock_vault(pass.to_vec(), path.to_str().unwrap().to_string())).unwrap();

        run(rename_folder(String::from("Work"), String::from("Career"))).unwrap();

        let folders = list_folders().unwrap();
        assert!(folders.contains(&String::from("Career")), "new name must appear");
        assert!(!folders.contains(&String::from("Work")), "old name must be gone");

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn delete_folder_removes_folder_via_bridge() {
        use std::env::temp_dir;
        use crate::api::vault::save_vault;

        let mut path = temp_dir();
        path.push("gabbro_bridge_delete_folder_test.gabbro");
        let pass = b"bridge-folder-test";

        save_vault(
            &VaultBody { folders: vec![String::from("Work"), String::from("Private")], entries: vec![] },
            pass,
            &path,
        ).unwrap();
        run(unlock_vault(pass.to_vec(), path.to_str().unwrap().to_string())).unwrap();

        run(delete_folder(String::from("Work"), None)).unwrap();

        let folders = list_folders().unwrap();
        assert!(!folders.contains(&String::from("Work")), "deleted folder must be gone");
        assert!(folders.contains(&String::from("Private")), "other folders must remain");

        lock_vault().unwrap();
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
                },
                title: String::from("NAS recovery key"),
                content: String::from("secret content here"),
                attachments: vec![],
            }),
            VaultEntry::Login(LoginEntry {
                meta: EntryMeta {
                    id: String::from("login-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Work"),
                },
                title: String::from("GitHub"),
                url: String::from("https://github.com"),
                username: String::from("Zabamund"),
                password: String::from("hunter2"),
                notes: None,
                custom_fields: vec![],
                attachments: vec![],
                previous_password: None,
            }),
        ];

        save_vault(&VaultBody { folders: vec![], entries }, pass, &path).unwrap();
        println!("Test vault written to {:?}", path);
    }
}
