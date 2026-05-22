//! Vault session — in-memory state between bridge calls.
//!
//! The decrypted vault lives here after unlock. Flutter never holds
//! the entries directly — it calls functions in this module to read
//! and write them.

use std::path::PathBuf;
use zeroize::{Zeroize, Zeroizing};

use once_cell::sync::Lazy;
use std::sync::Mutex;

use crate::api::vault::{
    load_vault, load_vault_with_key_record, load_vault_with_yubikey, reseal_vault_body, save_vault,
    save_vault_with_yubikey,
};
use crate::api::vault_bridge::EntrySummaryData;
use crate::vault::entry::VaultEntry;
use crate::vault::serialization::VaultBody;

// Extracted YubiKey quad: (hmac_secret, credential_id, hkdf_salt, vault_key_master?).
type YubikeyTriple = Option<(
    Zeroizing<Vec<u8>>,
    Vec<u8>,
    [u8; 32],
    Option<Zeroizing<[u8; 32]>>,
)>;

// ── Session state ─────────────────────────────────────────────────────────────

/// YubiKey material cached in memory for the duration of an unlocked session.
///
/// For VERSION 3 multi-key vaults, `vault_key_master` holds the random master
/// key that encrypts the vault body.  CRUD saves use it directly (no re-tap).
/// For legacy VERSION 2 single-key vaults it is None; saves use the old
/// `save_vault_with_yubikey` path which re-derives with the cached hmac_secret.
pub struct YubikeyMaterial {
    pub hmac_secret: Vec<u8>, // 32 bytes; zeroized in lock_vault
    pub hkdf_salt: [u8; 32],
    pub credential_id: Vec<u8>,
    /// Cached master key for CRUD re-seals (VERSION 3 multi-key vaults only).
    pub vault_key_master: Option<Zeroizing<[u8; 32]>>,
}

pub struct VaultSession {
    pub folders: Vec<String>,
    pub entries: Vec<VaultEntry>,
    pub path: PathBuf,
    pub passphrase: Vec<u8>,
    pub yubikey: Option<YubikeyMaterial>,
}

static VAULT_SESSION: Lazy<Mutex<Option<VaultSession>>> = Lazy::new(|| Mutex::new(None));

// ── Session API ───────────────────────────────────────────────────────────────

/// Decrypt the vault at `path` and store it in memory.
///
/// Flutter awaits this — Argon2id takes ~667ms on target hardware.
pub fn unlock_vault(passphrase: &[u8], path: PathBuf) -> Result<(), String> {
    let mut body = load_vault(passphrase, &path)?;
    crate::api::vault::purge_expired_history(&mut body.entries);
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    *session = Some(VaultSession {
        folders: body.folders,
        entries: body.entries,
        path,
        passphrase: passphrase.to_vec(),
        yubikey: None,
    });
    Ok(())
}

/// Decrypt a YubiKey-protected vault and store it in memory.
pub fn unlock_vault_with_yubikey(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: Vec<u8>,
    yubikey_salt: &[u8; 32],
    path: PathBuf,
) -> Result<(), String> {
    let mut body = load_vault_with_yubikey(passphrase, hmac_secret, yubikey_salt, &path)?;
    crate::api::vault::purge_expired_history(&mut body.entries);
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    *session = Some(VaultSession {
        folders: body.folders,
        entries: body.entries,
        path,
        passphrase: passphrase.to_vec(),
        yubikey: Some(YubikeyMaterial {
            hmac_secret: hmac_secret.to_vec(),
            hkdf_salt: *yubikey_salt,
            vault_key_master: None,
            credential_id,
        }),
    });
    Ok(())
}

/// Decrypt a VERSION 3 multi-key vault using any one registered YubiKey.
///
/// Caches `vault_key_master` for subsequent CRUD re-seals so the user
/// never needs to re-tap their key during an active session.
pub fn unlock_vault_with_key_record(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: Vec<u8>,
    yubikey_salt: &[u8; 32],
    path: PathBuf,
) -> Result<(), String> {
    let (mut body, master) =
        load_vault_with_key_record(passphrase, hmac_secret, &credential_id, &path)?;
    crate::api::vault::purge_expired_history(&mut body.entries);
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    *session = Some(VaultSession {
        folders: body.folders,
        entries: body.entries,
        path,
        passphrase: passphrase.to_vec(),
        yubikey: Some(YubikeyMaterial {
            hmac_secret: hmac_secret.to_vec(),
            hkdf_salt: *yubikey_salt,
            credential_id,
            vault_key_master: Some(master),
        }),
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
            yk.hmac_secret.zeroize();
            if let Some(ref mut master) = yk.vault_key_master {
                master.zeroize();
            }
        }
        s.entries.clear();
    }
    *session = None;
    Ok(())
}

