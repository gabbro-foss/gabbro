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
            app_id: e.app_id.clone(),
            email: e.email.clone(),
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
                field_times: Default::default(),
                history: Vec::new(),
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
            app_id: d.app_id,
            email: d.email,
        })),
        VaultEntryData::Note(d) => Ok(VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
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
                field_times: Default::default(),
                history: Vec::new(),
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
                field_times: Default::default(),
                history: Vec::new(),
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
            )?;
            Ok(VaultEntry::Card(entry))
        }
        VaultEntryData::File(d) => Ok(VaultEntry::File(FileEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
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
                field_times: Default::default(),
                history: Vec::new(),
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

/// R-03 P3: is the automatic safety copy (`.bak`) a *usable* vault — present
/// and parseable, not just present?
///
/// Drives whether the unlock screen may offer a restore when the vault file
/// itself cannot be parsed. Returns false for a missing, symlinked, or
/// unparseable `.bak`, so the offer can never claim a safety copy that a
/// confirmed restore would then refuse. Safe to call with no session.
pub async fn vault_backup_usable(path: String) -> bool {
    crate::vault::io::backup_usable(std::path::Path::new(&path))
}

/// R-03: replace a corrupt vault file with its `.bak` safety copy.
///
/// Explicit user action from the unlock screen's restore flow. Refuses an
/// unparseable `.bak`. The restored vault still requires full credentials —
/// restoring grants no access.
pub async fn restore_vault_backup(path: String) -> Result<(), String> {
    crate::vault::io::restore_vault_backup(std::path::Path::new(&path))
}

/// R-03: restore the vault at `path` from an external backup file the user
/// picked (their own off-device 3-2-1 copy).
///
/// Refuses a `source` that is not a usable Gabbro vault, so a corrupt vault is
/// never replaced by another unreadable file. The restored vault still requires
/// full credentials to open.
pub async fn restore_vault_from_file(path: String, source: String) -> Result<(), String> {
    crate::vault::io::restore_vault_from_file(
        std::path::Path::new(&path),
        std::path::Path::new(&source),
    )
}

/// Assign a folder to a set of entries by UUID and persist.
///
/// Pass `folder: ""` to move entries to unfoldered.
/// Returns `Err` if the folder name does not exist (empty string always valid).
/// Async — triggers a full vault save.
pub async fn assign_folder_to_entries(ids: Vec<String>, folder: String) -> Result<(), String> {
    session::session_assign_folder_to_entries(&ids, folder)
}

/// Write .gabbro + .gabbro.sha256, preserving the vault's protection (ADR-013).
///
/// The default export: copies the sealed on-disk vault byte-for-byte, so a
/// key-protected vault stays key-protected (its keyslots and alias are retained).
/// Async — filesystem operation.
pub async fn export_vault(path: String) -> Result<(), String> {
    session::session_export_vault(PathBuf::from(path))
}

/// Write a **passphrase-only** .gabbro + .gabbro.sha256 — the opt-in security
/// downgrade (ADR-013).
///
/// Re-seals the current session under the passphrase alone, dropping any YubiKey
/// requirement so the artifact opens with the passphrase only. The original vault
/// is never mutated. Flutter must only reach this via the explicit, warned export
/// toggle (shown for key-protected vaults). Async — filesystem operation.
pub async fn export_vault_passphrase_only(path: String) -> Result<(), String> {
    session::session_export_vault_passphrase_only(PathBuf::from(path))
}

/// Serialize the current session to a plaintext JSON file at `path`.
///
/// WARNING: the output file is completely unencrypted — all secrets appear
/// in plain text. Flutter must surface a visible warning before calling this.
/// Async — filesystem write.
pub async fn export_vault_json(path: String) -> Result<(), String> {
    session::session_export_vault_json(PathBuf::from(path))
}

/// The bytes of an export plus its detached SHA-256 line (ADR-002/013).
///
/// Returned by the Android byte-return export path: Rust produces the ciphertext
/// (`vault_bytes`, safe to cross the bridge) and the `sha256_line`, and the Kotlin
/// SAF layer writes both `<filename>` and `<filename>.sha256` into the user's
/// granted directory tree (raw-path writes can't overwrite a file another app
/// created under scoped storage).
pub struct ExportArtifact {
    pub vault_bytes: Vec<u8>,
    pub sha256_line: String,
}

/// Build the protection-preserving export artifact for the current session
/// without writing (ADR-013 default) — Android SAF path. `vault_filename` (e.g.
/// `Gabbro.gabbro`) names the file in the SHA line. Returns ciphertext bytes.
pub async fn build_export_bytes(vault_filename: String) -> Result<ExportArtifact, String> {
    let (vault_bytes, sha256_line) = session::session_export_vault_bytes(&vault_filename)?;
    Ok(ExportArtifact {
        vault_bytes,
        sha256_line,
    })
}

/// Build the opt-in passphrase-only downgrade export artifact for the current
/// session without writing (ADR-013) — Android SAF path. Re-seals under the
/// passphrase alone; bytes are ciphertext. Reach only via the explicit, warned
/// downgrade toggle.
pub async fn build_export_passphrase_only_bytes(
    vault_filename: String,
) -> Result<ExportArtifact, String> {
    let (vault_bytes, sha256_line) =
        session::session_export_vault_passphrase_only_bytes(&vault_filename)?;
    Ok(ExportArtifact {
        vault_bytes,
        sha256_line,
    })
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

/// Resolve one field-level clash surfaced by a merge (`MergeSummary.field_conflicts`).
/// `keep_incoming` true applies the other device's value; either way the choice is
/// stamped so it wins future merges. Persists (async — vault save).
pub async fn resolve_field_conflict(
    id: String,
    field: String,
    keep_incoming: bool,
    incoming_value: String,
) -> Result<(), String> {
    session::session_resolve_field_conflict(id, field, keep_incoming, incoming_value)
}

/// Resolve one pending item-delete surfaced by a merge (`MergeSummary.pending_item_deletes`).
/// `delete` true removes the item; false keeps it. Persists (async — vault save).
pub async fn resolve_item_delete(id: String, field: String, delete: bool) -> Result<(), String> {
    session::session_resolve_item_delete(id, field, delete)
}

/// Set `field` to `new_value` and keep `replaced_value` in the entry's recovery
/// history. Used when a kept brought-over edit or a clash-resolved-to-theirs
/// overwrites a local value. Persists (async — vault save).
pub async fn replace_field_with_history(
    id: String,
    field: String,
    new_value: String,
    replaced_value: String,
) -> Result<(), String> {
    session::session_replace_field_with_history(id, field, new_value, replaced_value)
}

/// Restore a recovery-history record (`index` into the entry's history): set its
/// field back to the saved value and remove the record. Persists.
pub async fn restore_history(id: String, index: u32) -> Result<(), String> {
    session::session_restore_history(id, index)
}

/// Delete a recovery-history record (`index`) without restoring it. Persists.
pub async fn delete_history(id: String, index: u32) -> Result<(), String> {
    session::session_delete_history(id, index)
}

/// Read an entry's recovery-history records (replaced values kept for restore).
pub async fn get_entry_history(
    id: String,
) -> Result<Vec<crate::api::vault::HistoryRecordData>, String> {
    session::session_get_entry_history(id)
}

/// Merge a **key-protected** incoming `.gabbro` file into the current session (ADR-013).
///
/// The analogue of [`merge_vault_from_file`] for a source created with YubiKey
/// protection: passphrase alone is refused by the crypto, so the source's chosen
/// protection is upheld across the sync. Opens the file at `path` with the source
/// passphrase AND a registered YubiKey (its hmac-secret output + credential id),
/// then runs the entry-level merge against the live session.
///
/// `hmac_secret` must be exactly 32 bytes.
///
/// Returns `Err` if:
/// - the vault is locked
/// - `path` cannot be read or is not a valid Gabbro file
/// - the passphrase + key combination does not unlock the file
pub async fn merge_vault_from_file_with_key(
    path: String,
    passphrase: Vec<u8>,
    hmac_secret: Vec<u8>,
    credential_id: Vec<u8>,
) -> Result<crate::api::vault::MergeSummary, String> {
    let secret: [u8; 32] = hmac_secret
        .try_into()
        .map_err(|_| "hmac_secret must be exactly 32 bytes".to_string())?;
    let file_path = PathBuf::from(path);
    let (incoming_body, _master, _wrapping) = crate::api::vault::load_vault_with_key_record(
        &passphrase,
        &secret,
        &credential_id,
        &file_path,
    )?;
    session::session_merge_vault_from_body(incoming_body)
}

/// Fast auto-merge a `.gabbro` file into the current session: apply everything
/// automatically, incoming wins (no prompts). The analogue of
/// [`merge_vault_from_file`] for the fast path. Returns the summary of what was
/// applied. Persists (async — vault save).
pub async fn fast_merge_vault_from_file(
    path: String,
    passphrase: Vec<u8>,
) -> Result<crate::api::vault::MergeSummary, String> {
    let file_path = PathBuf::from(path);
    let incoming_body = crate::api::vault::load_vault(&passphrase, &file_path)?;
    session::session_fast_merge_from_body(incoming_body)
}

/// Fast auto-merge a **key-protected** `.gabbro` file (ADR-013). The analogue of
/// [`merge_vault_from_file_with_key`] for the fast path. `hmac_secret` must be 32
/// bytes. Persists (async — vault save).
pub async fn fast_merge_vault_from_file_with_key(
    path: String,
    passphrase: Vec<u8>,
    hmac_secret: Vec<u8>,
    credential_id: Vec<u8>,
) -> Result<crate::api::vault::MergeSummary, String> {
    let secret: [u8; 32] = hmac_secret
        .try_into()
        .map_err(|_| "hmac_secret must be exactly 32 bytes".to_string())?;
    let file_path = PathBuf::from(path);
    let (incoming_body, _master, _wrapping) = crate::api::vault::load_vault_with_key_record(
        &passphrase,
        &secret,
        &credential_id,
        &file_path,
    )?;
    session::session_fast_merge_from_body(incoming_body)
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

    // R-03: exists -> restore -> delete wiring through the bridge surface
    #[test]
    #[serial]
    fn backup_bridge_roundtrip() {
        use crate::crypto::vault_crypto::seal_vault;
        use crate::vault::io::write_vault;
        use std::env::temp_dir;

        let path = temp_dir().join("gabbro_bridge_backup_test.gabbro");
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&bak);
        let path_s = path.to_string_lossy().to_string();

        let sealed_a = seal_vault(b"pw-a", b"body A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        // R-03 P1 + P3: a valid .bak is synced from the first save on, and a
        // parseable .bak reports usable.
        assert!(run(vault_backup_usable(path_s.clone())));

        let sealed_b = seal_vault(b"pw-b", b"body B", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();
        assert!(run(vault_backup_usable(path_s.clone())));

        std::fs::write(&path, b"corrupt").unwrap();
        run(restore_vault_backup(path_s.clone())).expect("restore must succeed");
        let restored = std::fs::read(&path).unwrap();
        assert_eq!(
            restored,
            sealed_b.to_bytes(),
            "restore must bring back the last verified save (B), not an older one"
        );

        // R-03 P3: a rotted .bak must report not usable — the offer cannot lie.
        std::fs::write(&bak, b"rotted backup").unwrap();
        assert!(!run(vault_backup_usable(path_s)));

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&bak);
    }

    // R-03: bridge restore-from-file replaces a corrupt vault with a picked
    // backup file, and refuses a source that is not a usable vault.
    #[test]
    #[serial]
    fn restore_from_file_bridge_roundtrip() {
        use crate::crypto::vault_crypto::seal_vault;
        use crate::vault::io::write_vault;
        use std::env::temp_dir;

        let path = temp_dir().join("gabbro_bridge_restore_file_test.gabbro");
        let source = temp_dir().join("gabbro_bridge_restore_file_source.gabbro");
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let source_bak = std::path::PathBuf::from(format!("{}.bak", source.display()));
        for p in [&path, &source, &bak, &source_bak] {
            let _ = std::fs::remove_file(p);
        }
        let path_s = path.to_string_lossy().to_string();
        let source_s = source.to_string_lossy().to_string();

        let sealed = seal_vault(b"pw", b"body", None).unwrap();
        write_vault(&sealed, &source).unwrap();
        let source_bytes = std::fs::read(&source).unwrap();
        std::fs::write(&path, b"corrupt").unwrap();

        run(restore_vault_from_file(path_s.clone(), source_s.clone()))
            .expect("restore from a valid file must succeed");
        let restored = std::fs::read(&path).unwrap();

        // A source that is not a vault must be refused, leaving the vault as-is.
        std::fs::write(&source, b"rotted source").unwrap();
        std::fs::write(&path, b"still corrupt").unwrap();
        let refused = run(restore_vault_from_file(path_s, source_s));
        let after_refuse = std::fs::read(&path).unwrap();

        for p in [&path, &source, &bak, &source_bak] {
            let _ = std::fs::remove_file(p);
        }
        assert_eq!(
            restored, source_bytes,
            "restore must write the source vault bytes"
        );
        assert!(refused.is_err(), "an unparseable source must be refused");
        assert_eq!(
            after_refuse, b"still corrupt",
            "a refused restore leaves the vault untouched"
        );
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
                field_times: Default::default(),
                history: Vec::new(),
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from(""),
            },
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("hunter2"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
                        field_times: Default::default(),
                        history: Vec::new(),
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
                    field_times: Default::default(),
                    history: Vec::new(),
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
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("login-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Work"),
                },
                title: String::from("Example"),
                url: String::from("https://example.com"),
                username: String::from("user"),
                password: String::from("hunter2"),
                notes: None,
                custom_fields: vec![],
                attachments: vec![],
                app_id: None,
                email: None,
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
            cardholder_name: String::from("Alex Smith"),
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
    fn login_app_id_survives_data_roundtrip() {
        use crate::vault::entry::{EntryMeta, LoginEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("login-appid-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from(""),
            },
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("secret"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: Some(String::from("com.company.app")),
            email: Some(String::from("user@example.com")),
        });
        // entry -> DTO -> entry preserves app_id + email: the editor read/write path.
        let data = vault_entry_to_data(&entry);
        let back = vault_entry_from_data(data).unwrap();
        match back {
            VaultEntry::Login(ref e) => {
                assert_eq!(e.app_id, Some(String::from("com.company.app")));
                assert_eq!(e.email, Some(String::from("user@example.com")));
            }
            _ => panic!("expected Login variant"),
        }
    }

    // ── Error-path and CRUD tests ─────────────────────────────────────────────

    #[test]
    #[serial]
    fn unlock_vault_wrong_passphrase_returns_error() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_wrong_pass_test.gabbro");
        let pass = b"correct passphrase";
        save_vault(&VaultBody::empty(), pass, &path).unwrap();

        let result = run(unlock_vault(
            b"wrong passphrase".to_vec(),
            path.to_str().unwrap().to_string(),
        ));
        assert!(result.is_err(), "wrong passphrase must fail");

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn get_entry_when_locked_returns_error() {
        lock_vault().ok();
        let result = get_entry(String::from("any-uuid"));
        assert!(result.is_err(), "get_entry must fail when vault is locked");
    }

    #[test]
    #[serial]
    fn get_entry_unknown_uuid_returns_error() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_get_unknown_test.gabbro");
        let pass = b"get-unknown-pass";
        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let result = get_entry(String::from("nonexistent-uuid-12345"));
        assert!(result.is_err(), "unknown UUID must return Err");

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn create_and_delete_entry_roundtrip() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_delete_entry_test.gabbro");
        let pass = b"delete-entry-pass";
        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let summary = run(create_entry(VaultEntryData::Note(
            crate::api::vault::NoteEntryData {
                id: String::new(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
                title: String::from("Temp note"),
                content: String::from("to be deleted"),
                custom_fields: vec![],
            },
        )))
        .unwrap();

        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        run(delete_entry(summary.id)).unwrap();

        assert_eq!(
            list_entry_summaries().unwrap().len(),
            0,
            "entry must be gone after delete"
        );

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn update_entry_persists_change() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_update_entry_test.gabbro");
        let pass = b"update-entry-pass";
        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let summary = run(create_entry(VaultEntryData::Note(
            crate::api::vault::NoteEntryData {
                id: String::new(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
                title: String::from("Original title"),
                content: String::from("original content"),
                custom_fields: vec![],
            },
        )))
        .unwrap();

        let id = summary.id.clone();

        run(update_entry(
            VaultEntryData::Note(crate::api::vault::NoteEntryData {
                id: id.clone(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
                title: String::from("Updated title"),
                content: String::from("updated content"),
                custom_fields: vec![],
            }),
            None,
        ))
        .unwrap();

        let retrieved = get_entry(id).unwrap();
        match retrieved {
            VaultEntryData::Note(e) => {
                assert_eq!(e.title, "Updated title");
                assert_eq!(e.content, "updated content");
            }
            _ => panic!("expected Note"),
        }

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn delete_entries_bulk_removes_all() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_delete_entries_test.gabbro");
        let pass = b"delete-entries-pass";
        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let s1 = run(create_entry(VaultEntryData::Note(
            crate::api::vault::NoteEntryData {
                id: String::new(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
                title: String::from("Note 1"),
                content: String::from("content 1"),
                custom_fields: vec![],
            },
        )))
        .unwrap();
        let s2 = run(create_entry(VaultEntryData::Note(
            crate::api::vault::NoteEntryData {
                id: String::new(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
                title: String::from("Note 2"),
                content: String::from("content 2"),
                custom_fields: vec![],
            },
        )))
        .unwrap();

        assert_eq!(list_entry_summaries().unwrap().len(), 2);

        run(delete_entries(vec![s1.id, s2.id])).unwrap();

        assert_eq!(
            list_entry_summaries().unwrap().len(),
            0,
            "all entries must be removed by delete_entries"
        );

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn change_passphrase_allows_unlock_with_new_passphrase() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_change_pass_test.gabbro");
        let old = b"old passphrase";
        let new = b"new passphrase";

        save_vault(&VaultBody::empty(), old, &path).unwrap();
        run(unlock_vault(
            old.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(change_passphrase(old.to_vec(), new.to_vec())).unwrap();
        lock_vault().unwrap();

        // New passphrase must open the vault.
        run(unlock_vault(
            new.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();
        lock_vault().unwrap();

        // Old passphrase must be rejected.
        let result = run(unlock_vault(
            old.to_vec(),
            path.to_str().unwrap().to_string(),
        ));
        assert!(
            result.is_err(),
            "old passphrase must be rejected after change"
        );

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn export_vault_creates_gabbro_file() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let mut src = temp_dir();
        src.push("gabbro_bridge_export_src_test.gabbro");
        let mut dst = temp_dir();
        dst.push("gabbro_bridge_export_dst_test.gabbro");
        let pass = b"export-test-pass";

        save_vault(&VaultBody::empty(), pass, &src).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            src.to_str().unwrap().to_string(),
        ))
        .unwrap();

        run(export_vault(dst.to_str().unwrap().to_string())).unwrap();

        assert!(dst.exists(), "export must create the destination file");

        lock_vault().unwrap();
        // The exported file must be openable with the same passphrase.
        run(unlock_vault(
            pass.to_vec(),
            dst.to_str().unwrap().to_string(),
        ))
        .unwrap();
        lock_vault().unwrap();

        let _ = std::fs::remove_file(&src);
        let _ = std::fs::remove_file(&dst);
    }

    #[test]
    #[serial]
    fn unlock_vault_with_yubikey_wrong_hmac_secret_size_returns_error() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_yubikey_size_test.gabbro");

        // 31-byte hmac_secret — must be rejected before any file I/O.
        let result = run(unlock_vault_with_yubikey(
            b"passphrase".to_vec(),
            vec![0u8; 31],
            vec![0u8; 32],
            vec![0u8; 32],
            path.to_str().unwrap().to_string(),
        ));
        assert!(result.is_err(), "31-byte hmac_secret must be rejected");

        // 33-byte hkdf_salt — must be rejected before any file I/O.
        let result = run(unlock_vault_with_yubikey(
            b"passphrase".to_vec(),
            vec![0u8; 32],
            vec![0u8; 32],
            vec![0u8; 33],
            path.to_str().unwrap().to_string(),
        ));
        assert!(result.is_err(), "33-byte hkdf_salt must be rejected");
    }

    #[test]
    #[serial]
    fn init_vault_with_keys_requires_at_least_two_keys() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_bridge_init_keys_min_test.gabbro");

        // Single key — must fail (ADR-010: minimum 2 keys at creation).
        let result = run(init_vault_with_keys(
            b"init-keys-min-pass".to_vec(),
            vec![YubiKeyInitData {
                credential_id: vec![0xABu8; 32],
                hmac_secret: vec![0x42u8; 32],
                hkdf_salt: vec![0x11u8; 32],
            }],
            path.to_str().unwrap().to_string(),
            None,
        ));
        assert!(
            result.is_err(),
            "init_vault_with_keys must require at least 2 keys"
        );
        let msg = result.unwrap_err();
        assert!(
            msg.contains("at least 2"),
            "error must mention minimum key count, got: {msg}"
        );

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
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
                cardholder_name: String::from("Alex Smith"),
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
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    // ── ADR-013: key-protected vault SYNC (the import-path fix, mirrored) ──────
    //
    // The bug found on 2026-06-10: ADR-013 taught the import-entries path to open
    // a key-protected source (passphrase + YubiKey), but the SYNC path
    // (`merge_vault_from_file`) still tried passphrase alone. A key-protected file
    // is correctly refused by the crypto, so sync surfaced a misleading "different
    // passphrase" error and never asked for the key. The fix:
    // `merge_vault_from_file_with_key` mirrors `import_from_gabbro_with_key`.

    /// Build a key-protected source vault (passphrase + YK1 + YK2), export it
    /// PRESERVING protection (ADR-013 default), and return the artifact + source
    /// paths. The artifact keeps the YubiKey keyslots, so passphrase alone cannot
    /// open it. YK1 = (hmac `[0x11;32]`, cred `[0xA1;64]`, salt `[0x12;32]`).
    fn export_keyprotected_artifact(
        pass: &[u8],
        suffix: &str,
    ) -> (std::path::PathBuf, std::path::PathBuf) {
        use crate::api::vault::{export_vault_preserving, save_vault_with_keys};
        use crate::crypto::vault_crypto::YubiKeyRegistration;
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let yk1 = YubiKeyRegistration {
            credential_id: vec![0xA1u8; 64],
            hmac_secret: [0x11u8; 32],
            salt: [0x12u8; 32],
        };
        let yk2 = YubiKeyRegistration {
            credential_id: vec![0xA2u8; 48],
            hmac_secret: [0x21u8; 32],
            salt: [0x22u8; 32],
        };

        let mut source = temp_dir();
        source.push(format!("gabbro_bridge_kp_source_{suffix}.gabbro"));
        let mut artifact = temp_dir();
        artifact.push(format!("gabbro_bridge_kp_artifact_{suffix}.gabbro"));

        let body = VaultBody {
            folders: vec![],
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("from-vault-a-001"),
                    created_at: String::from("2025-03-01T00:00:00Z"),
                    updated_at: String::from("2025-03-01T00:00:00Z"),
                    folder: String::new(),
                },
                title: String::from("Synced from A"),
                content: String::from("hardware secret"),
                custom_fields: vec![],
                attachments: vec![],
            })],
            ..Default::default()
        };
        save_vault_with_keys(&body, pass, &[yk1, yk2], &source).unwrap();
        export_vault_preserving(&source, &artifact).unwrap();
        (artifact, source)
    }

    /// Unlock an empty passphrase-only session B with one pre-existing note.
    fn setup_session_b(pass: &[u8], suffix: &str) -> std::path::PathBuf {
        use crate::api::vault::save_vault;
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push(format!("gabbro_bridge_kp_session_b_{suffix}.gabbro"));
        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![VaultEntry::Note(NoteEntry {
                    meta: EntryMeta {
                        field_times: Default::default(),
                        history: Vec::new(),
                        id: String::from("vault-b-own-001"),
                        created_at: String::from("2025-01-01T00:00:00Z"),
                        updated_at: String::from("2025-01-01T00:00:00Z"),
                        folder: String::new(),
                    },
                    title: String::from("Vault B own note"),
                    content: String::from("local"),
                    custom_fields: vec![],
                    attachments: vec![],
                })],
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
        path
    }

    #[test]
    #[serial]
    fn merge_vault_from_file_refuses_keyprotected_source_with_passphrase_alone() {
        let pass_a: &[u8] = b"vault A passphrase -- hardware protected";
        let (artifact, source) = export_keyprotected_artifact(pass_a, "sync_refuse");

        let pass_b = b"vault B passphrase -- yubikeyless";
        let path_b = setup_session_b(pass_b, "sync_refuse");

        // Passphrase alone must NOT open a key-protected export → sync refused.
        let result = run(merge_vault_from_file(
            artifact.to_str().unwrap().to_string(),
            pass_a.to_vec(),
        ));
        assert!(
            result.is_err(),
            "syncing a key-protected export with passphrase alone must be refused"
        );
        // Session untouched — nothing leaked in.
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path_b);
        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&artifact);
        let _ = std::fs::remove_file(artifact.with_extension("gabbro.sha256"));
    }

    #[test]
    #[serial]
    fn merge_vault_from_file_with_key_syncs_keyprotected_source() {
        let pass_a: &[u8] = b"vault A passphrase -- hardware protected";
        let (artifact, source) = export_keyprotected_artifact(pass_a, "sync_ok");

        let pass_b = b"vault B passphrase -- yubikeyless";
        let path_b = setup_session_b(pass_b, "sync_ok");

        // Passphrase_A + a registered key (YK1) authorises the sync.
        let summary = run(merge_vault_from_file_with_key(
            artifact.to_str().unwrap().to_string(),
            pass_a.to_vec(),
            vec![0x11u8; 32], // YK1 hmac-secret output
            vec![0xA1u8; 64], // YK1 credential id
        ))
        .unwrap();

        assert_eq!(summary.added, 1, "A's entry must sync into B");

        let summaries = list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 2, "B's own entry + A's synced entry");
        assert!(
            summaries.iter().any(|s| s.id == "from-vault-a-001"),
            "B must hold the entry that originated in key-protected vault A"
        );

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path_b);
        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&artifact);
        let _ = std::fs::remove_file(artifact.with_extension("gabbro.sha256"));
    }

    // ── Android SAF export: build-bytes path (the file write happens in Kotlin) ─

    #[test]
    #[serial]
    fn build_export_bytes_preserving_is_byte_identical_to_source() {
        use crate::api::vault::save_vault;
        use std::env::temp_dir;

        let pass = b"export-bytes-preserving-pass";
        let mut path = temp_dir();
        path.push("gabbro_bridge_export_bytes_preserving.gabbro");
        save_vault(&VaultBody::default(), pass, &path).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();

        let artifact = run(build_export_bytes("Gabbro.gabbro".to_string())).unwrap();

        let on_disk = std::fs::read(&path).unwrap();
        assert_eq!(
            artifact.vault_bytes, on_disk,
            "preserving export must be byte-identical to the on-disk vault (keyslots + alias retained)"
        );
        assert_eq!(
            artifact.sha256_line,
            crate::api::vault::sha256_line(&on_disk, "Gabbro.gabbro"),
            "sha line must hash the bytes and name the file"
        );

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn build_export_passphrase_only_bytes_opens_with_passphrase_alone() {
        use crate::api::vault::load_vault;
        use crate::vault::io::read_vault;
        use std::env::temp_dir;

        let pass = b"export-bytes-downgrade-pass";
        let mut path = temp_dir();
        path.push("gabbro_bridge_export_bytes_downgrade.gabbro");

        // Key-protected session: passphrase + 2 keys (ADR-010 minimum).
        run(init_vault_with_keys(
            pass.to_vec(),
            vec![
                YubiKeyInitData {
                    credential_id: vec![0xA1u8; 64],
                    hmac_secret: vec![0x11u8; 32],
                    hkdf_salt: vec![0x12u8; 32],
                },
                YubiKeyInitData {
                    credential_id: vec![0xA2u8; 48],
                    hmac_secret: vec![0x21u8; 32],
                    hkdf_salt: vec![0x22u8; 32],
                },
            ],
            path.to_str().unwrap().to_string(),
            None,
        ))
        .unwrap();

        let artifact = run(build_export_passphrase_only_bytes(
            "Gabbro.gabbro".to_string(),
        ))
        .unwrap();

        // Write the returned bytes and prove they open with the passphrase ALONE
        // and carry no YubiKey keyslots — i.e. the downgrade really dropped the key.
        let mut out = temp_dir();
        out.push("gabbro_bridge_export_bytes_downgrade_out.gabbro");
        std::fs::write(&out, &artifact.vault_bytes).unwrap();
        assert!(
            load_vault(pass, &out).is_ok(),
            "passphrase-only export must open with the passphrase alone"
        );
        assert!(
            read_vault(&out).unwrap().yubikey_records.is_empty(),
            "downgrade artifact must drop all YubiKey keyslots"
        );

        lock_vault().unwrap();
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&out);
    }
}
