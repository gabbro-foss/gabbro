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
    /// Entries skipped because their UUID already exists in the vault.
    pub skipped: Vec<SkippedEntryData>,
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
        skipped: vec![],
    })
}

/// Extract the UUID and display title from any `VaultEntry` variant.
fn entry_id_and_title(entry: &crate::vault::entry::VaultEntry) -> (String, String) {
    use crate::vault::entry::VaultEntry::*;
    match entry {
        Login(e)    => (e.meta.id.clone(), e.title.clone()),
        Note(e)     => (e.meta.id.clone(), e.title.clone()),
        Identity(e) => (e.meta.id.clone(), format!("{} {}", e.first_name, e.last_name)),
        Card(e)     => (e.meta.id.clone(), e.card_name.clone().unwrap_or_else(|| e.cardholder_name.clone())),
        File(e)     => (e.meta.id.clone(), e.filename.clone()),
        Custom(e)   => (e.meta.id.clone(), e.title.clone()),
    }
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
    let existing_ids = session::session_entry_ids()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in entries {
        let (id, title) = entry_id_and_title(&entry);
        if existing_ids.contains(&id) {
            skipped.push(SkippedEntryData {
                title,
                reason: String::from("UUID already exists"),
            });
        } else {
            session::session_add_entry_no_save(entry)?;
            imported += 1;
        }
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
        skipped,
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
    let existing_ids = session::session_entry_ids()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in entries {
        let (id, title) = entry_id_and_title(&entry);
        if existing_ids.contains(&id) {
            skipped.push(SkippedEntryData {
                title,
                reason: String::from("UUID already exists"),
            });
        } else {
            session::session_add_entry_no_save(entry)?;
            imported += 1;
        }
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
        skipped,
    })
}

// ── Gabbro → Gabbro import ────────────────────────────────────────────────────

/// A single entry skipped during Gabbro → Gabbro import.
#[derive(Debug)]
pub struct SkippedEntryData {
    /// Display title of the skipped entry.
    pub title: String,
    /// Human-readable reason for skipping.
    pub reason: String,
}

/// Returned by [`import_from_gabbro`].
#[derive(Debug)]
pub struct GabbroImportResult {
    /// Number of entries added to the session.
    pub imported: usize,
    /// Entries that were skipped (UUID already present in the session).
    pub skipped: Vec<SkippedEntryData>,
}

