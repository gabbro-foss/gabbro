//! Vault session — in-memory state between bridge calls.
//!
//! The decrypted vault lives here after unlock. Flutter never holds
//! the entries directly — it calls functions in this module to read
//! and write them.

use std::path::PathBuf;
use zeroize::{Zeroize, Zeroizing};

use std::sync::{LazyLock, Mutex};

use crate::api::vault::{
    add_yubikey_to_vault, change_passphrase_with_keys, load_vault, load_vault_with_key_record,
    migrate_multikey_vault_on_unlock, migrate_passphrase_vault_on_unlock,
    remove_yubikey_from_vault, reseal_vault_body, save_vault, MergeSummary,
};
use crate::api::vault_bridge::EntrySummaryData;
use crate::vault::entry::{CustomField, VaultEntry};
use crate::vault::serialization::{DeletedEntry, VaultBody};

// The cached master key for a multi-key session's CRUD re-seals, or `None` for a
// passphrase-only session. Extracted from the session before a save.
type YubikeyTriple = Option<Zeroizing<[u8; 32]>>;

// ── Session state ─────────────────────────────────────────────────────────────

/// YubiKey material cached in memory for the duration of an unlocked (multi-key)
/// session.
///
/// `vault_key_master` holds the random master key that encrypts the vault body;
/// CRUD saves use it directly (no re-tap). `wrapping_key` mediates between the
/// passphrase and the per-key blobs; it is needed to add a new key without
/// Argon2id re-derivation (`None` for the rare v3 multi-key vault without a
/// passphrase_blob).
pub struct YubikeyMaterial {
    /// Cached master key for CRUD re-seals.
    pub vault_key_master: Zeroizing<[u8; 32]>,
    /// Cached wrapping key for add-key operations.
    pub wrapping_key: Option<Zeroizing<[u8; 32]>>,
}

/// Pre-sync snapshot kept for the duration of a granular review so the user can
/// fully cancel. Holds the exact state from just before the merge mutated the
/// session. `entries` are `ZeroizeOnDrop`, so dropping the backup (on finish or
/// cancel) wipes the plaintext copy. Purely in-memory - never written to disk.
pub(crate) struct SyncBackup {
    folders: Vec<String>,
    entries: Vec<VaultEntry>,
    deleted_ids: Vec<DeletedEntry>,
}

pub struct VaultSession {
    pub folders: Vec<String>,
    pub entries: Vec<VaultEntry>,
    pub path: PathBuf,
    pub passphrase: Zeroizing<Vec<u8>>,
    pub yubikey: Option<YubikeyMaterial>,
    /// User-defined aliases for registered YubiKeys, keyed by credential_id hex string.
    /// Stored in the encrypted vault body for portability across devices.
    pub yubikey_aliases: std::collections::HashMap<String, String>,
    /// Tombstones for intentionally deleted entries, propagated during vault sync.
    pub deleted_ids: Vec<DeletedEntry>,
    /// Snapshot taken before a granular-sync merge, so the review can be cancelled
    /// back to the pre-sync state. `None` outside an in-progress granular sync.
    pub(crate) pre_sync_backup: Option<SyncBackup>,
}

static VAULT_SESSION: LazyLock<Mutex<Option<VaultSession>>> = LazyLock::new(|| Mutex::new(None));

// ── Session API ───────────────────────────────────────────────────────────────

/// Decrypt the vault at `path` and store it in memory.
///
/// Flutter awaits this — Argon2id takes ~667ms on target hardware.
pub fn unlock_vault(passphrase: &[u8], path: PathBuf) -> Result<(), String> {
    let mut body = load_vault(passphrase, &path)?;
    crate::api::vault::purge_expired_history(&mut body.entries);
    // RT-3: best-effort migrate an older passphrase-only vault to the current
    // format on unlock. A write failure must not block unlock (D1) — retried next
    // unlock; the reseal cap keeps the un-migrated vault safe meanwhile.
    let _ = migrate_passphrase_vault_on_unlock(passphrase, &body, &path);
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    *session = Some(VaultSession {
        folders: body.folders,
        entries: body.entries,
        yubikey_aliases: body.yubikey_aliases,
        deleted_ids: body.deleted_ids,
        path,
        passphrase: Zeroizing::new(passphrase.to_vec()),
        yubikey: None,
        pre_sync_backup: None,
    });
    Ok(())
}

/// Decrypt a VERSION 4 multi-key vault using any one registered YubiKey.
///
/// Caches `vault_key_master` for subsequent CRUD re-seals so the user
/// never needs to re-tap their key during an active session.
pub fn unlock_vault_with_key_record(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: Vec<u8>,
    path: PathBuf,
) -> Result<(), String> {
    let (mut body, master, wrapping_key) =
        load_vault_with_key_record(passphrase, hmac_secret, &credential_id, &path)?;
    crate::api::vault::purge_expired_history(&mut body.entries);
    // RT-3: best-effort migrate an older p+YK vault to the current format on unlock,
    // reusing the cached wrapping_key/master (no re-tap). Best-effort per D1; only
    // when a wrapping_key exists (v4+ multi-key). Borrow before the session takes them.
    if let Some(ref wrapping) = wrapping_key {
        let _ = migrate_multikey_vault_on_unlock(passphrase, wrapping, &master, &body, &path);
    }
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    *session = Some(VaultSession {
        folders: body.folders,
        entries: body.entries,
        yubikey_aliases: body.yubikey_aliases,
        deleted_ids: body.deleted_ids,
        path,
        passphrase: Zeroizing::new(passphrase.to_vec()),
        yubikey: Some(YubikeyMaterial {
            vault_key_master: master,
            wrapping_key,
        }),
        pre_sync_backup: None,
    });
    Ok(())
}

/// Drop the session state, locking the vault.
///
/// After this call, all session functions return Err until unlock is
/// called again.
pub fn is_vault_unlocked() -> bool {
    match VAULT_SESSION.lock() {
        Ok(session) => session.is_some(),
        Err(_) => false, // mutex poisoned — treat as locked
    }
}

pub fn lock_vault() -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    if let Some(ref mut s) = *session {
        // Cryptographic-grade zero: volatile writes the compiler cannot optimise away.
        // Covers the passphrase bytes fully. The entries vec is cleared via clear(),
        // which drops each element — triggering ZeroizeOnDrop on every VaultEntry.
        s.passphrase.zeroize();
        if let Some(ref mut yk) = s.yubikey {
            yk.vault_key_master.zeroize();
            if let Some(ref mut wk) = yk.wrapping_key {
                wk.zeroize();
            }
        }
        s.entries.clear();
        // Drop any in-progress sync snapshot: its entries are ZeroizeOnDrop, so
        // this wipes that plaintext copy too.
        s.pre_sync_backup = None;
    }
    *session = None;
    Ok(())
}

/// Build a `VaultBody` snapshot from the current session state.
fn build_body(session: &VaultSession) -> VaultBody {
    VaultBody {
        folders: session.folders.clone(),
        entries: session.entries.clone(),
        yubikey_aliases: session.yubikey_aliases.clone(),
        vault_updated_at: crate::api::vault::chrono_now(),
        deleted_ids: session.deleted_ids.clone(),
    }
}

/// Extracts the cached master key from the session while the lock is held.
fn extract_yubikey(session: &VaultSession) -> YubikeyTriple {
    session
        .yubikey
        .as_ref()
        .map(|yk| Zeroizing::new(*yk.vault_key_master))
}

/// Saves using passphrase alone, or a multi-key body-only re-seal if the session
/// has a cached `vault_key_master`.
///
/// Multi-key vaults: re-seals only the body using `vault_key_master` (no Argon2id
/// re-derivation; all YubiKey records stay intact).
fn do_save(
    body: &VaultBody,
    passphrase: &[u8],
    path: &std::path::Path,
    yubikey: YubikeyTriple,
) -> Result<(), String> {
    match yubikey {
        Some(ref vault_key_master) => reseal_vault_body(body, vault_key_master, path),
        None => save_vault(body, passphrase, path),
    }
}

/// Returns the UUID of any entry variant.
fn entry_id(entry: &VaultEntry) -> &str {
    match entry {
        VaultEntry::Login(e) => &e.meta.id,
        VaultEntry::Note(e) => &e.meta.id,
        VaultEntry::Identity(e) => &e.meta.id,
        VaultEntry::Card(e) => &e.meta.id,
        VaultEntry::File(e) => &e.meta.id,
        VaultEntry::Custom(e) => &e.meta.id,
    }
}

/// Concatenates non-empty strings into a single lowercase, space-joined blob.
fn make_blob(parts: &[&str]) -> String {
    parts
        .iter()
        .filter(|s| !s.is_empty())
        .map(|s| s.to_lowercase())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Appends non-hidden custom field values to `parts`. Field labels are
/// intentionally excluded: full-text search matches values, not labels (so an
/// empty field labelled "Phone" never matches a "phone" search).
fn push_custom_fields<'a>(parts: &mut Vec<&'a str>, fields: &'a [CustomField]) {
    for f in fields {
        if !f.hidden {
            parts.push(&f.value);
        }
    }
}

/// Builds a lightweight summary DTO from any entry variant.
///
/// Display title selection per type:
/// - Login:    `title` field; falls back to `url` if empty, then UUID
/// - Note:     `title` field
/// - Identity: `first_name + " " + last_name`
/// - Card:     `card_name` if present; falls back to `cardholder_name`
/// - File:     `filename`
/// - Custom:   `title` field
///
/// `search_blob` is a lowercase union of all searchable non-secret field
/// *values*. Field labels (incl. custom field labels) are excluded so search
/// matches values, not labels. Passwords, card numbers, CVVs, PINs, and hidden
/// custom field values are excluded.
fn entry_to_summary(entry: &VaultEntry) -> EntrySummaryData {
    match entry {
        VaultEntry::Login(e) => {
            let mut parts: Vec<&str> = vec![
                &e.title,
                &e.username,
                &e.url,
                e.notes.as_deref().unwrap_or(""),
            ];
            push_custom_fields(&mut parts, &e.custom_fields);
            EntrySummaryData {
                id: e.meta.id.clone(),
                entry_type: String::from("Login"),
                title: if !e.title.is_empty() {
                    e.title.clone()
                } else if !e.url.is_empty() {
                    e.url.clone()
                } else {
                    e.meta.id.clone()
                },
                folder: e.meta.folder.clone(),
                search_blob: make_blob(&parts),
            }
        }
        VaultEntry::Note(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Note"),
            title: e.title.clone(),
            folder: e.meta.folder.clone(),
            search_blob: make_blob(&[&e.title, &e.content]),
        },
        VaultEntry::Identity(e) => {
            let mut parts: Vec<&str> = vec![
                &e.first_name,
                &e.last_name,
                &e.email,
                e.phone.as_deref().unwrap_or(""),
                e.address.as_deref().unwrap_or(""),
            ];
            push_custom_fields(&mut parts, &e.custom_fields);
            EntrySummaryData {
                id: e.meta.id.clone(),
                entry_type: String::from("Identity"),
                title: format!("{} {}", e.first_name, e.last_name),
                folder: e.meta.folder.clone(),
                search_blob: make_blob(&parts),
            }
        }
        VaultEntry::Card(e) => {
            let mut parts: Vec<&str> = vec![
                e.card_name.as_deref().unwrap_or(""),
                &e.cardholder_name,
                e.bank_name.as_deref().unwrap_or(""),
                e.payment_network.as_deref().unwrap_or(""),
                e.notes.as_deref().unwrap_or(""),
            ];
            push_custom_fields(&mut parts, &e.custom_fields);
            EntrySummaryData {
                id: e.meta.id.clone(),
                entry_type: String::from("Card"),
                title: e
                    .card_name
                    .as_deref()
                    .filter(|s| !s.is_empty())
                    .unwrap_or(&e.cardholder_name)
                    .to_string(),
                folder: e.meta.folder.clone(),
                search_blob: make_blob(&parts),
            }
        }
        VaultEntry::File(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("File"),
            title: e.filename.clone(),
            folder: e.meta.folder.clone(),
            search_blob: make_blob(&[&e.filename, e.notes.as_deref().unwrap_or("")]),
        },
        VaultEntry::Custom(e) => {
            let mut parts: Vec<&str> = vec![&e.title];
            for f in e.fields.values() {
                if !f.hidden {
                    parts.push(&f.value);
                }
            }
            EntrySummaryData {
                id: e.meta.id.clone(),
                entry_type: String::from("Custom"),
                title: e.title.clone(),
                folder: e.meta.folder.clone(),
                search_blob: make_blob(&parts),
            }
        }
    }
}

/// Return lightweight summaries of all entries in the session.
///
/// No passwords, no file data — just enough for Flutter to render a list.
/// Sync — reads from in-memory session, no I/O.
pub fn list_entry_summaries() -> Result<Vec<EntrySummaryData>, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    Ok(session.entries.iter().map(entry_to_summary).collect())
}

/// Return one full entry by UUID.
///
/// Sync — reads from in-memory session, no I/O.
pub fn get_entry(id: &str) -> Result<VaultEntry, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    session
        .entries
        .iter()
        .find(|e| entry_id(e) == id)
        .cloned()
        .ok_or_else(|| format!("No entry found with id: {id}"))
}

/// Remove multiple entries by UUID from the in-memory session only — no disk write.
///
/// Used by bulk delete: remove all entries in one pass, then call
/// `session_save()` once rather than once per entry.
pub fn session_delete_entries_no_save(ids: &[String]) -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_mut().ok_or("Vault is locked")?;
    let now = crate::api::vault::chrono_now();
    for id in ids {
        if session.entries.iter().any(|e| entry_id(e) == id.as_str()) {
            session.deleted_ids.push(DeletedEntry {
                id: id.clone(),
                deleted_at: now.clone(),
            });
        }
    }
    session
        .entries
        .retain(|e| !ids.contains(&entry_id(e).to_string()));
    Ok(())
}

/// Return the set of UUIDs of all entries currently in the session.
///
/// Used by import to check for existing entries before adding new ones.
/// Sync — reads from in-memory session, no I/O.
pub fn session_entry_ids() -> Result<std::collections::HashSet<String>, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    Ok(session
        .entries
        .iter()
        .map(|e| entry_id(e).to_string())
        .collect())
}

/// Add a new entry to the in-memory session only — no disk write.
///
/// Used by bulk operations (e.g. import) that add many entries and
/// want to save once at the end rather than once per entry.
pub fn session_add_entry_no_save(entry: VaultEntry) -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_mut().ok_or("Vault is locked")?;
    session.entries.push(entry);
    Ok(())
}

/// Persist the current session state to disk.
///
/// Used after bulk operations that called `session_add_entry_no_save`
/// for each entry and now want a single save.
pub fn session_save() -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_ref().ok_or("Vault is locked")?;
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    };
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Add a new entry to the session and persist the vault to disk.
///
/// Async — triggers a full vault save (Argon2id + encryption).
pub fn session_create_entry(entry: VaultEntry) -> Result<EntrySummaryData, String> {
    let summary;
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        summary = entry_to_summary(&entry);
        session.entries.push(entry);
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(summary)
}

/// Replace an existing entry by UUID and persist.
///
/// Async — triggers a full vault save.
pub fn session_update_entry(updated: VaultEntry, expiry_days: Option<u32>) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        crate::api::vault::update_entry(&mut session.entries, updated, expiry_days)?;
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Remove an entry by UUID and persist.
///
/// Async — triggers a full vault save.
pub fn session_delete_entry(id: &str) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        crate::api::vault::delete_entry(&mut session.entries, id)?;
        session.deleted_ids.push(DeletedEntry {
            id: id.to_string(),
            deleted_at: crate::api::vault::chrono_now(),
        });
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Wipe the vault file from disk and drop the session.
pub fn session_delete_whole_vault() -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let inner = session.as_ref().ok_or("Vault is locked")?;
    crate::api::vault::delete_whole_vault(&inner.path)?;
    *session = None;
    Ok(())
}

/// Re-seal the vault under a new passphrase. Session remains live.
///
/// Multi-key vaults: only the passphrase_blob is re-encrypted; all key_blobs and
/// the vault body are unchanged, so any registered key continues to work.  Old
/// passphrase verified by decrypting passphrase_blob.
/// Passphrase-only vaults: full re-seal via save_vault.
pub fn session_change_passphrase(
    old_passphrase: &[u8],
    new_passphrase: &[u8],
) -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_mut().ok_or("Vault is locked")?;

    let path = session.path.clone();

    if let Some(ref yk) = session.yubikey {
        let vault_key_master = Zeroizing::new(*yk.vault_key_master);
        let body = build_body(session);
        let plaintext = Zeroizing::new(
            crate::vault::serialization::serialize_vault_body(&body).map_err(|e| e.to_string())?,
        );
        change_passphrase_with_keys(
            old_passphrase,
            new_passphrase,
            &vault_key_master,
            &plaintext,
            &path,
        )?;
    } else {
        load_vault(old_passphrase, &path)?;
        let body = build_body(session);
        save_vault(&body, new_passphrase, &path)?;
    }

    // The disk change has happened: update the session before anything that
    // can still fail, so session and disk can never disagree.
    session.passphrase = Zeroizing::new(new_passphrase.to_vec());

    // R-03: the save above rotated the pre-change vault into `.bak`, which the
    // user may no longer be able to open. Refresh it to the new credentials.
    crate::vault::io::refresh_backup_after_credential_change(&path)?;
    Ok(())
}

/// Restore a recovery-history record: set its field back to the saved value and
/// remove the record (it is now the current value). `index` is the record's
/// position in the entry's history list.
pub fn session_restore_history(id: String, index: u32) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let entry = session
            .entries
            .iter_mut()
            .find(|e| entry_id(e) == id)
            .ok_or_else(|| format!("No entry found with id: {id}"))?;
        let idx = index as usize;
        let record = {
            let meta = meta_of(entry);
            meta.history
                .get(idx)
                .cloned()
                .ok_or_else(|| format!("No history record at index {index}"))?
        };
        crate::api::vault::set_entry_field_by_key(entry, &record.field, &record.value);
        let now = crate::api::vault::now_ms();
        let meta = meta_of_mut(entry);
        meta.history.remove(idx);
        meta.field_times.insert(record.field.clone(), now);
        meta.updated_at = crate::api::vault::chrono_now();
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    };
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Read an entry's recovery-history records (replaced values kept for restore).
pub fn session_get_entry_history(
    id: String,
) -> Result<Vec<crate::api::vault::HistoryRecordData>, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    let entry = session
        .entries
        .iter()
        .find(|e| entry_id(e) == id)
        .ok_or_else(|| format!("No entry found with id: {id}"))?;
    Ok(meta_of(entry)
        .history
        .iter()
        .map(|h| crate::api::vault::HistoryRecordData {
            field: h.field.clone(),
            value: h.value.clone(),
            saved_at: h.saved_at.clone(),
            expires_at: h.expires_at.clone(),
        })
        .collect())
}

/// Delete a recovery-history record without restoring it.
pub fn session_delete_history(id: String, index: u32) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let entry = session
            .entries
            .iter_mut()
            .find(|e| entry_id(e) == id)
            .ok_or_else(|| format!("No entry found with id: {id}"))?;
        let idx = index as usize;
        let meta = meta_of_mut(entry);
        if idx >= meta.history.len() {
            return Err(format!("No history record at index {index}"));
        }
        meta.history.remove(idx);
        meta.updated_at = crate::api::vault::chrono_now();
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    };
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Write .gabbro + .gabbro.sha256, preserving the vault's protection (ADR-013).
///
/// The default export copies the sealed on-disk vault byte-for-byte, so a
/// key-protected vault stays key-protected (its keyslots and alias are retained)
/// and the copy is never weaker than the original. Every committed CRUD op already
/// persists to disk, so the on-disk file reflects current session state.
///
/// The opt-in passphrase-only *downgrade* is a separate path (see ADR-013) and is
/// not reachable here.
pub fn session_export_vault(export_path: PathBuf) -> Result<(), String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    crate::api::vault::export_vault_preserving(&session.path, &export_path)
}

/// Write a passphrase-only `.gabbro` + `.gabbro.sha256` — the opt-in security
/// downgrade (ADR-013).
///
/// Re-seals the current session body under the session passphrase **alone**,
/// dropping any YubiKey requirement, so the artifact opens with the passphrase
/// only. Reached solely via the explicit, warned export toggle; the original
/// vault on disk is never mutated (it stays in its protection class). The user is
/// already authenticated this session — a key-protected vault required a YubiKey
/// tap to unlock — so no extra hardware gate is imposed here.
pub fn session_export_vault_passphrase_only(export_path: PathBuf) -> Result<(), String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    let body = build_body(session);
    crate::api::vault::export_vault(&body, &session.passphrase, &export_path)
}

/// Serialize the current session to a plaintext JSON file at `export_path`.
///
/// The output is completely unencrypted — all secrets appear in plain text.
/// Flutter must surface a visible warning before calling this.
pub fn session_export_vault_json(export_path: PathBuf) -> Result<(), String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;

    #[derive(serde::Serialize)]
    struct JsonExport<'a> {
        exported_at: String,
        folders: &'a [String],
        entries: &'a [VaultEntry],
    }

    let export = JsonExport {
        exported_at: crate::api::vault::chrono_now(),
        folders: &session.folders,
        entries: &session.entries,
    };

    // Zeroize the plaintext-secrets buffer on drop (S-06). The on-disk file is
    // unencrypted by design (0600); this only scrubs the in-RAM copy.
    let json = Zeroizing::new(serde_json::to_string_pretty(&export).map_err(|e| e.to_string())?);
    crate::vault::io::atomic_write_0600(&export_path, json.as_bytes())?;
    Ok(())
}

/// Build the protection-preserving export artifact (ciphertext bytes + SHA-256
/// line) for the current session **without writing** — the Android SAF path,
/// where the file write happens in Kotlin via the granted directory tree.
///
/// Mirrors [`session_export_vault`] but returns the bytes instead of writing to a
/// path. `vault_filename` (e.g. `Gabbro.gabbro`) names the file in the SHA line;
/// the companion is `<vault_filename>.sha256`. The bytes are ciphertext — safe to
/// cross the Flutter/Rust bridge.
pub fn session_export_vault_bytes(vault_filename: &str) -> Result<(Vec<u8>, String), String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    let vault_bytes = std::fs::read(&session.path)
        .map_err(|e| format!("Failed to read vault for export: {e}"))?;
    let line = crate::api::vault::sha256_line(&vault_bytes, vault_filename);
    Ok((vault_bytes, line))
}

/// Build the opt-in passphrase-only downgrade export artifact (ADR-013) for the
/// current session **without writing** — the Android SAF counterpart to
/// [`session_export_vault_passphrase_only`]. Re-seals the body under the
/// passphrase alone; the bytes are ciphertext.
pub fn session_export_vault_passphrase_only_bytes(
    vault_filename: &str,
) -> Result<(Vec<u8>, String), String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    let body = build_body(session);
    let vault_bytes = crate::api::vault::build_passphrase_only_bytes(&body, &session.passphrase)?;
    let line = crate::api::vault::sha256_line(&vault_bytes, vault_filename);
    Ok((vault_bytes, line))
}

/// Lightweight login summary for the autofill fill path.
///
/// Contains only the fields needed for domain matching and credential delivery.
/// Passwords never appear here — the fill path fetches the full entry by id
/// only after the user has selected a match.
#[derive(Debug, Clone)]
pub struct LoginAutofillSummary {
    pub id: String,
    pub username: String,
    pub url: String,
    /// Recorded Android package name for native-app matching; `None` if unset.
    pub app_id: Option<String>,
    /// Email/identifier routed to email-typed fields; `None` if unset.
    pub email: Option<String>,
}

/// Serialize autofill summaries to the JSON array the autofill service reads.
///
/// Shape: `[{"id","username","url","app_id"}]`. `app_id` is the empty string
/// when unset (Kotlin treats empty as "no native-app match"). Extracted from
/// the JNI bridge so it is host-compiled and unit-testable. Kotlin parses this
/// with `org.json.JSONArray` — no new Android dependency.
pub fn login_summaries_json(summaries: &[LoginAutofillSummary]) -> String {
    // Build with serde_json so backslashes and control characters are escaped
    // correctly (S-07): a hand-rolled escaper that only handled `"` produced
    // invalid JSON for a username/url containing `\` or a control char.
    let arr: Vec<serde_json::Value> = summaries
        .iter()
        .map(|s| {
            serde_json::json!({
                "id": s.id,
                "username": s.username,
                "url": s.url,
                "app_id": s.app_id.as_deref().unwrap_or(""),
                "email": s.email.as_deref().unwrap_or(""),
            })
        })
        .collect();
    serde_json::Value::Array(arr).to_string()
}

/// Return lightweight summaries of all Login entries in the session.
///
/// Used by GabbroAutofillService (via JNI) to find candidates for domain
/// matching without crossing passwords over the JNI boundary.
/// Sync — reads from in-memory session, no I/O.
pub fn login_summaries_for_autofill() -> Result<Vec<LoginAutofillSummary>, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    Ok(session
        .entries
        .iter()
        .filter_map(|e| {
            if let VaultEntry::Login(ref login) = e {
                Some(LoginAutofillSummary {
                    id: login.meta.id.clone(),
                    username: login.username.clone(),
                    url: login.url.clone(),
                    app_id: login.app_id.clone(),
                    email: login.email.clone(),
                })
            } else {
                None
            }
        })
        .collect())
}

/// Return a JSON string encoding the id, username, and password for a
/// single Login entry, looked up by UUID.
///
/// Used by GabbroAutofillService (via JNI) to fetch the password for a
/// matched credential immediately before filling. The password only crosses
/// the JNI boundary at the moment the user has explicitly selected an entry.
///
/// Returns `Err` if the vault is locked, the id is not found, or the entry
/// is not a Login entry.
pub fn get_entry_for_autofill(id: &str) -> Result<Zeroizing<String>, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    let entry = session
        .entries
        .iter()
        .find(|e| entry_id(e) == id)
        .ok_or_else(|| format!("No entry found with id: {id}"))?;
    match entry {
        VaultEntry::Login(e) => {
            // Serialize from borrowed fields (no password clone into a map) and
            // return the carrier in a Zeroizing<String> so it is scrubbed on
            // drop once the JNI side has copied it (S-06). serde_json escapes
            // correctly, unlike a hand-rolled formatter (cf. S-07).
            #[derive(serde::Serialize)]
            struct AutofillEntry<'a> {
                id: &'a str,
                username: &'a str,
                password: &'a str,
            }
            let json = serde_json::to_string(&AutofillEntry {
                id: &e.meta.id,
                username: &e.username,
                password: &e.password,
            })
            .map_err(|err| err.to_string())?;
            Ok(Zeroizing::new(json))
        }
        _ => Err(format!("Entry {id} is not a Login entry")),
    }
}

// ── Folder management ─────────────────────────────────────────────────────────

/// Return the list of folder names from the current session.
///
/// Sync — reads from in-memory session, no I/O.
pub fn session_list_folders() -> Result<Vec<String>, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    Ok(session.folders.clone())
}

