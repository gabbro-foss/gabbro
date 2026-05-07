//! Import bridge — flutter_rust_bridge-facing wrappers for all importers.
//!
//! These functions are what Flutter actually calls. Each function delegates
//! to the relevant importer in `rust/src/import/` and uses the bulk
//! no-save + single-save pattern to avoid running Argon2id once per entry.

use crate::api::vault::chrono_now;
use crate::import::bitwarden;
use crate::import::csv::{import_csv, sniff_csv as csv_sniff, CsvImportConfig};
use crate::import::enpass;
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

// ── Import result types ───────────────────────────────────────────────────────

/// A single entry that failed domain validation during import.
///
/// Carries enough information for Flutter to show the user what was rejected
/// and why, and to pre-populate `CreateEntryScreen` for manual correction.
#[derive(Debug)]
pub struct ImportFailureData {
    /// Display title of the failed item (from the source file).
    pub title: String,
    /// Source category string (e.g. `"creditcard"`, `"login"`).
    pub category: String,
    /// Human-readable rejection reason (e.g. `"card number must be 12–19 digits"`).
    pub reason: String,
    /// Raw field values from the source file, as `(key, value)` pairs.
    /// Keys use Gabbro's canonical names where mappable
    /// (`"card_number"`, `"username"`, `"password"`, `"url"`, `"notes"`),
    /// falling back to the source label for unmapped fields.
    pub raw_fields: Vec<(String, String)>,
}

/// Returned by all three import bridge functions.
#[derive(Debug)]
pub struct ImportResult {
    /// Number of entries successfully imported into the vault.
    pub imported: usize,
    /// Entries that failed domain validation and were not imported.
    pub failures: Vec<ImportFailureData>,
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
pub async fn import_from_csv(input: String, config: CsvImportConfigData) -> Result<ImportResult, String> {
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
            previous_password: None,
        });
        session::session_add_entry_no_save(entry)?;
    }

    session::session_save()?;
    Ok(ImportResult {
        imported: count,
        failures: vec![],
    })
}

/// Import all entries from a Bitwarden unencrypted JSON export into the
/// live session, then persist once.
///
/// `data` is the raw bytes of the Bitwarden `.json` export file.
/// The vault must already be unlocked — returns `Err` if no session is active.
///
/// Entries that fail domain validation are collected into `ImportResult.failures`
/// rather than aborting the whole import.
///
/// Async — triggers a single vault save (Argon2id + encryption) at the end.
pub async fn import_from_bitwarden(data: Vec<u8>) -> Result<ImportResult, String> {
    let (entries, failures) = bitwarden::parse(&data)?;
    let imported = entries.len();
    for entry in entries {
        session::session_add_entry_no_save(entry)?;
    }
    session::session_save()?;
    Ok(ImportResult {
        imported,
        failures: failures
            .into_iter()
            .map(|f| ImportFailureData {
                title: f.title,
                category: f.category,
                reason: f.reason,
                raw_fields: f.raw_fields,
            })
            .collect(),
    })
}

/// Import all entries from an Enpass JSON export into the live session,
/// then persist once.
///
/// `data` is the raw bytes of the Enpass `.json` export file.
/// The vault must already be unlocked — returns `Err` if no session is active.
///
/// Entries that fail domain validation are collected into `ImportResult.failures`
/// rather than aborting the whole import.
///
/// Async — triggers a single vault save (Argon2id + encryption) at the end.
pub async fn import_from_enpass(data: Vec<u8>) -> Result<ImportResult, String> {
    let (entries, failures) = enpass::parse(&data)?;
    let imported = entries.len();
    for entry in entries {
        session::session_add_entry_no_save(entry)?;
    }
    session::session_save()?;
    Ok(ImportResult {
        imported,
        failures: failures
            .into_iter()
            .map(|f| ImportFailureData {
                title: f.title,
                category: f.category,
                reason: f.reason,
                raw_fields: f.raw_fields,
            })
            .collect(),
    })
}

// ── Tests ─────────────────────────────────────────────────────────────────────

