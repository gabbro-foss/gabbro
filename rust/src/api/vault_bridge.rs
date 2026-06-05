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
/// `search_blob` is a lowercase, space-joined string of all searchable
/// non-secret fields; Flutter uses it for opt-in full-text search.
pub struct EntrySummaryData {
    pub id: String,
    pub entry_type: String,
    pub title: String,
    pub folder: String,
    pub search_blob: String,
}

// ── Bridge-facing VaultEntry enum ────────────────────────────────────────────

/// A vault entry as seen by Flutter.
///
/// This is a bridge-facing enum that wraps the existing DTOs.
/// flutter_rust_bridge generates a Dart sealed class hierarchy from this,
/// which Flutter code can switch/match on — one case per entry type.
#[allow(clippy::large_enum_variant)]
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
            let custom_fields = d
                .custom_fields
                .into_iter()
                .map(|f| CustomField {
                    label: f.label,
                    value: f.value,
                    hidden: f.hidden,
                })
                .collect();
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
                custom_fields,
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
            custom_fields: d
                .custom_fields
                .into_iter()
                .map(|f| CustomField {
                    label: f.label,
                    value: f.value,
                    hidden: f.hidden,
                })
                .collect(),
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

/// Serialize the current session to a plaintext JSON file at `path`.
///
/// WARNING: the output file is completely unencrypted — all secrets appear
/// in plain text. Flutter must surface a visible warning before calling this.
/// Async — filesystem write.
pub async fn export_vault_json(path: String) -> Result<(), String> {
    session::session_export_vault_json(PathBuf::from(path))
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

/// Vault header data returned by `read_vault_header`.
///
/// Contains the alias and YubiKey records from the plaintext header.
/// Safe to read before the user enters their passphrase.
pub struct VaultHeaderData {
    pub alias: Option<String>,
    pub yubikey_records: Vec<YubikeyRecordData>,
}

/// Read the vault header at `path` and return alias + YubiKey records.
///
/// Does **not** decrypt the vault body — safe to call before passphrase entry.
/// Replaces `list_vault_yubikey_records` for the unlock screen so alias and
/// YubiKey records are fetched in one call.
/// Sync — file I/O + header parse, no crypto.
#[flutter_rust_bridge::frb(sync)]
pub fn read_vault_header(path: String) -> Result<VaultHeaderData, String> {
    use crate::vault::io::read_vault_header as io_read_vault_header;
    let header = io_read_vault_header(&PathBuf::from(path))?;
    Ok(VaultHeaderData {
        alias: header.alias,
        yubikey_records: header
            .yubikey_records
            .into_iter()
            .map(|r| YubikeyRecordData {
                credential_id: r.credential_id,
                salt: r.salt.to_vec(),
            })
            .collect(),
    })
}

/// Rename the active vault: updates the alias in the file header and re-seals
/// the body so the new alias is bound to the ciphertext via AES-GCM AAD.
///
/// Requires an unlocked session — returns `Err("Vault is locked")` if called
/// without an active session. Passing an empty string clears the alias.
/// Async — file I/O + re-seal.
pub async fn set_vault_alias(alias: String) -> Result<(), String> {
    session::session_set_vault_alias(alias)
}

/// Decrypt the vault at `path` using both passphrase and YubiKey hmac-secret.
///
/// Handles both VERSION 2 (legacy single-key) and VERSION 3 (multi-key) vaults.
/// For VERSION 3, caches `vault_key_master` in the session so CRUD saves
/// never require a YubiKey re-tap.
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
    session::unlock_vault_with_key_record(
        &passphrase,
        &secret,
        credential_id,
        &salt,
        PathBuf::from(path),
    )
}

/// Create a new empty vault at `path`, sealed with `passphrase`.
///
/// `alias` is stored in the VERSION 5 plaintext header and travels with the file.
/// Called during onboarding. Async — runs Argon2id + encryption.
pub async fn init_vault(
    passphrase: Vec<u8>,
    path: String,
    alias: Option<String>,
) -> Result<(), String> {
    use crate::crypto::vault_crypto::seal_vault;
    use crate::vault::io::write_vault;
    use crate::vault::serialization::{serialize_vault_body, VaultBody};
    let vault_path = PathBuf::from(&path);
    let plaintext = serialize_vault_body(&VaultBody::empty())?;
    let sealed = seal_vault(&passphrase, &plaintext, alias)?;
    write_vault(&sealed, &vault_path)?;
    session::unlock_vault(&passphrase, vault_path)
}

/// Key material for one YubiKey, supplied during multi-key vault creation.
pub struct YubiKeyInitData {
    pub credential_id: Vec<u8>,
    pub hmac_secret: Vec<u8>, // 32 bytes — FIDO2 hmac-secret output
    pub hkdf_salt: Vec<u8>,   // 32 bytes — per-key CTAP2 challenge salt
}