/// Import entries from a `.gabbro` vault file into the live session.
///
/// Decrypts the source vault at `path` using `passphrase`, then applies
/// UUID-based deduplication: entries whose UUID already exists in the session
/// are skipped; new entries are added. A single vault save is performed at
/// the end.
///
/// The vault must already be unlocked — returns `Err` if no session is active.
/// Async — triggers a single vault save (Argon2id + encryption) at the end.
pub async fn import_from_gabbro(
    path: String,
    passphrase: Vec<u8>,
) -> Result<GabbroImportResult, String> {
    use crate::api::vault::load_vault;
    use crate::vault::session;

    let source_path = std::path::PathBuf::from(&path);
    let source_entries = load_vault(&passphrase, &source_path)?;
    let existing_ids = session::session_entry_ids()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in source_entries.entries {
        let id = match &entry {
            crate::vault::entry::VaultEntry::Login(e)    => e.meta.id.clone(),
            crate::vault::entry::VaultEntry::Note(e)     => e.meta.id.clone(),
            crate::vault::entry::VaultEntry::Identity(e) => e.meta.id.clone(),
            crate::vault::entry::VaultEntry::Card(e)     => e.meta.id.clone(),
            crate::vault::entry::VaultEntry::File(e)     => e.meta.id.clone(),
            crate::vault::entry::VaultEntry::Custom(e)   => e.meta.id.clone(),
        };
        let title = match &entry {
            crate::vault::entry::VaultEntry::Login(e)    => e.title.clone(),
            crate::vault::entry::VaultEntry::Note(e)     => e.title.clone(),
            crate::vault::entry::VaultEntry::Identity(e) => format!("{} {}", e.first_name, e.last_name),
            crate::vault::entry::VaultEntry::Card(e)     => e.card_name.clone().unwrap_or_else(|| e.cardholder_name.clone()),
            crate::vault::entry::VaultEntry::File(e)     => e.filename.clone(),
            crate::vault::entry::VaultEntry::Custom(e)   => e.title.clone(),
        };

        if existing_ids.contains(&id) {
            skipped.push(SkippedEntryData {
                title,
                reason: String::from("UUID already exists"),
            });
        } else {
            session::session_add_entry_no_save(entry)?;
            imported += 1;
        }
    }

    session::session_save()?;
    Ok(GabbroImportResult { imported, skipped })
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
    use crate::vault::serialization::VaultBody;
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
        save_vault(&VaultBody { folders: vec![], entries }, passphrase, &path).unwrap();
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
    fn import_from_bitwarden_skips_existing_uuids() {
        // "bw-exists" matches "existing-001" in the session — must be skipped.
        let bitwarden_with_dupe: &str = r#"{
            "encrypted": false,
            "folders": [],
            "items": [
                {"id":"existing-001","folderId":null,"type":2,"name":"Dupe Note","notes":"already here","favorite":false,"fields":[],"secureNote":{}},
                {"id":"bw-new-001","folderId":null,"type":2,"name":"New Note","notes":"brand new","favorite":false,"fields":[],"secureNote":{}}
            ]
        }"#;

        let pass = b"bitwarden dedup passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_bitwarden(
            bitwarden_with_dupe.as_bytes().to_vec(),
        ))
        .unwrap();

        assert_eq!(result.imported, 1, "only the new entry should be imported");
        assert_eq!(result.skipped.len(), 1, "one duplicate should be skipped");
        assert_eq!(result.skipped[0].title, "Dupe Note");
        assert_eq!(result.skipped[0].reason, "UUID already exists");

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 1 new imported note
        assert_eq!(summaries.len(), 2);

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
    fn import_from_enpass_skips_existing_uuids() {
        // "existing-001" matches the entry already in the session from setup_vault.
        let enpass_with_dupe: &str = r#"{
            "items": [{
                "uuid": "existing-001",
                "title": "Dupe Note",
                "category": "note",
                "note": "already here",
                "favorite": 0,
                "archived": 0,
                "trashed": 0,
                "fields": [],
                "attachments": []
            }, {
                "uuid": "enp-new-001",
                "title": "New Note",
                "category": "note",
                "note": "brand new",
                "favorite": 0,
                "archived": 0,
                "trashed": 0,
                "fields": [],
                "attachments": []
            }]
        }"#;

        let pass = b"enpass dedup passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_enpass(enpass_with_dupe.as_bytes().to_vec())).unwrap();

        assert_eq!(result.imported, 1, "only the new entry should be imported");
        assert_eq!(result.skipped.len(), 1, "one duplicate should be skipped");
        assert_eq!(result.skipped[0].title, "Dupe Note");
        assert_eq!(result.skipped[0].reason, "UUID already exists");

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 1 new imported note
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

    // A minimal valid .gabbro vault containing two entries:
    // - "existing-001" (already in the session from setup_vault)
    // - "new-entry-001" (not in the session — should be imported)
    fn setup_source_vault(passphrase: &[u8]) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_import_source_test.gabbro");
        let entries = vec![
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from("existing-001"), // already in session
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                    tags: vec![],
                    favourite: false,
                },
                title: String::from("Existing note"),
                content: String::from("should be skipped"),
                attachments: vec![],
            }),
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from("new-entry-001"), // not in session
                    created_at: String::from("2025-02-01T00:00:00Z"),
                    updated_at: String::from("2025-02-01T00:00:00Z"),
                    folder: String::from("Personal"),
                    tags: vec![],
                    favourite: false,
                },
                title: String::from("New note"),
                content: String::from("should be imported"),
                attachments: vec![],
            }),
        ];
        save_vault(&VaultBody { folders: vec![], entries }, passphrase, &path).unwrap();
        path
    }

    #[test]
    #[serial]
    fn import_from_gabbro_skips_existing_uuids() {
        let session_pass = b"session passphrase";
        let session_path = setup_vault(session_pass);
        session::unlock_vault(session_pass, session_path.clone()).unwrap();

        let source_pass = b"source passphrase";
        let source_path = setup_source_vault(source_pass);

        let result = run(import_from_gabbro(
            source_path.to_str().unwrap().to_string(),
            source_pass.to_vec(),
        ))
        .unwrap();

        // "new-entry-001" is new → imported; "existing-001" is duplicate → skipped
        assert_eq!(result.imported, 1, "only the new entry should be imported");
        assert_eq!(result.skipped.len(), 1, "one entry should be skipped");
        assert_eq!(result.skipped[0].title, "Existing note");
        assert_eq!(result.skipped[0].reason, "UUID already exists");

        let summaries = session::list_entry_summaries().unwrap();
        // 1 original note + 1 new imported note
        assert_eq!(summaries.len(), 2);

        teardown(&session_path);
        let _ = std::fs::remove_file(&source_path);
    }

    #[test]
    #[serial]
    fn import_from_gabbro_locked_vault_returns_error() {
        session::lock_vault().unwrap();

        let source_pass = b"source passphrase";
        let mut source_path = temp_dir();
        source_path.push("gabbro_nonexistent_source.gabbro");

        let result = run(import_from_gabbro(
            source_path.to_str().unwrap().to_string(),
            source_pass.to_vec(),
        ));
        assert!(result.is_err());
    }

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