// NOTE: ImportResult and ImportFailureData are defined here as stubs so the
// test below can be written first (TDD red state). The real definitions will
// replace these once the test compiles and fails for the right reason.

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

    const BITWARDEN_JSON: &str = r#"{
        "encrypted": false,
        "folders": [],
        "items": [
            {"id":"bw-001","folderId":null,"type":1,"name":"GitHub","notes":null,"favorite":false,"fields":[],"login":{"uris":[{"uri":"https://github.com"}],"username":"rob","password":"hunter2"}},
            {"id":"bw-002","folderId":null,"type":2,"name":"SSH Key","notes":"my key passphrase","favorite":false,"fields":[],"secureNote":{}},
            {"id":"bw-003","folderId":null,"type":3,"name":"Visa","notes":null,"favorite":false,"fields":[],"card":{"cardholderName":"Rob","brand":"Visa","number":"4111111111111111","expMonth":"12","expYear":"2028","code":"123"}},
            {"id":"bw-004","folderId":null,"type":4,"name":"Rob Example","notes":null,"favorite":false,"fields":[],"identity":{"firstName":"Rob","lastName":"Example","email":"rob@example.com","phone":null,"company":null}},
            {"id":"bw-005","folderId":null,"type":99,"name":"Unknown","notes":null,"favorite":false,"fields":[]}
        ]
    }"#;

    const ENPASS_JSON: &str = r#"{
        "items": [{
            "uuid": "enp-001",
            "title": "GitHub",
            "category": "login",
            "note": "",
            "favorite": 0,
            "archived": 0,
            "trashed": 0,
            "fields": [
                {"label":"Username","type":"username","value":"rob","sensitive":0,"deleted":0},
                {"label":"Password","type":"password","value":"hunter2","sensitive":1,"deleted":0},
                {"label":"Website","type":"url","value":"https://github.com","sensitive":0,"deleted":0}
            ],
            "attachments": []
        }]
    }"#;

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

        let result = run(import_from_csv(SAMPLE_CSV.to_string(), config)).unwrap();
        assert_eq!(result.imported, 2);
        assert!(result.failures.is_empty());

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

        let _ = run(import_from_csv(SAMPLE_CSV.to_string(), config)).unwrap();
        session::lock_vault().unwrap();

        // Reload from disk and verify
        session::unlock_vault(pass, path.clone()).unwrap();
        let summaries = session::list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_bitwarden_adds_entries_to_session() {
        let pass = b"bitwarden test passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_bitwarden(
            BITWARDEN_JSON.as_bytes().to_vec(),
        ))
        .unwrap();
        assert_eq!(result.imported, 4); // login, note, card, identity — unknown type skipped
        assert!(result.failures.is_empty());

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 4 imported entries
        assert_eq!(summaries.len(), 5);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_enpass_adds_entries_to_session() {
        let pass = b"enpass test passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_enpass(ENPASS_JSON.as_bytes().to_vec())).unwrap();
        assert_eq!(result.imported, 1);
        assert!(result.failures.is_empty());

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 1 imported login
        assert_eq!(summaries.len(), 2);

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

    // Enpass JSON with a card whose number has only 4 digits — invalid per
    // CardEntry::new() (requires 12–19 digits). The entry must appear in
    // ImportResult.failures, not be silently dropped.
    const ENPASS_INVALID_CARD_JSON: &str = r#"{
        "items": [{
            "uuid": "enp-bad-001",
            "title": "Bad Card",
            "category": "creditcard",
            "note": "",
            "favorite": 0,
            "archived": 0,
            "trashed": 0,
            "fields": [
                {"label":"Card Number","type":"ccNumber","value":"1234","sensitive":0,"deleted":0},
                {"label":"Name on Card","type":"ccName","value":"Rob","sensitive":0,"deleted":0}
            ],
            "attachments": []
        }]
    }"#;

    #[test]
    #[serial]
    fn import_from_enpass_invalid_card_appears_in_failures() {
        let pass = b"enpass failure test passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_enpass(
            ENPASS_INVALID_CARD_JSON.as_bytes().to_vec(),
        ))
        .unwrap();

        assert_eq!(result.imported, 0, "no valid entries should be imported");
        assert_eq!(result.failures.len(), 1, "one failure expected");
        assert_eq!(result.failures[0].title, "Bad Card");
        assert!(
            result.failures[0].category.contains("creditcard"),
            "category should reflect source type"
        );
        assert!(
            !result.failures[0].reason.is_empty(),
            "rejection reason must not be empty"
        );
        // raw_fields must carry the original card number so Flutter can
        // pre-populate CreateEntryScreen
        assert!(
            result.failures[0]
                .raw_fields
                .iter()
                .any(|(k, v)| k == "card_number" && v == "1234"),
            "raw_fields must contain the invalid card number"
        );

        teardown(&path);
    }
}
