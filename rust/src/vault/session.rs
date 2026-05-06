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
    let mut entries = load_vault(passphrase, &path)?;
    crate::api::vault::purge_expired_history(&mut entries);
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
            title: e.card_name
                .as_deref()
                .filter(|s| !s.is_empty())
                .unwrap_or(&e.cardholder_name)
                .to_string(),
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

/// Remove multiple entries by UUID from the in-memory session only — no disk write.
///
/// Used by bulk delete: remove all entries in one pass, then call
/// `session_save()` once rather than once per entry.
pub fn session_delete_entries_no_save(ids: &[String]) -> Result<(), String> {
    let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
    let session = session.as_mut().ok_or("Vault is locked")?;
    session.entries.retain(|e| !ids.contains(&entry_id(e).to_string()));
    Ok(())
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
    let (entries, passphrase, path) = {
        let session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_ref().ok_or("Vault is locked")?;
        (session.entries.clone(), session.passphrase.clone(), session.path.clone())
    };
    save_vault(&entries, &passphrase, &path)?;
    Ok(())
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
pub fn session_update_entry(updated: VaultEntry, expiry_days: Option<u32>) -> Result<(), String> {
    let (entries, passphrase, path) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        crate::api::vault::update_entry(&mut session.entries, updated, expiry_days)?;
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

/// Clear the previous password history for a Login entry and persist.
///
/// Sets `previous_password` to `None` on the identified entry.
/// Returns `Err` if the entry is not found or is not a Login entry.
pub fn session_clear_password_history(id: &str) -> Result<(), String> {
    let (entries, passphrase, path) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let entry = session.entries.iter_mut()
            .find(|e| entry_id(e) == id)
            .ok_or_else(|| format!("No entry found with id: {id}"))?;
        match entry {
            VaultEntry::Login(ref mut e) => {
                e.previous_password = None;
                e.meta.updated_at = crate::api::vault::chrono_now();
            }
            _ => return Err(format!("Entry {id} is not a Login entry")),
        }
        (session.entries.clone(), session.passphrase.clone(), session.path.clone())
    }; // ← lock released here
    save_vault(&entries, &passphrase, &path)?;
    Ok(())
}

/// Revert the current password to the previous password for a Login entry and persist.
///
/// Swaps `password` ← `previous_password.value`, then clears `previous_password`.
/// Returns `Err` if the entry is not found, is not a Login entry, or has no history.
pub fn session_revert_password(id: &str) -> Result<(), String> {
    let (entries, passphrase, path) = {
        let mut session = VAULT_SESSION.lock().map_err(|e| e.to_string())?;
        let session = session.as_mut().ok_or("Vault is locked")?;
        let entry = session.entries.iter_mut()
            .find(|e| entry_id(e) == id)
            .ok_or_else(|| format!("No entry found with id: {id}"))?;
        match entry {
            VaultEntry::Login(ref mut e) => {
                let prev = e.previous_password.take()
                    .ok_or_else(|| format!("Entry {id} has no password history to revert"))?;
                e.password = prev.value.clone();
                e.meta.updated_at = crate::api::vault::chrono_now();
            }
            _ => return Err(format!("Entry {id} is not a Login entry")),
        }
        (session.entries.clone(), session.passphrase.clone(), session.path.clone())
    }; // ← lock released here
    save_vault(&entries, &passphrase, &path)?;
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
                attachments: vec![],
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
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("id-login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
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
        assert_eq!(summary.title, "GitHub",
            "summary title should use LoginEntry.title, not url or username");
    }

    #[test]
    #[serial]
    fn login_entry_to_summary_falls_back_to_url_when_title_empty() {
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("id-login-002"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
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
        assert_eq!(summary.title, "https://example.com",
            "summary should fall back to url when title is empty");
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
                tags: vec![],
                favourite: false,
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
        assert_eq!(summary.title, "Visa Platinum",
            "summary should use card_name when present");
    }

    #[test]
    #[serial]
    fn clear_password_history_removes_previous_password() {
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry, PreviousSecret};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_clear_history_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
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

        save_vault(&[entry], pass, &path).unwrap();
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
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry, PreviousSecret};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_clear_history_persist_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
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

        save_vault(&[entry], pass, &path).unwrap();
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
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry, PreviousSecret};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_revert_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
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

        save_vault(&[entry], pass, &path).unwrap();
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
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_revert_no_history_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
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

        save_vault(&[entry], pass, &path).unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = session_revert_password("login-001");
        assert!(result.is_err());

        teardown(&path);
    }

    #[test]
    #[serial]
    fn unexpired_history_is_preserved_on_unlock() {
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry, PreviousSecret};

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
                tags: vec![],
                favourite: false,
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

        save_vault(&[entry], pass, &path).unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = get_entry("login-unexp-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert!(e.previous_password.is_some(),
                    "unexpired history must be preserved on unlock");
            }
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn keep_forever_history_is_preserved_on_unlock() {
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry, PreviousSecret};

        let pass = b"test passphrase";
        let mut path = temp_dir();
        path.push("gabbro_keep_forever_history_test.gabbro");

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("login-forever-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
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

        save_vault(&[entry], pass, &path).unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = get_entry("login-forever-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert!(e.previous_password.is_some(),
                    "keep-forever history (expires_at: None) must never be purged");
            }
            _ => panic!("Expected Login variant"),
        }

        teardown(&path);
    }

    #[test]
    #[serial]
    fn expired_history_is_purged_on_unlock() {
        use crate::vault::entry::{LoginEntry, EntryMeta, VaultEntry, PreviousSecret};

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
                tags: vec![],
                favourite: false,
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

        save_vault(&[entry], pass, &path).unwrap();
        unlock_vault(pass, path.clone()).unwrap();

        let result = get_entry("login-exp-001").unwrap();
        match result {
            VaultEntry::Login(ref e) => {
                assert!(e.previous_password.is_none(),
                    "expired history should be purged on unlock");
                assert_eq!(e.password, "current",
                    "current password must not be affected");
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
                tags: vec![],
                favourite: false,
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
        assert_eq!(summary.title, "Rob Smith",
            "summary should fall back to cardholder_name when card_name is absent");
    }
}