/// Extracts YubiKey material from the session while the lock is held.
fn extract_yubikey(session: &VaultSession) -> YubikeyTriple {
    session.yubikey.as_ref().map(|yk| {
        (
            Zeroizing::new(yk.hmac_secret.clone()),
            yk.credential_id.clone(),
            yk.hkdf_salt,
            yk.vault_key_master.as_ref().map(|m| Zeroizing::new(**m)),
        )
    })
}

/// Saves using passphrase alone, or passphrase + YubiKey if the session
/// has YubiKey material cached.
///
/// VERSION 3 multi-key vaults: re-seals only the body using `vault_key_master`
/// (no Argon2id re-derivation; all YubiKey records stay intact).
/// Legacy VERSION 2 single-key vaults: full re-seal via `save_vault_with_yubikey`.
fn do_save(
    body: &VaultBody,
    passphrase: &[u8],
    path: &std::path::Path,
    yubikey: YubikeyTriple,
) -> Result<(), String> {
    match yubikey {
        Some((_, _, _, Some(ref vault_key_master))) => {
            reseal_vault_body(body, vault_key_master, path)
        }
        Some((hmac_secret, credential_id, hkdf_salt, None)) => {
            let secret: [u8; 32] = hmac_secret
                .as_slice()
                .try_into()
                .map_err(|_| "invalid cached hmac_secret length".to_string())?;
            save_vault_with_yubikey(body, passphrase, &secret, credential_id, hkdf_salt, path)
        }
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

/// Builds a lightweight summary DTO from any entry variant.
///
/// Display title selection per type:
/// - Login:    `title` field; falls back to `url` if empty, then UUID
/// - Note:     `title` field
/// - Identity: `first_name + " " + last_name`
/// - Card:     `card_name` if present; falls back to `cardholder_name`
/// - File:     `filename`
/// - Custom:   `title` field
fn entry_to_summary(entry: &VaultEntry) -> EntrySummaryData {
    match entry {
        VaultEntry::Login(e) => EntrySummaryData {
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
        },
        VaultEntry::Note(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Note"),
            title: e.title.clone(),
            folder: e.meta.folder.clone(),
        },
        VaultEntry::Identity(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Identity"),
            title: format!("{} {}", e.first_name, e.last_name),
            folder: e.meta.folder.clone(),
        },
        VaultEntry::Card(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Card"),
            title: e
                .card_name
                .as_deref()
                .filter(|s| !s.is_empty())
                .unwrap_or(&e.cardholder_name)
                .to_string(),
            folder: e.meta.folder.clone(),
        },
        VaultEntry::File(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("File"),
            title: e.filename.clone(),
            folder: e.meta.folder.clone(),
        },
        VaultEntry::Custom(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Custom"),
            title: e.title.clone(),
            folder: e.meta.folder.clone(),
        },
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
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
pub fn session_change_passphrase(
    old_passphrase: &[u8],
    new_passphrase: &[u8],
) -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_mut().ok_or("Vault is locked")?;
    // Verify old passphrase — use YubiKey path if vault was unlocked with YubiKey
    if let Some(ref yk) = session.yubikey {
        let secret: [u8; 32] = yk
            .hmac_secret
            .as_slice()
            .try_into()
            .map_err(|_| "invalid cached hmac_secret length".to_string())?;
        load_vault_with_yubikey(old_passphrase, &secret, &yk.hkdf_salt, &session.path)?;
    } else {
        load_vault(old_passphrase, &session.path)?;
    }
    let body = VaultBody {
        folders: session.folders.clone(),
        entries: session.entries.clone(),
    };
    // Re-seal with new passphrase, preserving YubiKey material
    if let Some(ref yk) = session.yubikey {
        let secret: [u8; 32] = yk
            .hmac_secret
            .as_slice()
            .try_into()
            .map_err(|_| "invalid cached hmac_secret length".to_string())?;
        save_vault_with_yubikey(
            &body,
            new_passphrase,
            &secret,
            yk.credential_id.clone(),
            yk.hkdf_salt,
            &session.path,
        )?;
    } else {
        save_vault(&body, new_passphrase, &session.path)?;
    }
    session.passphrase = new_passphrase.to_vec();
    Ok(())
}

/// Clear the previous password history for a Login entry and persist.
///
/// Sets `previous_password` to `None` on the identified entry.
/// Returns `Err` if the entry is not found or is not a Login entry.
pub fn session_clear_password_history(id: &str) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let entry = session
            .entries
            .iter_mut()
            .find(|e| entry_id(e) == id)
            .ok_or_else(|| format!("No entry found with id: {id}"))?;
        match entry {
            VaultEntry::Login(ref mut e) => {
                e.previous_password = None;
                e.meta.updated_at = crate::api::vault::chrono_now();
            }
            _ => return Err(format!("Entry {id} is not a Login entry")),
        }
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Revert the current password to the previous password for a Login entry and persist.
///
/// Swaps `password` ← `previous_password.value`, then clears `previous_password`.
/// Returns `Err` if the entry is not found, is not a Login entry, or has no history.
pub fn session_revert_password(id: &str) -> Result<(), String> {
    let (body, passphrase, path, yubikey) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let entry = session
            .entries
            .iter_mut()
            .find(|e| entry_id(e) == id)
            .ok_or_else(|| format!("No entry found with id: {id}"))?;
        match entry {
            VaultEntry::Login(ref mut e) => {
                let prev = e
                    .previous_password
                    .take()
                    .ok_or_else(|| format!("Entry {id} has no password history to revert"))?;
                e.password = prev.value.clone();
                e.meta.updated_at = crate::api::vault::chrono_now();
            }
            _ => return Err(format!("Entry {id} is not a Login entry")),
        }
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
    do_save(&body, &passphrase, &path, yubikey)?;
    Ok(())
}

/// Write .gabbro + .gabbro.sha256 from current session state.
pub fn session_export_vault(export_path: PathBuf) -> Result<(), String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    crate::api::vault::export_vault(&session.entries, &session.passphrase, &export_path)?;
    Ok(())
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
pub fn get_entry_for_autofill(id: &str) -> Result<String, String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    let entry = session
        .entries
        .iter()
        .find(|e| entry_id(e) == id)
        .ok_or_else(|| format!("No entry found with id: {id}"))?;
    match entry {
        VaultEntry::Login(e) => {
            let mut map = serde_json::Map::new();
            map.insert(
                "id".to_string(),
                serde_json::Value::String(e.meta.id.clone()),
            );
            map.insert(
                "username".to_string(),
                serde_json::Value::String(e.username.clone()),
            );
            map.insert(
                "password".to_string(),
                serde_json::Value::String(e.password.clone()),
            );
            let json = serde_json::Value::Object(map).to_string();
            Ok(json)
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
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
        let body = VaultBody {
            folders: session.folders.clone(),
            entries: session.entries.clone(),
        };
        let yubikey = extract_yubikey(session);
        (
            body,
            Zeroizing::new(session.passphrase.clone()),
            session.path.clone(),
            yubikey,
        )
    }; // ← lock released here
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
            }),
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from("id-002"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from(""),
                },
                title: String::from("A note"),
                content: String::from("content"),
                attachments: vec![],
            }),
        ];

        save_vault(
            &crate::vault::serialization::VaultBody {
                folders: vec![String::from("Work")],
                entries,
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
                id: String::from("rename-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Work"),
            },
            title: String::from("Rename test note"),
            content: String::from("content"),
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
                id: String::from("del-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Work"),
            },
            title: String::from("Delete test note"),
            content: String::from("content"),
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
                id: String::from("del-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Work"),
            },
            title: String::from("Reassign test note"),
            content: String::from("content"),
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
                id: String::from("af-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Autofill test note"),
            content: String::from("test"),
            attachments: vec![],
        })];
        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
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
                id: String::from("af-login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com/login"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        });
        let note = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: String::from("af-note-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Not a login"),
            content: String::from("irrelevant"),
            attachments: vec![],
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![login, note],
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
            json.contains("\"rob\""),
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
                id: String::from("af-login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com/login"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        });
        let note = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: String::from("af-note-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Not a login"),
            content: String::from("irrelevant"),
            attachments: vec![],
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![login, note],
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let summaries = login_summaries_for_autofill().unwrap();

        assert_eq!(summaries.len(), 1, "only Login entries should be returned");
        assert_eq!(summaries[0].id, "af-login-001");
        assert_eq!(summaries[0].username, "rob");
        assert_eq!(summaries[0].url, "https://github.com/login");

        teardown(&path);
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
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Session test note"),
            content: String::from("session secret content"),
            attachments: vec![],
        })];
        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
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
                id: String::from("id-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("New note"),
            content: String::from("new content"),
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

    #[test]
    #[serial]
    fn login_entry_to_summary_uses_title() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("id-login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("hunter2"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        });

        let summary = entry_to_summary(&entry);
        assert_eq!(
            summary.title, "GitHub",
            "summary title should use LoginEntry.title, not url or username"
        );
    }

    #[test]
    #[serial]
    fn login_entry_to_summary_falls_back_to_url_when_title_empty() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("id-login-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from(""),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
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
                id: String::from("id-card-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            card_name: Some(String::from("Visa Platinum")),
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
            custom_fields: vec![],
            attachments: vec![],
            previous_cvv: None,
            previous_pin: None,
        });

        let summary = entry_to_summary(&entry);
        assert_eq!(
            summary.title, "Visa Platinum",
            "summary should use card_name when present"
        );
    }

    #[test]
    #[serial]
    fn clear_password_history_removes_previous_password() {
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_clear_history_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("current_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(PreviousSecret {
                value: String::from("old_password"),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: None,
            }),
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        session_clear_password_history("login-001").unwrap();

        let result = get_entry("login-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert!(e.previous_password.is_none());
                assert_eq!(e.password, "current_password");
            }
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn clear_password_history_persists_to_disk() {
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_clear_history_persist_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("current_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(PreviousSecret {
                value: String::from("old_password"),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: None,
            }),
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();
        session_clear_password_history("login-001").unwrap();

        // Lock and reload to verify disk persistence
        lock_vault().unwrap();
        unlock_vault(pass, path.clone()).unwrap();
        let result = get_entry("login-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => assert!(e.previous_password.is_none()),
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn clear_password_history_on_non_login_returns_error() {
        let pass = b"test passphrase";
        let path = setup_vault(pass); // Note entry with id "id-001"

        unlock_vault(pass, path.clone()).unwrap();
        let result = session_clear_password_history("id-001");
        assert!(result.is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn revert_password_swaps_current_and_previous() {
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_revert_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("current_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(PreviousSecret {
                value: String::from("old_password"),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: None,
            }),
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        session_revert_password("login-001").unwrap();

        let result = get_entry("login-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert_eq!(e.password, "old_password");
                assert!(e.previous_password.is_none());
            }
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn revert_password_with_no_history_returns_error() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_revert_no_history_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("current_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
            },
            pass,
            &path,
        )
        .unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_revert_password("login-001");
        assert!(result.is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn unexpired_history_is_preserved_on_unlock() {
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_unexpired_history_test.gabbro");

        // expires_at is far in the future — 2099-12-31
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-unexp-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Unexpired"),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("current"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(PreviousSecret {
                value: String::from("old"),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: Some(String::from("2099-12-31T00:00:00Z")),
            }),
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
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
                    e.previous_password.is_some(),
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
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_keep_forever_history_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-forever-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Forever"),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("current"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(PreviousSecret {
                value: String::from("old"),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: None,
            }),
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
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
                    e.previous_password.is_some(),
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
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_expired_history_test.gabbro");

        // expires_at is in the past — 2000-01-01
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-exp-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Expired"),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("current"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(PreviousSecret {
                value: String::from("old"),
                saved_at: String::from("2000-01-01T00:00:00Z"),
                expires_at: Some(String::from("2000-01-02T00:00:00Z")),
            }),
        });

        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![entry],
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
                    e.previous_password.is_none(),
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
                id: String::from("id-card-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
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
            custom_fields: vec![],
            attachments: vec![],
            previous_cvv: None,
            previous_pin: None,
        });

        let summary = entry_to_summary(&entry);
        assert_eq!(
            summary.title, "Rob Smith",
            "summary should fall back to cardholder_name when card_name is absent"
        );
    }
}