/// Rename an existing folder and update all entries that reference it.
///
/// Returns `Err` if `old_name` does not exist, `new_name` is empty,
/// or `new_name` already exists.
/// Async — triggers a full vault save.
pub fn session_rename_folder(old_name: String, new_name: String) -> Result<(), String> {
    if new_name.is_empty() {
        return Err(String::from("Folder name must not be empty"));
    }
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        if !session.folders.contains(&old_name) {
            return Err(format!("Folder not found: {old_name}"));
        }
        if session.folders.contains(&new_name) {
            return Err(format!("Folder already exists: {new_name}"));
        }
        for f in session.folders.iter_mut() {
            if *f == old_name {
                *f = new_name.clone();
                break;
            }
        }
        for entry in session.entries.iter_mut() {
            let folder = match entry {
                VaultEntry::Login(e) => &mut e.meta.folder,
                VaultEntry::Note(e) => &mut e.meta.folder,
                VaultEntry::Identity(e) => &mut e.meta.folder,
                VaultEntry::Card(e) => &mut e.meta.folder,
                VaultEntry::File(e) => &mut e.meta.folder,
                VaultEntry::Custom(e) => &mut e.meta.folder,
            };
            if *folder == old_name {
                *folder = new_name.clone();
            }
        }
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Delete a folder and either reassign its entries to another folder or
/// clear them to `""` (unfoldered).
///
/// Returns `Err` if `name` does not exist, or if `reassign_to` names a
/// folder that does not exist.
/// Async — triggers a full vault save.
pub fn session_delete_folder(name: String, reassign_to: Option<String>) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        if !session.folders.contains(&name) {
            return Err(format!("Folder not found: {name}"));
        }
        if let Some(ref target) = reassign_to {
            if !session.folders.contains(target) {
                return Err(format!("Folder not found: {target}"));
            }
        }
        session.folders.retain(|f| *f != name);
        let target = reassign_to.unwrap_or_default();
        for entry in session.entries.iter_mut() {
            let folder = match entry {
                VaultEntry::Login(e) => &mut e.meta.folder,
                VaultEntry::Note(e) => &mut e.meta.folder,
                VaultEntry::Identity(e) => &mut e.meta.folder,
                VaultEntry::Card(e) => &mut e.meta.folder,
                VaultEntry::File(e) => &mut e.meta.folder,
                VaultEntry::Custom(e) => &mut e.meta.folder,
            };
            if *folder == name {
                *folder = target.clone();
            }
        }
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Assign a folder to a set of entries by UUID, in one pass, then persist.
///
/// Entries not in `ids` are unchanged. Returns `Err` if the vault is locked
/// or `folder` names a folder that does not exist (empty string is always
/// valid — it means unfoldered).
pub fn session_assign_folder_to_entries(ids: &[String], folder: String) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        if !folder.is_empty() && !session.folders.contains(&folder) {
            return Err(format!("Folder not found: {folder}"));
        }
        for entry in session.entries.iter_mut() {
            let (id, f) = match entry {
                VaultEntry::Login(e) => (&e.meta.id, &mut e.meta.folder),
                VaultEntry::Note(e) => (&e.meta.id, &mut e.meta.folder),
                VaultEntry::Identity(e) => (&e.meta.id, &mut e.meta.folder),
                VaultEntry::Card(e) => (&e.meta.id, &mut e.meta.folder),
                VaultEntry::File(e) => (&e.meta.id, &mut e.meta.folder),
                VaultEntry::Custom(e) => (&e.meta.id, &mut e.meta.folder),
            };
            if ids.contains(id) {
                *f = folder.clone();
            }
        }
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Add a new folder to the session and persist the vault to disk.
///
/// Returns `Err` if the name is empty or already exists.
/// Async — triggers a full vault save.
pub fn session_create_folder(name: String) -> Result<(), String> {
    if name.is_empty() {
        return Err(String::from("Folder name must not be empty"));
    }
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        if session.folders.contains(&name) {
            return Err(format!("Folder already exists: {name}"));
        }
        session.folders.push(name);
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

// ── YubiKey key-management ────────────────────────────────────────────────────

/// Add a new YubiKey to the vault header and re-seal the body.
///
/// Requires a VERSION 4 vault (`wrapping_key` and `vault_key_master` cached
/// from unlock). Re-seals the body so the updated header (new YubiKey record)
/// is committed as AES-GCM AAD for VERSION 7+ vaults.
pub fn session_add_yubikey(
    new_cred_id: Vec<u8>,
    new_hmac_secret: Vec<u8>,
    new_salt: Vec<u8>,
) -> Result<(), String> {
    let (body, path, wrapping_key, vault_key_master) = {
        let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_ref().ok_or("Vault is locked")?;
        let yk = session.yubikey.as_ref().ok_or("Not a YubiKey vault")?;
        let wk = yk
            .wrapping_key
            .as_ref()
            .ok_or("Adding a YubiKey requires a VERSION 4 vault")?;
        (
            build_body(session),
            session.path.clone(),
            Zeroizing::new(**wk),
            Zeroizing::new(*yk.vault_key_master),
        )
    };
    let hmac: [u8; 32] = new_hmac_secret
        .as_slice()
        .try_into()
        .map_err(|_| "new_hmac_secret must be 32 bytes".to_string())?;
    let salt: [u8; 32] = new_salt
        .as_slice()
        .try_into()
        .map_err(|_| "new_salt must be 32 bytes".to_string())?;
    let plaintext = Zeroizing::new(
        crate::vault::serialization::serialize_vault_body(&body).map_err(|e| e.to_string())?,
    );
    add_yubikey_to_vault(
        &plaintext,
        &wrapping_key,
        &vault_key_master,
        new_cred_id,
        &hmac,
        salt,
        &path,
    )?;
    // R-03: credential change — refresh .bak to the post-change vault.
    crate::vault::io::refresh_backup_after_credential_change(&path)
}

/// Remove a YubiKey record from the vault header by its credential ID and
/// re-seal the body so the updated header is committed as AES-GCM AAD.
///
/// Enforces a minimum of 1 key (removing the last key returns an error).
pub fn session_remove_yubikey(cred_id: Vec<u8>) -> Result<(), String> {
    let (body, path, vault_key_master) = {
        let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_ref().ok_or("Vault is locked")?;
        let yk = session.yubikey.as_ref().ok_or("Not a YubiKey vault")?;
        (
            build_body(session),
            session.path.clone(),
            Zeroizing::new(*yk.vault_key_master),
        )
    };
    let plaintext = Zeroizing::new(
        crate::vault::serialization::serialize_vault_body(&body).map_err(|e| e.to_string())?,
    );
    remove_yubikey_from_vault(&plaintext, &vault_key_master, &cred_id, &path)?;
    // R-03: credential change — refresh .bak to the post-change vault.
    crate::vault::io::refresh_backup_after_credential_change(&path)
}

/// Rename the vault and re-seal the body bound to the updated header.
///
/// Requires an unlocked session — the cached key material is used to re-seal
/// the body so the new alias is committed as AES-GCM AAD for VERSION 7+ vaults.
/// Passing an empty string clears the alias.
pub fn session_set_vault_alias(alias: String) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_ref().ok_or("Vault is locked")?;
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    };

    let new_alias = if alias.is_empty() { None } else { Some(alias) };
    let plaintext = Zeroizing::new(
        crate::vault::serialization::serialize_vault_body(&body).map_err(|e| e.to_string())?,
    );

    match yubikey {
        Some(ref vault_key_master) => {
            use crate::vault::io::{read_vault, write_vault};
            let mut sealed = read_vault(&path)?;
            sealed.alias = new_alias;
            crate::crypto::vault_crypto::reseal_vault_body(
                &mut sealed,
                vault_key_master,
                &plaintext,
            )?;
            write_vault(&sealed, &path)
        }
        None => {
            // Passphrase-only: full re-seal with alias bound to body via AAD.
            use crate::vault::io::write_vault;
            let sealed =
                crate::crypto::vault_crypto::seal_vault(&passphrase, &plaintext, new_alias)?;
            write_vault(&sealed, &path)
        }
    }
}

/// Set or update the display alias for a registered YubiKey.
///
/// `credential_id_hex` is the hex-encoded credential ID (key in `yubikey_aliases`).
/// Stored in the encrypted vault body and persisted to disk immediately.
pub fn session_set_yubikey_alias(credential_id_hex: String, alias: String) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        session.yubikey_aliases.insert(credential_id_hex, alias);
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    };
    do_save(&body, &passphrase, &path, yubikey)
}

/// Return a snapshot of all YubiKey aliases stored in the current session.
pub fn session_list_yubikey_aliases() -> Result<std::collections::HashMap<String, String>, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    Ok(session.yubikey_aliases.clone())
}

// ── Vault sync merge ──────────────────────────────────────────────────────────

/// Return the folder of any entry variant.
fn entry_folder(entry: &VaultEntry) -> &str {
    match entry {
        VaultEntry::Login(e) => &e.meta.folder,
        VaultEntry::Note(e) => &e.meta.folder,
        VaultEntry::Identity(e) => &e.meta.folder,
        VaultEntry::Card(e) => &e.meta.folder,
        VaultEntry::File(e) => &e.meta.folder,
        VaultEntry::Custom(e) => &e.meta.folder,
    }
}

/// Return a human-readable display title for any entry variant.
///
/// Uses the same fallback logic as `entry_to_summary`.
fn entry_display_title(entry: &VaultEntry) -> String {
    match entry {
        VaultEntry::Login(e) => {
            if !e.title.is_empty() {
                e.title.clone()
            } else if !e.url.is_empty() {
                e.url.clone()
            } else {
                e.meta.id.clone()
            }
        }
        VaultEntry::Note(e) => e.title.clone(),
        VaultEntry::Identity(e) => format!("{} {}", e.first_name, e.last_name),
        VaultEntry::Card(e) => e
            .card_name
            .as_deref()
            .filter(|s| !s.is_empty())
            .unwrap_or(&e.cardholder_name)
            .to_string(),
        VaultEntry::File(e) => e.filename.clone(),
        VaultEntry::Custom(e) => e.title.clone(),
    }
}

// ── Granular (field-level) merge of a same-UUID entry pair (v9) ───────────────

use crate::api::vault::{FieldConflictItem, PendingItemDeleteItem};
use crate::vault::entry::{
    CardEntry, CustomEntry, EntryAttachment, EntryMeta, FileEntry, IdentityEntry, LoginEntry,
    NoteEntry,
};

#[derive(Clone, Copy)]
enum Side {
    Local,
    Incoming,
}

fn meta_of(e: &VaultEntry) -> &EntryMeta {
    match e {
        VaultEntry::Login(x) => &x.meta,
        VaultEntry::Note(x) => &x.meta,
        VaultEntry::Identity(x) => &x.meta,
        VaultEntry::Card(x) => &x.meta,
        VaultEntry::File(x) => &x.meta,
        VaultEntry::Custom(x) => &x.meta,
    }
}

fn meta_of_mut(e: &mut VaultEntry) -> &mut EntryMeta {
    match e {
        VaultEntry::Login(x) => &mut x.meta,
        VaultEntry::Note(x) => &mut x.meta,
        VaultEntry::Identity(x) => &mut x.meta,
        VaultEntry::Card(x) => &mut x.meta,
        VaultEntry::File(x) => &mut x.meta,
        VaultEntry::Custom(x) => &mut x.meta,
    }
}

/// Decide one field, by EDIT-MARK PRESENCE, not by timestamp value. A field that
/// was edited carries a change-stamp (`Some`); an untouched field does not (`None`).
/// Returns the winning side, the stamp to record on the merged field, and whether
/// this is a collision the user must resolve.
///
/// Rules (values that are equal are never a collision):
/// - both sides edited it (both stamped), values differ -> COLLISION, keep local.
///   A clock is never used to pick a winner (a real same-instant edit is near
///   impossible; the realistic case is two edits at different times, both kept
///   until the user chooses).
/// - exactly one side edited it -> take that side's value (additive), no prompt.
/// - neither side carries a stamp (pre-v9, or both untouched): fall back to the
///   whole-entry `updated_at`; an exact tie with differing values is a collision.
fn decide_field(
    lt: Option<u64>,
    it: Option<u64>,
    l_updated: &str,
    i_updated: &str,
    values_equal: bool,
) -> (Side, Option<u64>, bool) {
    // Stamp recorded on the merged field: stay "edited" if either side was, using
    // the max for deterministic convergence. Decisions use only PRESENCE below.
    let merged_stamp = match (lt, it) {
        (Some(l), Some(i)) => Some(l.max(i)),
        (Some(l), None) => Some(l),
        (None, Some(i)) => Some(i),
        (None, None) => None,
    };
    if values_equal {
        return (Side::Local, merged_stamp, false);
    }
    match (lt, it) {
        (Some(_), Some(_)) => (Side::Local, merged_stamp, true), // both edited -> collision
        (Some(_), None) => (Side::Local, merged_stamp, false),   // only local edited
        (None, Some(_)) => (Side::Incoming, merged_stamp, false), // only incoming edited
        (None, None) => {
            if i_updated > l_updated {
                (Side::Incoming, None, false)
            } else if l_updated > i_updated {
                (Side::Local, None, false)
            } else {
                (Side::Local, None, true)
            }
        }
    }
}

/// Accumulates the per-field decisions for one entry pair: the merged field-times,
/// any clashes to surface, and any pending item deletions.
struct FieldMerger<'a> {
    id: String,
    title: String,
    lm: &'a EntryMeta,
    im: &'a EntryMeta,
    times: std::collections::BTreeMap<String, u64>,
    conflicts: Vec<FieldConflictItem>,
    pending: Vec<PendingItemDeleteItem>,
    brought_over: Vec<crate::api::vault::BroughtOverItem>,
}

impl<'a> FieldMerger<'a> {
    fn new(lm: &'a EntryMeta, im: &'a EntryMeta, title: String) -> Self {
        FieldMerger {
            id: lm.id.clone(),
            title,
            lm,
            im,
            times: std::collections::BTreeMap::new(),
            conflicts: Vec::new(),
            pending: Vec::new(),
            brought_over: Vec::new(),
        }
    }

    // Record a non-conflicting incoming value that won additively, so the user can
    // review and drop it (drop = restore `old`).
    fn record_brought_over(&mut self, key: &str, old: &str, new: &str) {
        self.brought_over.push(crate::api::vault::BroughtOverItem {
            id: self.id.clone(),
            title: self.title.clone(),
            field: key.to_string(),
            old_value: old.to_string(),
            new_value: new.to_string(),
        });
    }

    fn decide(&mut self, key: &str, equal: bool, l_disp: &str, i_disp: &str) -> Side {
        let lt = self.lm.field_times.get(key).copied();
        let it = self.im.field_times.get(key).copied();
        let (side, ts, clash) =
            decide_field(lt, it, &self.lm.updated_at, &self.im.updated_at, equal);
        if let Some(t) = ts {
            self.times.insert(key.to_string(), t);
        }
        if clash {
            self.conflicts.push(FieldConflictItem {
                id: self.id.clone(),
                title: self.title.clone(),
                field: key.to_string(),
                local_value: l_disp.to_string(),
                incoming_value: i_disp.to_string(),
            });
        } else if matches!(side, Side::Incoming) {
            // Incoming won an unequal field that this side never edited: a
            // brought-over change to surface for review.
            self.record_brought_over(key, l_disp, i_disp);
        }
        side
    }

    fn pick_str(&mut self, key: &str, lv: &str, iv: &str) -> String {
        match self.decide(key, lv == iv, lv, iv) {
            Side::Local => lv.to_string(),
            Side::Incoming => iv.to_string(),
        }
    }

    fn pick_opt(&mut self, key: &str, lv: &Option<String>, iv: &Option<String>) -> Option<String> {
        let l_disp = lv.clone().unwrap_or_default();
        let i_disp = iv.clone().unwrap_or_default();
        match self.decide(key, lv == iv, &l_disp, &i_disp) {
            Side::Local => lv.clone(),
            Side::Incoming => iv.clone(),
        }
    }

    // Carry an item that exists on only one side (an add, or this side is newer);
    // preserve its recorded change-time.
    fn carry_one_sided(&mut self, key: &str, from_incoming: bool) {
        let src = if from_incoming { self.im } else { self.lm };
        if let Some(t) = src.field_times.get(key).copied() {
            self.times.insert(key.to_string(), t);
        }
    }

    // An item present on only one side: keep it, but if the OTHER side deleted it
    // (a "del:<key>" tombstone) more recently than this side last changed it,
    // record a pending delete for the user to confirm. Never auto-drops. Returns
    // true if a pending delete was flagged.
    fn carry_or_flag_delete(&mut self, key: &str, present_on_incoming: bool) -> bool {
        let del_key = format!("del:{key}");
        let (present_meta, other_meta) = if present_on_incoming {
            (self.im, self.lm)
        } else {
            (self.lm, self.im)
        };
        let item_ts = present_meta.field_times.get(key).copied().unwrap_or(0);
        let mut flagged = false;
        if let Some(del_ts) = other_meta.field_times.get(&del_key).copied() {
            if del_ts > item_ts {
                self.pending.push(PendingItemDeleteItem {
                    id: self.id.clone(),
                    title: self.title.clone(),
                    field: key.to_string(),
                });
                flagged = true;
            }
        }
        self.carry_one_sided(key, present_on_incoming);
        flagged
    }

    fn merge_custom(
        &mut self,
        local: &[CustomField],
        incoming: &[CustomField],
    ) -> Vec<CustomField> {
        let local_by: std::collections::HashMap<&str, &CustomField> =
            local.iter().map(|f| (f.label.as_str(), f)).collect();
        let inc_by: std::collections::HashMap<&str, &CustomField> =
            incoming.iter().map(|f| (f.label.as_str(), f)).collect();
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for f in local.iter().chain(incoming.iter()) {
            if !seen.insert(f.label.clone()) {
                continue;
            }
            let key = format!("custom_fields:{}", f.label);
            match (local_by.get(f.label.as_str()), inc_by.get(f.label.as_str())) {
                (Some(lf), Some(inf)) => {
                    let equal = lf.value == inf.value && lf.hidden == inf.hidden;
                    out.push(match self.decide(&key, equal, &lf.value, &inf.value) {
                        Side::Local => (*lf).clone(),
                        Side::Incoming => (*inf).clone(),
                    });
                }
                (Some(lf), None) => {
                    self.carry_or_flag_delete(&key, false);
                    out.push((*lf).clone());
                }
                (None, Some(inf)) => {
                    if !self.carry_or_flag_delete(&key, true) {
                        self.record_brought_over(&key, "", &inf.value);
                    }
                    out.push((*inf).clone());
                }
                (None, None) => unreachable!(),
            }
        }
        out
    }

    fn merge_attachments(
        &mut self,
        local: &[EntryAttachment],
        incoming: &[EntryAttachment],
    ) -> Vec<EntryAttachment> {
        let local_by: std::collections::HashMap<&str, &EntryAttachment> =
            local.iter().map(|a| (a.uuid.as_str(), a)).collect();
        let inc_by: std::collections::HashMap<&str, &EntryAttachment> =
            incoming.iter().map(|a| (a.uuid.as_str(), a)).collect();
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for a in local.iter().chain(incoming.iter()) {
            if !seen.insert(a.uuid.clone()) {
                continue;
            }
            let key = format!("attachments:{}", a.uuid);
            match (local_by.get(a.uuid.as_str()), inc_by.get(a.uuid.as_str())) {
                (Some(la), Some(ia)) => {
                    let equal = la.name == ia.name && la.kind == ia.kind && la.data == ia.data;
                    out.push(match self.decide(&key, equal, &la.name, &ia.name) {
                        Side::Local => (*la).clone(),
                        Side::Incoming => (*ia).clone(),
                    });
                }
                (Some(la), None) => {
                    self.carry_or_flag_delete(&key, false);
                    out.push((*la).clone());
                }
                (None, Some(ia)) => {
                    if !self.carry_or_flag_delete(&key, true) {
                        self.record_brought_over(&key, "", &ia.name);
                    }
                    out.push((*ia).clone());
                }
                (None, None) => unreachable!(),
            }
        }
        out
    }
}

/// Merge two same-UUID entries field by field. The newer change-time wins each
/// field; a cleared-but-newer value still wins; a true clash (same field, same
/// instant, different value) is recorded and the local value kept. Derived secrets
/// (`previous_*`) follow their parent field's winner.
pub(crate) fn merge_entry_pair(
    local: &VaultEntry,
    incoming: &VaultEntry,
) -> (
    VaultEntry,
    Vec<FieldConflictItem>,
    Vec<PendingItemDeleteItem>,
    Vec<crate::api::vault::BroughtOverItem>,
) {
    let lm = meta_of(local);
    let im = meta_of(incoming);
    let title = entry_display_title(local);
    let mut m = FieldMerger::new(lm, im, title);

    let mut merged = match (local, incoming) {
        (VaultEntry::Login(l), VaultEntry::Login(i)) => {
            let pw_side = m.decide(
                "password",
                l.password == i.password,
                &l.password,
                &i.password,
            );
            let password = match pw_side {
                Side::Local => l.password.clone(),
                Side::Incoming => i.password.clone(),
            };
            VaultEntry::Login(LoginEntry {
                meta: lm.clone(),
                title: m.pick_str("title", &l.title, &i.title),
                url: m.pick_str("url", &l.url, &i.url),
                username: m.pick_str("username", &l.username, &i.username),
                password,
                notes: m.pick_opt("notes", &l.notes, &i.notes),
                custom_fields: m.merge_custom(&l.custom_fields, &i.custom_fields),
                attachments: m.merge_attachments(&l.attachments, &i.attachments),
                app_id: m.pick_opt("app_id", &l.app_id, &i.app_id),
                email: m.pick_opt("email", &l.email, &i.email),
            })
        }
        (VaultEntry::Note(l), VaultEntry::Note(i)) => VaultEntry::Note(NoteEntry {
            meta: lm.clone(),
            title: m.pick_str("title", &l.title, &i.title),
            content: m.pick_str("content", &l.content, &i.content),
            custom_fields: m.merge_custom(&l.custom_fields, &i.custom_fields),
            attachments: m.merge_attachments(&l.attachments, &i.attachments),
        }),
        (VaultEntry::Identity(l), VaultEntry::Identity(i)) => VaultEntry::Identity(IdentityEntry {
            meta: lm.clone(),
            first_name: m.pick_str("first_name", &l.first_name, &i.first_name),
            last_name: m.pick_str("last_name", &l.last_name, &i.last_name),
            email: m.pick_str("email", &l.email, &i.email),
            phone: m.pick_opt("phone", &l.phone, &i.phone),
            address: m.pick_opt("address", &l.address, &i.address),
            custom_fields: m.merge_custom(&l.custom_fields, &i.custom_fields),
            attachments: m.merge_attachments(&l.attachments, &i.attachments),
        }),
        (VaultEntry::Card(l), VaultEntry::Card(i)) => {
            let cvv_side = m.decide("cvv", l.cvv == i.cvv, &l.cvv, &i.cvv);
            let cvv = match cvv_side {
                Side::Local => l.cvv.clone(),
                Side::Incoming => i.cvv.clone(),
            };
            let l_pin = l.pin.clone().unwrap_or_default();
            let i_pin = i.pin.clone().unwrap_or_default();
            let pin_side = m.decide("pin", l.pin == i.pin, &l_pin, &i_pin);
            let pin = match pin_side {
                Side::Local => l.pin.clone(),
                Side::Incoming => i.pin.clone(),
            };
            VaultEntry::Card(CardEntry {
                meta: lm.clone(),
                card_name: m.pick_opt("card_name", &l.card_name, &i.card_name),
                status: m.pick_str("status", &l.status, &i.status),
                cardholder_name: m.pick_str(
                    "cardholder_name",
                    &l.cardholder_name,
                    &i.cardholder_name,
                ),
                card_number: m.pick_str("card_number", &l.card_number, &i.card_number),
                expiry: m.pick_str("expiry", &l.expiry, &i.expiry),
                cvv,
                credit_limit: m.pick_opt("credit_limit", &l.credit_limit, &i.credit_limit),
                card_account_number: m.pick_opt(
                    "card_account_number",
                    &l.card_account_number,
                    &i.card_account_number,
                ),
                payment_network: m.pick_opt(
                    "payment_network",
                    &l.payment_network,
                    &i.payment_network,
                ),
                pin,
                bank_name: m.pick_opt("bank_name", &l.bank_name, &i.bank_name),
                transaction_password: m.pick_opt(
                    "transaction_password",
                    &l.transaction_password,
                    &i.transaction_password,
                ),
                notes: m.pick_opt("notes", &l.notes, &i.notes),
                custom_fields: m.merge_custom(&l.custom_fields, &i.custom_fields),
                attachments: m.merge_attachments(&l.attachments, &i.attachments),
            })
        }
        (VaultEntry::File(l), VaultEntry::File(i)) => {
            // File contents are binary, so they ride the string resolution path
            // as base64 (decoded back by set_entry_scalar's "data" arm). Carrying
            // the real bytes here is what lets "use other" actually swap the file
            // (the old "<binary>" placeholder made that a no-op). The UI still
            // renders "<binary>", never the base64.
            use base64::Engine;
            let b64 = |b: &[u8]| base64::engine::general_purpose::STANDARD.encode(b);
            let data = match m.decide("data", l.data == i.data, &b64(&l.data), &b64(&i.data)) {
                Side::Local => l.data.clone(),
                Side::Incoming => i.data.clone(),
            };
            VaultEntry::File(FileEntry {
                meta: lm.clone(),
                filename: m.pick_str("filename", &l.filename, &i.filename),
                data,
                notes: m.pick_opt("notes", &l.notes, &i.notes),
                custom_fields: m.merge_custom(&l.custom_fields, &i.custom_fields),
            })
        }
        (VaultEntry::Custom(l), VaultEntry::Custom(i)) => {
            let mut fields = indexmap::IndexMap::new();
            let mut keys: Vec<&String> = l.fields.keys().chain(i.fields.keys()).collect();
            keys.sort();
            keys.dedup();
            for k in keys {
                let key = format!("custom_fields:{k}");
                match (l.fields.get(k), i.fields.get(k)) {
                    (Some(lf), Some(inf)) => {
                        let equal = lf.value == inf.value
                            && lf.hidden == inf.hidden
                            && lf.label == inf.label;
                        fields.insert(
                            k.clone(),
                            match m.decide(&key, equal, &lf.value, &inf.value) {
                                Side::Local => lf.clone(),
                                Side::Incoming => inf.clone(),
                            },
                        );
                    }
                    (Some(lf), None) => {
                        m.carry_or_flag_delete(&key, false);
                        fields.insert(k.clone(), lf.clone());
                    }
                    (None, Some(inf)) => {
                        if !m.carry_or_flag_delete(&key, true) {
                            m.record_brought_over(&key, "", &inf.value);
                        }
                        fields.insert(k.clone(), inf.clone());
                    }
                    (None, None) => unreachable!(),
                }
            }
            VaultEntry::Custom(CustomEntry {
                meta: lm.clone(),
                title: m.pick_str("title", &l.title, &i.title),
                fields,
                attachments: m.merge_attachments(&l.attachments, &i.attachments),
            })
        }
        // Same id, different type (defensive): fall back to whole-entry LWW.
        _ => {
            let winner = if im.updated_at > lm.updated_at {
                incoming
            } else {
                local
            };
            return (winner.clone(), Vec::new(), Vec::new(), Vec::new());
        }
    };

    let merged_updated = std::cmp::max(lm.updated_at.clone(), im.updated_at.clone());
    let conflicts = std::mem::take(&mut m.conflicts);
    let pending = std::mem::take(&mut m.pending);
    let brought_over = std::mem::take(&mut m.brought_over);
    let mut times = std::mem::take(&mut m.times);
    // Propagate per-item deletion tombstones from both sides (newer wins) so a
    // delete is not lost on the next merge.
    for (k, v) in lm.field_times.iter().chain(im.field_times.iter()) {
        if let Some(stripped) = k.strip_prefix("del:") {
            // Drop a tombstone the merged entry has since re-added (the item is
            // present and its change is at least as new as the deletion).
            if times.contains_key(stripped) && times.get(stripped) >= Some(v) {
                continue;
            }
            let e = times.entry(k.clone()).or_insert(*v);
            if *v > *e {
                *e = *v;
            }
        }
    }
    // Union the per-entry replacement history from both sides (dedup), so a saved
    // value is never dropped on merge.
    let mut history = lm.history.clone();
    for h in &im.history {
        if !history.contains(h) {
            history.push(h.clone());
        }
    }
    {
        let meta = meta_of_mut(&mut merged);
        meta.updated_at = merged_updated;
        meta.field_times = times;
        meta.history = history;
    }
    (merged, conflicts, pending, brought_over)
}

/// Asserts a vault matches the known end-state of the hardware walk in
/// `test_data/sync_test_vaults/README.md` (import A, sync B keeping all, sync C
/// with the dictated picks). Shared by the JSON checker (`check_sync_walk_export`)
/// and the in-code simulation (`sync_walk_simulation_matches_checker`).
#[cfg(test)]
fn assert_walk_end_state(ents: &[VaultEntry]) {
    let get = |id: &str| {
        ents.iter()
            .find(|e| meta_of(e).id == id)
            .unwrap_or_else(|| panic!("missing entry: {id}"))
    };
    let cf = |fields: &[crate::vault::entry::CustomField], label: &str| -> Option<String> {
        fields
            .iter()
            .find(|f| f.label == label)
            .map(|f| f.value.clone())
    };

    // Whole-entry decisions.
    assert!(
        ents.iter().all(|e| meta_of(e).id != "delme"),
        "delme must be deleted"
    );
    assert!(
        ents.iter().any(|e| meta_of(e).id == "extra-b"),
        "extra-b (new on B) must be kept"
    );
    assert_eq!(ents.len(), 13, "12 base + extra-b, delme removed");

    // Non-colliding fields: B's and C's edits all merged.
    match get("login-nc") {
        VaultEntry::Login(e) => {
            assert_eq!(e.password, "p0-B");
            assert_eq!(e.url, "https://mail-C.example.com");
            assert!(cf(&e.custom_fields, "OldNote").is_none(), "OldNote deleted");
        }
        _ => panic!("login-nc not a Login"),
    }
    match get("note-nc") {
        VaultEntry::Note(e) => {
            assert_eq!(e.content, "milk-B");
            assert_eq!(cf(&e.custom_fields, "Tag").as_deref(), Some("tag-C"));
        }
        _ => panic!(),
    }
    match get("id-nc") {
        VaultEntry::Identity(e) => {
            assert_eq!(e.email, "alex-B@example.com");
            assert_eq!(e.address.as_deref(), Some("addr-C"));
        }
        _ => panic!(),
    }
    match get("card-nc") {
        VaultEntry::Card(e) => {
            assert_eq!(e.expiry, "06/29");
            assert_eq!(e.bank_name.as_deref(), Some("ING-C"));
        }
        _ => panic!(),
    }
    match get("file-nc") {
        VaultEntry::File(e) => {
            assert_eq!(e.data, b"original-C");
            assert_eq!(e.notes.as_deref(), Some("notes-B"));
        }
        _ => panic!(),
    }
    match get("custom-nc") {
        VaultEntry::Custom(e) => {
            assert_eq!(e.title, "API creds (C)");
            assert_eq!(
                e.fields.get("env").map(|f| f.value.as_str()),
                Some("prod-B")
            );
        }
        _ => panic!(),
    }

    // Clashes: use-other on Bank/Sam/key, keep-mine on Ideas/Amex/Tokens.
    match get("login-co") {
        VaultEntry::Login(e) => {
            assert_eq!(e.username, "bob-B");
            assert_eq!(e.password, "qC", "Bank password -> use other");
            assert!(
                e.meta
                    .history
                    .iter()
                    .any(|h| h.field == "password" && h.value == "qA"),
                "the replaced password (qA) is kept in recovery history"
            );
        }
        _ => panic!(),
    }
    match get("note-co") {
        VaultEntry::Note(e) => assert_eq!(e.content, "ideaA", "Ideas -> keep mine"),
        _ => panic!(),
    }
    match get("id-co") {
        VaultEntry::Identity(e) => {
            assert_eq!(e.first_name, "Sam-B");
            assert_eq!(e.last_name, "StoneC", "Sam last name -> use other");
        }
        _ => panic!(),
    }
    match get("card-co") {
        VaultEntry::Card(e) => {
            assert_eq!(e.cvv, "555A", "Amex CVV -> keep mine");
            assert_eq!(e.expiry, "07/29");
        }
        _ => panic!(),
    }
    match get("file-co") {
        VaultEntry::File(e) => assert_eq!(e.data, b"dataC", "key.txt data -> use other"),
        _ => panic!(),
    }
    match get("custom-co") {
        VaultEntry::Custom(e) => {
            assert_eq!(
                e.fields.get("token").map(|f| f.value.as_str()),
                Some("tokA"),
                "Tokens -> keep mine"
            );
            assert_eq!(
                e.fields.get("scope").map(|f| f.value.as_str()),
                Some("scope-B")
            );
        }
        _ => panic!(),
    }
}

#[cfg(test)]
mod field_merge_tests {
    use super::*;

