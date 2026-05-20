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
            custom_fields: e
                .custom_fields
                .iter()
                .map(|f| CustomFieldData {
                    label: f.label.clone(),
                    value: f.value.clone(),
                    hidden: f.hidden,
                })
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
            custom_fields: e
                .custom_fields
                .iter()
                .map(|f| CustomFieldData {
                    label: f.label.clone(),
                    value: f.value.clone(),
                    hidden: f.hidden,
                })
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
            custom_fields: e
                .custom_fields
                .iter()
                .map(|f| CustomFieldData {
                    label: f.label.clone(),
                    value: f.value.clone(),
                    hidden: f.hidden,
                })
                .collect(),
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
            fields: e
                .fields
                .values()
                .map(|f| CustomFieldData {
                    label: f.label.clone(),
                    value: f.value.clone(),
                    hidden: f.hidden,
                })
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
            custom_fields: d
                .custom_fields
                .into_iter()
                .map(|f| CustomField {
                    label: f.label,
                    value: f.value,
                    hidden: f.hidden,
                })
                .collect(),
            attachments: vec![],
            previous_password: d
                .previous_password
                .map(|p| crate::vault::entry::PreviousSecret {
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
            custom_fields: d
                .custom_fields
                .into_iter()
                .map(|f| CustomField {
                    label: f.label,
                    value: f.value,
                    hidden: f.hidden,
                })
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
            fields: d
                .fields
                .into_iter()
                .map(|f| {
                    (
                        f.label.clone(),
                        CustomField {
                            label: f.label,
                            value: f.value,
                            hidden: f.hidden,
                        },
                    )
                })
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
    use crate::api::vault::chrono_now;
    use uuid::Uuid;
    let mut internal = vault_entry_from_data(entry)?;
    let now = chrono_now();
    let id = Uuid::new_v4().to_string();
    // `ref mut e` borrows the inner value rather than moving it — required
    // because VaultEntry now implements Drop via ZeroizeOnDrop.
    match &mut internal {
        VaultEntry::Login(ref mut e) => {
            e.meta.id = id;
            e.meta.created_at = now.clone();
            e.meta.updated_at = now;
        }
        VaultEntry::Note(ref mut e) => {
            e.meta.id = id;
            e.meta.created_at = now.clone();
            e.meta.updated_at = now;
        }
        VaultEntry::Identity(ref mut e) => {
            e.meta.id = id;
            e.meta.created_at = now.clone();
            e.meta.updated_at = now;
        }
        VaultEntry::Card(ref mut e) => {
            e.meta.id = id;
            e.meta.created_at = now.clone();
            e.meta.updated_at = now;
        }
        VaultEntry::File(ref mut e) => {
            e.meta.id = id;
            e.meta.created_at = now.clone();
            e.meta.updated_at = now;
        }
        VaultEntry::Custom(ref mut e) => {
            e.meta.id = id;
            e.meta.created_at = now.clone();
            e.meta.updated_at = now;
        }
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

/// Assign a folder to a set of entries by UUID and persist.
///
/// Pass `folder: ""` to move entries to unfoldered.
/// Returns `Err` if the folder name does not exist (empty string always valid).
/// Async — triggers a full vault save.
pub async fn assign_folder_to_entries(ids: Vec<String>, folder: String) -> Result<(), String> {
    session::session_assign_folder_to_entries(&ids, folder)
}

/// Write .gabbro + .gabbro.sha256 from current session state.
///
/// Async — filesystem operation.
pub async fn export_vault(path: String) -> Result<(), String> {
    session::session_export_vault(PathBuf::from(path))
}

/// YubiKey credential record returned by `list_vault_yubikey_records`.
///
/// The Android layer uses `credential_id` to identify which YubiKey credential
/// to present, and `salt` as the CTAP2 hmac-secret challenge salt.
pub struct YubikeyRecordData {
    pub credential_id: Vec<u8>,
    pub salt: Vec<u8>,
}

/// Read the vault header at `path` and return any YubiKey records it contains.
///
/// Does **not** decrypt the vault body — safe to call before the user enters
/// their passphrase. Returns an empty list for passphrase-only vaults.
/// Sync — file I/O + header parse, no crypto.
#[flutter_rust_bridge::frb(sync)]
pub fn list_vault_yubikey_records(path: String) -> Result<Vec<YubikeyRecordData>, String> {
    use crate::vault::io::read_vault;
    let sealed = read_vault(&PathBuf::from(path))?;
    Ok(sealed
        .yubikey_records
        .into_iter()
        .map(|r| YubikeyRecordData {
            credential_id: r.credential_id,
            salt: r.salt.to_vec(),
        })
        .collect())
}

/// Decrypt the vault at `path` using both passphrase and YubiKey hmac-secret.
///
/// `hmac_secret` must be exactly 32 bytes (FIDO2 hmac-secret output).
/// `hkdf_salt` must be exactly 32 bytes (from `YubikeyRecordData.salt`).
/// Async — Argon2id takes ~667ms on target hardware.
pub async fn unlock_vault_with_yubikey(
    passphrase: Vec<u8>,
    hmac_secret: Vec<u8>,
    credential_id: Vec<u8>,
    hkdf_salt: Vec<u8>,
    path: String,
) -> Result<(), String> {
    let secret: [u8; 32] = hmac_secret
        .try_into()
        .map_err(|_| "hmac_secret must be exactly 32 bytes".to_string())?;
    let salt: [u8; 32] = hkdf_salt
        .try_into()
        .map_err(|_| "hkdf_salt must be exactly 32 bytes".to_string())?;
    session::unlock_vault_with_yubikey(
        &passphrase,
        &secret,
        credential_id,
        &salt,
        PathBuf::from(path),
    )
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

/// Create a new empty vault at `path`, sealed with both passphrase and YubiKey.
///
/// Called during onboarding when the user opts in to YubiKey protection.
/// After creation, unlocks into session immediately.
/// `hmac_secret` must be exactly 32 bytes. `hkdf_salt` must be exactly 32 bytes.
/// Async — runs Argon2id + encryption.
pub async fn init_vault_with_yubikey(
    passphrase: Vec<u8>,
    hmac_secret: Vec<u8>,
    credential_id: Vec<u8>,
    hkdf_salt: Vec<u8>,
    path: String,
) -> Result<(), String> {
    use crate::api::vault::save_vault_with_yubikey;
    use crate::vault::serialization::VaultBody;
    let secret: [u8; 32] = hmac_secret
        .try_into()
        .map_err(|_| "hmac_secret must be exactly 32 bytes".to_string())?;
    let salt: [u8; 32] = hkdf_salt
        .try_into()
        .map_err(|_| "hkdf_salt must be exactly 32 bytes".to_string())?;
    let vault_path = PathBuf::from(&path);
    save_vault_with_yubikey(
        &VaultBody::empty(),
        &passphrase,
        &secret,
        credential_id.clone(),
        salt,
        &vault_path,
    )?;
    session::unlock_vault_with_yubikey(&passphrase, &secret, credential_id, &salt, vault_path)
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::serialization::VaultBody;
    use serial_test::serial;

    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(f)
    }

    #[test]
    #[serial]
    fn unlock_lock_roundtrip() {
        use crate::api::vault::save_vault;
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

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
        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
            },
            pass,
            &path,
        )
        .unwrap();

        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();
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
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_list_folders_test.gabbro");
        let pass = b"bridge-folder-test";
        let folders = vec![String::from("Work"), String::from("Private")];

        save_vault(
            &VaultBody {
                folders: folders.clone(),
                entries: vec![],
            },
            pass,
            &path,
        )
        .unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let result = list_folders().unwrap();
        assert_eq!(result, folders);

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn create_folder_adds_folder_via_bridge() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_create_folder_test.gabbro");
        let pass = b"bridge-folder-test";

        save_vault(
            &VaultBody {
                folders: vec![String::from("Work")],
                entries: vec![],
            },
            pass,
            &path,
        )
        .unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

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
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_rename_folder_test.gabbro");
        let pass = b"bridge-folder-test";

        save_vault(
            &VaultBody {
                folders: vec![String::from("Work")],
                entries: vec![],
            },
            pass,
            &path,
        )
        .unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(rename_folder(String::from("Work"), String::from("Career"))).unwrap();

        let folders = list_folders().unwrap();
        assert!(
            folders.contains(&String::from("Career")),
            "new name must appear"
        );
        assert!(
            !folders.contains(&String::from("Work")),
            "old name must be gone"
        );

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn delete_folder_removes_folder_via_bridge() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_delete_folder_test.gabbro");
        let pass = b"bridge-folder-test";

        save_vault(
            &VaultBody {
                folders: vec![String::from("Work"), String::from("Private")],
                entries: vec![],
            },
            pass,
            &path,
        )
        .unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(delete_folder(String::from("Work"), None)).unwrap();

        let folders = list_folders().unwrap();
        assert!(
            !folders.contains(&String::from("Work")),
            "deleted folder must be gone"
        );
        assert!(
            folders.contains(&String::from("Private")),
            "other folders must remain"
        );

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn assign_folder_to_entries_via_bridge() {
        use crate::api::vault::save_vault;
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_assign_folder_test.gabbro");
        let pass = b"bridge-assign-folder-test";

        let entries = vec![VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from(""),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("hunter2"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        })];

        save_vault(
            &VaultBody {
                folders: vec![String::from("Work")],
                entries,
            },
            pass,
            &path,
        )
        .unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(assign_folder_to_entries(
            vec![String::from("id-001")],
            String::from("Work"),
        ))
        .unwrap();

        let entry = get_entry(String::from("id-001")).unwrap();
        match entry {
            VaultEntryData::Login(e) => {
                assert_eq!(e.folder, "Work", "entry folder must be updated via bridge")
            }
            _ => panic!("expected Login"),
        }

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[ignore]
    fn create_test_vault_on_disk() {
        use crate::api::vault::save_vault;
        use crate::vault::entry::{EntryMeta, LoginEntry, NoteEntry, VaultEntry};
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

        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
            },
            pass,
            &path,
        )
        .unwrap();
        println!("Test vault written to {:?}", path);
    }

    // ── YubiKey bridge tests ──────────────────────────────────────────────────

    #[test]
    #[serial]
    fn list_yubikey_records_empty_for_passphrase_only_vault() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_yubikey_list_empty_test.gabbro");
        let pass = b"passphrase-only";

        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        let records = list_vault_yubikey_records(path.to_str().unwrap().to_string()).unwrap();
        assert!(
            records.is_empty(),
            "passphrase-only vault must have no YubiKey records"
        );

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn list_yubikey_records_returns_record_for_yubikey_vault() {
        use crate::api::vault::save_vault_with_yubikey;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_yubikey_list_record_test.gabbro");
        let pass = b"test-passphrase";
        let hmac_secret = [0x42u8; 32];
        let credential_id = vec![0xABu8; 64];
        let hkdf_salt = [0x11u8; 32];

        save_vault_with_yubikey(
            &VaultBody::empty(),
            pass,
            &hmac_secret,
            credential_id.clone(),
            hkdf_salt,
            &path,
        )
        .unwrap();

        let records = list_vault_yubikey_records(path.to_str().unwrap().to_string()).unwrap();
        assert_eq!(records.len(), 1, "YubiKey vault must have one record");
        assert_eq!(records[0].credential_id, credential_id);
        assert_eq!(records[0].salt, hkdf_salt.to_vec());

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn unlock_vault_with_yubikey_via_bridge() {
        use crate::api::vault::save_vault_with_yubikey;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_yubikey_unlock_test.gabbro");
        let pass = b"unlock-test-pass";
        let hmac_secret = [0x77u8; 32];
        let credential_id = vec![0xCDu8; 48];
        let hkdf_salt = [0x22u8; 32];

        save_vault_with_yubikey(
            &VaultBody::empty(),
            pass,
            &hmac_secret,
            credential_id.clone(),
            hkdf_salt,
            &path,
        )
        .unwrap();

        run(unlock_vault_with_yubikey(
            pass.to_vec(),
            hmac_secret.to_vec(),
            credential_id,
            hkdf_salt.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let summaries = list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 0, "empty vault must have no entries");

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn init_vault_with_yubikey_creates_and_unlocks() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_yubikey_init_test.gabbro");
        let pass = b"init-yubikey-pass";
        let hmac_secret = [0x55u8; 32];
        let credential_id = vec![0xEFu8; 32];
        let hkdf_salt = [0x33u8; 32];

        run(init_vault_with_yubikey(
            pass.to_vec(),
            hmac_secret.to_vec(),
            credential_id.clone(),
            hkdf_salt.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        // Session is live after init
        let summaries = list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 0, "fresh vault must be empty");

        lock_vault().unwrap();

        // Vault file must carry the YubiKey record
        let records = list_vault_yubikey_records(path.to_str().unwrap().to_string()).unwrap();
        assert_eq!(records.len(), 1, "init must write YubiKey record");
        assert_eq!(records[0].credential_id, credential_id);

        let _ = std::fs::remove_file(&path);
    }
}
