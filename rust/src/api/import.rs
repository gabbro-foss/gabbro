//! Import bridge — flutter_rust_bridge-facing wrappers for all importers.
//!
//! These functions are what Flutter actually calls. Each function delegates
//! to the relevant importer in `rust/src/import/` and uses the bulk
//! no-save + single-save pattern to avoid running Argon2id once per entry.

use crate::api::vault::chrono_now;
use crate::import::csv::{import_csv, sniff_csv as csv_sniff, CsvImportConfig};
use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
use crate::vault::session;
use uuid::Uuid;

// ── CSV preview ───────────────────────────────────────────────────────────────

/// Preview of a CSV file — headers and up to 3 sample rows.
/// Returned by [`sniff_csv_file`] for Flutter's column-mapping UI.
pub struct CsvPreviewData {
    pub headers: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

/// Column mapping config passed in by Flutter after the user maps columns.
pub struct CsvImportConfigData {
    pub title_col: Option<String>,
    pub url_col: Option<String>,
    pub username_col: Option<String>,
    pub password_col: Option<String>,
    pub notes_col: Option<String>,
    pub favourite_col: Option<String>,
}

// ── Bridge functions ──────────────────────────────────────────────────────────

/// Sniff the headers and first 3 rows of a CSV string.
///
/// Sync — no I/O, pure string parsing.
#[flutter_rust_bridge::frb(sync)]
pub fn sniff_csv_file(input: String) -> Result<CsvPreviewData, String> {
    let preview = csv_sniff(&input)?;
    Ok(CsvPreviewData {
        headers: preview.headers,
        rows: preview.rows,
    })
}

/// Import all rows from a CSV string into the live session, then persist once.
///
/// The vault must already be unlocked — returns `Err` if no session is active.
/// Async — triggers a single vault save (Argon2id + encryption) at the end.
pub async fn import_from_csv(input: String, config: CsvImportConfigData) -> Result<usize, String> {
    let csv_config = CsvImportConfig {
        title_col: config.title_col,
        url_col: config.url_col,
        username_col: config.username_col,
        password_col: config.password_col,
        notes_col: config.notes_col,
        favourite_col: config.favourite_col,
    };

    let entries = import_csv(&input, &csv_config)?;
    let count = entries.len();

    for csv_entry in entries {
        let now = chrono_now();
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: Uuid::new_v4().to_string(),
                created_at: now.clone(),
                updated_at: now,
                folder: String::from("Personal"),
                tags: vec![],
                favourite: csv_entry.favourite,
            },
            title: csv_entry.title,
            url: csv_entry.url,
            username: csv_entry.username,
            password: csv_entry.password,
            notes: csv_entry.notes,
            custom_fields: csv_entry
                .custom_fields
                .into_iter()
                .map(|(label, value)| CustomField {
                    label,
                    value,
                    hidden: false,
                })
                .collect(),
            attachments: vec![],
        });
        session::session_add_entry_no_save(entry)?;
    }

    session::session_save()?;
    Ok(count)
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::vault::save_vault;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
    use serial_test::serial;
    use std::env::temp_dir;

    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(f)
    }

    fn setup_vault(passphrase: &[u8]) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_import_test.gabbro");
        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: String::from("existing-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
                tags: vec![],
                favourite: false,
            },
            title: String::from("Existing note"),
            content: String::from("already here"),
            attachments: vec![],
        })];
        save_vault(&entries, passphrase, &path).unwrap();
        path
    }

    fn teardown(path: &std::path::PathBuf) {
        let _ = session::lock_vault();
        let _ = std::fs::remove_file(path);
    }

    const SAMPLE_CSV: &str = "\
name,url,login,password,comments,favourite
GitHub,https://github.com,rob,hunter2,my github,yes
Google,https://google.com,rob@gmail.com,s3cr3t,,no";

    #[test]
    fn sniff_csv_file_returns_headers() {
        let result = sniff_csv_file(SAMPLE_CSV.to_string()).unwrap();
        assert_eq!(
            result.headers,
            vec!["name", "url", "login", "password", "comments", "favourite"]
        );
    }

    #[test]
    fn sniff_csv_file_returns_preview_rows() {
        let result = sniff_csv_file(SAMPLE_CSV.to_string()).unwrap();
        assert_eq!(result.rows.len(), 2);
    }

    #[test]
    #[serial]
    fn import_from_csv_adds_entries_to_session() {
        let pass = b"import test passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = CsvImportConfigData {
            title_col: Some("name".to_string()),
            url_col: Some("url".to_string()),
            username_col: Some("login".to_string()),
            password_col: Some("password".to_string()),
            notes_col: Some("comments".to_string()),
            favourite_col: Some("favourite".to_string()),
        };

        let count = run(import_from_csv(SAMPLE_CSV.to_string(), config)).unwrap();
        assert_eq!(count, 2);

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 2 imported logins
        assert_eq!(summaries.len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_csv_persists_to_disk() {
        let pass = b"import persist passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = CsvImportConfigData {
            title_col: Some("name".to_string()),
            password_col: Some("password".to_string()),
            url_col: None,
            username_col: None,
            notes_col: None,
            favourite_col: None,
        };

        run(import_from_csv(SAMPLE_CSV.to_string(), config)).unwrap();
        session::lock_vault().unwrap();

        // Reload from disk and verify
        session::unlock_vault(pass, path.clone()).unwrap();
        let summaries = session::list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_csv_locked_vault_returns_error() {
        session::lock_vault().unwrap();

        let config = CsvImportConfigData {
            title_col: Some("name".to_string()),
            url_col: None,
            username_col: None,
            password_col: None,
            notes_col: None,
            favourite_col: None,
        };

        let result = run(import_from_csv(SAMPLE_CSV.to_string(), config));
        assert!(result.is_err());
    }
}