/// Create a new empty vault sealed with a passphrase and two or more YubiKeys.
///
/// Enforces ADR-010: minimum 2 registered keys at vault creation.
/// `alias` is stored in the VERSION 5 plaintext header and travels with the file.
/// After creation, unlocks into session immediately using the first key.
/// Async — runs Argon2id + encryption.
pub async fn init_vault_with_keys(
    passphrase: Vec<u8>,
    keys: Vec<YubiKeyInitData>,
    path: String,
    alias: Option<String>,
) -> Result<(), String> {
    use crate::crypto::vault_crypto::{seal_vault_with_keys, YubiKeyRegistration};
    use crate::vault::io::write_vault;
    use crate::vault::serialization::{serialize_vault_body, VaultBody};

    if keys.len() < 2 {
        return Err(format!("at least 2 YubiKeys required; got {}", keys.len()));
    }

    let registrations = keys
        .iter()
        .map(|k| {
            let hmac: [u8; 32] = k
                .hmac_secret
                .as_slice()
                .try_into()
                .map_err(|_| "hmac_secret must be 32 bytes".to_string())?;
            let salt: [u8; 32] = k
                .hkdf_salt
                .as_slice()
                .try_into()
                .map_err(|_| "hkdf_salt must be 32 bytes".to_string())?;
            Ok(YubiKeyRegistration {
                credential_id: k.credential_id.clone(),
                hmac_secret: hmac,
                salt,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;

    let vault_path = PathBuf::from(&path);
    let plaintext = serialize_vault_body(&VaultBody::empty())?;
    let sealed = seal_vault_with_keys(&passphrase, &registrations, &plaintext, alias)?;
    write_vault(&sealed, &vault_path)?;

    // Unlock into session using the first key's material
    let first = &keys[0];
    let secret: [u8; 32] = first
        .hmac_secret
        .as_slice()
        .try_into()
        .map_err(|_| "hmac_secret must be 32 bytes".to_string())?;
    let salt: [u8; 32] = first
        .hkdf_salt
        .as_slice()
        .try_into()
        .map_err(|_| "hkdf_salt must be 32 bytes".to_string())?;
    session::unlock_vault_with_key_record(
        &passphrase,
        &secret,
        first.credential_id.clone(),
        &salt,
        vault_path,
    )
}

/// Create a new empty vault at `path`, sealed with both passphrase and YubiKey.
///
/// `alias` is stored in the VERSION 5 plaintext header and travels with the file.
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
    alias: Option<String>,
) -> Result<(), String> {
    use crate::crypto::vault_crypto::seal_vault_with_yubikey;
    use crate::vault::io::write_vault;
    use crate::vault::serialization::{serialize_vault_body, VaultBody};
    let secret: [u8; 32] = hmac_secret
        .try_into()
        .map_err(|_| "hmac_secret must be exactly 32 bytes".to_string())?;
    let salt: [u8; 32] = hkdf_salt
        .try_into()
        .map_err(|_| "hkdf_salt must be exactly 32 bytes".to_string())?;
    let vault_path = PathBuf::from(&path);
    let plaintext = serialize_vault_body(&VaultBody::empty())?;
    let sealed = seal_vault_with_yubikey(
        &passphrase,
        &secret,
        credential_id.clone(),
        salt,
        &plaintext,
        alias,
    )?;
    write_vault(&sealed, &vault_path)?;
    session::unlock_vault_with_yubikey(&passphrase, &secret, credential_id, &salt, vault_path)
}

// ── YubiKey key-management bridge ─────────────────────────────────────────────

/// Alias record for one registered YubiKey, returned by `list_yubikey_aliases`.
pub struct YubikeyAliasData {
    /// Hex-encoded credential ID (map key in the vault body).
    pub credential_id_hex: String,
    /// User-supplied display name; empty string if no alias has been set.
    pub alias: String,
}

/// Return all YubiKey aliases stored in the current session.
///
/// Sync — reads from in-memory session, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn list_yubikey_aliases() -> Result<Vec<YubikeyAliasData>, String> {
    let map = session::session_list_yubikey_aliases()?;
    Ok(map
        .into_iter()
        .map(|(credential_id_hex, alias)| YubikeyAliasData {
            credential_id_hex,
            alias,
        })
        .collect())
}

/// Set or update the display alias for a registered YubiKey.
///
/// `credential_id_hex` is the hex-encoded credential ID.
/// Async — triggers a full vault body save.
pub async fn set_yubikey_alias(credential_id_hex: String, alias: String) -> Result<(), String> {
    session::session_set_yubikey_alias(credential_id_hex, alias)
}

/// Add a new YubiKey to the vault.
///
/// Requires a VERSION 4 vault (wrapping_key must be cached from unlock).
/// Returns `Err` if the vault already has 4 keys or `new_cred_id` is already registered.
/// `new_hmac_secret` and `new_salt` must each be exactly 32 bytes.
/// Async — writes the updated vault header to disk.
pub async fn add_yubikey(
    new_cred_id: Vec<u8>,
    new_hmac_secret: Vec<u8>,
    new_salt: Vec<u8>,
) -> Result<(), String> {
    session::session_add_yubikey(new_cred_id, new_hmac_secret, new_salt)
}

/// Remove a YubiKey from the vault by credential ID.
///
/// Enforces a minimum of 1 remaining key.
/// Async — writes the updated vault header to disk.
pub async fn remove_yubikey(cred_id: Vec<u8>) -> Result<(), String> {
    session::session_remove_yubikey(cred_id)
}

// ── Vault sync ────────────────────────────────────────────────────────────────

/// Merge an incoming `.gabbro` file into the current session and persist.
///
/// Loads and decrypts the file at `path` using `passphrase`, then runs the
/// entry-level merge algorithm against the live session.  Returns a summary
/// for Flutter to display in the pre-merge confirmation dialog.
///
/// Returns `Err` if:
/// - the vault is locked
/// - `path` cannot be read or is not a valid Gabbro file
/// - the passphrase is wrong (decryption failure)
pub async fn merge_vault_from_file(
    path: String,
    passphrase: Vec<u8>,
) -> Result<crate::api::vault::MergeSummary, String> {
    let file_path = PathBuf::from(path);
    let incoming_body = crate::api::vault::load_vault(&passphrase, &file_path)?;
    session::session_merge_vault_from_body(incoming_body)
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
            custom_fields: vec![],
            attachments: vec![],
        })];
        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
                ..Default::default()
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
                ..Default::default()
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
                ..Default::default()
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
                ..Default::default()
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
                ..Default::default()
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
                ..Default::default()
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
    #[serial]
    fn export_vault_json_via_bridge() {
        use crate::api::vault::save_vault;
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let pass = b"bridge-json-export";
        let mut vault_path = temp_dir();
        vault_path.push("gabbro_bridge_json_export.gabbro");
        let mut json_path = temp_dir();
        json_path.push("gabbro_bridge_json_export_output.json");

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![VaultEntry::Note(NoteEntry {
                    meta: EntryMeta {
                        id: String::from("bje-001"),
                        created_at: String::from("2025-01-01T00:00:00Z"),
                        updated_at: String::from("2025-01-01T00:00:00Z"),
                        folder: String::from(""),
                    },
                    title: String::from("Bridge JSON export test"),
                    content: String::from("bridge content"),
                    custom_fields: vec![],
                    attachments: vec![],
                })],
                ..Default::default()
            },
            pass,
            &vault_path,
        )
        .unwrap();

        run(unlock_vault(
            pass.to_vec(),
            vault_path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(export_vault_json(json_path.to_str().unwrap().to_string())).unwrap();

        let raw = std::fs::read_to_string(&json_path).unwrap();
        assert!(
            raw.contains("Bridge JSON export test"),
            "note title must appear in JSON export"
        );
        assert!(raw.contains("gabbro_version"), "must include version field");

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&vault_path);
        let _ = std::fs::remove_file(&json_path);
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
                custom_fields: vec![],
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
                ..Default::default()
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
            None,
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

    #[test]
    #[serial]
    fn read_vault_header_returns_alias_and_yubikey_records() {
        use crate::api::vault::save_vault_with_yubikey;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_read_header_test.gabbro");
        let pass = b"header-read-pass";
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

        // set_vault_alias requires an unlocked session (Phase 3).
        run(unlock_vault_with_yubikey(
            pass.to_vec(),
            hmac_secret.to_vec(),
            credential_id.clone(),
            hkdf_salt.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(set_vault_alias(String::from("Test Vault"))).unwrap();

        lock_vault().unwrap();

        let header = read_vault_header(path.to_str().unwrap().to_string()).unwrap();
        assert_eq!(header.alias, Some(String::from("Test Vault")));
        assert_eq!(header.yubikey_records.len(), 1);
        assert_eq!(header.yubikey_records[0].credential_id, credential_id);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn set_vault_alias_rebinds_body_and_vault_still_opens() {
        use crate::api::vault::save_vault;
        use crate::vault::io::read_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_set_alias_rebind_test.gabbro");
        let pass = b"alias-rebind-pass";

        save_vault(&VaultBody::empty(), pass, &path).unwrap();

        // Capture ciphertext before alias change.
        let ciphertext_before = read_vault(&path).unwrap().ciphertext.clone();

        // set_vault_alias now requires an active session.
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(set_vault_alias(String::from("My Vault"))).unwrap();

        lock_vault().unwrap();

        let sealed_after = read_vault(&path).unwrap();
        // Alias must be written to the header.
        assert_eq!(sealed_after.alias, Some(String::from("My Vault")));
        // Body must be re-sealed (fresh nonce → different ciphertext).
        assert_ne!(
            sealed_after.ciphertext, ciphertext_before,
            "ciphertext must be refreshed after alias re-seal"
        );
        // Vault must still open with the original passphrase.
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();
        lock_vault().unwrap();

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn set_vault_alias_requires_unlocked_session() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_alias_locked_test.gabbro");
        let pass = b"alias-locked-pass";

        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        lock_vault().ok(); // ensure locked

        let result = run(set_vault_alias(String::from("Sneaky")));
        assert!(
            result.is_err(),
            "set_vault_alias must fail when vault is locked"
        );

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[serial]
    fn init_vault_stores_alias_in_header() {
        use crate::vault::io::read_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_init_alias_test.gabbro");
        let pass = b"init-alias-pass";

        run(init_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
            Some(String::from("Work")),
        ))
        .unwrap();

        lock_vault().unwrap();

        let sealed = read_vault(&path).unwrap();
        assert_eq!(sealed.alias, Some(String::from("Work")));

        let _ = std::fs::remove_file(&path);
    }

    // ── Custom-field roundtrip tests ──────────────────────────────────────────

    #[test]
    fn card_entry_from_data_preserves_custom_fields() {
        use crate::api::vault::CustomFieldData;

        let data = VaultEntryData::Card(crate::api::vault::CardEntryData {
            id: String::from("card-cf-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from(""),
            card_name: None,
            status: String::from("active"),
            cardholder_name: String::from("Rob Smith"),
            card_number: String::from("4111111111111111"),
            expiry: String::from("12/28"),
            cvv: String::from("123"),
            credit_limit: None,
            card_account_number: None,
            payment_network: None,
            pin: None,
            bank_name: None,
            transaction_password: None,
            notes: None,
            custom_fields: vec![
                CustomFieldData {
                    label: String::from("Loyalty number"),
                    value: String::from("LN-9876"),
                    hidden: false,
                },
                CustomFieldData {
                    label: String::from("Portal password"),
                    value: String::from("s3cr3t"),
                    hidden: true,
                },
            ],
            previous_cvv: None,
            previous_pin: None,
        });

        let entry = vault_entry_from_data(data).unwrap();
        match entry {
            VaultEntry::Card(ref e) => {
                assert_eq!(e.custom_fields.len(), 2, "custom fields must be preserved");
                assert_eq!(e.custom_fields[0].label, "Loyalty number");
                assert!(!e.custom_fields[0].hidden);
                assert_eq!(e.custom_fields[1].label, "Portal password");
                assert!(e.custom_fields[1].hidden);
            }
            _ => panic!("expected Card variant"),
        }
    }

    #[test]
    #[serial]
    fn card_create_entry_preserves_custom_fields() {
        use crate::api::vault::{save_vault, CustomFieldData};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_card_cf_test.gabbro");
        let pass = b"card-cf-test-pass";

        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let summary = run(create_entry(VaultEntryData::Card(
            crate::api::vault::CardEntryData {
                id: String::from(""),
                created_at: String::from(""),
                updated_at: String::from(""),
                folder: String::from(""),
                card_name: None,
                status: String::from("active"),
                cardholder_name: String::from("Rob Smith"),
                card_number: String::from("4111111111111111"),
                expiry: String::from("12/28"),
                cvv: String::from("123"),
                credit_limit: None,
                card_account_number: None,
                payment_network: None,
                pin: None,
                bank_name: None,
                transaction_password: None,
                notes: None,
                custom_fields: vec![CustomFieldData {
                    label: String::from("Loyalty number"),
                    value: String::from("LN-9876"),
                    hidden: false,
                }],
                previous_cvv: None,
                previous_pin: None,
            },
        )))
        .unwrap();

        let entry = get_entry(summary.id).unwrap();
        match entry {
            VaultEntryData::Card(e) => {
                assert_eq!(
                    e.custom_fields.len(),
                    1,
                    "custom fields must survive create + get"
                );
                assert_eq!(e.custom_fields[0].label, "Loyalty number");
                assert_eq!(e.custom_fields[0].value, "LN-9876");
            }
            _ => panic!("expected Card variant"),
        }

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
    }
}