#[cfg(test)]
mod yubikey_session_tests {
    use super::*;
    use crate::api::vault::save_vault_with_yubikey;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    const HMAC: [u8; 32] = [0xAAu8; 32];
    const CRED_ID: &[u8] = &[0xBBu8; 64];
    const YK_SALT: [u8; 32] = [0xCCu8; 32];

    fn setup_yubikey_vault(passphrase: &[u8]) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_yk_session_test.gabbro");
        let body = VaultBody {
            folders: vec![],
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from("yk-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from(""),
                },
                title: String::from("YubiKey test note"),
                content: String::from("secret content"),
                attachments: vec![],
            })],
        };
        save_vault_with_yubikey(&body, passphrase, &HMAC, CRED_ID.to_vec(), YK_SALT, &path)
            .unwrap();
        path
    }

    fn teardown(path: &std::path::PathBuf) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    #[serial]
    fn unlock_vault_with_yubikey_loads_session() {
        let pass = b"yubikey-test-passphrase";
        let path = setup_yubikey_vault(pass);

        unlock_vault_with_yubikey(pass, &HMAC, CRED_ID.to_vec(), &YK_SALT, path.clone()).unwrap();

        let summaries = list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].id, "yk-001");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn wrong_hmac_secret_fails_to_unlock() {
        let pass = b"yubikey-test-passphrase";
        let path = setup_yubikey_vault(pass);
        let wrong_hmac = [0x00u8; 32];

        let result =
            unlock_vault_with_yubikey(pass, &wrong_hmac, CRED_ID.to_vec(), &YK_SALT, path.clone());
        assert!(result.is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn wrong_passphrase_with_yubikey_fails_to_unlock() {
        let path = setup_yubikey_vault(b"correct-pass");

        let result = unlock_vault_with_yubikey(
            b"wrong-pass",
            &HMAC,
            CRED_ID.to_vec(),
            &YK_SALT,
            path.clone(),
        );
        assert!(result.is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn session_save_after_yubikey_unlock_preserves_yubikey_protection() {
        let pass = b"yubikey-test-passphrase";
        let path = setup_yubikey_vault(pass);

        unlock_vault_with_yubikey(pass, &HMAC, CRED_ID.to_vec(), &YK_SALT, path.clone()).unwrap();

        // Add an entry and save — must re-seal with YubiKey
        let new_entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: String::from("yk-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from(""),
            },
            title: String::from("Added after unlock"),
            content: String::from("more secrets"),
            attachments: vec![],
        });
        session_create_entry(new_entry).unwrap();
        lock_vault().unwrap();

        // Passphrase-only open must fail (vault is still YubiKey-protected)
        let result = unlock_vault(pass, path.clone());
        assert!(
            result.is_err(),
            "passphrase-only unlock must fail on a YubiKey vault"
        );

        // YubiKey open must succeed and show both entries
        unlock_vault_with_yubikey(pass, &HMAC, CRED_ID.to_vec(), &YK_SALT, path.clone()).unwrap();
        let summaries = list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 2, "both entries must survive the re-seal");

        teardown(&path);
    }

    #[test]
    #[serial]
    fn change_passphrase_on_yubikey_vault_preserves_yubikey_protection() {
        let old_pass = b"old-yubikey-pass";
        let new_pass = b"new-yubikey-pass";
        let path = setup_yubikey_vault(old_pass);

        unlock_vault_with_yubikey(old_pass, &HMAC, CRED_ID.to_vec(), &YK_SALT, path.clone())
            .unwrap();
        session_change_passphrase(old_pass, new_pass).unwrap();
        lock_vault().unwrap();

        // Old passphrase must no longer work
        let result =
            unlock_vault_with_yubikey(old_pass, &HMAC, CRED_ID.to_vec(), &YK_SALT, path.clone());
        assert!(result.is_err());

        // New passphrase + YubiKey must work
        unlock_vault_with_yubikey(new_pass, &HMAC, CRED_ID.to_vec(), &YK_SALT, path.clone())
            .unwrap();
        let summaries = list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 1);

        teardown(&path);
    }
}