    // Loads the SAME three divergent vaults shipped for hardware testing
    // (test_data/sync_test_vaults/ — 12 shared entries, two of every type, plus a
    // B-only new entry and a C-tombstoned entry; see its README), converges them,
    // and asserts the full result: non-colliding edits all survive, every type's
    // colliding edit clashes, the item-delete is flagged, no entry is lost.
    // Read-only + cheap Argon2 params, so it runs in the normal suite.
    #[test]
    fn sync_test_corpus_converges_without_loss() {
        use crate::vault::serialization::VaultBody;
        use std::collections::{BTreeMap, BTreeSet};
        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("test_data/sync_test_vaults");
        let pass = b"0123456789a";
        let load = |n: &str| {
            crate::api::vault::load_vault(pass, &dir.join(format!("sync_test_{n}.gabbro")))
                .unwrap_or_else(|e| panic!("load {n}: {e}"))
        };
        let a = load("A");
        let b = load("B");
        let c = load("C");

        // Converge a given sync order: union + the real field-level merge, collecting
        // the (id, field) collisions surfaced and the pending item-deletes.
        let converge = |order: &[&VaultBody]| {
            let mut acc: BTreeMap<String, VaultEntry> = order[0]
                .entries
                .iter()
                .map(|e| (meta_of(e).id.clone(), e.clone()))
                .collect();
            let mut collisions: BTreeSet<(String, String)> = BTreeSet::new();
            let mut pending: Vec<PendingItemDeleteItem> = Vec::new();
            for body in &order[1..] {
                for e in &body.entries {
                    let id = meta_of(e).id.clone();
                    if let Some(local) = acc.get(&id) {
                        let (m, cs, mut ps, _bo) = merge_entry_pair(local, e);
                        for cc in cs {
                            collisions.insert((cc.id, cc.field));
                        }
                        pending.append(&mut ps);
                        acc.insert(id, m);
                    } else {
                        acc.insert(id, e.clone());
                    }
                }
            }
            (acc, collisions, pending)
        };

        let expected_collisions: BTreeSet<(String, String)> = [
            ("login-co", "password"),
            ("note-co", "content"),
            ("id-co", "last_name"),
            ("card-co", "cvv"),
            ("file-co", "data"),
            ("custom-co", "custom_fields:token"),
        ]
        .iter()
        .map(|(i, f)| (i.to_string(), f.to_string()))
        .collect();

        let pairs = |cfs: &[CustomField]| -> std::collections::HashMap<String, String> {
            cfs.iter()
                .map(|f| (f.label.clone(), f.value.clone()))
                .collect()
        };

        // Several sync orders, like the backward-compat harness — the result must not
        // depend on which direction you sync first.
        for order in [[&a, &b, &c], [&c, &b, &a], [&b, &a, &c], [&c, &a, &b]] {
            let (acc, collisions, pending) = converge(&order);

            assert_eq!(acc.len(), 14, "all entries survive");
            assert!(
                acc.contains_key("delme"),
                "entry on A and B survives the merge"
            );
            assert!(
                acc.contains_key("extra-b"),
                "B-only new entry survives the merge"
            );
            assert_eq!(
                collisions, expected_collisions,
                "the same six collisions must surface regardless of sync order"
            );

            // Non-colliding edits converge to the same values in EVERY order.
            match &acc["login-nc"] {
                VaultEntry::Login(e) => {
                    assert_eq!(e.username, "alice-A");
                    assert_eq!(e.password, "p0-B");
                    assert_eq!(e.url, "https://mail-C.example.com");
                    assert!(
                        pairs(&e.custom_fields).contains_key("OldNote"),
                        "deleted item kept until confirmed"
                    );
                }
                _ => panic!("login-nc not a Login"),
            }
            match &acc["note-nc"] {
                VaultEntry::Note(e) => {
                    assert_eq!(e.title, "Shopping-A");
                    assert_eq!(e.content, "milk-B");
                    assert_eq!(
                        pairs(&e.custom_fields).get("Tag").map(String::as_str),
                        Some("tag-C")
                    );
                }
                _ => panic!(),
            }
            match &acc["id-nc"] {
                VaultEntry::Identity(e) => {
                    assert_eq!(e.phone.as_deref(), Some("+31-A"));
                    assert_eq!(e.email, "alex-B@example.com");
                    assert_eq!(e.address.as_deref(), Some("addr-C"));
                }
                _ => panic!(),
            }
            match &acc["card-nc"] {
                VaultEntry::Card(e) => {
                    assert_eq!(e.cvv, "456");
                    assert_eq!(e.expiry, "06/29");
                    assert_eq!(e.bank_name.as_deref(), Some("ING-C"));
                }
                _ => panic!(),
            }
            match &acc["file-nc"] {
                VaultEntry::File(e) => {
                    assert_eq!(e.filename, "passport-A.txt");
                    assert_eq!(e.notes.as_deref(), Some("notes-B"));
                    assert_eq!(e.data, b"original-C");
                }
                _ => panic!(),
            }
            match &acc["custom-nc"] {
                VaultEntry::Custom(e) => {
                    assert_eq!(e.title, "API creds (C)");
                    assert_eq!(
                        e.fields.get("api_key").map(|f| f.value.as_str()),
                        Some("k0-A")
                    );
                    assert_eq!(
                        e.fields.get("env").map(|f| f.value.as_str()),
                        Some("prod-B")
                    );
                }
                _ => panic!(),
            }

            // The deleted item surfaces as a pending delete in every order.
            assert!(
                pending
                    .iter()
                    .any(|d| d.id == "login-nc" && d.field == "custom_fields:OldNote"),
                "the deleted item must surface as a pending delete"
            );
        }
    }

    // Walk the hardware procedure through the real merge: hold A, sync B (B's
    // extra entry must show as NEW), then sync C (C's tombstone must surface the
    // shared entry as a whole-entry delete). Locks the two review paths the
    // corpus was extended to cover.
    #[test]
    fn corpus_surfaces_new_entry_then_whole_entry_delete() {
        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("test_data/sync_test_vaults");
        let pass = b"0123456789a";
        let load = |n: &str| {
            crate::api::vault::load_vault(pass, &dir.join(format!("sync_test_{n}.gabbro"))).unwrap()
        };
        let a = load("A");

        let mut session = test_session(a.entries);
        let sb = do_merge(&mut session, load("B"));
        assert!(
            sb.added_entries.iter().any(|e| e.id == "extra-b"),
            "B's extra entry shows as a NEW entry"
        );
        assert!(
            sb.pending_deletes.is_empty(),
            "no whole-entry delete on the B sync"
        );

        let sc = do_merge(&mut session, load("C"));
        assert!(
            sc.pending_deletes.iter().any(|d| d.id == "delme"),
            "C's tombstone surfaces the shared entry as a whole-entry delete"
        );
    }

    // Proves "if a sync is interrupted, just run it again": a re-merge of the
    // same source neither duplicates already-applied changes nor loses data, and
    // an unresolved clash re-surfaces unchanged. This is the convergence the
    // post-sync message relies on.
    #[test]
    fn re_syncing_the_same_source_converges_without_loss() {
        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("test_data/sync_test_vaults");
        let pass = b"0123456789a";
        let load = |n: &str| {
            crate::api::vault::load_vault(pass, &dir.join(format!("sync_test_{n}.gabbro"))).unwrap()
        };
        let mut session = test_session(load("A").entries);

        // First sync of B brings values over; a second sync of B is a no-op.
        let first = do_merge(&mut session, load("B"));
        assert!(!first.brought_over.is_empty(), "B has values to bring over");
        let again = do_merge(&mut session, load("B"));
        assert_eq!(again.added, 0, "re-sync adds nothing");
        assert!(
            again.brought_over.is_empty(),
            "re-sync repeats no brought-over"
        );
        assert!(
            again.field_conflicts.is_empty(),
            "re-sync invents no clashes"
        );

        // C clashes on six fields. Leaving them unresolved (an interrupted
        // review), a re-sync of C re-surfaces the same clashes and still repeats
        // nothing already applied.
        let c1 = do_merge(&mut session, load("C"));
        assert_eq!(c1.field_conflicts.len(), 6, "C surfaces its six clashes");
        let c2 = do_merge(&mut session, load("C"));
        assert_eq!(
            c2.field_conflicts.len(),
            6,
            "unresolved clashes re-surface on a re-sync"
        );
        assert!(
            c2.brought_over.is_empty(),
            "already-applied values are not repeated"
        );
        assert_eq!(c2.added, 0);
    }

