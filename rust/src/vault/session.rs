//! Vault session — in-memory state between bridge calls.
//!
//! The decrypted vault lives here after unlock. Flutter never holds
//! the entries directly — it calls functions in this module to read
//! and write them.

use std::path::PathBuf;
use zeroize::Zeroize;

use once_cell::sync::Lazy;
use std::sync::Mutex;

use crate::api::vault::{load_vault, save_vault};
use crate::api::vault_bridge::EntrySummaryData;
use crate::vault::entry::VaultEntry;

// ── Session state ─────────────────────────────────────────────────────────────

pub struct VaultSession {
    pub entries: Vec<VaultEntry>,
    pub path: PathBuf,
    pub passphrase: Vec<u8>,
}

static VAULT_SESSION: Lazy<Mutex<Option<VaultSession>>> = 
    Lazy::new(|| Mutex::new(None));

// ── Session API ───────────────────────────────────────────────────────────────

/// Decrypt the vault at `path` and store it in memory.
///
/// Flutter awaits this — Argon2id takes ~667ms on target hardware.
pub fn unlock_vault(passphrase: &[u8], path: PathBuf) -> Result<(), String> {
    let entries = load_vault(passphrase, &path)?;
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    *session = Some(VaultSession { entries, path, passphrase: passphrase.to_vec() });
    Ok(())
}

/// Drop the session state, locking the vault.
///
/// After this call, all session functions return Err until unlock is
/// called again.
pub fn lock_vault() -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    if let Some(ref mut s) = *session {
        // Cryptographic-grade zero: volatile writes the compiler cannot optimise away.
        // Covers the passphrase bytes fully. The entries vec is cleared (drops all
        // heap-allocated String fields promptly); full per-field zeroize is a backlog item.
        s.passphrase.zeroize();
        s.entries.clear();
    }
    *session = None;
    Ok(())
}

/// Returns the UUID of any entry variant.
fn entry_id(entry: &VaultEntry) -> &str {
    match entry {
        VaultEntry::Login(e)    => &e.meta.id,
        VaultEntry::Note(e)     => &e.meta.id,
        VaultEntry::Identity(e) => &e.meta.id,
        VaultEntry::Card(e)     => &e.meta.id,
        VaultEntry::File(e)     => &e.meta.id,
        VaultEntry::Custom(e)   => &e.meta.id,
    }
}

/// Builds a lightweight summary DTO from any entry variant.
fn entry_to_summary(entry: &VaultEntry) -> EntrySummaryData {
    match entry {
        VaultEntry::Login(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Login"),
            title: e.url.clone(),
            folder: e.meta.folder.clone(),
            tags: e.meta.tags.clone(),
            favourite: e.meta.favourite,
        },
        VaultEntry::Note(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Note"),
            title: e.title.clone(),
            folder: e.meta.folder.clone(),
            tags: e.meta.tags.clone(),
            favourite: e.meta.favourite,
        },
        VaultEntry::Identity(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Identity"),
            title: format!("{} {}", e.first_name, e.last_name),
            folder: e.meta.folder.clone(),
            tags: e.meta.tags.clone(),
            favourite: e.meta.favourite,
        },
        VaultEntry::Card(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Card"),
            title: e.cardholder_name.clone(),
            folder: e.meta.folder.clone(),
            tags: e.meta.tags.clone(),
            favourite: e.meta.favourite,
        },
        VaultEntry::File(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("File"),
            title: e.filename.clone(),
            folder: e.meta.folder.clone(),
            tags: e.meta.tags.clone(),
            favourite: e.meta.favourite,
        },
        VaultEntry::Custom(e) => EntrySummaryData {
            id: e.meta.id.clone(),
            entry_type: String::from("Custom"),
            title: e.title.clone(),
            folder: e.meta.folder.clone(),
            tags: e.meta.tags.clone(),
            favourite: e.meta.favourite,
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
    session.entries
        .iter()
        .find(|e| entry_id(e) == id)
        .cloned()
        .ok_or_else(|| format!("No entry found with id: {id}"))
}

/// Add a new entry to the session and persist the vault to disk.
///
/// Async — triggers a full vault save (Argon2id + encryption).
pub fn session_create_entry(entry: VaultEntry) -> Result<EntrySummaryData, String> {
    let summary;
    let (entries, passphrase, path) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        summary = entry_to_summary(&entry);
        session.entries.push(entry);
        (session.entries.clone(), session.passphrase.clone(), session.path.clone())
    }; // ← lock released here
    save_vault(&entries, &passphrase, &path)?;
    Ok(summary)
}

/// Replace an existing entry by UUID and persist.
///
/// Async — triggers a full vault save.
pub fn session_update_entry(updated: VaultEntry) -> Result<(), String> {
    let (entries, passphrase, path) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        crate::api::vault::update_entry(&mut session.entries, updated)?;
        (session.entries.clone(), session.passphrase.clone(), session.path.clone())
    }; // ← lock released here
    save_vault(&entries, &passphrase, &path)?;
    Ok(())
}

/// Remove an entry by UUID and persist.
///
/// Async — triggers a full vault save.
pub fn session_delete_entry(id: &str) -> Result<(), String> {
    let (entries, passphrase, path) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        crate::api::vault::delete_entry(&mut session.entries, id)?;
        (session.entries.clone(), session.passphrase.clone(), session.path.clone())
    }; // ← lock released here
    save_vault(&entries, &passphrase, &path)?;
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
    // Verify old passphrase by attempting a load — reject if wrong
    load_vault(old_passphrase, &session.path)?;
    save_vault(&session.entries, new_passphrase, &session.path)?;
    session.passphrase = new_passphrase.to_vec();
    Ok(())
}

/// Write .gabbro + .gabbro.sha256 from current session state.
pub fn session_export_vault(export_path: PathBuf) -> Result<(), String> {
    let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_ref().ok_or("Vault is locked")?;
    crate::api::vault::export_vault(&session.entries, &session.passphrase, &export_path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use std::env::temp_dir;

    /// Helper — creates a minimal vault file on disk and returns its path.
    fn setup_vault(passphrase: &[u8]) -> PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_session_test.gabbro");
        let entries = vec![
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from("id-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                    tags: vec![],
                    favourite: false,
                },
                title: String::from("Session test note"),
                content: String::from("session secret content"),
            }),
        ];
        save_vault(&entries, passphrase, &path).unwrap();
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
                tags: vec![],
                favourite: false,
            },
            title: String::from("New note"),
            content: String::from("new content"),
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
}