    // A File-content clash must carry the incoming bytes (base64) so the user's
    // "use other" can actually restore them — not the "<binary>" placeholder,
    // which made the choice a silent no-op (found 2026-06-30).
    #[test]
    fn file_data_clash_carries_incoming_bytes_as_base64() {
        use crate::vault::entry::FileEntry;
        use base64::Engine;
        let local = VaultEntry::File(FileEntry {
            meta: meta("f", "t", &[("data", 100)]),
            filename: String::from("k.txt"),
            data: b"localbytes".to_vec(),
            notes: None,
            custom_fields: vec![],
        });
        let incoming = VaultEntry::File(FileEntry {
            meta: meta("f", "t", &[("data", 200)]),
            filename: String::from("k.txt"),
            data: b"incomingbytes".to_vec(),
            notes: None,
            custom_fields: vec![],
        });
        let (_merged, conflicts, _pending, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(
            conflicts.len(),
            1,
            "differing data on both sides is a clash"
        );
        let c = &conflicts[0];
        assert_eq!(c.field, "data");
        let decode = |s: &str| base64::engine::general_purpose::STANDARD.decode(s).unwrap();
        assert_eq!(
            decode(&c.incoming_value),
            b"incomingbytes",
            "use other restores incoming"
        );
        assert_eq!(decode(&c.local_value), b"localbytes");
    }

    // Checks a JSON vault exported after the exact hardware walk in
    // test_data/sync_test_vaults/README.md (import A, sync B keeping all, sync C
    // with the dictated picks). Run after exporting:
    //   GABBRO_WALK_JSON=/path/to/sync_walk.json \
    //     cargo test --release --lib check_sync_walk_export -- --ignored
    #[test]
    #[ignore = "validates a hardware-walk export; set GABBRO_WALK_JSON to the .json path"]
    fn check_sync_walk_export() {
        let path = std::env::var("GABBRO_WALK_JSON")
            .expect("set GABBRO_WALK_JSON to the exported sync_walk.json path");
        let data = std::fs::read_to_string(&path).expect("read export json");

        #[derive(serde::Deserialize)]
        struct Export {
            entries: Vec<VaultEntry>,
        }
        let export: Export = serde_json::from_str(&data).expect("parse export json");
        assert_walk_end_state(&export.entries);
    }

    // ── Sync-test corpus generator ────────────────────────────────────────
    // Mints the three divergent vaults in test_data/sync_test_vaults/ that the
    // converge test above and the hardware walk both use. Run on demand:
    //   cargo test --release regenerate_sync_test_corpus -- --ignored
    // Presence in `field_times` marks the side that edited a field (see
    // decide_field): both present + differ = clash; one present = brought over;
    // a "del:<key>" time = a deletion. A oldest, then B, then C.
    const TA: u64 = 1000;
    const TB: u64 = 2000;
    const TC: u64 = 3000;
    const BT: &str = "2025-01-01T00:00:00Z";

    fn cf(label: &str, value: &str) -> CustomField {
        CustomField {
            label: label.into(),
            value: value.into(),
            hidden: false,
        }
    }
    fn login(
        id: &str,
        title: &str,
        url: &str,
        user: &str,
        pass: &str,
        customs: Vec<CustomField>,
    ) -> VaultEntry {
        VaultEntry::Login(LoginEntry {
            meta: meta(id, BT, &[]),
            title: title.into(),
            url: url.into(),
            username: user.into(),
            password: pass.into(),
            notes: None,
            custom_fields: customs,
            attachments: vec![],
            app_id: None,
            email: None,
        })
    }
    fn ident(
        id: &str,
        first: &str,
        last: &str,
        email: &str,
        phone: &str,
        address: &str,
    ) -> VaultEntry {
        VaultEntry::Identity(IdentityEntry {
            meta: meta(id, BT, &[]),
            first_name: first.into(),
            last_name: last.into(),
            email: email.into(),
            phone: Some(phone.into()),
            address: Some(address.into()),
            custom_fields: vec![],
            attachments: vec![],
        })
    }
    fn card(
        id: &str,
        name: &str,
        holder: &str,
        number: &str,
        expiry: &str,
        cvv: &str,
        bank: &str,
    ) -> VaultEntry {
        VaultEntry::Card(CardEntry {
            meta: meta(id, BT, &[]),
            card_name: Some(name.into()),
            status: "active".into(),
            cardholder_name: holder.into(),
            card_number: number.into(),
            expiry: expiry.into(),
            cvv: cvv.into(),
            credit_limit: None,
            card_account_number: None,
            payment_network: None,
            pin: None,
            bank_name: Some(bank.into()),
            transaction_password: None,
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
        })
    }
    fn file(id: &str, filename: &str, data: &[u8], notes: &str) -> VaultEntry {
        VaultEntry::File(FileEntry {
            meta: meta(id, BT, &[]),
            filename: filename.into(),
            data: data.to_vec(),
            notes: Some(notes.into()),
            custom_fields: vec![],
        })
    }
    fn custom(id: &str, title: &str, fields: &[(&str, &str)]) -> VaultEntry {
        let mut m = indexmap::IndexMap::new();
        for (k, v) in fields {
            m.insert((*k).to_string(), cf(k, v));
        }
        VaultEntry::Custom(CustomEntry {
            meta: meta(id, BT, &[]),
            title: title.into(),
            fields: m,
            attachments: vec![],
        })
    }

    fn lg(e: &mut VaultEntry) -> &mut LoginEntry {
        match e {
            VaultEntry::Login(x) => x,
            _ => panic!("not a login"),
        }
    }
    fn nt(e: &mut VaultEntry) -> &mut NoteEntry {
        match e {
            VaultEntry::Note(x) => x,
            _ => panic!("not a note"),
        }
    }
    fn idn(e: &mut VaultEntry) -> &mut IdentityEntry {
        match e {
            VaultEntry::Identity(x) => x,
            _ => panic!("not an identity"),
        }
    }
    fn cd(e: &mut VaultEntry) -> &mut CardEntry {
        match e {
            VaultEntry::Card(x) => x,
            _ => panic!("not a card"),
        }
    }
    fn fl(e: &mut VaultEntry) -> &mut FileEntry {
        match e {
            VaultEntry::File(x) => x,
            _ => panic!("not a file"),
        }
    }
    fn cu(e: &mut VaultEntry) -> &mut CustomEntry {
        match e {
            VaultEntry::Custom(x) => x,
            _ => panic!("not a custom"),
        }
    }
    fn stamp(e: &mut VaultEntry, key: &str, t: u64) {
        meta_of_mut(e).field_times.insert(key.into(), t);
    }
    fn edit(v: &mut [VaultEntry], id: &str, f: impl FnOnce(&mut VaultEntry)) {
        f(v.iter_mut()
            .find(|e| meta_of(e).id == id)
            .expect("entry id present"));
    }

    // The 12 shared base entries (two of every type), identical on all devices.
    fn base() -> Vec<VaultEntry> {
        vec![
            login(
                "login-nc",
                "Email",
                "https://mail.example.com",
                "alice",
                "p0",
                vec![cf("OldNote", "keep")],
            ),
            login(
                "login-co",
                "Bank",
                "https://bank.example.com",
                "bob",
                "q0",
                vec![],
            ),
            note("note-nc", "Shopping", "milk", BT, &[]),
            note("note-co", "Ideas", "idea0", BT, &[]),
            ident("id-nc", "Alex", "Stone", "alex@example.com", "+31", "addr"),
            ident("id-co", "Sam", "Stone", "sam@example.com", "+1", "road"),
            card(
                "card-nc",
                "Visa",
                "Alex Stone",
                "4111",
                "01/28",
                "123",
                "Bank1",
            ),
            card(
                "card-co",
                "Amex",
                "Sam Stone",
                "3711",
                "02/28",
                "999",
                "Bank2",
            ),
            file("file-nc", "passport.txt", b"original", "n0"),
            file("file-co", "key.txt", b"base", "n1"),
            custom(
                "custom-nc",
                "API creds",
                &[("api_key", "k0"), ("secret", "s0")],
            ),
            custom("custom-co", "Tokens", &[("token", "t0")]),
        ]
    }

    #[test]
    #[ignore = "writes the committed corpus; run explicitly to regenerate"]
    fn regenerate_sync_test_corpus() {
        // Device A (oldest): one non-colliding field per type, plus the A side of
        // each colliding field.
        let mut a = base();
        edit(&mut a, "login-nc", |e| {
            lg(e).username = "alice-A".into();
            stamp(e, "username", TA);
        });
        edit(&mut a, "login-co", |e| {
            lg(e).password = "qA".into();
            stamp(e, "password", TA);
        });
        edit(&mut a, "note-nc", |e| {
            nt(e).title = "Shopping-A".into();
            stamp(e, "title", TA);
        });
        edit(&mut a, "note-co", |e| {
            nt(e).content = "ideaA".into();
            stamp(e, "content", TA);
        });
        edit(&mut a, "id-nc", |e| {
            idn(e).phone = Some("+31-A".into());
            stamp(e, "phone", TA);
        });
        edit(&mut a, "id-co", |e| {
            idn(e).last_name = "StoneA".into();
            stamp(e, "last_name", TA);
        });
        edit(&mut a, "card-nc", |e| {
            cd(e).cvv = "456".into();
            stamp(e, "cvv", TA);
        });
        edit(&mut a, "card-co", |e| {
            cd(e).cvv = "555A".into();
            stamp(e, "cvv", TA);
        });
        edit(&mut a, "file-nc", |e| {
            fl(e).filename = "passport-A.txt".into();
            stamp(e, "filename", TA);
        });
        edit(&mut a, "file-co", |e| {
            fl(e).data = b"dataA".to_vec();
            stamp(e, "data", TA);
        });
        edit(&mut a, "custom-nc", |e| {
            cu(e).fields.get_mut("api_key").unwrap().value = "k0-A".into();
            stamp(e, "custom_fields:api_key", TA);
        });
        edit(&mut a, "custom-co", |e| {
            cu(e).fields.get_mut("token").unwrap().value = "tokA".into();
            stamp(e, "custom_fields:token", TA);
        });
        a.push(note("delme", "Delete me", "gone", BT, &[]));

        // Device B: a different non-colliding field per type, no colliding edits.
        let mut b = base();
        edit(&mut b, "login-nc", |e| {
            lg(e).password = "p0-B".into();
            stamp(e, "password", TB);
        });
        edit(&mut b, "login-co", |e| {
            lg(e).username = "bob-B".into();
            stamp(e, "username", TB);
        });
        edit(&mut b, "note-nc", |e| {
            nt(e).content = "milk-B".into();
            stamp(e, "content", TB);
        });
        edit(&mut b, "note-co", |e| {
            nt(e).title = "Ideas-B".into();
            stamp(e, "title", TB);
        });
        edit(&mut b, "id-nc", |e| {
            idn(e).email = "alex-B@example.com".into();
            stamp(e, "email", TB);
        });
        edit(&mut b, "id-co", |e| {
            idn(e).first_name = "Sam-B".into();
            stamp(e, "first_name", TB);
        });
        edit(&mut b, "card-nc", |e| {
            cd(e).expiry = "06/29".into();
            stamp(e, "expiry", TB);
        });
        edit(&mut b, "card-co", |e| {
            cd(e).expiry = "07/29".into();
            stamp(e, "expiry", TB);
        });
        edit(&mut b, "file-nc", |e| {
            fl(e).notes = Some("notes-B".into());
            stamp(e, "notes", TB);
        });
        edit(&mut b, "file-co", |e| {
            fl(e).filename = "key-B.txt".into();
            stamp(e, "filename", TB);
        });
        edit(&mut b, "custom-nc", |e| {
            cu(e).fields.insert("env".into(), cf("env", "prod-B"));
            stamp(e, "custom_fields:env", TB);
        });
        edit(&mut b, "custom-co", |e| {
            cu(e).fields.insert("scope".into(), cf("scope", "scope-B"));
            stamp(e, "custom_fields:scope", TB);
        });
        b.push(note("delme", "Delete me", "gone", BT, &[]));
        b.push(login(
            "extra-b",
            "New on B",
            "https://new.example.com",
            "carol",
            "z9",
            vec![],
        )); // entry only on B -> NEW on sync

        // Device C: the last non-colliding field per type, the C side of each
        // colliding field, and the OldNote item deletion.
        let mut c = base();
        edit(&mut c, "login-nc", |e| {
            lg(e).url = "https://mail-C.example.com".into();
            lg(e).custom_fields.retain(|f| f.label != "OldNote");
            stamp(e, "url", TC);
            stamp(e, "del:custom_fields:OldNote", TC);
        });
        edit(&mut c, "login-co", |e| {
            lg(e).password = "qC".into();
            stamp(e, "password", TC);
        });
        edit(&mut c, "note-nc", |e| {
            nt(e).custom_fields.push(cf("Tag", "tag-C"));
            stamp(e, "custom_fields:Tag", TC);
        });
        edit(&mut c, "note-co", |e| {
            nt(e).content = "ideaC".into();
            stamp(e, "content", TC);
        });
        edit(&mut c, "id-nc", |e| {
            idn(e).address = Some("addr-C".into());
            stamp(e, "address", TC);
        });
        edit(&mut c, "id-co", |e| {
            idn(e).last_name = "StoneC".into();
            stamp(e, "last_name", TC);
        });
        edit(&mut c, "card-nc", |e| {
            cd(e).bank_name = Some("ING-C".into());
            stamp(e, "bank_name", TC);
        });
        edit(&mut c, "card-co", |e| {
            cd(e).cvv = "555C".into();
            stamp(e, "cvv", TC);
        });
        edit(&mut c, "file-nc", |e| {
            fl(e).data = b"original-C".to_vec();
            stamp(e, "data", TC);
        });
        edit(&mut c, "file-co", |e| {
            fl(e).data = b"dataC".to_vec();
            stamp(e, "data", TC);
        });
        edit(&mut c, "custom-nc", |e| {
            cu(e).title = "API creds (C)".into();
            stamp(e, "title", TC);
        });
        edit(&mut c, "custom-co", |e| {
            cu(e).fields.get_mut("token").unwrap().value = "tokC".into();
            stamp(e, "custom_fields:token", TC);
        });

        let body = |entries: Vec<VaultEntry>, deleted: Vec<DeletedEntry>| {
            crate::vault::serialization::VaultBody {
                entries,
                deleted_ids: deleted,
                vault_updated_at: BT.into(),
                ..Default::default()
            }
        };
        let bodies = [
            ("A", body(a, vec![])),
            ("B", body(b, vec![])),
            (
                "C",
                body(
                    c,
                    vec![DeletedEntry {
                        id: "delme".into(),
                        deleted_at: "2025-06-01T00:00:00Z".into(),
                    }],
                ),
            ),
        ];

        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("test_data/sync_test_vaults");
        for (name, b) in &bodies {
            let params = crate::crypto::kdf::Argon2idParams {
                m_cost: 64,
                t_cost: 1,
                p_cost: 1,
            };
            let pt = crate::vault::serialization::serialize_vault_body(b).expect("serialize");
            let sealed = crate::crypto::vault_crypto::seal_vault_with_params(
                b"0123456789a",
                &pt,
                Some("synctest".into()),
                params,
            )
            .expect("seal");
            crate::vault::io::write_vault(&sealed, &dir.join(format!("sync_test_{name}.gabbro")))
                .expect("write");
            // write_vault rotates a .bak alongside the vault — correct for a real
            // vault, just an untracked stray for the committed corpus. Drop it.
            // Absent on a first-ever mint, so a missing file is not an error.
            let bak = dir.join(format!("sync_test_{name}.gabbro.bak"));
            if bak.exists() {
                std::fs::remove_file(&bak).expect("remove stray .bak");
            }
        }
    }

    fn meta(id: &str, updated_at: &str, times: &[(&str, u64)]) -> EntryMeta {
        let mut ft = std::collections::BTreeMap::new();
        for (k, v) in times {
            ft.insert((*k).to_string(), *v);
        }
        EntryMeta {
            id: id.to_string(),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: updated_at.to_string(),
            folder: String::new(),
            field_times: ft,
            history: Vec::new(),
        }
    }

    fn note(
        id: &str,
        title: &str,
        content: &str,
        updated: &str,
        times: &[(&str, u64)],
    ) -> VaultEntry {
        VaultEntry::Note(NoteEntry {
            meta: meta(id, updated, times),
            title: title.to_string(),
            content: content.to_string(),
            custom_fields: vec![],
            attachments: vec![],
        })
    }

    fn note_content(e: &VaultEntry) -> &str {
        match e {
            VaultEntry::Note(n) => &n.content,
            _ => panic!("not a note"),
        }
    }
    fn note_title(e: &VaultEntry) -> &str {
        match e {
            VaultEntry::Note(n) => &n.title,
            _ => panic!("not a note"),
        }
    }

    #[test]
    fn merge_two_devices_edit_different_fields_keeps_both() {
        // local edited title, incoming edited content — the headline fix.
        let local = note("n1", "T-local", "C", "t", &[("title", 200)]);
        let incoming = note("n1", "T", "C-remote", "t", &[("content", 300)]);
        let (merged, conflicts, _dels, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(note_title(&merged), "T-local");
        assert_eq!(note_content(&merged), "C-remote");
        assert!(conflicts.is_empty());
    }

    #[test]
    fn merge_same_field_edited_on_both_is_conflict_regardless_of_timestamp() {
        // Realistic collision: both devices edited the same field, at DIFFERENT
        // times. The newer one is NOT auto-picked; it is surfaced for the user.
        let local = note("n1", "T", "A", "t", &[("content", 100)]);
        let incoming = note("n1", "T", "B", "t", &[("content", 999)]);
        let (merged, conflicts, _, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(
            note_content(&merged),
            "A",
            "keeps local pending the user's pick"
        );
        assert!(
            conflicts.iter().any(|f| f.field == "content"),
            "both edited the same field -> conflict, never an auto-pick by clock"
        );
    }

    #[test]
    fn merge_field_edited_on_one_side_only_comes_over() {
        // Only incoming edited content (to empty); local never touched it. The edit
        // comes over additively, no prompt. Empty does not lose.
        let local = note("n1", "T", "text", "t", &[]);
        let incoming = note("n1", "T", "", "t", &[("content", 200)]);
        let (merged, conflicts, _, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(note_content(&merged), "");
        assert!(
            conflicts.is_empty(),
            "one-sided edit is additive, no conflict"
        );
    }

    #[test]
    fn merge_field_edited_only_on_local_is_kept() {
        let local = note("n1", "T", "A", "t", &[("content", 100)]);
        let incoming = note("n1", "T", "base", "t", &[]);
        let (merged, conflicts, _, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(note_content(&merged), "A");
        assert!(conflicts.is_empty(), "local-only edit kept, no conflict");
    }

    #[test]
    fn merge_equal_field_ts_different_value_is_clash_keeps_local() {
        let local = note("n1", "T", "A", "t", &[("content", 100)]);
        let incoming = note("n1", "T", "B", "t", &[("content", 100)]);
        let (merged, conflicts, _dels, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(note_content(&merged), "A", "clash keeps local");
        assert_eq!(conflicts.len(), 1);
        assert_eq!(conflicts[0].field, "content");
        assert_eq!(conflicts[0].local_value, "A");
        assert_eq!(conflicts[0].incoming_value, "B");
    }

    #[test]
    fn merge_both_without_field_times_falls_back_to_updated_at() {
        // Pre-v9 vaults: no per-field times -> whole-entry updated_at decides.
        let local = note("n1", "T", "A", "2025-01-01T00:00:01Z", &[]);
        let incoming = note("n1", "T", "B", "2025-01-01T00:00:02Z", &[]);
        let (merged, conflicts, _dels, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(note_content(&merged), "B", "newer whole entry wins");
        assert!(conflicts.is_empty());
    }

    #[test]
    fn merge_mixed_field_times_incoming_prev9_has_no_mark_local_wins() {
        // Cross-version sync: local (v9) edited a field so it carries a field-time
        // mark; the incoming entry comes from a pre-v9 vault so it has NO field
        // times at all, even though its whole-entry updated_at is newer. An absent
        // mark counts as "oldest", so the marked (local) value wins and no clash is
        // raised - the incoming value cannot be proven to be a real edit.
        let local = note(
            "n1",
            "T",
            "local-val",
            "2025-01-01T00:00:01Z",
            &[("content", 200)],
        );
        let incoming = note("n1", "T", "incoming-val", "2025-01-01T00:00:09Z", &[]);
        let (merged, conflicts, _dels, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(
            note_content(&merged),
            "local-val",
            "marked side wins; unmarked pre-v9 field counts as oldest"
        );
        assert!(
            conflicts.is_empty(),
            "no clash - incoming has no proven edit"
        );
    }

    #[test]
    fn self_sync_identical_vault_reports_nothing_to_sync() {
        // Syncing a vault into an identical copy of itself (same entries, same
        // field marks) must surface no changes at all -> the UI shows "nothing to
        // sync" and never a spurious clash.
        use crate::vault::serialization::VaultBody;
        let entry = note("n1", "T", "C", "t", &[("content", 100)]);
        let mut session = test_session(vec![entry.clone()]);
        let incoming = VaultBody {
            entries: vec![entry],
            folders: vec![],
            ..Default::default()
        };
        let s = do_merge(&mut session, incoming);
        assert_eq!(s.added, 0);
        assert_eq!(s.updated, 0);
        assert!(s.field_conflicts.is_empty());
        assert!(s.brought_over.is_empty());
        assert!(s.pending_deletes.is_empty());
        assert!(s.pending_item_deletes.is_empty());
        assert!(s.folder_conflicts.is_empty());
        assert!(s.added_entries.is_empty());
    }

    #[test]
    fn merge_cleared_field_clashes_and_is_not_lost() {
        // Local cleared the field (empty, marked); incoming kept a value (marked).
        // Empty is a value like any other: both edited -> a real clash, surfaced;
        // the local (cleared) value is kept pending the user's choice, not dropped.
        let local = note("n1", "T", "", "t", &[("content", 300)]);
        let incoming = note("n1", "T", "keep", "t", &[("content", 200)]);
        let (merged, conflicts, _dels, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(conflicts.len(), 1, "cleared-vs-value is a real clash");
        assert_eq!(conflicts[0].field, "content");
        assert_eq!(
            note_content(&merged),
            "",
            "local cleared value kept pending"
        );
    }

    #[test]
    fn merge_incoming_cleared_field_is_brought_over_recoverable() {
        // Incoming cleared the field (empty, marked); local never touched it. The
        // clear wins additively and is surfaced as a brought-over change whose old
        // value stays recoverable if the user drops it.
        let local = note("n1", "T", "keep", "t", &[]);
        let incoming = note("n1", "T", "", "t", &[("content", 200)]);
        let (merged, _c, _dels, brought) = merge_entry_pair(&local, &incoming);
        assert_eq!(
            note_content(&merged),
            "",
            "incoming clear wins (newer, marked)"
        );
        assert_eq!(brought.len(), 1);
        assert_eq!(brought[0].field, "content");
        assert_eq!(brought[0].old_value, "keep", "pre-clear value recoverable");
        assert_eq!(brought[0].new_value, "");
    }

    #[test]
    fn merge_both_without_field_times_equal_updated_at_different_value_is_clash() {
        let local = note("n1", "T", "A", "2025-01-01T00:00:01Z", &[]);
        let incoming = note("n1", "T", "B", "2025-01-01T00:00:01Z", &[]);
        let (merged, conflicts, _dels, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(note_content(&merged), "A");
        assert_eq!(conflicts.len(), 1, "equal-time divergence must surface");
    }

    #[test]
    fn merge_is_commutative_for_independent_field_edits() {
        let a = note("n1", "T-a", "C", "t", &[("title", 200)]);
        let b = note("n1", "T", "C-b", "t", &[("content", 300)]);
        let (ab, _, _, _) = merge_entry_pair(&a, &b);
        let (ba, _, _, _) = merge_entry_pair(&b, &a);
        assert_eq!(ab, ba, "merge order must not change the result");
    }

    // ── brought-over: non-conflicting incoming values surfaced for review ─────

    #[test]
    fn merge_lists_brought_over_field_with_old_and_new() {
        // Incoming edited content; local never touched it -> the new value comes
        // over additively and is listed so the user can drop it (restore old).
        let local = note("n1", "T", "old", "t", &[]);
        let incoming = note("n1", "T", "new", "t", &[("content", 200)]);
        let (_m, conflicts, _d, brought) = merge_entry_pair(&local, &incoming);
        assert!(conflicts.is_empty());
        assert_eq!(brought.len(), 1);
        assert_eq!(brought[0].field, "content");
        assert_eq!(brought[0].old_value, "old");
        assert_eq!(brought[0].new_value, "new");
    }

    #[test]
    fn merge_conflict_is_not_listed_as_brought_over() {
        // A clash is a user pick, not a silent bring-over.
        let local = note("n1", "T", "A", "t", &[("content", 100)]);
        let incoming = note("n1", "T", "B", "t", &[("content", 999)]);
        let (_m, conflicts, _d, brought) = merge_entry_pair(&local, &incoming);
        assert_eq!(conflicts.len(), 1);
        assert!(brought.is_empty());
    }

    #[test]
    fn merge_local_only_edit_is_not_brought_over() {
        let local = note("n1", "T", "A", "t", &[("content", 100)]);
        let incoming = note("n1", "T", "base", "t", &[]);
        let (_m, _c, _d, brought) = merge_entry_pair(&local, &incoming);
        assert!(
            brought.is_empty(),
            "local kept its own value -> nothing came over"
        );
    }

    #[test]
    fn merge_lists_brought_over_custom_pair_add() {
        use crate::vault::entry::CustomField;
        let cf = CustomField {
            label: String::from("Tag"),
            value: String::from("blue"),
            hidden: false,
        };
        // Incoming added a pair local never had -> brought over (old empty).
        let local = note_cf("n1", vec![], &[]);
        let incoming = note_cf("n1", vec![cf], &[("custom_fields:Tag", 200)]);
        let (_m, _c, dels, brought) = merge_entry_pair(&local, &incoming);
        assert!(dels.is_empty());
        assert_eq!(brought.len(), 1);
        assert_eq!(brought[0].field, "custom_fields:Tag");
        assert_eq!(brought[0].old_value, "");
        assert_eq!(brought[0].new_value, "blue");
    }

    #[test]
    fn merge_lists_brought_over_attachment_by_name_not_bytes() {
        use crate::vault::entry::EntryAttachment;
        let att = EntryAttachment {
            uuid: String::from("att-1"),
            name: String::from("passport.pdf"),
            kind: String::from("application/pdf"),
            data: vec![1, 2, 3],
        };
        let local = VaultEntry::Note(NoteEntry {
            meta: meta("n1", "t", &[]),
            title: String::from("T"),
            content: String::from("C"),
            custom_fields: vec![],
            attachments: vec![],
        });
        let incoming = VaultEntry::Note(NoteEntry {
            meta: meta("n1", "t", &[("attachments:att-1", 200)]),
            title: String::from("T"),
            content: String::from("C"),
            custom_fields: vec![],
            attachments: vec![att],
        });
        let (_m, _c, dels, brought) = merge_entry_pair(&local, &incoming);
        assert!(dels.is_empty());
        assert_eq!(brought.len(), 1);
        assert_eq!(brought[0].field, "attachments:att-1");
        assert_eq!(
            brought[0].new_value, "passport.pdf",
            "name, never raw bytes"
        );
    }

    #[test]
    fn merge_reentry_over_local_delete_is_pending_not_brought_over() {
        use crate::vault::entry::CustomField;
        let cf = CustomField {
            label: String::from("PIN"),
            value: String::from("1"),
            hidden: false,
        };
        // Incoming still has PIN; local deleted it more recently -> keep/delete
        // prompt, NOT a silent bring-over.
        let local = note_cf("n1", vec![], &[("del:custom_fields:PIN", 300)]);
        let incoming = note_cf("n1", vec![cf], &[("custom_fields:PIN", 200)]);
        let (_m, _c, dels, brought) = merge_entry_pair(&local, &incoming);
        assert_eq!(dels.len(), 1);
        assert!(brought.is_empty());
    }

    fn test_session(entries: Vec<VaultEntry>) -> VaultSession {
        VaultSession {
            folders: vec![],
            entries,
            path: std::path::PathBuf::new(),
            passphrase: Zeroizing::new(b"x".to_vec()),
            yubikey: None,
            yubikey_aliases: std::collections::HashMap::new(),
            deleted_ids: vec![],
            pre_sync_backup: None,
        }
    }

    #[test]
    fn do_merge_lists_added_entries_for_review() {
        let mut session = test_session(vec![note("local-1", "Local", "C", "t", &[])]);
        let incoming = crate::vault::serialization::VaultBody {
            entries: vec![
                note("local-1", "Local", "C", "t", &[]),
                note("remote-1", "Remote", "C", "t", &[]),
            ],
            folders: vec![],
            ..Default::default()
        };
        let summary = do_merge(&mut session, incoming);
        assert_eq!(summary.added, 1);
        assert_eq!(summary.added_entries.len(), 1);
        assert_eq!(summary.added_entries[0].id, "remote-1");
        assert_eq!(summary.added_entries[0].title, "Remote");
    }

    #[test]
    fn do_merge_aggregates_brought_over_across_entries() {
        let mut session = test_session(vec![note("n1", "T", "old", "t", &[])]);
        let incoming = crate::vault::serialization::VaultBody {
            entries: vec![note("n1", "T", "new", "t", &[("content", 200)])],
            folders: vec![],
            ..Default::default()
        };
        let summary = do_merge(&mut session, incoming);
        assert_eq!(summary.brought_over.len(), 1);
        assert_eq!(summary.brought_over[0].id, "n1");
        assert_eq!(summary.brought_over[0].field, "content");
        assert_eq!(summary.brought_over[0].new_value, "new");
    }

    // Interruption/restart safety: if a sync is interrupted before the user's
    // picks are applied, restarting must re-surface the SAME decisions and lose
    // nothing. Modelled as do_merge run twice with the same incoming and no picks
    // applied between - the unresolved surface (clashes, pending deletes) must be
    // identical and every entry preserved. Pins the "just sync again" guarantee.
    #[test]
    fn re_merge_after_unapplied_sync_resurfaces_same_decisions() {
        use crate::vault::serialization::VaultBody;
        let mut session = test_session(vec![
            note("clash", "T", "local", "t", &[("content", TA)]),
            note("victim", "Doomed", "keep", "t", &[]),
        ]);
        let incoming = || VaultBody {
            entries: vec![note("clash", "T", "incoming", "t", &[("content", TC)])],
            folders: vec![],
            deleted_ids: vec![DeletedEntry {
                id: "victim".into(),
                deleted_at: "2025-02-01T00:00:00Z".into(),
            }],
            ..Default::default()
        };

        let s1 = do_merge(&mut session, incoming());
        // Interrupted here: the user never resolved the clash or confirmed the delete.
        let s2 = do_merge(&mut session, incoming());

        let clash = |s: &MergeSummary| -> Vec<(String, String)> {
            s.field_conflicts
                .iter()
                .map(|c| (c.id.clone(), c.field.clone()))
                .collect()
        };
        let del = |s: &MergeSummary| -> Vec<String> {
            s.pending_deletes.iter().map(|d| d.id.clone()).collect()
        };
        assert_eq!(clash(&s1), vec![("clash".into(), "content".into())]);
        assert_eq!(clash(&s2), clash(&s1), "restart re-surfaces the same clash");
        assert_eq!(del(&s1), vec![String::from("victim")]);
        assert_eq!(
            del(&s2),
            del(&s1),
            "restart re-surfaces the same pending delete"
        );

        // Nothing lost: both entries still present, and the unresolved clash kept
        // the local value (never silently overwritten while pending).
        let ids: Vec<&str> = session.entries.iter().map(entry_id).collect();
        assert!(
            ids.contains(&"clash") && ids.contains(&"victim"),
            "no entry lost across the re-merge"
        );
        match session
            .entries
            .iter()
            .find(|e| entry_id(e) == "clash")
            .unwrap()
        {
            VaultEntry::Note(n) => {
                assert_eq!(n.content, "local", "unresolved clash keeps the local value")
            }
            _ => panic!("clash entry is a note"),
        }
    }

    // Batched granular apply (in-memory part): one call applies every review
    // decision - keep-mine, kept clash with history, item delete, folder assign,
    // whole-entry delete - so the whole review re-seals the vault once instead of
    // once per decision. Mirrors the per-decision session_* mutations exactly.
    #[test]
    fn do_apply_sync_decisions_applies_every_decision_kind() {
        use crate::api::vault::{
            SyncFieldResolutionInput, SyncFolderInput, SyncHistoryReplacementInput,
            SyncItemDeleteInput,
        };
        let mut session = test_session(vec![
            login("keepmine", "T", "u", "url", "mine", vec![]),
            note("hist", "T", "loser", "t", &[]),
            custom("itemdel", "T", &[("old_key", "v")]),
            note("foldered", "T", "c", "t", &[]),
            note("gone", "T", "c", "t", &[]),
        ]);
        session.folders = vec![String::from("Work")];

        do_apply_sync_decisions(
            &mut session,
            &[SyncFieldResolutionInput {
                id: "keepmine".into(),
                field: "password".into(),
                keep_incoming: false,
                value: "theirs".into(), // ignored: keep-mine
            }],
            &[SyncHistoryReplacementInput {
                id: "hist".into(),
                field: "content".into(),
                new_value: "winner".into(),
                replaced_value: "loser".into(),
            }],
            &[SyncItemDeleteInput {
                id: "itemdel".into(),
                field: "custom_fields:old_key".into(),
                delete: true,
            }],
            &[SyncFolderInput {
                id: "foldered".into(),
                folder: "Work".into(),
            }],
            &["gone".into()],
        )
        .unwrap();

        let get = |id: &str| session.entries.iter().find(|e| entry_id(e) == id);

        // keep-mine: value unchanged, but field marked edited so it stops clashing.
        match get("keepmine").unwrap() {
            VaultEntry::Login(l) => {
                assert_eq!(l.password, "mine", "keep-mine leaves the local value");
                assert!(l.meta.field_times.contains_key("password"));
            }
            _ => panic!(),
        }
        // history replacement: new value set, replaced value kept in history.
        match get("hist").unwrap() {
            VaultEntry::Note(n) => {
                assert_eq!(n.content, "winner");
                assert!(
                    n.meta.history.iter().any(|h| h.value == "loser"),
                    "replaced value kept in history"
                );
            }
            _ => panic!(),
        }
        // item delete: the custom pair is gone, a del: mark stamped.
        match get("itemdel").unwrap() {
            VaultEntry::Custom(c) => {
                assert!(!c.fields.contains_key("old_key"), "item removed");
                assert!(c.meta.field_times.contains_key("del:custom_fields:old_key"));
            }
            _ => panic!(),
        }
        // folder assign.
        assert_eq!(meta_of(get("foldered").unwrap()).folder, "Work");
        // whole-entry delete: entry gone, tombstone recorded so future syncs see it.
        assert!(get("gone").is_none(), "entry deleted");
        assert!(
            session.deleted_ids.iter().any(|d| d.id == "gone"),
            "tombstone recorded for the deleted entry"
        );
    }

    #[test]
    fn do_apply_sync_decisions_rejects_unknown_folder() {
        use crate::api::vault::SyncFolderInput;
        let mut session = test_session(vec![note("n1", "T", "c", "t", &[])]);
        let err = do_apply_sync_decisions(
            &mut session,
            &[],
            &[],
            &[],
            &[SyncFolderInput {
                id: "n1".into(),
                folder: "Nope".into(),
            }],
            &[],
        )
        .unwrap_err();
        assert!(err.contains("Folder not found"), "got: {err}");
    }

    #[test]
    fn merge_unions_entry_history_from_both_sides() {
        use crate::vault::entry::HistoryRecord;
        let rec = |v: &str, at: &str| HistoryRecord {
            field: String::from("content"),
            value: v.to_string(),
            saved_at: at.to_string(),
            expires_at: None,
        };
        let mut local = note("n1", "T", "C", "t", &[]);
        let mut incoming = note("n1", "T", "C", "t", &[]);
        if let VaultEntry::Note(n) = &mut local {
            n.meta.history.push(rec("local-old", "1"));
        }
        if let VaultEntry::Note(n) = &mut incoming {
            n.meta.history.push(rec("incoming-old", "2"));
        }
        let (merged, _, _, _) = merge_entry_pair(&local, &incoming);
        let hist = match &merged {
            VaultEntry::Note(n) => n.meta.history.clone(),
            _ => panic!(),
        };
        let vals: Vec<&str> = hist.iter().map(|r| r.value.as_str()).collect();
        assert_eq!(hist.len(), 2, "both sides' recovery history survives");
        assert!(vals.contains(&"local-old"));
        assert!(vals.contains(&"incoming-old"));
    }

    #[test]
    fn merge_dedups_identical_history_records() {
        use crate::vault::entry::HistoryRecord;
        let rec = HistoryRecord {
            field: String::from("content"),
            value: String::from("same"),
            saved_at: String::from("1"),
            expires_at: None,
        };
        let mut local = note("n1", "T", "C", "t", &[]);
        let mut incoming = note("n1", "T", "C", "t", &[]);
        if let VaultEntry::Note(n) = &mut local {
            n.meta.history.push(rec.clone());
        }
        if let VaultEntry::Note(n) = &mut incoming {
            n.meta.history.push(rec.clone());
        }
        let (merged, _, _, _) = merge_entry_pair(&local, &incoming);
        let hist = match &merged {
            VaultEntry::Note(n) => n.meta.history.clone(),
            _ => panic!(),
        };
        assert_eq!(hist.len(), 1, "identical records dedup on merge");
    }

    #[test]
    fn merge_custom_pair_edits_on_different_labels_both_survive() {
        use crate::vault::entry::CustomField;
        let cf = |label: &str, value: &str| CustomField {
            label: label.to_string(),
            value: value.to_string(),
            hidden: false,
        };
        let login = |custom: Vec<CustomField>, times: &[(&str, u64)]| {
            VaultEntry::Login(LoginEntry {
                meta: meta("l1", "t", times),
                title: String::from("Acct"),
                url: String::new(),
                username: String::from("u"),
                password: String::from("p"),
                notes: None,
                custom_fields: custom,
                attachments: vec![],
                app_id: None,
                email: None,
            })
        };
        // local edited PIN's value; incoming added a different pair "Recovery".
        let local = login(vec![cf("PIN", "2222")], &[("custom_fields:PIN", 200)]);
        let incoming = login(
            vec![cf("PIN", "1111"), cf("Recovery", "x@example.com")],
            &[("custom_fields:Recovery", 300)],
        );
        let (merged, _, _, _) = merge_entry_pair(&local, &incoming);
        match &merged {
            VaultEntry::Login(e) => {
                let by: std::collections::HashMap<_, _> = e
                    .custom_fields
                    .iter()
                    .map(|f| (f.label.clone(), f.value.clone()))
                    .collect();
                assert_eq!(
                    by.get("PIN").map(String::as_str),
                    Some("2222"),
                    "local PIN edit kept"
                );
                assert_eq!(
                    by.get("Recovery").map(String::as_str),
                    Some("x@example.com"),
                    "incoming-added pair kept"
                );
            }
            _ => panic!("expected Login"),
        }
    }

    fn note_cf(
        id: &str,
        custom: Vec<crate::vault::entry::CustomField>,
        times: &[(&str, u64)],
    ) -> VaultEntry {
        VaultEntry::Note(NoteEntry {
            meta: meta(id, "t", times),
            title: String::from("T"),
            content: String::from("C"),
            custom_fields: custom,
            attachments: vec![],
        })
    }

    #[test]
    fn merge_item_deleted_on_one_side_surfaces_pending_delete() {
        use crate::vault::entry::CustomField;
        let cf = CustomField {
            label: String::from("PIN"),
            value: String::from("1"),
            hidden: false,
        };
        // local still has PIN (last changed at 100); incoming deleted it at 200.
        let local = note_cf("n1", vec![cf], &[("custom_fields:PIN", 100)]);
        let incoming = note_cf("n1", vec![], &[("del:custom_fields:PIN", 200)]);
        let (merged, _conflicts, dels, _bo) = merge_entry_pair(&local, &incoming);
        assert_eq!(dels.len(), 1, "a newer delete must surface as pending");
        assert_eq!(dels[0].field, "custom_fields:PIN");
        assert_eq!(dels[0].id, "n1");
        assert_eq!(dels[0].title, "T");
        // Item is kept (never silently dropped) until the user confirms.
        match &merged {
            VaultEntry::Note(n) => assert_eq!(n.custom_fields.len(), 1),
            _ => panic!("expected Note"),
        }
    }

    #[test]
    fn merge_item_edited_after_delete_keeps_item_no_pending() {
        use crate::vault::entry::CustomField;
        let cf = CustomField {
            label: String::from("PIN"),
            value: String::from("2"),
            hidden: false,
        };
        // local edited PIN at 300, AFTER incoming's delete at 200 -> edit wins.
        let local = note_cf("n1", vec![cf], &[("custom_fields:PIN", 300)]);
        let incoming = note_cf("n1", vec![], &[("del:custom_fields:PIN", 200)]);
        let (merged, _conflicts, dels, _bo) = merge_entry_pair(&local, &incoming);
        assert!(
            dels.is_empty(),
            "edit newer than delete -> no pending delete"
        );
        match &merged {
            VaultEntry::Note(n) => assert_eq!(n.custom_fields.len(), 1),
            _ => panic!("expected Note"),
        }
    }

    #[test]
    fn merge_collision_keeps_local_password_and_its_history() {
        use crate::vault::entry::HistoryRecord;
        let login = |pw: &str, prev: &str, times: &[(&str, u64)]| {
            let mut m = meta("l1", "t", times);
            m.history.push(HistoryRecord {
                field: String::from("password"),
                value: prev.to_string(),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: None,
            });
            VaultEntry::Login(LoginEntry {
                meta: m,
                title: String::from("Acct"),
                url: String::new(),
                username: String::from("u"),
                password: pw.to_string(),
                notes: None,
                custom_fields: vec![],
                attachments: vec![],
                app_id: None,
                email: None,
            })
        };
        // Both devices edited the password (different times) -> collision. Local is
        // kept pending the user's choice, and its history (local) is kept with it.
        let local = login("new-local", "old-local", &[("password", 200)]);
        let incoming = login("new-remote", "old-remote", &[("password", 300)]);
        let (merged, conflicts, _, _bo) = merge_entry_pair(&local, &incoming);
        match &merged {
            VaultEntry::Login(e) => {
                assert_eq!(e.password, "new-local");
                let rec = e
                    .meta
                    .history
                    .iter()
                    .find(|h| h.field == "password")
                    .expect("local password history kept");
                assert_eq!(rec.value, "old-local");
            }
            _ => panic!("expected Login"),
        }
        assert!(conflicts.iter().any(|f| f.field == "password"));
    }
}

/// Apply the entry-level merge algorithm to `session`, mutating it in place.
///
/// Merge rules (all timestamps are ISO 8601 strings; lexicographic ordering
/// is equivalent to temporal ordering for the format produced by `chrono_now`):
///
/// - **Entries — UNION + LWW**: always add incoming entries not present locally;
///   for same-UUID conflicts the newer `updated_at` wins as a whole.
/// - **Deletions — user consent**: incoming tombstones matching local entries are
///   collected in `pending_deletes`; no entry is ever deleted automatically.
/// - **Folders — UNION**: all folder names from both sides are kept; no auto-deletion.
/// - **Folder conflicts**: same-UUID entries with different folder assignments on each
///   device are collected in `folder_conflicts`; Flutter lets the user pick.
/// - **Tombstones**: union of both `deleted_ids` lists, deduped by id (newer
///   `deleted_at` kept when the same id appears on both sides).
fn do_merge(session: &mut VaultSession, incoming: VaultBody) -> MergeSummary {
    let mut added: u32 = 0;
    let mut updated: u32 = 0;
    let mut pending_deletes: Vec<crate::api::vault::PendingDeleteItem> = Vec::new();
    let mut folder_conflicts: Vec<crate::api::vault::FolderConflictItem> = Vec::new();
    let mut field_conflicts: Vec<FieldConflictItem> = Vec::new();
    let mut pending_item_deletes: Vec<PendingItemDeleteItem> = Vec::new();
    let mut added_entries: Vec<crate::api::vault::AddedEntryItem> = Vec::new();
    let mut brought_over: Vec<crate::api::vault::BroughtOverItem> = Vec::new();

    // Build lookup maps.
    let local_by_id: std::collections::HashMap<&str, &VaultEntry> =
        session.entries.iter().map(|e| (entry_id(e), e)).collect();
    let incoming_by_id: std::collections::HashMap<&str, &VaultEntry> =
        incoming.entries.iter().map(|e| (entry_id(e), e)).collect();
    let incoming_deletions: std::collections::HashMap<&str, &str> = incoming
        .deleted_ids
        .iter()
        .map(|d| (d.id.as_str(), d.deleted_at.as_str()))
        .collect();

    let mut result_entries: Vec<VaultEntry> = Vec::new();

    // --- Process local entries ---
    for local_entry in &session.entries {
        let id = entry_id(local_entry);

        if let Some(inc_entry) = incoming_by_id.get(id) {
            // Same UUID on both sides — check for folder conflict, then LWW on content.
            let local_folder = entry_folder(local_entry);
            let incoming_folder = entry_folder(inc_entry);
            if local_folder != incoming_folder {
                folder_conflicts.push(crate::api::vault::FolderConflictItem {
                    id: id.to_string(),
                    title: entry_display_title(local_entry),
                    local_folder: local_folder.to_string(),
                    incoming_folder: incoming_folder.to_string(),
                });
            }
            // Field-level merge: each field's newer change-time wins; falls back
            // to whole-entry LWW when neither side has per-field times (pre-v9).
            // Genuine clashes and newer-deletes are surfaced to the user.
            let (merged, mut conflicts, mut item_deletes, mut carried) =
                merge_entry_pair(local_entry, inc_entry);
            if merged != *local_entry {
                updated += 1;
            }
            field_conflicts.append(&mut conflicts);
            pending_item_deletes.append(&mut item_deletes);
            brought_over.append(&mut carried);
            result_entries.push(merged);
        } else if incoming_deletions.contains_key(id) {
            // Incoming tombstone — requires user consent before deletion; keep entry for now.
            pending_deletes.push(crate::api::vault::PendingDeleteItem {
                id: id.to_string(),
                title: entry_display_title(local_entry),
            });
            result_entries.push(local_entry.clone());
        } else {
            // Only on local side, no incoming tombstone — keep it.
            result_entries.push(local_entry.clone());
        }
    }

    // --- Process incoming-only entries (UNION) ---
    for inc_entry in &incoming.entries {
        let id = entry_id(inc_entry);
        if !local_by_id.contains_key(id) {
            // Not present locally — always add, even if a local tombstone exists.
            added_entries.push(crate::api::vault::AddedEntryItem {
                id: id.to_string(),
                title: entry_display_title(inc_entry),
            });
            result_entries.push(inc_entry.clone());
            added += 1;
        }
    }

    // --- Merge folders (UNION, dedup by name) ---
    let mut merged_folders = session.folders.clone();
    for folder in &incoming.folders {
        if !merged_folders.contains(folder) {
            merged_folders.push(folder.clone());
        }
    }

    // --- Union deleted_ids (keep newer deleted_at for the same id) ---
    let mut merged_tombstones: std::collections::HashMap<String, String> = session
        .deleted_ids
        .iter()
        .map(|d| (d.id.clone(), d.deleted_at.clone()))
        .collect();
    for d in &incoming.deleted_ids {
        let entry = merged_tombstones
            .entry(d.id.clone())
            .or_insert_with(|| d.deleted_at.clone());
        if d.deleted_at > *entry {
            *entry = d.deleted_at.clone();
        }
    }
    let merged_deleted_ids: Vec<DeletedEntry> = merged_tombstones
        .into_iter()
        .map(|(id, deleted_at)| DeletedEntry { id, deleted_at })
        .collect();

    session.entries = result_entries;
    session.folders = merged_folders;
    session.deleted_ids = merged_deleted_ids;

    MergeSummary {
        added,
        updated,
        added_entries,
        brought_over,
        pending_deletes,
        folder_conflicts,
        field_conflicts,
        pending_item_deletes,
    }
}

/// Merge an already-decrypted incoming `VaultBody` into the live session,
/// then persist the result.
///
/// Called by `merge_vault_from_file` after decryption.
pub fn session_merge_vault_from_body(incoming: VaultBody) -> Result<MergeSummary, String> {
    let (body, passphrase, path, yubikey, summary) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        // Snapshot the pre-sync state so a granular review can be fully cancelled.
        // Kept in memory only; entries are ZeroizeOnDrop.
        session.pre_sync_backup = Some(SyncBackup {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
            deleted_ids: session.deleted_ids.clone(),
        });
        let summary = do_merge(session, incoming);
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
            summary,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(summary)
}

/// Fast auto-merge: like [`do_merge`], but every surfaced decision is resolved
/// automatically in favour of the incoming vault (KeePassXC-style whole-incoming
/// wins), so the outcome is deterministic. Field collisions take the incoming
/// value (the losing local value kept in history); folder conflicts take the
/// incoming folder; tombstoned deletes (whole-entry and per-item) are applied;
/// and brought-over edits keep the replaced local value in history. Nothing is
/// lost — every replaced value lives in the entry's unified history.
fn do_fast_merge(session: &mut VaultSession, incoming: VaultBody) -> MergeSummary {
    let summary = do_merge(session, incoming);
    let now = crate::api::vault::chrono_now();
    let now_ms = crate::api::vault::now_ms();

    let find = |session: &mut VaultSession, id: &str| -> Option<usize> {
        session.entries.iter().position(|e| entry_id(e) == id)
    };

    // Brought-over edits (incoming edited a field the local side did not): the
    // value is already applied by do_merge; keep the replaced local value in
    // history. Added items (new attachments / new custom pairs) have no prior
    // value to preserve.
    for b in &summary.brought_over {
        if b.old_value.is_empty() || b.field.starts_with("attachments:") {
            continue;
        }
        if let Some(i) = find(session, &b.id) {
            meta_of_mut(&mut session.entries[i]).record_previous(
                &b.field,
                &b.old_value,
                &now,
                None,
            );
        }
    }
    // Field collisions -> incoming value; losing local value kept in history.
    for c in &summary.field_conflicts {
        if let Some(i) = find(session, &c.id) {
            let e = &mut session.entries[i];
            crate::api::vault::set_entry_field_by_key(e, &c.field, &c.incoming_value);
            let meta = meta_of_mut(e);
            meta.record_previous(&c.field, &c.local_value, &now, None);
            meta.field_times.insert(c.field.clone(), now_ms);
            meta.updated_at = now.clone();
        }
    }
    // Folder conflicts -> incoming folder.
    for f in &summary.folder_conflicts {
        if let Some(i) = find(session, &f.id) {
            let meta = meta_of_mut(&mut session.entries[i]);
            meta.folder = f.incoming_folder.clone();
            meta.updated_at = now.clone();
        }
    }
    // Per-item deletes (custom pair / attachment the other side removed) -> apply.
    for d in &summary.pending_item_deletes {
        if let Some(i) = find(session, &d.id) {
            let e = &mut session.entries[i];
            crate::api::vault::remove_entry_item_by_key(e, &d.field);
            let meta = meta_of_mut(e);
            meta.field_times.insert(format!("del:{}", d.field), now_ms);
            meta.field_times.remove(&d.field);
            meta.updated_at = now.clone();
        }
    }
    // Whole-entry deletes (incoming tombstone) -> apply.
    for d in &summary.pending_deletes {
        session.entries.retain(|e| entry_id(e) != d.id);
    }
    summary
}

/// Fast auto-merge an already-decrypted incoming `VaultBody` into the live
/// session and persist. Deterministic, no user prompts; see [`do_fast_merge`].
pub fn session_fast_merge_from_body(incoming: VaultBody) -> Result<MergeSummary, String> {
    let (body, passphrase, path, yubikey, summary) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let summary = do_fast_merge(session, incoming);
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
            summary,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(summary)
}

/// Apply a batch of granular-sync review decisions to the session in memory.
/// Mirrors the per-decision `session_*` mutations exactly but performs no save,
/// so the public wrapper can re-seal the vault once for the whole review.
/// Application order matches Flutter's apply loop: field resolutions, history
/// replacements, item deletes, folder assignments, then whole-entry deletes.
/// One timestamp stamps the whole batch (deterministic within one review).
fn do_apply_sync_decisions(
    session: &mut VaultSession,
    field_resolutions: &[crate::api::vault::SyncFieldResolutionInput],
    history_replacements: &[crate::api::vault::SyncHistoryReplacementInput],
    item_deletes: &[crate::api::vault::SyncItemDeleteInput],
    folders: &[crate::api::vault::SyncFolderInput],
    entry_deletes: &[String],
) -> Result<(), String> {
    let now = crate::api::vault::chrono_now();
    let now_ms = crate::api::vault::now_ms();
    let find = |session: &mut VaultSession, id: &str| -> Option<usize> {
        session.entries.iter().position(|e| entry_id(e) == id)
    };

    // Clash resolved to keep-mine (value untouched) or a dropped brought-over edit
    // (field set to the restored value). Either way the field is marked edited so
    // it stops re-clashing; no history recorded.
    for f in field_resolutions {
        if let Some(i) = find(session, &f.id) {
            let e = &mut session.entries[i];
            if f.keep_incoming {
                crate::api::vault::set_entry_field_by_key(e, &f.field, &f.value);
            }
            let meta = meta_of_mut(e);
            meta.field_times.insert(f.field.clone(), now_ms);
            meta.updated_at = now.clone();
        }
    }
    // Kept clash-to-theirs / kept brought-over edit: set the new value, keep the
    // replaced local value in history.
    for h in history_replacements {
        if let Some(i) = find(session, &h.id) {
            let e = &mut session.entries[i];
            crate::api::vault::set_entry_field_by_key(e, &h.field, &h.new_value);
            let meta = meta_of_mut(e);
            meta.record_previous(&h.field, &h.replaced_value, &now, None);
            meta.field_times.insert(h.field.clone(), now_ms);
            meta.updated_at = now.clone();
        }
    }
    // Item (custom pair / attachment) delete/keep the other side removed.
    for d in item_deletes {
        if let Some(i) = find(session, &d.id) {
            let e = &mut session.entries[i];
            if d.delete {
                crate::api::vault::remove_entry_item_by_key(e, &d.field);
                let meta = meta_of_mut(e);
                meta.field_times.insert(format!("del:{}", d.field), now_ms);
                meta.field_times.remove(&d.field);
            } else {
                meta_of_mut(e).field_times.insert(d.field.clone(), now_ms);
            }
            meta_of_mut(e).updated_at = now.clone();
        }
    }
    // Folder pick. Validate up front like session_assign_folder_to_entries; on an
    // unknown folder we bail before any save (caller discards the session change).
    for f in folders {
        if !f.folder.is_empty() && !session.folders.contains(&f.folder) {
            return Err(format!("Folder not found: {}", f.folder));
        }
        if let Some(i) = find(session, &f.id) {
            let meta = meta_of_mut(&mut session.entries[i]);
            meta.folder = f.folder.clone();
            meta.updated_at = now.clone();
        }
    }
    // Whole-entry deletes: dropped new entries and confirmed incoming tombstones.
    // Stamp a tombstone so future syncs see the delete.
    for id in entry_deletes {
        if session.entries.iter().any(|e| entry_id(e) == id.as_str()) {
            crate::api::vault::delete_entry(&mut session.entries, id)?;
            session.deleted_ids.push(DeletedEntry {
                id: id.clone(),
                deleted_at: now.clone(),
            });
        }
    }
    Ok(())
}

/// Apply a batch of granular-sync review decisions and persist the vault once:
/// field resolutions, kept-value history replacements, item keeps/deletes, folder
/// picks, and whole-entry deletes. One lock, one Argon2id re-seal for the whole
/// review, instead of one re-seal per decision.
pub fn session_apply_sync_decisions(
    field_resolutions: Vec<crate::api::vault::SyncFieldResolutionInput>,
    history_replacements: Vec<crate::api::vault::SyncHistoryReplacementInput>,
    item_deletes: Vec<crate::api::vault::SyncItemDeleteInput>,
    folders: Vec<crate::api::vault::SyncFolderInput>,
    entry_deletes: Vec<String>,
) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        do_apply_sync_decisions(
            session,
            &field_resolutions,
            &history_replacements,
            &item_deletes,
            &folders,
            &entry_deletes,
        )?;
        // The sync is being committed; drop the cancel snapshot (zeroizes its
        // plaintext entries) so a later cancel is a no-op.
        session.pre_sync_backup = None;
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Cancel an in-progress granular sync: restore the session to the pre-sync
/// snapshot taken by the merge and persist that state, so the vault ends exactly
/// where it was before the sync began (additive merge and any partial picks
/// discarded). No-op if there is no snapshot. The snapshot is dropped (its
/// plaintext entries zeroized) either way.
pub fn session_cancel_sync() -> Result<(), String> {
    let saved = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let Some(backup) = session.pre_sync_backup.take() else {
            return Ok(()); // nothing to cancel
        };
        session.folders = backup.folders.clone();
        session.entries = backup.entries.clone();
        session.deleted_ids = backup.deleted_ids.clone();
        // `backup` drops here -> its ZeroizeOnDrop entries are wiped.
        let body = build_body(session);
        let yubikey = extract_yubikey(session);
        (
            body,
            session.passphrase.clone(),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    let (body, passphrase, path, yubikey) = saved;
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

#[cfg(test)]
mod assign_folder_tests {
    use super::*;
    use crate::api::vault::save_vault;
    use crate::vault::entry::{EntryMeta, LoginEntry, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn teardown(path: &std::path::PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn assign_folder_to_entries_updates_selected_entries() {
        let pass = b"assign-folder-test";
        let mut path = temp_dir();
        path.push("gabbro_assign_folder_test.gabbro");

        let entries = vec![
            VaultEntry::Login(LoginEntry {
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
            }),
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("id-002"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from(""),
                },
                title: String::from("A note"),
                content: String::from("content"),
                custom_fields: vec![],
                attachments: vec![],
            }),
        ];

        save_vault(
            &crate::vault::serialization::VaultBody {
                folders: vec![String::from("Work")],
                entries,
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        session_assign_folder_to_entries(&[String::from("id-001")], String::from("Work")).unwrap();

        let e1 = get_entry("id-001").unwrap();
        let e2 = get_entry("id-002").unwrap();

        match e1 {
            VaultEntry::Login(ref e) => assert_eq!(
                e.meta.folder, "Work",
                "selected entry must be moved to the target folder"
            ),
            _ => panic!("expected Login"),
        }
        match e2 {
            VaultEntry::Note(ref e) => {
                assert_eq!(e.meta.folder, "", "unselected entry must not be changed")
            }
            _ => panic!("expected Note"),
        }

        teardown(&path);
    }
}

#[cfg(test)]
mod folder_tests {
    use super::*;
    use crate::api::vault::save_vault;
    use serial_test::serial;
    use std::env::temp_dir;

    fn setup_with_folders(
        passphrase: &[u8],
        path_suffix: &str,
        folders: Vec<String>,
    ) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push(format!("gabbro_folder_{}.gabbro", path_suffix));
        save_vault(
            &VaultBody {
                folders,
                entries: vec![],
                ..Default::default()
            },
            passphrase,
            &path,
        )
        .unwrap();
        path
    }

    fn teardown(path: &std::path::PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn list_folders_returns_folders_from_session() {
        let pass = b"folder-test-passphrase";
        let folders = vec![
            String::from("Work"),
            String::from("Private"),
            String::from("Other"),
        ];
        let path = setup_with_folders(pass, "list", folders.clone());
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_list_folders().unwrap();
        assert_eq!(result, folders);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn create_folder_adds_folder_to_session() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "create", vec![String::from("Work")]);
        unlock_vault(pass, path.clone()).unwrap();

        session_create_folder(String::from("Private")).unwrap();

        let folders = session_list_folders().unwrap();
        assert!(folders.contains(&String::from("Private")));
        assert!(folders.contains(&String::from("Work")));

        teardown(&path);
    }

    #[test]
    #[serial]
    fn create_folder_rejects_duplicate() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "create_dup", vec![String::from("Work")]);
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_create_folder(String::from("Work"));
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Folder already exists: Work");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn create_folder_rejects_empty_name() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "create_empty", vec![]);
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_create_folder(String::from(""));
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Folder name must not be empty");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn rename_folder_updates_folder_name_and_entries() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "rename", vec![String::from("Work")]);
        unlock_vault(pass, path.clone()).unwrap();

        // Add an entry in "Work"
        let entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("rename-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Work"),
            },
            title: String::from("Rename test note"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        });
        session_add_entry_no_save(entry).unwrap();

        session_rename_folder(String::from("Work"), String::from("Career")).unwrap();

        let folders = session_list_folders().unwrap();
        assert!(
            folders.contains(&String::from("Career")),
            "new name must appear"
        );
        assert!(
            !folders.contains(&String::from("Work")),
            "old name must be gone"
        );

        let updated = get_entry("rename-001").unwrap();
        match updated {
            VaultEntry::Note(ref e) => assert_eq!(
                e.meta.folder, "Career",
                "entry folder must be updated to new name"
            ),
            _ => panic!("Expected Note"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn rename_folder_rejects_nonexistent_old_name() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "rename_missing", vec![String::from("Work")]);
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_rename_folder(String::from("Ghost"), String::from("Career"));
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Folder not found: Ghost");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn rename_folder_rejects_duplicate_new_name() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(
            pass,
            "rename_dup",
            vec![String::from("Work"), String::from("Private")],
        );
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_rename_folder(String::from("Work"), String::from("Private"));
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Folder already exists: Private");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn rename_folder_rejects_empty_new_name() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "rename_empty", vec![String::from("Work")]);
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_rename_folder(String::from("Work"), String::from(""));
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Folder name must not be empty");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn delete_folder_removes_folder_and_clears_entries() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(
            pass,
            "delete_clear",
            vec![String::from("Work"), String::from("Private")],
        );
        unlock_vault(pass, path.clone()).unwrap();

        let entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("del-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Work"),
            },
            title: String::from("Delete test note"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        });
        session_add_entry_no_save(entry).unwrap();

        // Delete "Work", no reassign — entry folder should become ""
        session_delete_folder(String::from("Work"), None).unwrap();

        let folders = session_list_folders().unwrap();
        assert!(
            !folders.contains(&String::from("Work")),
            "deleted folder must be gone"
        );
        assert!(
            folders.contains(&String::from("Private")),
            "other folders must remain"
        );

        let updated = get_entry("del-001").unwrap();
        match updated {
            VaultEntry::Note(ref e) => assert_eq!(
                e.meta.folder, "",
                "entry folder must be cleared to empty string"
            ),
            _ => panic!("Expected Note"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn delete_folder_reassigns_entries_to_target() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(
            pass,
            "delete_reassign",
            vec![String::from("Work"), String::from("Private")],
        );
        unlock_vault(pass, path.clone()).unwrap();

        let entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("del-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Work"),
            },
            title: String::from("Reassign test note"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        });
        session_add_entry_no_save(entry).unwrap();

        // Delete "Work", reassign entries to "Private"
        session_delete_folder(String::from("Work"), Some(String::from("Private"))).unwrap();

        let folders = session_list_folders().unwrap();
        assert!(!folders.contains(&String::from("Work")));

        let updated = get_entry("del-002").unwrap();
        match updated {
            VaultEntry::Note(ref e) => assert_eq!(
                e.meta.folder, "Private",
                "entry must be reassigned to target folder"
            ),
            _ => panic!("Expected Note"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn delete_folder_rejects_nonexistent_folder() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "delete_missing", vec![String::from("Work")]);
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_delete_folder(String::from("Ghost"), None);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Folder not found: Ghost");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn delete_folder_rejects_invalid_reassign_target() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "delete_bad_target", vec![String::from("Work")]);
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_delete_folder(String::from("Work"), Some(String::from("Ghost")));
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Folder not found: Ghost");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn list_folders_returns_error_when_locked() {
        let pass = b"folder-test-passphrase";
        let path = setup_with_folders(pass, "list_locked", vec![]);
        lock_vault().ok();

        let result = session_list_folders();
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Vault is locked");

        teardown(&path);
    }
}

#[cfg(test)]
mod autofill_tests {
    use super::*;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn setup(passphrase: &[u8]) -> PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_autofill_test.gabbro");
        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("af-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Autofill test note"),
            content: String::from("test"),
            custom_fields: vec![],
            attachments: vec![],
        })];
        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
                ..Default::default()
            },
            passphrase,
            &path,
        )
        .unwrap();
        path
    }

    fn teardown(path: &PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn is_unlocked_returns_false_when_locked() {
        let path = setup(b"autofill-test-passphrase");
        lock_vault().ok();
        assert!(!is_vault_unlocked());
        teardown(&path);
    }

    #[test]
    #[serial]
    fn is_unlocked_returns_true_after_unlock() {
        let path = setup(b"autofill-test-passphrase");
        lock_vault().ok();
        unlock_vault(b"autofill-test-passphrase", path.clone()).unwrap();
        assert!(is_vault_unlocked());
        teardown(&path);
    }

    #[test]
    #[serial]
    fn get_entry_for_autofill_returns_json_with_password() {
        use crate::vault::entry::{LoginEntry, NoteEntry, VaultEntry};

        let pass = b"autofill-test-passphrase";
        let mut path = temp_dir();
        path.push("gabbro_autofill_get_entry_test.gabbro");

        let login = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("af-login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Example"),
            url: String::from("https://example.com/login"),
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let note = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("af-note-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Not a login"),
            content: String::from("irrelevant"),
            custom_fields: vec![],
            attachments: vec![],
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![login, note],
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let json = get_entry_for_autofill("af-login-001").unwrap();
        assert!(
            json.contains("\"password\""),
            "JSON must contain a password key"
        );
        assert!(
            json.contains("\"s3cr3t\""),
            "JSON must contain the correct password value"
        );
        assert!(
            json.contains("\"username\""),
            "JSON must contain a username key"
        );
        assert!(
            json.contains("\"user\""),
            "JSON must contain the correct username value"
        );
        assert!(json.contains("\"id\""), "JSON must contain an id key");

        let err = get_entry_for_autofill("af-note-001");
        assert!(err.is_err(), "Non-Login entry should return Err");

        let missing = get_entry_for_autofill("does-not-exist");
        assert!(missing.is_err(), "Missing id should return Err");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn login_summaries_for_autofill_returns_only_login_entries() {
        use crate::vault::entry::{LoginEntry, VaultEntry};

        let pass = b"autofill-test-passphrase";
        let mut path = temp_dir();
        path.push("gabbro_autofill_summaries_test.gabbro");

        let login = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("af-login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Example"),
            url: String::from("https://example.com/login"),
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let note = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("af-note-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Not a login"),
            content: String::from("irrelevant"),
            custom_fields: vec![],
            attachments: vec![],
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![login, note],
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let summaries = login_summaries_for_autofill().unwrap();

        assert_eq!(summaries.len(), 1, "only Login entries should be returned");
        assert_eq!(summaries[0].id, "af-login-001");
        assert_eq!(summaries[0].username, "user");
        assert_eq!(summaries[0].url, "https://example.com/login");
        // app_id/email carried through (None here; set-case covered by the unit test below).
        assert_eq!(summaries[0].app_id, None);
        assert_eq!(summaries[0].email, None);

        teardown(&path);
    }

    // Pure JSON formatter for the autofill summary list — no session needed, so
    // it runs in the fast lane (the session-backed test above does Argon2).
    #[test]
    fn login_summaries_json_includes_app_id_and_escapes() {
        let summaries = vec![
            LoginAutofillSummary {
                id: String::from("id1"),
                username: String::from("user"),
                url: String::from("https://example.com"),
                app_id: Some(String::from("com.company.app")),
                email: Some(String::from("user@example.com")),
            },
            LoginAutofillSummary {
                id: String::from("id2"),
                username: String::from("a\"b"),
                url: String::from("https://other.example"),
                app_id: None,
                email: None,
            },
        ];
        let json = login_summaries_json(&summaries);
        assert!(
            json.contains("\"app_id\":\"com.company.app\""),
            "app_id must be present when set: {json}"
        );
        assert!(
            json.contains("\"app_id\":\"\""),
            "app_id None must serialize as empty string: {json}"
        );
        assert!(
            json.contains("\"email\":\"user@example.com\""),
            "email must be present when set: {json}"
        );
        assert!(
            json.contains("\"email\":\"\""),
            "email None must serialize as empty string: {json}"
        );
        assert!(json.contains("a\\\"b"), "quotes must stay escaped: {json}");
        assert!(
            json.starts_with('[') && json.ends_with(']'),
            "array shape: {json}"
        );
    }

    #[test]
    fn login_summaries_json_escapes_backslash_and_control_chars() {
        // S-07: a backslash or control char in a summary field must produce
        // valid JSON that round-trips, not a broken/misparsed string.
        let summaries = vec![LoginAutofillSummary {
            id: String::from("id"),
            username: String::from("a\\b\tc"), // backslash + tab
            url: String::from("u"),
            app_id: None,
            email: None,
        }];
        let json = login_summaries_json(&summaries);
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("must be valid JSON");
        assert_eq!(
            parsed[0]["username"], "a\\b\tc",
            "value must round-trip: {json}"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    /// Helper — creates a minimal vault file on disk and returns its path.
    fn setup_vault(passphrase: &[u8]) -> PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_session_test.gabbro");
        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Session test note"),
            content: String::from("session secret content"),
            custom_fields: vec![],
            attachments: vec![],
        })];
        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
                ..Default::default()
            },
            passphrase,
            &path,
        )
        .unwrap();
        path
    }

    /// Helper — ensures the session is locked and vault file is cleaned up.
    fn teardown(path: &PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    #[test]
    #[serial]
    fn unlock_then_list_summaries_returns_entries() {
        let pass = b"test passphrase";
        let path = setup_vault(pass);

        unlock_vault(pass, path.clone()).unwrap();
        let summaries = list_entry_summaries().unwrap();

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].entry_type, "Note");
        assert_eq!(summaries[0].id, "id-001");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn locked_vault_list_summaries_returns_error() {
        let pass = b"test passphrase";
        let path = setup_vault(pass);

        // Ensure locked
        lock_vault().unwrap();
        let result = list_entry_summaries();
        assert!(result.is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn get_entry_returns_correct_entry() {
        let pass = b"test passphrase";
        let path = setup_vault(pass);

        unlock_vault(pass, path.clone()).unwrap();
        let entry = get_entry("id-001").unwrap();

        match entry {
            VaultEntry::Note(ref e) => assert_eq!(e.content, "session secret content"),
            _ => panic!("Expected Note variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn get_entry_wrong_id_returns_error() {
        let pass = b"test passphrase";
        let path = setup_vault(pass);

        unlock_vault(pass, path.clone()).unwrap();
        assert!(get_entry("does-not-exist").is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn create_entry_persists_to_disk() {
        let pass = b"test passphrase";
        let path = setup_vault(pass);

        unlock_vault(pass, path.clone()).unwrap();

        let new_entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("New note"),
            content: String::from("new content"),
            custom_fields: vec![],
            attachments: vec![],
        });

        session_create_entry(new_entry).unwrap();

        // Lock and reload from disk to verify persistence
        lock_vault().unwrap();
        unlock_vault(pass, path.clone()).unwrap();
        let summaries = list_entry_summaries().unwrap();

        assert_eq!(summaries.len(), 2);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn lock_vault_clears_session() {
        let pass = b"test passphrase";
        let path = setup_vault(pass);

        unlock_vault(pass, path.clone()).unwrap();
        // Vault is unlocked — summaries should be accessible
        assert!(list_entry_summaries().is_ok());

        lock_vault().unwrap();
        // After lock, session must be cleared — all access must fail
        assert!(list_entry_summaries().is_err());
        assert!(get_entry("id-001").is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn change_passphrase_old_fails_new_works() {
        let old = b"old passphrase";
        let new = b"new passphrase";
        let path = setup_vault(old);

        unlock_vault(old, path.clone()).unwrap();
        session_change_passphrase(old, new).unwrap();
        lock_vault().unwrap();

        assert!(unlock_vault(old, path.clone()).is_err());
        assert!(unlock_vault(new, path.clone()).is_ok());

        teardown(&path);
    }

    // R-03 P1: a CRUD save syncs the .bak to the CURRENT vault, so a restore
    // after corruption returns the user's latest state — including the edit
    // that just triggered this save. (The pre-P1 behaviour trailed by one save
    // and lost the most recent edit on restore; hardware-found 2026-06-11.)
    #[test]
    #[serial]
    fn bak_after_crud_save_matches_current_vault() {
        let pass = b"crud bak pass";
        let path = setup_vault(pass);
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&bak);

        unlock_vault(pass, path.clone()).unwrap();
        let pre_op_bytes = std::fs::read(&path).unwrap();

        let new_entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-bak-crud"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Bak sync probe"),
            content: String::from("probe"),
            custom_fields: vec![],
            attachments: vec![],
        });
        session_create_entry(new_entry).unwrap();

        let main_bytes = std::fs::read(&path).unwrap();
        let bak_bytes = std::fs::read(&bak);
        let _ = std::fs::remove_file(&bak);
        teardown(&path);

        let bak_bytes = bak_bytes.expect(".bak must exist after a CRUD save");
        assert_eq!(
            bak_bytes, main_bytes,
            "a CRUD save must sync: .bak holds the current (post-operation) vault"
        );
        assert_ne!(
            bak_bytes, pre_op_bytes,
            "the .bak must have advanced past the pre-operation state, not trail it"
        );
    }

    // R-03: after a passphrase change the .bak must open with the NEW
    // passphrase (the user may not remember the old one), never the old.
    // Credential-changing saves refresh the .bak instead of rotating it.
    #[test]
    #[serial]
    fn bak_after_passphrase_change_opens_with_new_passphrase_only() {
        let old = b"old bak passphrase";
        let new = b"new bak passphrase";
        let path = setup_vault(old);
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&bak);

        unlock_vault(old, path.clone()).unwrap();
        session_change_passphrase(old, new).unwrap();
        lock_vault().unwrap();

        let opened = crate::vault::io::read_vault(&bak)
            .map_err(|e| format!(".bak missing or unreadable after passphrase change: {e}"))
            .map(|sealed| {
                (
                    crate::crypto::vault_crypto::open_vault(new, &sealed).is_ok(),
                    crate::crypto::vault_crypto::open_vault(old, &sealed).is_err(),
                )
            });
        let _ = std::fs::remove_file(&bak);
        teardown(&path);

        let (opens_with_new, refuses_old) = opened.expect(".bak must exist");
        assert!(opens_with_new, ".bak must open with the NEW passphrase");
        assert!(refuses_old, ".bak must refuse the OLD passphrase");
    }

    #[test]
    #[serial]
    fn login_entry_to_summary_uses_title() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
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
        });

        let summary = entry_to_summary(&entry);
        assert_eq!(
            summary.title, "Example",
            "summary title should use LoginEntry.title, not url or username"
        );
    }

    #[test]
    #[serial]
    fn login_entry_to_summary_falls_back_to_url_when_title_empty() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-login-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from(""),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });

        let summary = entry_to_summary(&entry);
        assert_eq!(
            summary.title, "https://example.com",
            "summary should fall back to url when title is empty"
        );
    }

    #[test]
    #[serial]
    fn card_entry_to_summary_uses_card_name_when_present() {
        use crate::vault::entry::{CardEntry, EntryMeta, VaultEntry};

        let entry = VaultEntry::Card(CardEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-card-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            card_name: Some(String::from("Visa Platinum")),
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
            custom_fields: vec![],
            attachments: vec![],
        });

        let summary = entry_to_summary(&entry);
        assert_eq!(
            summary.title, "Visa Platinum",
            "summary should use card_name when present"
        );
    }

    #[test]
    #[serial]
    fn unexpired_history_is_preserved_on_unlock() {
        use crate::vault::entry::{EntryMeta, HistoryRecord, LoginEntry, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_unexpired_history_test.gabbro");

        // expires_at is far in the future - 2099-12-31
        let mut meta = EntryMeta {
            field_times: Default::default(),
            history: Vec::new(),
            id: String::from("login-unexp-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        meta.history.push(HistoryRecord {
            field: String::from("password"),
            value: String::from("old"),
            saved_at: String::from("2025-01-01T00:00:00Z"),
            expires_at: Some(String::from("2099-12-31T00:00:00Z")),
        });
        let entry = VaultEntry::Login(LoginEntry {
            meta,
            title: String::from("Unexpired"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("current"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = get_entry("login-unexp-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert!(
                    e.meta.history.iter().any(|h| h.field == "password"),
                    "unexpired history must be preserved on unlock"
                );
            }
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn keep_forever_history_is_preserved_on_unlock() {
        use crate::vault::entry::{EntryMeta, HistoryRecord, LoginEntry, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_keep_forever_history_test.gabbro");

        let mut meta = EntryMeta {
            field_times: Default::default(),
            history: Vec::new(),
            id: String::from("login-forever-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        meta.history.push(HistoryRecord {
            field: String::from("password"),
            value: String::from("old"),
            saved_at: String::from("2025-01-01T00:00:00Z"),
            expires_at: None,
        });
        let entry = VaultEntry::Login(LoginEntry {
            meta,
            title: String::from("Forever"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("current"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = get_entry("login-forever-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert!(
                    e.meta.history.iter().any(|h| h.field == "password"),
                    "keep-forever history (expires_at: None) must never be purged"
                );
            }
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn expired_history_is_purged_on_unlock() {
        use crate::vault::entry::{EntryMeta, HistoryRecord, LoginEntry, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_expired_history_test.gabbro");

        // expires_at is in the past - 2000-01-01
        let mut meta = EntryMeta {
            field_times: Default::default(),
            history: Vec::new(),
            id: String::from("login-exp-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        meta.history.push(HistoryRecord {
            field: String::from("password"),
            value: String::from("old"),
            saved_at: String::from("2000-01-01T00:00:00Z"),
            expires_at: Some(String::from("2000-01-02T00:00:00Z")),
        });
        let entry = VaultEntry::Login(LoginEntry {
            meta,
            title: String::from("Expired"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("current"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = get_entry("login-exp-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert!(
                    !e.meta.history.iter().any(|h| h.field == "password"),
                    "expired history should be purged on unlock"
                );
                assert_eq!(
                    e.password, "current",
                    "current password must not be affected"
                );
            }
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn card_entry_to_summary_falls_back_to_cardholder_name() {
        use crate::vault::entry::{CardEntry, EntryMeta, VaultEntry};

        let entry = VaultEntry::Card(CardEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-card-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
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
            custom_fields: vec![],
            attachments: vec![],
        });

        let summary = entry_to_summary(&entry);
        assert_eq!(
            summary.title, "Alex Smith",
            "summary should fall back to cardholder_name when card_name is absent"
        );
    }
}

#[cfg(test)]
mod yubikey_session_tests {
    use super::*;
    use crate::api::vault::save_vault_with_keys;
    use crate::crypto::vault_crypto::YubiKeyRegistration;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn teardown(path: &std::path::PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    // ── VERSION 4 multi-key passphrase change ─────────────────────────────────

    fn setup_multi_key_vault(passphrase: &[u8]) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_v4_change_pass_test.gabbro");
        let body = VaultBody {
            folders: vec![],
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("v4-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from(""),
                },
                title: String::from("Multi-key test note"),
                content: String::from("secret content"),
                custom_fields: vec![],
                attachments: vec![],
            })],
            ..Default::default()
        };
        let keys = [
            YubiKeyRegistration {
                credential_id: vec![0x01u8; 64],
                hmac_secret: [0x11u8; 32],
                salt: [0x22u8; 32],
            },
            YubiKeyRegistration {
                credential_id: vec![0x02u8; 48],
                hmac_secret: [0x33u8; 32],
                salt: [0x44u8; 32],
            },
        ];
        save_vault_with_keys(&body, passphrase, &keys, &path).unwrap();
        path
    }

    #[test]
    #[serial]
    fn change_passphrase_on_multi_key_vault_works_with_any_registered_key() {
        let old_pass = b"old-multi-key-pass";
        let new_pass = b"new-multi-key-pass";
        let path = setup_multi_key_vault(old_pass);

        // Unlock with key 0 → vault_key_master cached → VERSION 4 path
        unlock_vault_with_key_record(old_pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone())
            .unwrap();
        session_change_passphrase(old_pass, new_pass).unwrap();
        lock_vault().unwrap();

        // Old passphrase must no longer work with either key
        assert!(unlock_vault_with_key_record(
            old_pass,
            &[0x11u8; 32],
            vec![0x01u8; 64],
            path.clone(),
        )
        .is_err());
        assert!(unlock_vault_with_key_record(
            old_pass,
            &[0x33u8; 32],
            vec![0x02u8; 48],
            path.clone(),
        )
        .is_err());

        // New passphrase + key 0 must work
        unlock_vault_with_key_record(new_pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone())
            .unwrap();
        assert_eq!(list_entry_summaries().unwrap().len(), 1);
        lock_vault().unwrap();

        // New passphrase + key 1 must also work
        unlock_vault_with_key_record(new_pass, &[0x33u8; 32], vec![0x02u8; 48], path.clone())
            .unwrap();
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        teardown(&path);
    }

    // ADR-013 opt-in downgrade: exporting a key-protected vault passphrase-only
    // yields an artifact openable by the passphrase ALONE, while the original
    // vault on disk stays key-protected (its class is never mutated).
    #[test]
    #[serial]
    fn passphrase_only_downgrade_of_keyprotected_vault_opens_with_passphrase_alone() {
        use crate::api::vault::load_vault;
        use std::env::temp_dir;

        let pass = b"multi-key downgrade pass";
        let path = setup_multi_key_vault(pass);

        // Unlock with a registered key — proves the vault is key-protected and the
        // session is hardware-authenticated (the implicit downgrade authorization).
        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();

        let mut export_path = temp_dir();
        export_path.push("gabbro_downgrade_passonly_out.gabbro");
        session_export_vault_passphrase_only(export_path.clone()).unwrap();

        // The downgraded artifact opens with the passphrase ALONE — no YubiKey.
        let body = load_vault(pass, &export_path)
            .expect("passphrase-only downgrade artifact must open with the passphrase alone");
        assert_eq!(body.entries.len(), 1);

        // The ORIGINAL vault is untouched — still key-protected.
        assert!(
            load_vault(pass, &path).is_err(),
            "original key-protected vault must stay key-protected after a downgrade export"
        );

        teardown(&path);
        let _ = std::fs::remove_file(&export_path);
        let _ = std::fs::remove_file(export_path.with_extension("gabbro.sha256"));
    }
}

#[cfg(test)]
mod yubikey_mgmt_tests {
    use super::*;
    use crate::api::vault::save_vault_with_keys;
    use crate::crypto::vault_crypto::YubiKeyRegistration;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn setup_two_key_vault(passphrase: &[u8], suffix: &str) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push(format!("gabbro_yk_mgmt_{suffix}.gabbro"));
        let body = VaultBody {
            folders: vec![],
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("mgmt-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from(""),
                },
                title: String::from("Key mgmt test note"),
                content: String::from("secret"),
                custom_fields: vec![],
                attachments: vec![],
            })],
            ..Default::default()
        };
        let keys = [
            YubiKeyRegistration {
                credential_id: vec![0x01u8; 64],
                hmac_secret: [0x11u8; 32],
                salt: [0x22u8; 32],
            },
            YubiKeyRegistration {
                credential_id: vec![0x02u8; 48],
                hmac_secret: [0x33u8; 32],
                salt: [0x44u8; 32],
            },
        ];
        save_vault_with_keys(&body, passphrase, &keys, &path).unwrap();
        path
    }

    fn teardown(path: &std::path::PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    // ── session_add_yubikey ───────────────────────────────────────────────────

    #[test]
    #[serial]
    fn add_yubikey_succeeds_on_v4_vault() {
        let pass = b"add-key-pass";
        let path = setup_two_key_vault(pass, "add");

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        session_add_yubikey(vec![0x03u8; 32], vec![0x55u8; 32], vec![0x66u8; 32]).unwrap();
        lock_vault().unwrap();

        // New credential must be able to unlock
        unlock_vault_with_key_record(pass, &[0x55u8; 32], vec![0x03u8; 32], path.clone()).unwrap();
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        teardown(&path);
    }

    // R-03: adding a key is a credential change — .bak refreshes to the
    // post-change vault instead of rotating to the pre-change one
    #[test]
    #[serial]
    fn bak_after_add_yubikey_matches_current_vault() {
        let pass = b"add-key-bak-pass";
        let path = setup_two_key_vault(pass, "addbak");
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&bak);

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        session_add_yubikey(vec![0x03u8; 32], vec![0x55u8; 32], vec![0x66u8; 32]).unwrap();
        lock_vault().unwrap();

        let main_bytes = std::fs::read(&path).unwrap();
        let bak_bytes = std::fs::read(&bak);
        let _ = std::fs::remove_file(&bak);
        teardown(&path);
        assert_eq!(
            bak_bytes.expect(".bak must exist after adding a key"),
            main_bytes,
            "adding a YubiKey must refresh .bak to the post-change vault"
        );
    }

    // R-03: removing a key is a credential change — .bak must match the
    // post-removal vault (a rotated .bak would still trust the removed key)
    #[test]
    #[serial]
    fn bak_after_remove_yubikey_matches_current_vault() {
        let pass = b"remove-key-bak-pass";
        let path = setup_two_key_vault(pass, "removebak");
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&bak);

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        session_remove_yubikey(vec![0x02u8; 48]).unwrap();
        lock_vault().unwrap();

        let main_bytes = std::fs::read(&path).unwrap();
        let bak_bytes = std::fs::read(&bak);
        let _ = std::fs::remove_file(&bak);
        teardown(&path);
        assert_eq!(
            bak_bytes.expect(".bak must exist after removing a key"),
            main_bytes,
            "removing a YubiKey must refresh .bak to the post-change vault"
        );
    }

    // ── session_remove_yubikey ────────────────────────────────────────────────

    #[test]
    #[serial]
    fn remove_yubikey_reduces_key_count() {
        let pass = b"remove-key-pass";
        let path = setup_two_key_vault(pass, "remove");

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        session_remove_yubikey(vec![0x02u8; 48]).unwrap();
        lock_vault().unwrap();

        // Removed key must no longer work
        let result =
            unlock_vault_with_key_record(pass, &[0x33u8; 32], vec![0x02u8; 48], path.clone());
        assert!(result.is_err(), "removed key must not unlock");

        // Remaining key must still work
        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn remove_last_yubikey_returns_error() {
        let pass = b"remove-last-pass";
        let path = setup_two_key_vault(pass, "remove_last");

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();

        // Remove the second key — leaves one key on disk
        session_remove_yubikey(vec![0x02u8; 48]).unwrap();

        // Removing the last remaining key must fail
        let result = session_remove_yubikey(vec![0x01u8; 64]);
        assert!(result.is_err(), "cannot remove the last registered key");

        teardown(&path);
    }

    // ── session_set_yubikey_alias / session_list_yubikey_aliases ─────────────

    #[test]
    #[serial]
    fn set_and_list_aliases_round_trips() {
        let pass = b"alias-pass";
        let path = setup_two_key_vault(pass, "alias_roundtrip");

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        session_set_yubikey_alias(String::from("aabb"), String::from("Primary")).unwrap();
        session_set_yubikey_alias(String::from("ccdd"), String::from("Backup")).unwrap();

        let aliases = session_list_yubikey_aliases().unwrap();
        assert_eq!(aliases.get("aabb").map(|s| s.as_str()), Some("Primary"));
        assert_eq!(aliases.get("ccdd").map(|s| s.as_str()), Some("Backup"));

        teardown(&path);
    }

    #[test]
    #[serial]
    fn alias_persists_across_lock_unlock() {
        let pass = b"alias-persist-pass";
        let path = setup_two_key_vault(pass, "alias_persist");

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        session_set_yubikey_alias(String::from("aabb"), String::from("Main")).unwrap();
        lock_vault().unwrap();

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        let aliases = session_list_yubikey_aliases().unwrap();
        assert_eq!(
            aliases.get("aabb").map(|s| s.as_str()),
            Some("Main"),
            "alias must survive lock/unlock cycle"
        );

        teardown(&path);
    }

    #[test]
    #[serial]
    fn list_aliases_empty_on_fresh_vault() {
        let pass = b"alias-empty-pass";
        let path = setup_two_key_vault(pass, "alias_empty");

        unlock_vault_with_key_record(pass, &[0x11u8; 32], vec![0x01u8; 64], path.clone()).unwrap();
        let aliases = session_list_yubikey_aliases().unwrap();
        assert!(aliases.is_empty(), "fresh vault must have no aliases");

        teardown(&path);
    }
}

#[cfg(test)]
mod json_export_tests {
    use super::*;
    use crate::api::vault::save_vault;
    use crate::vault::entry::{EntryMeta, LoginEntry, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn teardown(vault_path: &PathBuf, json_path: &PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(vault_path);
        let _ = std::fs::remove_file(format!("{}.bak", vault_path.display()));
        let _ = std::fs::remove_file(json_path);
    }

    #[test]
    #[serial]
    fn export_vault_json_returns_err_when_locked() {
        let mut json_path = temp_dir();
        json_path.push("gabbro_json_export_locked.json");
        lock_vault().ok();
        let result = session_export_vault_json(json_path);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Vault is locked");
    }

    #[test]
    #[serial]
    fn export_vault_json_writes_file_with_valid_json() {
        let pass = b"json-export-test";
        let mut vault_path = temp_dir();
        vault_path.push("gabbro_json_export_source.gabbro");
        let mut json_path = temp_dir();
        json_path.push("gabbro_json_export_output.json");

        let entries = vec![
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("je-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                },
                title: String::from("JSON export test note"),
                content: String::from("test content"),
                custom_fields: vec![],
                attachments: vec![],
            }),
            VaultEntry::Login(LoginEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("je-002"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Work"),
                },
                title: String::from("Example"),
                url: String::from("https://example.com"),
                username: String::from("user"),
                password: String::from("s3cr3t"),
                notes: None,
                custom_fields: vec![],
                attachments: vec![],
                app_id: None,
                email: None,
            }),
        ];

        save_vault(
            &VaultBody {
                folders: vec![String::from("Personal"), String::from("Work")],
                entries,
                ..Default::default()
            },
            pass,
            &vault_path,
        )
        .unwrap();
        unlock_vault(pass, vault_path.clone()).unwrap();

        session_export_vault_json(json_path.clone()).unwrap();

        let raw = std::fs::read_to_string(&json_path).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap();

        assert!(
            parsed["exported_at"].is_string(),
            "must have exported_at timestamp"
        );
        assert!(
            parsed.get("gabbro_version").is_none(),
            "gabbro_version was dropped from the JSON export (brittle hard-coded value)"
        );
        assert_eq!(parsed["folders"].as_array().unwrap().len(), 2);
        assert_eq!(parsed["entries"].as_array().unwrap().len(), 2);
        assert!(
            raw.contains("s3cr3t"),
            "password must appear in plaintext export"
        );

        teardown(&vault_path, &json_path);
    }

    #[test]
    #[serial]
    fn export_vault_json_empty_vault_writes_empty_arrays() {
        let pass = b"json-export-empty";
        let mut vault_path = temp_dir();
        vault_path.push("gabbro_json_export_empty.gabbro");
        let mut json_path = temp_dir();
        json_path.push("gabbro_json_export_empty_output.json");

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![],
                ..Default::default()
            },
            pass,
            &vault_path,
        )
        .unwrap();
        unlock_vault(pass, vault_path.clone()).unwrap();

        session_export_vault_json(json_path.clone()).unwrap();

        let raw = std::fs::read_to_string(&json_path).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap();

        assert!(parsed["entries"].as_array().unwrap().is_empty());
        assert!(parsed["folders"].as_array().unwrap().is_empty());

        teardown(&vault_path, &json_path);
    }

    // ── search_blob unit tests (no vault session needed) ──────────────────────

    #[test]
    fn search_blob_for_login_includes_username_and_url() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-1".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Example".to_string(),
            url: "https://example.com".to_string(),
            username: "user@example.com".to_string(),
            password: "s3cr3t".to_string(),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        assert!(
            s.search_blob.contains("user@example.com"),
            "blob must include username"
        );
        assert!(
            s.search_blob.contains("example.com"),
            "blob must include url"
        );
    }

    #[test]
    fn search_blob_for_login_excludes_password() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-2".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Example".to_string(),
            url: "https://example.com".to_string(),
            username: "user".to_string(),
            password: "s3cr3t_password_xyz".to_string(),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        assert!(
            !s.search_blob.contains("s3cr3t_password_xyz"),
            "blob must not include password"
        );
    }

    #[test]
    fn search_blob_for_login_includes_notes() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-3".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Work VPN".to_string(),
            url: "".to_string(),
            username: "user".to_string(),
            password: "pw".to_string(),
            notes: Some("corporate access only".to_string()),
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        assert!(
            s.search_blob.contains("corporate access only"),
            "blob must include notes"
        );
    }

    #[test]
    fn search_blob_for_login_includes_value_excludes_custom_field_label() {
        use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-4".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Example".to_string(),
            url: "".to_string(),
            username: "user".to_string(),
            password: "pw".to_string(),
            notes: None,
            custom_fields: vec![CustomField {
                label: "Recovery email".to_string(),
                value: "backup@example.com".to_string(),
                hidden: false,
            }],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        // Full-text search matches values, not field labels: searching "email"
        // must not match an entry merely because it has an email-labelled field.
        assert!(
            !s.search_blob.contains("recovery email"),
            "blob must NOT include custom field labels (values only)"
        );
        assert!(
            s.search_blob.contains("backup@example.com"),
            "blob must include non-hidden custom field value"
        );
    }

    #[test]
    fn search_blob_for_login_excludes_hidden_custom_field_value() {
        use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-5".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Example".to_string(),
            url: "".to_string(),
            username: "user".to_string(),
            password: "pw".to_string(),
            notes: None,
            custom_fields: vec![CustomField {
                label: "Secret token".to_string(),
                value: "tok_xyz_hidden_1234".to_string(),
                hidden: true,
            }],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        assert!(
            !s.search_blob.contains("tok_xyz_hidden_1234"),
            "blob must not include hidden custom field value"
        );
        assert!(
            !s.search_blob.contains("secret token"),
            "blob must not include custom field labels (values only)"
        );
    }

    #[test]
    fn search_blob_for_note_includes_content() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        let entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-6".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Shopping".to_string(),
            content: "Milk eggs bread olive oil".to_string(),
            custom_fields: vec![],
            attachments: vec![],
        });
        let s = entry_to_summary(&entry);
        assert!(
            s.search_blob.contains("olive oil"),
            "blob must include note content"
        );
    }

    #[test]
    fn search_blob_for_identity_includes_email_and_address() {
        use crate::vault::entry::{EntryMeta, IdentityEntry, VaultEntry};
        let entry = VaultEntry::Identity(IdentityEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-7".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            first_name: "Alice".to_string(),
            last_name: "Smith".to_string(),
            email: "alice@example.com".to_string(),
            phone: Some("+41791234567".to_string()),
            address: Some("Rue du Rhône 10, Geneva".to_string()),
            custom_fields: vec![],
            attachments: vec![],
        });
        let s = entry_to_summary(&entry);
        assert!(
            s.search_blob.contains("alice@example.com"),
            "blob must include email"
        );
        assert!(
            s.search_blob.contains("rue du rhône"),
            "blob must include address (lowercased)"
        );
    }

    #[test]
    fn search_blob_for_card_includes_cardholder_and_bank_excludes_card_number() {
        use crate::vault::entry::{CardEntry, EntryMeta, VaultEntry};
        let entry = VaultEntry::Card(CardEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-8".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            card_name: Some("Visa Platinum".to_string()),
            status: "active".to_string(),
            cardholder_name: "Alex Smith".to_string(),
            card_number: "4111999988887777".to_string(),
            expiry: "12/28".to_string(),
            cvv: "999".to_string(),
            credit_limit: None,
            card_account_number: None,
            payment_network: Some("Visa".to_string()),
            pin: None,
            bank_name: Some("UBS".to_string()),
            transaction_password: None,
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
        });
        let s = entry_to_summary(&entry);
        assert!(
            s.search_blob.contains("alex smith"),
            "blob must include cardholder name"
        );
        assert!(s.search_blob.contains("ubs"), "blob must include bank name");
        assert!(
            !s.search_blob.contains("4111999988887777"),
            "blob must not include card number"
        );
        assert!(!s.search_blob.contains("999"), "blob must not include cvv");
    }

    #[test]
    fn search_blob_excludes_empty_labelled_fields_enpass_regression() {
        // Enpass templates carry typed fields (Email, Phone, ...) that import as
        // empty-valued custom fields. Their labels must not make a full-text
        // search for the label word match the entry. (2026-06-24 regression.)
        use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-enpass".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Acme account".to_string(),
            url: "".to_string(),
            username: "user".to_string(),
            password: "pw".to_string(),
            notes: None,
            custom_fields: vec![
                CustomField {
                    label: "Phone".to_string(),
                    value: "".to_string(),
                    hidden: false,
                },
                CustomField {
                    label: "Email".to_string(),
                    value: "".to_string(),
                    hidden: false,
                },
            ],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        assert!(
            !s.search_blob.contains("phone"),
            "empty Phone-labelled field must not match a 'phone' search"
        );
        assert!(
            !s.search_blob.contains("email"),
            "empty Email-labelled field must not match an 'email' search"
        );
    }

    #[test]
    fn search_blob_matches_word_in_free_text_notes() {
        // The flip side of values-not-labels: a word in free-text notes is
        // content and must match, even when no field is labelled with it.
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-notes2".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Acme account".to_string(),
            url: "".to_string(),
            username: "user".to_string(),
            password: "pw".to_string(),
            notes: Some("reset link is sent to your email".to_string()),
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        assert!(
            s.search_blob.contains("email"),
            "a word in free-text notes must match"
        );
    }

    #[test]
    fn search_blob_for_custom_excludes_field_labels() {
        // values-not-labels applies to Custom entries too: a field labelled
        // "Router" must not match a "router" search; its value still matches.
        use crate::vault::entry::{CustomEntry, CustomField, EntryMeta, VaultEntry};
        let mut fields = indexmap::IndexMap::new();
        fields.insert(
            "f1".to_string(),
            CustomField {
                label: "Router".to_string(),
                value: "10.0.0.1".to_string(),
                hidden: false,
            },
        );
        let entry = VaultEntry::Custom(CustomEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-custom2".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Home network".to_string(),
            fields,
            attachments: vec![],
        });
        let s = entry_to_summary(&entry);
        assert!(
            !s.search_blob.contains("router"),
            "Custom field label must not be searchable"
        );
        assert!(
            s.search_blob.contains("10.0.0.1"),
            "Custom field value must remain searchable"
        );
    }

    #[test]
    fn search_blob_for_custom_includes_title_and_visible_values_excludes_hidden() {
        // Net-first pin: the Custom-entry blob must keep its title and non-hidden
        // field values searchable, and never leak hidden values. (Independent of
        // whether field labels are folded in.)
        use crate::vault::entry::{CustomEntry, CustomField, EntryMeta, VaultEntry};
        let mut fields = indexmap::IndexMap::new();
        fields.insert(
            "f1".to_string(),
            CustomField {
                label: "Router".to_string(),
                value: "192.168.1.1".to_string(),
                hidden: false,
            },
        );
        fields.insert(
            "f2".to_string(),
            CustomField {
                label: "Passcode".to_string(),
                value: "hidden_value_zzz".to_string(),
                hidden: true,
            },
        );
        let entry = VaultEntry::Custom(CustomEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-custom".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "Home network".to_string(),
            fields,
            attachments: vec![],
        });
        let s = entry_to_summary(&entry);
        assert!(
            s.search_blob.contains("home network"),
            "blob must include title"
        );
        assert!(
            s.search_blob.contains("192.168.1.1"),
            "blob must include non-hidden field value"
        );
        assert!(
            !s.search_blob.contains("hidden_value_zzz"),
            "blob must not include hidden field value"
        );
    }

    #[test]
    fn search_blob_is_lowercase() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: "id-blob-9".to_string(),
                created_at: "".to_string(),
                updated_at: "".to_string(),
                folder: "".to_string(),
            },
            title: "UPPERCASE TITLE".to_string(),
            url: "https://EXAMPLE.COM".to_string(),
            username: "User@Example.Com".to_string(),
            password: "pw".to_string(),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });
        let s = entry_to_summary(&entry);
        assert_eq!(
            s.search_blob,
            s.search_blob.to_lowercase(),
            "search_blob must be fully lowercase"
        );
    }
}

#[cfg(test)]
mod merge_tests {
    use super::*;
    use crate::api::vault::save_vault;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn note(id: &str, title: &str, updated_at: &str) -> VaultEntry {
        VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: id.to_string(),
                created_at: String::from("2026-01-01T00:00:00Z"),
                updated_at: updated_at.to_string(),
                folder: String::from(""),
            },
            title: title.to_string(),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        })
    }

    fn note_with_folder(id: &str, title: &str, updated_at: &str, folder: &str) -> VaultEntry {
        VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: id.to_string(),
                created_at: String::from("2026-01-01T00:00:00Z"),
                updated_at: updated_at.to_string(),
                folder: folder.to_string(),
            },
            title: title.to_string(),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        })
    }

    fn tombstone(id: &str, deleted_at: &str) -> DeletedEntry {
        DeletedEntry {
            id: id.to_string(),
            deleted_at: deleted_at.to_string(),
        }
    }

    // Runs the README hardware walk entirely in code (no UI): import A, sync B
    // keeping all defaults, sync C applying the dictated picks through the single
    // batched `session_apply_sync_decisions` call, and assert the same end-state
    // the JSON checker verifies. Proves the walk's expected result is exactly what
    // the engine produces — so a failing hardware checker means a mis-click, not a
    // code bug.
    #[test]
    #[serial]
    #[ignore = "production-Argon saves; run in release via the gate"]
    fn sync_walk_batched_apply_matches_checker() {
        use crate::api::vault::{
            SyncFieldResolutionInput, SyncHistoryReplacementInput, SyncItemDeleteInput,
        };
        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("test_data/sync_test_vaults");
        let pass = b"0123456789a";
        let load = |n: &str| {
            crate::api::vault::load_vault(pass, &dir.join(format!("sync_test_{n}.gabbro"))).unwrap()
        };

        let path = setup(pass, "walk_batched", load("A").entries);
        unlock_vault(pass, path.clone()).unwrap();

        session_merge_vault_from_body(load("B")).unwrap();
        let sc = session_merge_vault_from_body(load("C")).unwrap();

        // Clashes resolved to the other device's value keep the losing local value
        // in history.
        let history_replacements = [
            ("login-co", "password"),
            ("id-co", "last_name"),
            ("file-co", "data"),
        ]
        .iter()
        .map(|(id, field)| {
            let c = sc
                .field_conflicts
                .iter()
                .find(|c| c.id == *id && c.field == *field)
                .unwrap_or_else(|| panic!("expected clash {id}/{field}"));
            SyncHistoryReplacementInput {
                id: (*id).to_string(),
                field: (*field).to_string(),
                new_value: c.incoming_value.clone(),
                replaced_value: c.local_value.clone(),
            }
        })
        .collect();
        // Clashes resolved keep-mine: value untouched (matches the real UI, which
        // still sends a resolution so the field stops re-clashing).
        let field_resolutions = [
            ("note-co", "content"),
            ("card-co", "cvv"),
            ("custom-co", "custom_fields:token"),
        ]
        .iter()
        .map(|(id, field)| SyncFieldResolutionInput {
            id: (*id).to_string(),
            field: (*field).to_string(),
            keep_incoming: false,
            value: String::new(),
        })
        .collect();

        session_apply_sync_decisions(
            field_resolutions,
            history_replacements,
            vec![SyncItemDeleteInput {
                id: "login-nc".into(),
                field: "custom_fields:OldNote".into(),
                delete: true,
            }],
            vec![],
            vec!["delme".into()],
        )
        .unwrap();

        {
            let session = VAULT_SESSION.lock().unwrap();
            assert_walk_end_state(&session.as_ref().unwrap().entries);
        }
        teardown(&path);
    }

    // Cross-version sync end to end: load a real pre-v9 (v8) vault file as the
    // incoming body - through the same load_vault -> deserialize path the app uses
    // - and merge it into a current-format session. Proves the whole flow loads an
    // older format, upgrades it (empty field_times), and merges without loss or
    // panic: the v8 entry is added, the local entry survives.
    #[test]
    #[serial]
    #[ignore = "loads a production-Argon golden fixture + saves; run via the gate"]
    fn cross_version_sync_loads_and_merges_a_v8_file() {
        let fixture = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/vaults/v8_passphrase.gabbro");
        let fixture_pass = b"correct horse battery staple -- gabbro fixture";
        let incoming =
            crate::api::vault::load_vault(fixture_pass, &fixture).expect("load v8 fixture");
        // The v8 canary deserializes with no per-field marks (pre-v9).
        let canary_id = "00000000-0000-0000-0000-000000000001";
        let canary = incoming
            .entries
            .iter()
            .find(|e| entry_id(e) == canary_id)
            .expect("v8 fixture has the canary entry");
        assert!(
            meta_of(canary).field_times.is_empty(),
            "a pre-v9 entry carries no field times"
        );

        // Current-format local session with a distinct entry.
        let pass = b"xversion-local-pass";
        let path = setup(
            pass,
            "xversion",
            vec![note("local-only", "Local", "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();

        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.added, 1, "the v8 canary is the one added entry");
        {
            let s = VAULT_SESSION.lock().unwrap();
            let ents = &s.as_ref().unwrap().entries;
            assert!(
                ents.iter().any(|e| entry_id(e) == "local-only"),
                "local entry preserved across the cross-version merge"
            );
            assert!(
                ents.iter().any(|e| entry_id(e) == canary_id),
                "v8 entry added without loss"
            );
        }
        teardown(&path);
    }

    // Atomic cancel: after a merge, session_cancel_sync must roll the whole sync
    // back - the merged-in entry is gone from both the session and disk, and the
    // pre-sync backup is cleared.
    #[test]
    #[serial]
    #[ignore = "production-Argon saves; run via the gate"]
    fn cancel_sync_rolls_back_to_pre_sync_state() {
        use crate::vault::serialization::VaultBody;
        let pass = b"cancel-sync-pass";
        let path = setup(
            pass,
            "cancel_rollback",
            vec![note("keep", "Keep", "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();

        let incoming = VaultBody {
            entries: vec![note("incoming-new", "New", "2026-02-01T00:00:00Z")],
            folders: vec![],
            ..Default::default()
        };
        let summary = session_merge_vault_from_body(incoming).unwrap();
        assert_eq!(summary.added, 1, "merge brought in the new entry");

        session_cancel_sync().unwrap();
        {
            let s = VAULT_SESSION.lock().unwrap();
            let sess = s.as_ref().unwrap();
            let ids: Vec<&str> = sess.entries.iter().map(entry_id).collect();
            assert_eq!(ids, vec!["keep"], "cancel discards the merged-in entry");
            assert!(
                sess.pre_sync_backup.is_none(),
                "backup cleared after cancel"
            );
        }
        let on_disk = crate::api::vault::load_vault(pass, &path).unwrap();
        let disk_ids: Vec<String> = on_disk
            .entries
            .iter()
            .map(|e| entry_id(e).to_string())
            .collect();
        assert_eq!(disk_ids, vec!["keep"], "disk rolled back to pre-sync state");
        teardown(&path);
    }

    // Committing the sync (apply_sync_decisions) clears the cancel snapshot, so a
    // later cancel is a no-op and cannot undo the committed merge.
    #[test]
    #[serial]
    #[ignore = "production-Argon saves; run via the gate"]
    fn apply_sync_decisions_clears_backup_so_cancel_is_noop() {
        use crate::vault::serialization::VaultBody;
        let pass = b"apply-clears-pass";
        let path = setup(
            pass,
            "apply_clears",
            vec![note("keep", "Keep", "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();
        let incoming = VaultBody {
            entries: vec![note("incoming-new", "New", "2026-02-01T00:00:00Z")],
            folders: vec![],
            ..Default::default()
        };
        session_merge_vault_from_body(incoming).unwrap();
        session_apply_sync_decisions(vec![], vec![], vec![], vec![], vec![]).unwrap();
        {
            let s = VAULT_SESSION.lock().unwrap();
            assert!(
                s.as_ref().unwrap().pre_sync_backup.is_none(),
                "backup cleared once the sync is committed"
            );
        }
        session_cancel_sync().unwrap(); // no-op
        {
            let s = VAULT_SESSION.lock().unwrap();
            let ids: Vec<&str> = s.as_ref().unwrap().entries.iter().map(entry_id).collect();
            assert!(
                ids.contains(&"incoming-new") && ids.contains(&"keep"),
                "cancel after commit must not undo the merge"
            );
        }
        teardown(&path);
    }

    // Leakage guard: a secret carried through a sync (merge, then cancel) is never
    // written to disk in cleartext - the vault file (and its .bak) stay sealed and
    // reopen correctly at every step.
    #[test]
    #[serial]
    #[ignore = "production-Argon saves; run via the gate"]
    fn sync_never_writes_plaintext_secret_to_disk() {
        use crate::vault::serialization::VaultBody;
        let pass = b"leak-check-pass";
        let secret = "SUPER-SECRET-do-not-leak-9XyZ";
        let assert_sealed = |path: &std::path::Path| {
            let contains =
                |bytes: &[u8]| bytes.windows(secret.len()).any(|w| w == secret.as_bytes());
            assert!(
                !contains(&std::fs::read(path).unwrap()),
                "plaintext secret on disk"
            );
            let bak = format!("{}.bak", path.display());
            if let Ok(b) = std::fs::read(&bak) {
                assert!(!contains(&b), "plaintext secret in .bak");
            }
            assert!(
                crate::api::vault::load_vault(pass, path).is_ok(),
                "file must stay a sealed, openable vault"
            );
        };

        // The secret rides as a note title (inside the encrypted body).
        let path = setup(
            pass,
            "leak",
            vec![note("s1", secret, "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();
        let incoming = VaultBody {
            entries: vec![note("incoming-new", "New", "2026-02-01T00:00:00Z")],
            folders: vec![],
            ..Default::default()
        };
        session_merge_vault_from_body(incoming).unwrap();
        assert_sealed(&path);
        session_cancel_sync().unwrap();
        assert_sealed(&path);
        teardown(&path);
    }

    // Fast auto-merge walk: load A, then fast-merge the other two (no prompts,
    // incoming always wins). Proves (1) every A-vs-C clash resolves to C's value
    // regardless of B/C order, and (2) order still matters via the delete/re-add
    // path: C tombstones `delme`, so A->B->C drops it, but A->C->B re-adds it from
    // B (additive rule: an incoming entry is re-added even past a tombstone).
    // Equivalent of `check_sync_walk_export`, for the fast path.
    #[test]
    #[serial]
    #[ignore = "fast-merge walk on the sync_test corpus (cheap Argon2); opt-in"]
    fn fast_merge_walk_incoming_wins_and_order_dependent() {
        use crate::vault::serialization::VaultBody;
        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("test_data/sync_test_vaults");
        let pass = b"0123456789a";
        let load = |n: &str| {
            crate::api::vault::load_vault(pass, &dir.join(format!("sync_test_{n}.gabbro"))).unwrap()
        };
        let a = load("A");
        let b = load("B");
        let c = load("C");

        // The four simple scalar clash fields (login-co/password, note-co/content,
        // id-co/last_name, card-co/cvv), extracted by the entry's type.
        let scalar = |ents: &[VaultEntry], id: &str| -> String {
            match ents.iter().find(|e| entry_id(e) == id).expect(id) {
                VaultEntry::Login(l) => l.password.clone(),
                VaultEntry::Note(n) => n.content.clone(),
                VaultEntry::Identity(i) => i.last_name.clone(),
                VaultEntry::Card(cc) => cc.cvv.clone(),
                _ => panic!("unexpected type for {id}"),
            }
        };
        let has = |ents: &[VaultEntry], id: &str| ents.iter().any(|e| entry_id(e) == id);

        let c_login = scalar(&c.entries, "login-co");
        let c_note = scalar(&c.entries, "note-co");
        let c_id = scalar(&c.entries, "id-co");
        let c_card = scalar(&c.entries, "card-co");

        let run = |first: &VaultBody, second: &VaultBody, suffix: &str| -> Vec<VaultEntry> {
            let path = setup(pass, suffix, a.entries.clone());
            unlock_vault(pass, path.clone()).unwrap();
            session_fast_merge_from_body(first.clone()).unwrap();
            session_fast_merge_from_body(second.clone()).unwrap();
            let ents = {
                let s = VAULT_SESSION.lock().unwrap();
                s.as_ref().unwrap().entries.clone()
            };
            teardown(&path);
            ents
        };

        let abc = run(&b, &c, "fast_abc");
        let acb = run(&c, &b, "fast_acb");

        // Incoming (C) wins every A-vs-C clash, regardless of B/C order.
        for ents in [&abc, &acb] {
            assert_eq!(scalar(ents, "login-co"), c_login, "login-co password -> C");
            assert_eq!(scalar(ents, "note-co"), c_note, "note-co content -> C");
            assert_eq!(scalar(ents, "id-co"), c_id, "id-co last_name -> C");
            assert_eq!(scalar(ents, "card-co"), c_card, "card-co cvv -> C");
        }

        // Order matters via delete/re-add: C deletes `delme`.
        assert!(!has(&abc, "delme"), "A->B->C: C's delete of delme sticks");
        assert!(
            has(&acb, "delme"),
            "A->C->B: B re-adds delme after C deleted it"
        );

        // The B-only new entry is kept in both orders.
        assert!(has(&abc, "extra-b"), "extra-b kept (A->B->C)");
        assert!(has(&acb, "extra-b"), "extra-b kept (A->C->B)");
    }

    // Hardware check for the FAST auto-merge path — the analogue of
    // `check_sync_walk_export`. Export a vault built by: import A, then Sync B and
    // Sync C both via "Merge automatically", to JSON at $GABBRO_FAST_WALK_JSON.
    // This recomputes the reference fast A->B->C merge from the same corpus in
    // process and compares by content (ignoring timestamps / field_times /
    // history, which legitimately differ run-to-run).
    #[test]
    #[serial]
    #[ignore = "validates a FAST-merge hardware export; set GABBRO_FAST_WALK_JSON to the .json path"]
    fn check_fast_sync_walk_export() {
        use std::collections::BTreeMap;
        let json_path = std::env::var("GABBRO_FAST_WALK_JSON")
            .expect("set GABBRO_FAST_WALK_JSON to the exported fast-merge json path");
        let data = std::fs::read_to_string(&json_path).expect("read export json");
        #[derive(serde::Deserialize)]
        struct Export {
            entries: Vec<VaultEntry>,
        }
        let export: Export = serde_json::from_str(&data).expect("parse export json");

        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("test_data/sync_test_vaults");
        let pass = b"0123456789a";
        let load = |n: &str| {
            crate::api::vault::load_vault(pass, &dir.join(format!("sync_test_{n}.gabbro"))).unwrap()
        };

        // Reference: fast auto-merge A, then B, then C (the README order).
        let path = setup(pass, "fast_walk_check", load("A").entries);
        unlock_vault(pass, path.clone()).unwrap();
        session_fast_merge_from_body(load("B")).unwrap();
        session_fast_merge_from_body(load("C")).unwrap();
        let reference = {
            let s = VAULT_SESSION.lock().unwrap();
            s.as_ref().unwrap().entries.clone()
        };
        teardown(&path);

        // Compare by content: clear volatile metadata that differs run-to-run.
        let normalize = |ents: &[VaultEntry]| -> BTreeMap<String, VaultEntry> {
            ents.iter()
                .map(|e| {
                    let mut e = e.clone();
                    let m = meta_of_mut(&mut e);
                    m.updated_at.clear();
                    m.created_at.clear();
                    m.field_times.clear();
                    m.history.clear();
                    (entry_id(&e).to_string(), e)
                })
                .collect()
        };
        let want = normalize(&reference);
        let got = normalize(&export.entries);

        let want_ids: Vec<&String> = want.keys().collect();
        let got_ids: Vec<&String> = got.keys().collect();
        assert_eq!(got_ids, want_ids, "export has the same set of entries");
        for (id, w) in &want {
            assert_eq!(
                got.get(id),
                Some(w),
                "entry {id} does not match the fast A->B->C reference"
            );
        }
    }

    fn setup(pass: &[u8], path_suffix: &str, entries: Vec<VaultEntry>) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push(format!("gabbro_merge_{path_suffix}.gabbro"));
        save_vault(
            &VaultBody {
                entries,
                folders: vec![String::from("Work")],
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        path
    }

    fn teardown(path: &std::path::PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    // ── recovery history: replace -> read -> restore ──────────────────────────

    #[test]
    #[serial]
    fn replace_field_with_history_records_then_restores() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "history",
            vec![note("n1", "T", "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();

        // Overwrite content via the live sync-apply path, keeping the old value
        // in recovery history.
        session_apply_sync_decisions(
            vec![],
            vec![crate::api::vault::SyncHistoryReplacementInput {
                id: "n1".into(),
                field: "content".into(),
                new_value: "new".into(),
                replaced_value: "content".into(),
            }],
            vec![],
            vec![],
            vec![],
        )
        .unwrap();

        match get_entry("n1").unwrap() {
            VaultEntry::Note(ref n) => assert_eq!(n.content, "new"),
            _ => panic!("expected Note"),
        }
        let hist = session_get_entry_history("n1".into()).unwrap();
        assert_eq!(hist.len(), 1);
        assert_eq!(hist[0].field, "content");
        assert_eq!(hist[0].value, "content");

        // Restore: field goes back, record consumed.
        session_restore_history("n1".into(), 0).unwrap();
        match get_entry("n1").unwrap() {
            VaultEntry::Note(ref n) => assert_eq!(n.content, "content"),
            _ => panic!("expected Note"),
        }
        assert!(session_get_entry_history("n1".into()).unwrap().is_empty());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn recovery_history_survives_a_disk_round_trip() {
        // The hardware sequence: a sync records history and saves; the app later
        // auto-locks and the user re-opens the vault. The record must survive
        // the disk round-trip (serialize + reload + purge), not just live in the
        // session that wrote it.
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "history_roundtrip",
            vec![note("n1", "T", "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();
        session_apply_sync_decisions(
            vec![],
            vec![crate::api::vault::SyncHistoryReplacementInput {
                id: "n1".into(),
                field: "content".into(),
                new_value: "new".into(),
                replaced_value: "old".into(),
            }],
            vec![],
            vec![],
            vec![],
        )
        .unwrap();

        // Re-open from disk, as after an auto-lock.
        unlock_vault(pass, path.clone()).unwrap();

        let hist = session_get_entry_history("n1".into()).unwrap();
        assert_eq!(hist.len(), 1, "history must survive the disk round-trip");
        assert_eq!(hist[0].value, "old");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn delete_history_drops_record_without_restoring() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "history_del",
            vec![note("n1", "T", "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();
        session_apply_sync_decisions(
            vec![],
            vec![crate::api::vault::SyncHistoryReplacementInput {
                id: "n1".into(),
                field: "content".into(),
                new_value: "new".into(),
                replaced_value: "content".into(),
            }],
            vec![],
            vec![],
            vec![],
        )
        .unwrap();

        session_delete_history("n1".into(), 0).unwrap();
        assert!(session_get_entry_history("n1".into()).unwrap().is_empty());
        // The current value is untouched by a delete.
        match get_entry("n1").unwrap() {
            VaultEntry::Note(ref n) => assert_eq!(n.content, "new"),
            _ => panic!("expected Note"),
        }
        teardown(&path);
    }

    // ── tombstone recorded on single delete ───────────────────────────────────

    #[test]
    #[serial]
    fn delete_entry_records_tombstone() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "tombstone_single",
            vec![note("n1", "Note", "2026-01-01T00:00:00Z")],
        );
        unlock_vault(pass, path.clone()).unwrap();
        session_delete_entry("n1").unwrap();

        // Reload and verify tombstone persisted
        lock_vault().unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let session = VAULT_SESSION.lock().unwrap();
        let s = session.as_ref().unwrap();
        assert!(s.entries.is_empty(), "entry must be gone");
        assert_eq!(s.deleted_ids.len(), 1);
        assert_eq!(s.deleted_ids[0].id, "n1");
        assert!(!s.deleted_ids[0].deleted_at.is_empty());

        drop(session);
        teardown(&path);
    }

    // ── tombstones recorded on bulk delete ────────────────────────────────────

    #[test]
    #[serial]
    fn bulk_delete_records_tombstones() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "tombstone_bulk",
            vec![
                note("n1", "Note 1", "2026-01-01T00:00:00Z"),
                note("n2", "Note 2", "2026-01-01T00:00:00Z"),
            ],
        );
        unlock_vault(pass, path.clone()).unwrap();
        session_delete_entries_no_save(&[String::from("n1"), String::from("n2")]).unwrap();
        session_save().unwrap();

        lock_vault().unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let session = VAULT_SESSION.lock().unwrap();
        let s = session.as_ref().unwrap();
        assert!(s.entries.is_empty());
        let ids: Vec<&str> = s.deleted_ids.iter().map(|d| d.id.as_str()).collect();
        assert!(ids.contains(&"n1"));
        assert!(ids.contains(&"n2"));

        drop(session);
        teardown(&path);
    }

    // ── merge: addition (entry only in incoming) ──────────────────────────────

    #[test]
    #[serial]
    fn merge_adds_incoming_only_entry() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "add",
            vec![note("local-1", "Local", "2026-01-01T00:00:00Z")],
        );

        let incoming = VaultBody {
            entries: vec![
                note("local-1", "Local", "2026-01-01T00:00:00Z"),
                note("remote-1", "Remote", "2026-01-02T00:00:00Z"),
            ],
            folders: vec![],
            ..Default::default()
        };

        unlock_vault(pass, path.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.added, 1);
        assert_eq!(summary.updated, 0);
        assert!(summary.pending_deletes.is_empty());
        assert!(summary.folder_conflicts.is_empty());

        let ids: Vec<String> = list_entry_summaries()
            .unwrap()
            .into_iter()
            .map(|s| s.id)
            .collect();
        assert!(ids.contains(&String::from("local-1")));
        assert!(ids.contains(&String::from("remote-1")));

        teardown(&path);
    }

    // ── merge: edit conflict — last-write-wins ────────────────────────────────

    #[test]
    #[serial]
    fn merge_last_write_wins_incoming_newer() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "lww_remote",
            vec![note("shared", "Old title", "2026-01-01T00:00:00Z")],
        );

        let incoming = VaultBody {
            entries: vec![note("shared", "New title", "2026-01-02T00:00:00Z")],
            folders: vec![],
            ..Default::default()
        };

        unlock_vault(pass, path.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.added, 0);
        assert_eq!(summary.updated, 1);
        assert!(summary.pending_deletes.is_empty());

        let entry = get_entry("shared").unwrap();
        match entry {
            VaultEntry::Note(ref n) => assert_eq!(n.title, "New title"),
            _ => panic!("expected Note"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn merge_last_write_wins_local_newer() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "lww_local",
            vec![note("shared", "Local newer", "2026-01-03T00:00:00Z")],
        );

        let incoming = VaultBody {
            entries: vec![note("shared", "Remote older", "2026-01-01T00:00:00Z")],
            folders: vec![],
            ..Default::default()
        };

        unlock_vault(pass, path.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.updated, 0, "local wins — no update counted");
        let entry = get_entry("shared").unwrap();
        match entry {
            VaultEntry::Note(ref n) => assert_eq!(n.title, "Local newer"),
            _ => panic!("expected Note"),
        }

        teardown(&path);
    }

    // ── merge: incoming tombstone → pending_delete (user consent required) ──────

    #[test]
    #[serial]
    fn merge_incoming_tombstone_becomes_pending_delete() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "tomb_pending",
            vec![note("victim", "Deleted remotely", "2026-01-01T00:00:00Z")],
        );

        // Incoming deleted "victim" — requires user consent, not silent delete.
        let incoming = VaultBody {
            entries: vec![],
            deleted_ids: vec![tombstone("victim", "2026-01-02T00:00:00Z")],
            ..Default::default()
        };

        unlock_vault(pass, path.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.pending_deletes.len(), 1);
        assert_eq!(summary.pending_deletes[0].id, "victim");
        assert_eq!(summary.pending_deletes[0].title, "Deleted remotely");
        // Entry must still be present — not deleted without user consent.
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn merge_local_tombstone_incoming_entry_added_via_union() {
        let pass = b"merge-test-pass";
        // Local vault has a tombstone for "victim" but no live entry.
        let body_with_tombstone = VaultBody {
            entries: vec![],
            deleted_ids: vec![tombstone("victim", "2026-01-02T00:00:00Z")],
            folders: vec![],
            ..Default::default()
        };
        let mut path = temp_dir();
        path.push("gabbro_merge_local_tomb_union.gabbro");
        save_vault(&body_with_tombstone, pass, &path).unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        // Incoming has the entry — UNION means it is always added.
        let incoming = VaultBody {
            entries: vec![note("victim", "Added remotely", "2026-01-01T00:00:00Z")],
            deleted_ids: vec![],
            ..Default::default()
        };

        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.added, 1);
        assert!(summary.pending_deletes.is_empty());
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        teardown(&path);
    }

    // ── merge: incoming tombstone + local entry → pending_delete regardless of timestamp

    #[test]
    #[serial]
    fn merge_incoming_tombstone_on_locally_edited_entry_is_pending_delete() {
        let pass = b"merge-test-pass";
        // Local entry edited AFTER the remote deletion timestamp.
        let path = setup(
            pass,
            "tomb_pending_newer",
            vec![note("survivor", "Edited locally", "2026-01-03T00:00:00Z")],
        );

        let incoming = VaultBody {
            entries: vec![],
            deleted_ids: vec![tombstone("survivor", "2026-01-02T00:00:00Z")],
            ..Default::default()
        };

        unlock_vault(pass, path.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        // Regardless of timestamps, incoming tombstone → pending_delete (user consent).
        assert_eq!(summary.pending_deletes.len(), 1);
        assert_eq!(summary.pending_deletes[0].title, "Edited locally");
        // Entry must still be present.
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn merge_incoming_entry_with_local_tombstone_added_via_union() {
        let pass = b"merge-test-pass";
        // Local has a tombstone for "survivor", incoming has the entry (any timestamp).
        let body_with_tombstone = VaultBody {
            entries: vec![],
            deleted_ids: vec![tombstone("survivor", "2026-01-01T00:00:00Z")],
            folders: vec![],
            ..Default::default()
        };
        let mut path = temp_dir();
        path.push("gabbro_merge_inc_entry_local_tomb.gabbro");
        save_vault(&body_with_tombstone, pass, &path).unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let incoming = VaultBody {
            entries: vec![note("survivor", "Edited remotely", "2026-01-02T00:00:00Z")],
            deleted_ids: vec![],
            ..Default::default()
        };

        let summary = session_merge_vault_from_body(incoming).unwrap();

        // UNION: incoming entry is added; no pending_delete (tombstone is local, not incoming).
        assert_eq!(summary.added, 1);
        assert!(summary.pending_deletes.is_empty());
        assert_eq!(list_entry_summaries().unwrap().len(), 1);

        teardown(&path);
    }

    // ── merge: folder union ───────────────────────────────────────────────────

    #[test]
    #[serial]
    fn merge_unions_folders() {
        let pass = b"merge-test-pass";
        let mut path = temp_dir();
        path.push("gabbro_merge_folders.gabbro");
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
        unlock_vault(pass, path.clone()).unwrap();

        let incoming = VaultBody {
            folders: vec![String::from("Private"), String::from("Personal")],
            entries: vec![],
            ..Default::default()
        };

        session_merge_vault_from_body(incoming).unwrap();

        let folders = session_list_folders().unwrap();
        assert!(folders.contains(&String::from("Work")));
        assert!(folders.contains(&String::from("Private")));
        assert!(folders.contains(&String::from("Personal")));
        assert_eq!(
            folders.iter().filter(|f| *f == "Private").count(),
            1,
            "dedup: Private must appear only once"
        );

        teardown(&path);
    }

    // ── merge: identical vaults → zero-change summary ─────────────────────────

    #[test]
    #[serial]
    fn merge_identical_vaults_returns_zero_summary() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "identical",
            vec![note("n1", "Same", "2026-01-01T00:00:00Z")],
        );

        let incoming = VaultBody {
            entries: vec![note("n1", "Same", "2026-01-01T00:00:00Z")],
            folders: vec![String::from("Work")],
            ..Default::default()
        };

        unlock_vault(pass, path.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.added, 0);
        assert_eq!(summary.updated, 0);
        assert!(summary.pending_deletes.is_empty());
        assert!(summary.folder_conflicts.is_empty());

        teardown(&path);
    }

    // ── merge: tombstone union (dedup, keep newer) ────────────────────────────

    #[test]
    #[serial]
    fn merge_unions_tombstones_keeping_newer() {
        let pass = b"merge-test-pass";
        let body = VaultBody {
            entries: vec![],
            deleted_ids: vec![
                tombstone("a", "2026-01-01T00:00:00Z"),
                tombstone("b", "2026-01-01T00:00:00Z"),
            ],
            folders: vec![],
            ..Default::default()
        };
        let mut path = temp_dir();
        path.push("gabbro_merge_tombstone_union.gabbro");
        save_vault(&body, pass, &path).unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let incoming = VaultBody {
            entries: vec![],
            deleted_ids: vec![
                tombstone("b", "2026-01-02T00:00:00Z"), // newer for "b"
                tombstone("c", "2026-01-01T00:00:00Z"), // new id
            ],
            ..Default::default()
        };

        session_merge_vault_from_body(incoming).unwrap();

        lock_vault().unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let session = VAULT_SESSION.lock().unwrap();
        let s = session.as_ref().unwrap();
        let tombstone_map: std::collections::HashMap<&str, &str> = s
            .deleted_ids
            .iter()
            .map(|d| (d.id.as_str(), d.deleted_at.as_str()))
            .collect();

        assert_eq!(tombstone_map.len(), 3, "a, b, c must all be present");
        assert_eq!(tombstone_map["a"], "2026-01-01T00:00:00Z");
        assert_eq!(
            tombstone_map["b"], "2026-01-02T00:00:00Z",
            "newer timestamp must win"
        );
        assert_eq!(tombstone_map["c"], "2026-01-01T00:00:00Z");

        drop(session);
        teardown(&path);
    }

    // ── merge: folder assignment conflict ─────────────────────────────────────

    #[test]
    #[serial]
    fn merge_surfaces_folder_conflict_for_same_uuid_different_folder() {
        let pass = b"merge-test-pass";
        let mut path = temp_dir();
        path.push("gabbro_merge_folder_conflict.gabbro");
        save_vault(
            &VaultBody {
                folders: vec![String::from("Work"), String::from("Personal")],
                entries: vec![note_with_folder(
                    "shared",
                    "Shared entry",
                    "2026-01-01T00:00:00Z",
                    "Work",
                )],
                ..Default::default()
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let incoming = VaultBody {
            folders: vec![String::from("Work"), String::from("Personal")],
            entries: vec![note_with_folder(
                "shared",
                "Shared entry",
                "2026-01-01T00:00:00Z",
                "Personal",
            )],
            ..Default::default()
        };

        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(summary.folder_conflicts.len(), 1);
        assert_eq!(summary.folder_conflicts[0].id, "shared");
        assert_eq!(summary.folder_conflicts[0].local_folder, "Work");
        assert_eq!(summary.folder_conflicts[0].incoming_folder, "Personal");
        assert!(summary.pending_deletes.is_empty());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn merge_no_folder_conflict_when_folders_match() {
        let pass = b"merge-test-pass";
        let path = setup(
            pass,
            "no_folder_conflict",
            vec![note_with_folder(
                "shared",
                "Shared",
                "2026-01-01T00:00:00Z",
                "Work",
            )],
        );

        let incoming = VaultBody {
            folders: vec![String::from("Work")],
            entries: vec![note_with_folder(
                "shared",
                "Shared",
                "2026-01-01T00:00:00Z",
                "Work",
            )],
            ..Default::default()
        };

        unlock_vault(pass, path.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert!(summary.folder_conflicts.is_empty());

        teardown(&path);
    }

    // ── vault_updated_at is stamped on every save ─────────────────────────────

    #[test]
    #[serial]
    fn vault_updated_at_is_set_after_save() {
        let pass = b"merge-test-pass";
        let path = setup(pass, "updated_at", vec![]);
        unlock_vault(pass, path.clone()).unwrap();

        // Trigger a save via merge with an empty incoming vault.
        let incoming = VaultBody {
            ..Default::default()
        };
        session_merge_vault_from_body(incoming).unwrap();

        lock_vault().unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let session = VAULT_SESSION.lock().unwrap();
        let _ = session.as_ref().unwrap();
        drop(session);

        // Load the body directly to inspect vault_updated_at.
        let loaded_body = crate::api::vault::load_vault(pass, &path).unwrap();
        assert!(
            !loaded_body.vault_updated_at.is_empty(),
            "vault_updated_at must be stamped after save"
        );

        teardown(&path);
    }
}

#[cfg(test)]
mod export_sync_tests {
    use super::*;
    use crate::api::vault::{load_vault, save_vault};
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn note(id: &str, updated_at: &str) -> VaultEntry {
        VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: id.to_string(),
                created_at: String::from("2026-01-01T00:00:00Z"),
                updated_at: updated_at.to_string(),
                folder: String::from(""),
            },
            title: format!("Note {id}"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        })
    }

    fn note_in_folder(id: &str, folder: &str) -> VaultEntry {
        VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: id.to_string(),
                created_at: String::from("2026-01-01T00:00:00Z"),
                updated_at: String::from("2026-01-01T00:00:00Z"),
                folder: folder.to_string(),
            },
            title: format!("Note {id}"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        })
    }

    fn teardown(paths: &[std::path::PathBuf]) {
        let _ = lock_vault();
        for p in paths {
            let _ = std::fs::remove_file(p);
            let _ = std::fs::remove_file(p.with_extension("gabbro.sha256"));
            let _ = std::fs::remove_file(format!("{}.bak", p.display()));
        }
    }

    // ── test 1: deleted_ids round-trips through export ────────────────────────

    #[test]
    #[serial]
    fn export_roundtrips_deleted_ids() {
        let pass = b"export-sync-pass";
        let mut vault_path = temp_dir();
        vault_path.push("gabbro_export_sync_tomb.gabbro");
        let mut export_path = temp_dir();
        export_path.push("gabbro_export_sync_tomb_out.gabbro");

        save_vault(
            &VaultBody {
                entries: vec![note("n1", "2026-01-01T00:00:00Z")],
                ..Default::default()
            },
            pass,
            &vault_path,
        )
        .unwrap();
        unlock_vault(pass, vault_path.clone()).unwrap();
        session_delete_entry("n1").unwrap();
        session_export_vault(export_path.clone()).unwrap();

        let body = load_vault(pass, &export_path).unwrap();
        assert_eq!(
            body.deleted_ids.len(),
            1,
            "tombstone must be present in export"
        );
        assert_eq!(body.deleted_ids[0].id, "n1");

        teardown(&[vault_path, export_path]);
    }

    // ── test 2: folder names round-trip through export and merge ─────────────

    #[test]
    #[serial]
    fn export_folder_names_merge_into_receiving_vault() {
        let pass = b"export-sync-pass";
        let mut vault_a = temp_dir();
        vault_a.push("gabbro_export_sync_folder_a.gabbro");
        let mut vault_b = temp_dir();
        vault_b.push("gabbro_export_sync_folder_b.gabbro");
        let mut export_path = temp_dir();
        export_path.push("gabbro_export_sync_folder_out.gabbro");

        // Vault A: folder "Work" with one entry
        save_vault(
            &VaultBody {
                folders: vec![String::from("Work")],
                entries: vec![note_in_folder("n1", "Work")],
                ..Default::default()
            },
            pass,
            &vault_a,
        )
        .unwrap();
        unlock_vault(pass, vault_a.clone()).unwrap();
        session_export_vault(export_path.clone()).unwrap();
        lock_vault().unwrap();

        // Vault B: no folders
        save_vault(
            &VaultBody {
                ..Default::default()
            },
            pass,
            &vault_b,
        )
        .unwrap();
        unlock_vault(pass, vault_b.clone()).unwrap();

        let incoming = load_vault(pass, &export_path).unwrap();
        session_merge_vault_from_body(incoming).unwrap();

        let folders = session_list_folders().unwrap();
        assert!(
            folders.contains(&String::from("Work")),
            "folder 'Work' must appear in vault B after merge"
        );

        teardown(&[vault_a, vault_b, export_path]);
    }

    // ── test 3: tombstone in export causes deletion on receiving vault ────────

    #[test]
    #[serial]
    fn export_tombstone_causes_delete_on_receiving_vault() {
        let pass = b"export-sync-pass";
        let mut vault_a = temp_dir();
        vault_a.push("gabbro_export_sync_del_a.gabbro");
        let mut vault_b = temp_dir();
        vault_b.push("gabbro_export_sync_del_b.gabbro");
        let mut export_path = temp_dir();
        export_path.push("gabbro_export_sync_del_out.gabbro");

        let shared = note("n1", "2026-01-01T00:00:00Z");

        // Vault A: shared entry then deleted (creates tombstone with current timestamp)
        save_vault(
            &VaultBody {
                entries: vec![shared.clone()],
                ..Default::default()
            },
            pass,
            &vault_a,
        )
        .unwrap();
        unlock_vault(pass, vault_a.clone()).unwrap();
        session_delete_entry("n1").unwrap();
        session_export_vault(export_path.clone()).unwrap();
        lock_vault().unwrap();

        // Vault B: still has the shared entry
        save_vault(
            &VaultBody {
                entries: vec![shared],
                ..Default::default()
            },
            pass,
            &vault_b,
        )
        .unwrap();
        unlock_vault(pass, vault_b.clone()).unwrap();

        let incoming = load_vault(pass, &export_path).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();

        assert_eq!(
            summary.pending_deletes.len(),
            1,
            "tombstone must create a pending_delete requiring user consent"
        );
        assert_eq!(summary.pending_deletes[0].id, "n1");
        // Entry must still be present — not deleted without explicit user consent.
        let ids: Vec<String> = list_entry_summaries()
            .unwrap()
            .into_iter()
            .map(|s| s.id)
            .collect();
        assert!(
            ids.contains(&String::from("n1")),
            "entry must still be present in vault B pending user consent"
        );

        teardown(&[vault_a, vault_b, export_path]);
    }
}

// ── Multi-device sync fuzz proof (granular sync, v9) ──────────────────────────
//
// Deterministic fuzzer for the field-level merge. Each pass starts from a fixed
// 12-entry base (all 6 types), forks 3 device copies, and applies random divergent
// edits/adds/deletes with globally-unique timestamps across EVERY mergeable field:
// scalars (title, password, notes, card fields, ...), custom k:v pairs, AND
// attachments. The copies are then converged in two random orders. Invariants:
//   * no loss / correct LWW: converged values equal an INDEPENDENT oracle
//     (newest value per field, computed directly from device states, not via merge);
//   * order-independent: both convergence orders give the same result;
//   * convergence: re-merging the converged set with any device is stable.
// Field keys match exactly what `merge_entry_pair` reads, so this exercises the
// real per-field decisions. Runs in the normal (fast) suite — no crypto.
#[cfg(test)]
mod sync_fuzz {
    use super::*;
    use crate::vault::entry::{
        CardEntry, CustomEntry, CustomField, EntryAttachment, FileEntry, IdentityEntry, LoginEntry,
        NoteEntry,
    };
    use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

    // SplitMix64 — deterministic, dependency-free.
    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
            z ^ (z >> 31)
        }
        fn below(&mut self, n: usize) -> usize {
            (self.next() % n as u64) as usize
        }
    }

    fn ts_str(ts: u64) -> String {
        format!("{ts:020}")
    }
    fn cf(label: &str, value: &str) -> CustomField {
        CustomField {
            label: label.to_string(),
            value: value.to_string(),
            hidden: false,
        }
    }
    // Distinguish Option::None from any real Some(_) in the value oracle.
    fn opt_repr(o: &Option<String>) -> String {
        match o {
            None => String::from("\u{1}NONE"),
            Some(s) => s.clone(),
        }
    }

    // Scalar field names per type — identical to the keys merge_entry_pair uses.
    fn scalar_keys(e: &VaultEntry) -> &'static [&'static str] {
        match e {
            VaultEntry::Login(_) => &[
                "title", "url", "username", "password", "notes", "app_id", "email",
            ],
            VaultEntry::Note(_) => &["title", "content"],
            VaultEntry::Identity(_) => &["first_name", "last_name", "email", "phone", "address"],
            VaultEntry::Card(_) => &[
                "card_name",
                "status",
                "cardholder_name",
                "card_number",
                "expiry",
                "cvv",
                "credit_limit",
                "card_account_number",
                "payment_network",
                "pin",
                "bank_name",
                "transaction_password",
                "notes",
            ],
            VaultEntry::File(_) => &["filename", "data", "notes"],
            VaultEntry::Custom(_) => &["title"],
        }
    }

    fn scalar_repr(e: &VaultEntry, key: &str) -> String {
        match e {
            VaultEntry::Login(x) => match key {
                "title" => x.title.clone(),
                "url" => x.url.clone(),
                "username" => x.username.clone(),
                "password" => x.password.clone(),
                "notes" => opt_repr(&x.notes),
                "app_id" => opt_repr(&x.app_id),
                "email" => opt_repr(&x.email),
                _ => unreachable!(),
            },
            VaultEntry::Note(x) => match key {
                "title" => x.title.clone(),
                "content" => x.content.clone(),
                _ => unreachable!(),
            },
            VaultEntry::Identity(x) => match key {
                "first_name" => x.first_name.clone(),
                "last_name" => x.last_name.clone(),
                "email" => x.email.clone(),
                "phone" => opt_repr(&x.phone),
                "address" => opt_repr(&x.address),
                _ => unreachable!(),
            },
            VaultEntry::Card(x) => match key {
                "card_name" => opt_repr(&x.card_name),
                "status" => x.status.clone(),
                "cardholder_name" => x.cardholder_name.clone(),
                "card_number" => x.card_number.clone(),
                "expiry" => x.expiry.clone(),
                "cvv" => x.cvv.clone(),
                "credit_limit" => opt_repr(&x.credit_limit),
                "card_account_number" => opt_repr(&x.card_account_number),
                "payment_network" => opt_repr(&x.payment_network),
                "pin" => opt_repr(&x.pin),
                "bank_name" => opt_repr(&x.bank_name),
                "transaction_password" => opt_repr(&x.transaction_password),
                "notes" => opt_repr(&x.notes),
                _ => unreachable!(),
            },
            VaultEntry::File(x) => match key {
                "filename" => x.filename.clone(),
                "data" => format!("{:?}", x.data),
                "notes" => opt_repr(&x.notes),
                _ => unreachable!(),
            },
            VaultEntry::Custom(x) => match key {
                "title" => x.title.clone(),
                _ => unreachable!(),
            },
        }
    }

    fn set_scalar(e: &mut VaultEntry, key: &str, value: &str) {
        let s = value.to_string();
        let some = Some(value.to_string());
        match e {
            VaultEntry::Login(x) => match key {
                "title" => x.title = s,
                "url" => x.url = s,
                "username" => x.username = s,
                "password" => x.password = s,
                "notes" => x.notes = some,
                "app_id" => x.app_id = some,
                "email" => x.email = some,
                _ => unreachable!(),
            },
            VaultEntry::Note(x) => match key {
                "title" => x.title = s,
                "content" => x.content = s,
                _ => unreachable!(),
            },
            VaultEntry::Identity(x) => match key {
                "first_name" => x.first_name = s,
                "last_name" => x.last_name = s,
                "email" => x.email = s,
                "phone" => x.phone = some,
                "address" => x.address = some,
                _ => unreachable!(),
            },
            VaultEntry::Card(x) => match key {
                "card_name" => x.card_name = some,
                "status" => x.status = s,
                "cardholder_name" => x.cardholder_name = s,
                "card_number" => x.card_number = s,
                "expiry" => x.expiry = s,
                "cvv" => x.cvv = s,
                "credit_limit" => x.credit_limit = some,
                "card_account_number" => x.card_account_number = some,
                "payment_network" => x.payment_network = some,
                "pin" => x.pin = some,
                "bank_name" => x.bank_name = some,
                "transaction_password" => x.transaction_password = some,
                "notes" => x.notes = some,
                _ => unreachable!(),
            },
            VaultEntry::File(x) => match key {
                "filename" => x.filename = s,
                "data" => x.data = value.as_bytes().to_vec(),
                "notes" => x.notes = some,
                _ => unreachable!(),
            },
            VaultEntry::Custom(x) => match key {
                "title" => x.title = s,
                _ => unreachable!(),
            },
        }
    }

    fn has_attachments(e: &VaultEntry) -> bool {
        !matches!(e, VaultEntry::File(_))
    }
    fn att_vec(e: &VaultEntry) -> &[EntryAttachment] {
        match e {
            VaultEntry::Login(x) => &x.attachments,
            VaultEntry::Note(x) => &x.attachments,
            VaultEntry::Identity(x) => &x.attachments,
            VaultEntry::Card(x) => &x.attachments,
            VaultEntry::Custom(x) => &x.attachments,
            VaultEntry::File(_) => &[],
        }
    }
    fn att_vec_mut(e: &mut VaultEntry) -> &mut Vec<EntryAttachment> {
        match e {
            VaultEntry::Login(x) => &mut x.attachments,
            VaultEntry::Note(x) => &mut x.attachments,
            VaultEntry::Identity(x) => &mut x.attachments,
            VaultEntry::Card(x) => &mut x.attachments,
            VaultEntry::Custom(x) => &mut x.attachments,
            VaultEntry::File(_) => unreachable!(),
        }
    }
    fn attachment_name(e: &VaultEntry, uuid: &str) -> Option<String> {
        att_vec(e)
            .iter()
            .find(|a| a.uuid == uuid)
            .map(|a| a.name.clone())
    }
    fn set_att(e: &mut VaultEntry, uuid: &str, name: &str) {
        let v = att_vec_mut(e);
        if let Some(a) = v.iter_mut().find(|a| a.uuid == uuid) {
            a.name = name.to_string();
        } else {
            v.push(EntryAttachment {
                uuid: uuid.to_string(),
                name: name.to_string(),
                kind: String::from("text"),
                data: vec![],
            });
        }
    }

    fn entry_pairs(e: &VaultEntry) -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        match e {
            VaultEntry::Custom(x) => {
                for (k, f) in &x.fields {
                    m.insert(k.clone(), f.value.clone());
                }
            }
            VaultEntry::Login(x) => collect(&x.custom_fields, &mut m),
            VaultEntry::Note(x) => collect(&x.custom_fields, &mut m),
            VaultEntry::Identity(x) => collect(&x.custom_fields, &mut m),
            VaultEntry::Card(x) => collect(&x.custom_fields, &mut m),
            VaultEntry::File(x) => collect(&x.custom_fields, &mut m),
        }
        m
    }
    fn collect(v: &[CustomField], m: &mut BTreeMap<String, String>) {
        for f in v {
            m.insert(f.label.clone(), f.value.clone());
        }
    }
    fn custom_vec_mut(e: &mut VaultEntry) -> &mut Vec<CustomField> {
        match e {
            VaultEntry::Login(x) => &mut x.custom_fields,
            VaultEntry::Note(x) => &mut x.custom_fields,
            VaultEntry::Identity(x) => &mut x.custom_fields,
            VaultEntry::Card(x) => &mut x.custom_fields,
            VaultEntry::File(x) => &mut x.custom_fields,
            VaultEntry::Custom(_) => unreachable!(),
        }
    }
    fn set_pair(e: &mut VaultEntry, label: &str, value: &str) {
        if let VaultEntry::Custom(x) = e {
            x.fields.insert(label.to_string(), cf(label, value));
        } else {
            let v = custom_vec_mut(e);
            if let Some(f) = v.iter_mut().find(|f| f.label == label) {
                f.value = value.to_string();
            } else {
                v.push(cf(label, value));
            }
        }
    }
    fn del_pair(e: &mut VaultEntry, label: &str) {
        if let VaultEntry::Custom(x) = e {
            x.fields.shift_remove(label);
        } else {
            custom_vec_mut(e).retain(|f| f.label != label);
        }
    }
    fn del_att(e: &mut VaultEntry, uuid: &str) {
        att_vec_mut(e).retain(|a| a.uuid != uuid);
    }

    // Every field key currently on an entry: scalars + present pairs + attachments.
    fn all_field_keys(e: &VaultEntry) -> Vec<String> {
        let mut keys: Vec<String> = scalar_keys(e).iter().map(|s| s.to_string()).collect();
        for label in entry_pairs(e).keys() {
            keys.push(format!("custom_fields:{label}"));
        }
        for a in att_vec(e) {
            keys.push(format!("attachments:{}", a.uuid));
        }
        keys
    }

    // Uniform value getter: scalars always present; collection items only if present.
    fn field_value(e: &VaultEntry, key: &str) -> Option<String> {
        if let Some(label) = key.strip_prefix("custom_fields:") {
            return entry_pairs(e).get(label).cloned();
        }
        if let Some(uuid) = key.strip_prefix("attachments:") {
            return attachment_name(e, uuid);
        }
        Some(scalar_repr(e, key))
    }

    fn stamp_all(e: &mut VaultEntry, ts: u64) {
        let keys = all_field_keys(e);
        let meta = meta_of_mut(e);
        for k in keys {
            meta.field_times.insert(k, ts);
        }
    }

    fn base_vault() -> Vec<VaultEntry> {
        let pairs = || vec![cf("k0", "v0"), cf("k1", "v1")];
        let att = || {
            vec![EntryAttachment {
                uuid: String::from("a0"),
                name: String::from("att0"),
                kind: String::from("text"),
                data: vec![],
            }]
        };
        let blank_meta = |id: &str| EntryMeta {
            id: id.to_string(),
            created_at: ts_str(1),
            updated_at: ts_str(1),
            folder: String::new(),
            field_times: BTreeMap::new(),
            history: Vec::new(),
        };
        let mut out = Vec::new();
        for i in 0..2 {
            out.push(VaultEntry::Login(LoginEntry {
                meta: blank_meta(&format!("login-{i}")),
                title: String::from("L"),
                url: String::from("http://x"),
                username: String::from("u"),
                password: String::from("p"),
                notes: None,
                custom_fields: pairs(),
                attachments: att(),
                app_id: None,
                email: None,
            }));
            out.push(VaultEntry::Note(NoteEntry {
                meta: blank_meta(&format!("note-{i}")),
                title: String::from("N"),
                content: String::from("c"),
                custom_fields: pairs(),
                attachments: att(),
            }));
            out.push(VaultEntry::Identity(IdentityEntry {
                meta: blank_meta(&format!("identity-{i}")),
                first_name: String::from("F"),
                last_name: String::from("L"),
                email: String::from("e@example.com"),
                phone: None,
                address: None,
                custom_fields: pairs(),
                attachments: att(),
            }));
            out.push(VaultEntry::Card(CardEntry {
                meta: blank_meta(&format!("card-{i}")),
                card_name: None,
                status: String::from("active"),
                cardholder_name: String::from("CH"),
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
                custom_fields: pairs(),
                attachments: att(),
            }));
            out.push(VaultEntry::File(FileEntry {
                meta: blank_meta(&format!("file-{i}")),
                filename: String::from("f.bin"),
                data: vec![1, 2, 3],
                notes: None,
                custom_fields: pairs(),
            }));
            let mut fields = indexmap::IndexMap::new();
            fields.insert(String::from("k0"), cf("k0", "v0"));
            fields.insert(String::from("k1"), cf("k1", "v1"));
            out.push(VaultEntry::Custom(CustomEntry {
                meta: blank_meta(&format!("custom-{i}")),
                title: String::from("C"),
                fields,
                attachments: att(),
            }));
        }
        // Stamp every base field at ts=1 so the oracle is pure max-timestamp.
        for e in out.iter_mut() {
            stamp_all(e, 1);
        }
        out
    }

    fn set_field(e: &mut VaultEntry, key: &str, value: &str, ts: u64) {
        if let Some(label) = key.strip_prefix("custom_fields:") {
            set_pair(e, label, value);
        } else if let Some(uuid) = key.strip_prefix("attachments:") {
            set_att(e, uuid, value);
        } else {
            set_scalar(e, key, value);
        }
        let meta = meta_of_mut(e);
        meta.field_times.insert(key.to_string(), ts);
        meta.field_times.remove(&format!("del:{key}"));
        meta.updated_at = ts_str(ts);
    }
    fn del_field(e: &mut VaultEntry, key: &str, ts: u64) {
        if let Some(label) = key.strip_prefix("custom_fields:") {
            del_pair(e, label);
        } else if let Some(uuid) = key.strip_prefix("attachments:") {
            del_att(e, uuid);
        }
        let meta = meta_of_mut(e);
        meta.field_times.insert(format!("del:{key}"), ts);
        meta.field_times.remove(key);
        meta.updated_at = ts_str(ts);
    }

    fn mutate(dev: &mut [VaultEntry], rng: &mut Rng, counter: &mut u64) {
        let ei = rng.below(dev.len());
        let mut cands = all_field_keys(&dev[ei]);
        cands.push(String::from("custom_fields:k2"));
        cands.push(String::from("custom_fields:k3"));
        if has_attachments(&dev[ei]) {
            cands.push(String::from("attachments:a2"));
            cands.push(String::from("attachments:a3"));
        }
        let key = cands[rng.below(cands.len())].clone();
        *counter += 1;
        let ts = *counter;
        let is_collection = key.starts_with("custom_fields:") || key.starts_with("attachments:");
        if is_collection && rng.below(10) < 3 {
            del_field(&mut dev[ei], &key, ts);
        } else {
            set_field(&mut dev[ei], &key, &format!("val-{ts}"), ts);
        }
    }

    // Sync b into a: union by id, granular merge for shared ids. Returns the merged
    // set AND the (id, field) collisions surfaced by the merge.
    type FieldKey = (String, String);
    fn sync_sets(a: &[VaultEntry], b: &[VaultEntry]) -> (Vec<VaultEntry>, Vec<FieldKey>) {
        let a_by: HashMap<&str, &VaultEntry> =
            a.iter().map(|e| (meta_of(e).id.as_str(), e)).collect();
        let b_by: HashMap<&str, &VaultEntry> =
            b.iter().map(|e| (meta_of(e).id.as_str(), e)).collect();
        let mut ids = Vec::new();
        let mut seen = HashSet::new();
        for e in a.iter().chain(b.iter()) {
            let id = meta_of(e).id.clone();
            if seen.insert(id.clone()) {
                ids.push(id);
            }
        }
        let mut out = Vec::new();
        let mut conflicts = Vec::new();
        for id in &ids {
            match (a_by.get(id.as_str()), b_by.get(id.as_str())) {
                (Some(x), Some(y)) => {
                    let (m, cs, _pending, _bo) = merge_entry_pair(x, y);
                    for c in cs {
                        conflicts.push((c.id.clone(), c.field.clone()));
                    }
                    out.push(m);
                }
                (Some(x), None) => out.push((*x).clone()),
                (None, Some(y)) => out.push((*y).clone()),
                (None, None) => {}
            }
        }
        (out, conflicts)
    }
    fn converge(
        devices: &[Vec<VaultEntry>],
        order: &[usize],
    ) -> (Vec<VaultEntry>, BTreeSet<FieldKey>) {
        let mut acc = devices[order[0]].clone();
        let mut conflicts = BTreeSet::new();
        for &i in &order[1..] {
            let (next, cs) = sync_sets(&acc, &devices[i]);
            conflicts.extend(cs);
            acc = next;
        }
        (acc, conflicts)
    }

    // INDEPENDENT oracle, computed straight from device states (never via the merge):
    // for each (entry, field), look at which devices EDITED it (carry an edit-stamp)
    // and their values.
    //   edited on 0 or 1 distinct value -> agreed/additive: one expected value.
    //   edited to 2+ distinct values    -> a collision the merge must surface.
    #[allow(clippy::type_complexity)]
    fn oracle(
        devices: &[Vec<VaultEntry>],
    ) -> (
        BTreeMap<FieldKey, String>,
        BTreeSet<FieldKey>,
        HashMap<FieldKey, HashSet<String>>,
    ) {
        let mut any_vals: HashMap<FieldKey, HashSet<String>> = HashMap::new();
        let mut editor_vals: HashMap<FieldKey, HashSet<String>> = HashMap::new();
        for dev in devices {
            for e in dev {
                let id = meta_of(e).id.clone();
                let ft = &meta_of(e).field_times;
                for key in all_field_keys(e) {
                    if let Some(v) = field_value(e, &key) {
                        let k = (id.clone(), key.clone());
                        any_vals.entry(k.clone()).or_default().insert(v.clone());
                        if ft.contains_key(&key) {
                            editor_vals.entry(k).or_default().insert(v);
                        }
                    }
                }
            }
        }
        let mut single = BTreeMap::new();
        let mut conflicts = BTreeSet::new();
        let mut allowed = HashMap::new();
        for (k, anyset) in any_vals {
            let evals = editor_vals.remove(&k).unwrap_or_default();
            if evals.len() >= 2 {
                conflicts.insert(k.clone());
                allowed.insert(k, evals);
            } else if evals.len() == 1 {
                single.insert(k, evals.into_iter().next().unwrap());
            } else {
                // never edited: the base value (identical across devices).
                single.insert(k, anyset.into_iter().next().unwrap());
            }
        }
        (single, conflicts, allowed)
    }
    fn result_values(entries: &[VaultEntry]) -> BTreeMap<(String, String), String> {
        let mut m = BTreeMap::new();
        for e in entries {
            let id = meta_of(e).id.clone();
            for key in all_field_keys(e) {
                if let Some(value) = field_value(e, &key) {
                    m.insert((id.clone(), key), value);
                }
            }
        }
        m
    }

    fn perm(n: usize, rng: &mut Rng) -> Vec<usize> {
        let mut v: Vec<usize> = (0..n).collect();
        for i in (1..n).rev() {
            let j = rng.below(i + 1);
            v.swap(i, j);
        }
        v
    }

    #[test]
    fn fuzz_multi_device_sync_converges_without_loss() {
        const SEED: u64 = 0x6761_6262_726f_5379; // "gabbrSy"
        const PASSES: usize = 120;
        const DEVICES: usize = 3;

        for pass in 0..PASSES {
            let mut rng = Rng(SEED ^ (pass as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15));
            let mut counter = 100u64;
            let mut devices: Vec<Vec<VaultEntry>> = (0..DEVICES).map(|_| base_vault()).collect();

            for dev in devices.iter_mut() {
                let edits = 3 + rng.below(8);
                for _ in 0..edits {
                    mutate(dev, &mut rng, &mut counter);
                }
            }

            let (single, collisions, allowed) = oracle(&devices);
            let order1 = perm(DEVICES, &mut rng);
            let order2 = perm(DEVICES, &mut rng);
            let (r1, c1) = converge(&devices, &order1);
            let (r2, c2) = converge(&devices, &order2);
            let rv1 = result_values(&r1);
            let rv2 = result_values(&r2);

            // 1. The set of collisions is exactly the expected one, in BOTH orders
            //    (order-independence of what gets surfaced).
            assert_eq!(c1, collisions, "pass {pass}: order1 collisions");
            assert_eq!(c2, collisions, "pass {pass}: order2 collisions");

            // 2. Every agreed / one-sided field converges to its value, both orders,
            //    and is not falsely flagged as a collision.
            for (k, v) in &single {
                assert_eq!(rv1.get(k), Some(v), "pass {pass}: {k:?} did not converge");
                assert_eq!(rv2.get(k), Some(v), "pass {pass}: {k:?} order-dependent");
                assert!(
                    !collisions.contains(k),
                    "pass {pass}: {k:?} falsely a collision"
                );
            }

            // 3. Every collision keeps ONE of the contended values (never lost, never
            //    invented) on each side.
            for k in &collisions {
                let v1 = rv1
                    .get(k)
                    .unwrap_or_else(|| panic!("pass {pass}: {k:?} missing"));
                let v2 = rv2
                    .get(k)
                    .unwrap_or_else(|| panic!("pass {pass}: {k:?} missing"));
                assert!(
                    allowed[k].contains(v1),
                    "pass {pass}: {k:?} invented a value"
                );
                assert!(
                    allowed[k].contains(v2),
                    "pass {pass}: {k:?} invented a value"
                );
            }

            // 4. Stability: re-merging the converged set with any device surfaces no
            //    NEW collision beyond the known set.
            for dev in &devices {
                let (_again, cs) = sync_sets(&r1, dev);
                for c in cs {
                    assert!(
                        collisions.contains(&c),
                        "pass {pass}: new collision {c:?} on re-merge"
                    );
                }
            }
        }
    }
}

// Phase B: prove the global VAULT_SESSION singleton never lets one vault's
// authentication or data cross-pollinate another. All #[serial] (they share the
// process-global session). Two distinct on-disk vaults A & B per test.
#[cfg(test)]
mod multi_vault_isolation_tests {
    use super::*;
    use crate::api::vault::{load_vault, save_vault, save_vault_with_keys};
    use crate::crypto::vault_crypto::YubiKeyRegistration;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use crate::vault::io::read_vault_header;
    use crate::vault::serialization::VaultBody;
    use serial_test::serial;
    use std::env::temp_dir;
    use std::path::PathBuf;

    fn note(id: &str, content: &str) -> VaultEntry {
        VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from(id),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::new(),
            },
            title: String::from("note"),
            content: String::from(content),
            custom_fields: vec![],
            attachments: vec![],
        })
    }

    fn body(id: &str) -> VaultBody {
        VaultBody {
            folders: vec![],
            entries: vec![note(id, "content")],
            ..Default::default()
        }
    }

    fn passphrase_vault(suffix: &str, passphrase: &[u8], id: &str) -> PathBuf {
        let mut path = temp_dir();
        path.push(format!("gabbro_iso_{suffix}.gabbro"));
        save_vault(&body(id), passphrase, &path).unwrap();
        path
    }

    // key1: cred 0x01 x64 / hmac 0x11 / salt 0x22 ; key2: cred 0x02 x48 / hmac 0x33 / salt 0x44
    fn multikey_vault(suffix: &str, passphrase: &[u8], id: &str) -> PathBuf {
        let mut path = temp_dir();
        path.push(format!("gabbro_iso_{suffix}.gabbro"));
        let keys = [
            YubiKeyRegistration {
                credential_id: vec![0x01u8; 64],
                hmac_secret: [0x11u8; 32],
                salt: [0x22u8; 32],
            },
            YubiKeyRegistration {
                credential_id: vec![0x02u8; 48],
                hmac_secret: [0x33u8; 32],
                salt: [0x44u8; 32],
            },
        ];
        save_vault_with_keys(&body(id), passphrase, &keys, &path).unwrap();
        path
    }

    fn teardown(paths: &[&PathBuf]) {
        let _ = lock_vault();
        for p in paths {
            let _ = std::fs::remove_file(p);
            let _ = std::fs::remove_file(format!("{}.bak", p.display()));
        }
    }

    // 1. unlock A -> unlock B -> A's file bytes on disk unchanged.
    #[test]
    #[serial]
    fn switching_vaults_leaves_prior_file_untouched() {
        let a = passphrase_vault("1a", b"pass-a", "a-001");
        let b = passphrase_vault("1b", b"pass-b", "b-001");
        let a_before = std::fs::read(&a).unwrap();
        unlock_vault(b"pass-a", a.clone()).unwrap();
        unlock_vault(b"pass-b", b.clone()).unwrap();
        assert_eq!(
            a_before,
            std::fs::read(&a).unwrap(),
            "A's file changed after switching to B"
        );
        teardown(&[&a, &b]);
    }

    // 2. after unlock B, a CRUD save writes to B's path, never A's.
    #[test]
    #[serial]
    fn crud_after_switch_targets_only_the_active_vault() {
        let a = passphrase_vault("2a", b"pass-a", "a-001");
        let b = passphrase_vault("2b", b"pass-b", "b-001");
        unlock_vault(b"pass-a", a.clone()).unwrap();
        unlock_vault(b"pass-b", b.clone()).unwrap();
        let a_before = std::fs::read(&a).unwrap();
        let b_before = std::fs::read(&b).unwrap();
        session_create_entry(note("b-002", "added")).unwrap();
        assert_eq!(
            a_before,
            std::fs::read(&a).unwrap(),
            "A's file changed by a CRUD on B"
        );
        assert_ne!(
            b_before,
            std::fs::read(&b).unwrap(),
            "B's file did not change after CRUD"
        );
        lock_vault().unwrap();
        unlock_vault(b"pass-b", b.clone()).unwrap();
        assert_eq!(
            list_entry_summaries().unwrap().len(),
            2,
            "B should have 2 entries"
        );
        lock_vault().unwrap();
        unlock_vault(b"pass-a", a.clone()).unwrap();
        assert_eq!(
            list_entry_summaries().unwrap().len(),
            1,
            "A should still have 1 entry"
        );
        teardown(&[&a, &b]);
    }

    // 3. lock clears the session: nothing readable afterward.
    #[test]
    #[serial]
    fn lock_clears_session_no_residual_entries() {
        let a = passphrase_vault("3a", b"pass-a", "a-001");
        unlock_vault(b"pass-a", a.clone()).unwrap();
        lock_vault().unwrap();
        assert!(!is_vault_unlocked());
        assert!(get_entry("a-001").is_err(), "entry readable after lock");
        teardown(&[&a]);
    }

    // 4. a failed unlock of B leaves the prior A session intact (never a half-session).
    #[test]
    #[serial]
    fn failed_unlock_leaves_prior_session_intact() {
        let a = passphrase_vault("4a", b"pass-a", "a-001");
        let b = passphrase_vault("4b", b"pass-b", "b-001");
        unlock_vault(b"pass-a", a.clone()).unwrap();
        assert!(unlock_vault(b"wrong-pass", b.clone()).is_err());
        assert!(is_vault_unlocked(), "session lost after a failed unlock");
        assert!(
            get_entry("a-001").is_ok(),
            "A's entry lost after a failed unlock of B"
        );
        assert!(
            get_entry("b-001").is_err(),
            "B leaked into the session after a failed unlock"
        );
        teardown(&[&a, &b]);
    }

    // 5. each vault opens only with its own passphrase (no cross-open).
    #[test]
    #[serial]
    fn each_vault_opens_only_with_its_own_passphrase() {
        let a = passphrase_vault("5a", b"pass-a", "a-001");
        let b = passphrase_vault("5b", b"pass-b", "b-001");
        assert!(unlock_vault(b"pass-a", a.clone()).is_ok());
        lock_vault().unwrap();
        assert!(
            unlock_vault(b"pass-a", b.clone()).is_err(),
            "B opened with A's passphrase"
        );
        assert!(unlock_vault(b"pass-b", b.clone()).is_ok());
        teardown(&[&a, &b]);
    }

    // 6. add a YubiKey to B doesn't alter A's header records.
    #[test]
    #[serial]
    fn add_yubikey_to_one_vault_leaves_another_vaults_records() {
        let a = passphrase_vault("6a", b"pass-a", "a-001");
        let b = multikey_vault("6b", b"pass-b", "b-001");
        let a_before = read_vault_header(&a).unwrap().yubikey_records.len();
        unlock_vault_with_key_record(b"pass-b", &[0x11u8; 32], vec![0x01u8; 64], b.clone())
            .unwrap();
        session_add_yubikey(vec![0x03u8; 32], vec![0x55u8; 32], vec![0x66u8; 32]).unwrap();
        lock_vault().unwrap();
        assert_eq!(
            a_before,
            read_vault_header(&a).unwrap().yubikey_records.len(),
            "A's YubiKey records changed"
        );
        assert_eq!(
            read_vault_header(&b).unwrap().yubikey_records.len(),
            3,
            "B did not gain the new key"
        );
        teardown(&[&a, &b]);
    }

    // 7. remove a YubiKey on B leaves A's records + openability intact.
    #[test]
    #[serial]
    fn remove_yubikey_on_one_vault_leaves_another_intact() {
        let a = passphrase_vault("7a", b"pass-a", "a-001");
        let b = multikey_vault("7b", b"pass-b", "b-001");
        unlock_vault_with_key_record(b"pass-b", &[0x11u8; 32], vec![0x01u8; 64], b.clone())
            .unwrap();
        session_remove_yubikey(vec![0x02u8; 48]).unwrap();
        lock_vault().unwrap();
        assert_eq!(
            read_vault_header(&a).unwrap().yubikey_records.len(),
            0,
            "A's records changed"
        );
        assert!(
            unlock_vault(b"pass-a", a.clone()).is_ok(),
            "A no longer opens with its passphrase"
        );
        lock_vault().unwrap();
        assert_eq!(
            read_vault_header(&b).unwrap().yubikey_records.len(),
            1,
            "B key count wrong after removal"
        );
        teardown(&[&a, &b]);
    }

    // 8. passphrase-only A and YubiKey B coexist: each opens only with its own credentials.
    #[test]
    #[serial]
    fn passphrase_and_yubikey_vaults_coexist_isolated() {
        let a = passphrase_vault("8a", b"pass-a", "a-001");
        let b = multikey_vault("8b", b"pass-b", "b-001");
        assert!(
            unlock_vault(b"pass-a", a.clone()).is_ok(),
            "A did not open with its passphrase alone"
        );
        lock_vault().unwrap();
        assert!(
            unlock_vault(b"pass-b", b.clone()).is_err(),
            "key-protected B opened passphrase-only"
        );
        assert!(
            unlock_vault_with_key_record(b"pass-b", &[0x11u8; 32], vec![0x01u8; 64], b.clone())
                .is_ok(),
            "B did not open with its key"
        );
        lock_vault().unwrap();
        assert!(
            unlock_vault_with_key_record(b"pass-a", &[0x11u8; 32], vec![0x01u8; 64], a.clone())
                .is_err(),
            "passphrase-only A opened via a key record"
        );
        teardown(&[&a, &b]);
    }

    // 9. syncing an incoming file into B doesn't touch uninvolved vault A, and
    //    B's own auth survives the sync re-seal.
    #[test]
    #[serial]
    fn sync_leaves_uninvolved_vault_untouched_and_preserves_active_auth() {
        let a = passphrase_vault("9a", b"pass-a", "a-001");
        let b = passphrase_vault("9b", b"pass-b", "b-001");
        let c = passphrase_vault("9c", b"pass-c", "c-001"); // incoming source
        let a_before = std::fs::read(&a).unwrap();
        let incoming = load_vault(b"pass-c", &c).unwrap();
        unlock_vault(b"pass-b", b.clone()).unwrap();
        let summary = session_merge_vault_from_body(incoming).unwrap();
        assert_eq!(summary.added, 1, "the incoming entry should be added");
        lock_vault().unwrap();
        assert_eq!(
            a_before,
            std::fs::read(&a).unwrap(),
            "A's file changed by a sync into B"
        );
        // B still opens with its own passphrase and holds both entries.
        unlock_vault(b"pass-b", b.clone()).unwrap();
        assert_eq!(
            list_entry_summaries().unwrap().len(),
            2,
            "B lost an entry across sync"
        );
        teardown(&[&a, &b, &c]);
    }

    // 10a. passphrase auth survives a full sync round-trip (merge -> lock -> reopen).
    #[test]
    #[serial]
    fn passphrase_auth_survives_a_sync_round_trip() {
        let b = passphrase_vault("10a", b"pass-b", "b-001");
        let c = passphrase_vault("10ac", b"pass-c", "c-001");
        let incoming = load_vault(b"pass-c", &c).unwrap();
        unlock_vault(b"pass-b", b.clone()).unwrap();
        session_merge_vault_from_body(incoming).unwrap();
        lock_vault().unwrap();
        unlock_vault(b"pass-b", b.clone()).unwrap();
        assert_eq!(
            list_entry_summaries().unwrap().len(),
            2,
            "entries lost across the sync round-trip"
        );
        teardown(&[&b, &c]);
    }

    // 10b. YubiKey auth survives a sync re-seal: records intact, still opens with the key.
    #[test]
    #[serial]
    fn yubikey_auth_survives_a_sync_re_seal() {
        let b = multikey_vault("10b", b"pass-b", "b-001");
        let c = passphrase_vault("10bc", b"pass-c", "c-001");
        let incoming = load_vault(b"pass-c", &c).unwrap();
        unlock_vault_with_key_record(b"pass-b", &[0x11u8; 32], vec![0x01u8; 64], b.clone())
            .unwrap();
        session_merge_vault_from_body(incoming).unwrap();
        lock_vault().unwrap();
        assert_eq!(
            read_vault_header(&b).unwrap().yubikey_records.len(),
            2,
            "sync dropped a YubiKey record"
        );
        unlock_vault_with_key_record(b"pass-b", &[0x11u8; 32], vec![0x01u8; 64], b.clone())
            .unwrap();
        assert_eq!(
            list_entry_summaries().unwrap().len(),
            2,
            "entries lost across the YubiKey sync re-seal"
        );
        teardown(&[&b, &c]);
    }
}

#[cfg(test)]
mod read_only_unlock_tests {
    use super::*;
    use crate::api::vault::save_vault;
    use crate::vault::serialization::VaultBody;
    use serial_test::serial;
    use std::env::temp_dir;

    /// Net-first pin (RT-3 / Phase 4). Opening and closing an *already-current*
    /// vault must NOT rewrite the file. Phase 4 adds migrate-on-unlock, which writes
    /// only when the on-disk version is older than current -- so this steady-state
    /// property (a current vault is never rewritten on unlock) must survive that
    /// change, and it guards against a Phase-4 bug that re-seals on every unlock.
    #[test]
    #[serial]
    fn unlock_then_lock_leaves_a_current_version_vault_byte_identical() {
        let pass = b"read-only-unlock-pin-passphrase";
        let mut path = temp_dir();
        path.push("gabbro_readonly_unlock_pin.gabbro");

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

        let before = std::fs::read(&path).expect("read sealed vault");

        unlock_vault(pass, path.clone()).unwrap();
        lock_vault().unwrap();

        let after = std::fs::read(&path).expect("read vault after unlock+lock");
        assert_eq!(
            before, after,
            "unlock+lock must not modify an already-current vault file"
        );

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }
}

#[cfg(test)]
mod migrate_on_unlock_tests {
    use super::*;
    use crate::crypto::vault_crypto::{
        migrate_multikey_to_version, open_vault_with_key_record, seal_vault_with_keys,
        YubiKeyRegistration,
    };
    use crate::vault::io::{read_vault, write_vault};
    use crate::vault::serialization::{serialize_vault_body, VaultBody};
    use serial_test::serial;
    use std::env::temp_dir;

    /// S10/S11/S12 at the session level: unlocking an OLD (v9) p+YK vault migrates
    /// it in place to the current VERSION, preserving data, with no re-tap. This is
    /// the only test exercising the migrate-on-unlock *wiring* (the gate drives the
    /// crypto primitives directly, bypassing the session).
    #[test]
    #[serial]
    fn unlock_migrates_an_old_multikey_vault_to_current_version() {
        let pass = b"migrate-on-unlock-multikey-pass";
        let keys = [
            YubiKeyRegistration {
                credential_id: vec![0x01u8; 64],
                hmac_secret: [0x11u8; 32],
                salt: [0x22u8; 32],
            },
            YubiKeyRegistration {
                credential_id: vec![0x02u8; 48],
                hmac_secret: [0x33u8; 32],
                salt: [0x44u8; 32],
            },
        ];
        let body = VaultBody {
            folders: vec![String::from("Work")],
            entries: vec![],
            ..Default::default()
        };
        let plaintext = serialize_vault_body(&body).unwrap();

        // Mint a genuine v9 (legacy StdRng X25519) multi-key vault on disk.
        let sealed = seal_vault_with_keys(pass, &keys, &plaintext, None).unwrap();
        let (_, master, wrapping) =
            open_vault_with_key_record(pass, &keys[0].hmac_secret, &keys[0].credential_id, &sealed)
                .unwrap();
        let wrapping = wrapping.unwrap();
        let v9 =
            migrate_multikey_to_version(&sealed, pass, &wrapping, &master, &plaintext, 9).unwrap();
        assert_eq!(v9.version, 9, "precondition: an on-disk v9 vault");

        let mut path = temp_dir();
        path.push("gabbro_migrate_on_unlock_multikey.gabbro");
        write_vault(&v9, &path).unwrap();

        // Unlock with one key -> should migrate the file to the current VERSION.
        unlock_vault_with_key_record(
            pass,
            &keys[0].hmac_secret,
            keys[0].credential_id.clone(),
            path.clone(),
        )
        .unwrap();

        assert_eq!(
            read_vault(&path).unwrap().version,
            crate::vault::file_format::VERSION,
            "unlock must migrate the old vault to the current VERSION"
        );
        assert_eq!(
            session_list_folders().unwrap(),
            vec![String::from("Work")],
            "data must survive migration"
        );
        lock_vault().unwrap();

        // The migrated file still opens with EACH registered key.
        let migrated = read_vault(&path).unwrap();
        for k in &keys {
            open_vault_with_key_record(pass, &k.hmac_secret, &k.credential_id, &migrated)
                .unwrap_or_else(|e| panic!("migrated vault must open with each key: {e}"));
        }

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }
}
