//! Import bridge — flutter_rust_bridge-facing wrappers for all importers.
//!
//! These functions are what Flutter actually calls. Each function delegates
//! to the relevant importer in `rust/src/import/` and uses the bulk
//! no-save + single-save pattern to avoid running Argon2id once per entry.

use crate::api::vault::chrono_now;
use crate::import::bitwarden;
use crate::import::csv::{import_csv, sniff_csv as csv_sniff, CsvImportConfig};
use crate::import::dashlane;
use crate::import::enpass;
use crate::import::google_pm;
use crate::vault::entry::{new_entry_id, CustomField, EntryMeta, LoginEntry, VaultEntry};
use crate::vault::session;

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
    /// Entries skipped because the vault already holds identical content.
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
pub async fn import_from_csv(
    input: String,
    config: CsvImportConfigData,
) -> Result<ImportResult, String> {
    let csv_config = CsvImportConfig {
        title_col: config.title_col,
        url_col: config.url_col,
        username_col: config.username_col,
        password_col: config.password_col,
        notes_col: config.notes_col,
    };

    // Scrub the raw import buffer (holds plaintext secrets) on drop (S-06).
    let input = zeroize::Zeroizing::new(input);
    let entries = import_csv(&input, &csv_config)?;
    // Grows as rows are added, so a file listing the same row twice imports it once.
    let mut existing = session::session_entry_content_hashes()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for csv_entry in entries {
        let now = chrono_now();
        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: new_entry_id(),
                created_at: now.clone(),
                updated_at: now,
                folder: String::new(),
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
            app_id: None,
            email: None,
        });
        let (_, title) = entry_id_and_title(&entry);
        let hash = entry.content_hash();
        if existing.contains(&hash) {
            skipped.push(SkippedEntryData { title });
        } else {
            existing.insert(hash);
            session::session_add_entry_no_save(entry)?;
            imported += 1;
        }
    }

    session::session_save()?;
    Ok(ImportResult {
        imported,
        failures: vec![],
        skipped,
    })
}

/// Fill empty `created_at` / `updated_at` timestamps on a freshly-imported
/// entry. Google PM and Dashlane parsers generate new UUIDs but leave
/// timestamps empty; the bridge stamps them before adding to the session.
fn stamp_timestamps(mut entry: VaultEntry, now: &str) -> VaultEntry {
    let meta = match &mut entry {
        VaultEntry::Login(e) => &mut e.meta,
        _ => return entry,
    };
    if meta.created_at.is_empty() {
        meta.created_at = now.to_string();
    }
    if meta.updated_at.is_empty() {
        meta.updated_at = now.to_string();
    }
    entry
}

/// Extract the UUID and display title from any `VaultEntry` variant.
fn entry_id_and_title(entry: &crate::vault::entry::VaultEntry) -> (String, String) {
    use crate::vault::entry::VaultEntry::*;
    match entry {
        Login(e) => (e.meta.id.clone(), e.title.clone()),
        Note(e) => (e.meta.id.clone(), e.title.clone()),
        Identity(e) => (
            e.meta.id.clone(),
            format!("{} {}", e.first_name, e.last_name),
        ),
        Card(e) => (
            e.meta.id.clone(),
            e.card_name
                .clone()
                .unwrap_or_else(|| e.cardholder_name.clone()),
        ),
        File(e) => (e.meta.id.clone(), e.filename.clone()),
        Custom(e) => (e.meta.id.clone(), e.title.clone()),
        Passkey(e) => (e.meta.id.clone(), e.rp_id.clone()),
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
    // Scrub the raw import buffer (holds plaintext secrets) on drop (S-06).
    let data = zeroize::Zeroizing::new(data);
    let (entries, failures) = bitwarden::parse(&data)?;
    // Grows as entries are added, so a file listing the same credential twice
    // imports it once.
    let mut existing = session::session_entry_content_hashes()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in entries {
        let (_, title) = entry_id_and_title(&entry);
        let hash = entry.content_hash();
        if existing.contains(&hash) {
            skipped.push(SkippedEntryData { title });
        } else {
            existing.insert(hash);
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
    // Scrub the raw import buffer (holds plaintext secrets) on drop (S-06).
    let data = zeroize::Zeroizing::new(data);
    let (entries, failures) = enpass::parse(&data)?;
    // Grows as entries are added, so a file listing the same credential twice
    // imports it once.
    let mut existing = session::session_entry_content_hashes()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in entries {
        let (_, title) = entry_id_and_title(&entry);
        let hash = entry.content_hash();
        if existing.contains(&hash) {
            skipped.push(SkippedEntryData { title });
        } else {
            existing.insert(hash);
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

/// Import all entries from a Google Password Manager CSV export into the
/// live session, then persist once.
///
/// `data` is the raw bytes of the `.csv` export from passwords.google.com.
/// The vault must already be unlocked — returns `Err` if no session is active.
///
/// Async — triggers a single vault save (Argon2id + encryption) at the end.
pub async fn import_from_google_pm(data: Vec<u8>) -> Result<ImportResult, String> {
    // Scrub the raw import buffer (holds plaintext secrets) on drop (S-06).
    let data = zeroize::Zeroizing::new(data);
    let (entries, failures) = google_pm::parse(&data)?;
    // Grows as entries are added, so a file listing the same credential twice
    // imports it once.
    let mut existing = session::session_entry_content_hashes()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in entries {
        let (_, title) = entry_id_and_title(&entry);
        let hash = entry.content_hash();
        if existing.contains(&hash) {
            skipped.push(SkippedEntryData { title });
        } else {
            existing.insert(hash);
            let now = chrono_now();
            // Google PM entries are freshly assigned UUIDs — stamp timestamps.
            let entry = stamp_timestamps(entry, &now);
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

/// Import all entries from a Dashlane credentials CSV export into the
/// live session, then persist once.
///
/// `data` is the raw bytes of the `.csv` credentials export from Dashlane.
/// The vault must already be unlocked — returns `Err` if no session is active.
///
/// Async — triggers a single vault save (Argon2id + encryption) at the end.
pub async fn import_from_dashlane(data: Vec<u8>) -> Result<ImportResult, String> {
    // Scrub the raw import buffer (holds plaintext secrets) on drop (S-06).
    let data = zeroize::Zeroizing::new(data);
    let (entries, failures) = dashlane::parse(&data)?;
    // Grows as entries are added, so a file listing the same credential twice
    // imports it once.
    let mut existing = session::session_entry_content_hashes()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in entries {
        let (_, title) = entry_id_and_title(&entry);
        let hash = entry.content_hash();
        if existing.contains(&hash) {
            skipped.push(SkippedEntryData { title });
        } else {
            existing.insert(hash);
            let now = chrono_now();
            let entry = stamp_timestamps(entry, &now);
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
    ///
    /// No reason field: there is exactly one reason (the vault already holds this
    /// content), and the dialog states it once in the user's own language. A
    /// per-entry reason meant shipping hardcoded English across the bridge.
    pub title: String,
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
/// content-hash deduplication: entries the session already holds are skipped;
/// new entries are added. Import never updates an existing entry — that is
/// sync's job. A single vault save is performed at the end.
///
/// The vault must already be unlocked — returns `Err` if no session is active.
/// Async — triggers a single vault save (Argon2id + encryption) at the end.
pub async fn import_from_gabbro(
    path: String,
    passphrase: Vec<u8>,
) -> Result<GabbroImportResult, String> {
    use crate::api::vault::load_vault;

    let source_path = std::path::PathBuf::from(&path);
    let source = load_vault(&passphrase, &source_path)?;
    merge_source_into_session(source)
}

/// Import/sync from a **key-protected** `.gabbro` vault (ADR-013).
///
/// Opens the source at `path` with the source passphrase AND a registered YubiKey
/// (its hmac-secret output + credential id), then merges into the session exactly
/// as [`import_from_gabbro`]. This is the path for syncing a vault created with
/// YubiKey protection: passphrase alone is refused by the crypto, so the source's
/// chosen protection is upheld across the sync. `hmac_secret` must be 32 bytes.
///
/// The vault must already be unlocked — returns `Err` if no session is active.
pub async fn import_from_gabbro_with_key(
    path: String,
    passphrase: Vec<u8>,
    hmac_secret: Vec<u8>,
    credential_id: Vec<u8>,
) -> Result<GabbroImportResult, String> {
    use crate::api::vault::load_vault_with_key_record;

    let secret: [u8; 32] = hmac_secret
        .try_into()
        .map_err(|_| "hmac_secret must be exactly 32 bytes".to_string())?;
    let source_path = std::path::PathBuf::from(&path);
    let (source, _master, _wrapping) =
        load_vault_with_key_record(&passphrase, &secret, &credential_id, &source_path)?;
    merge_source_into_session(source)
}

/// Merge a decrypted source vault body into the live session: UUID-based dedup
/// (existing UUIDs skipped, new entries added), then a single save. Shared by the
/// passphrase-only and key-protected Gabbro import paths.
fn merge_source_into_session(
    source: crate::vault::serialization::VaultBody,
) -> Result<GabbroImportResult, String> {
    // Grows as entries are added, so a source holding the same entry twice
    // imports it once.
    let mut existing = session::session_entry_content_hashes()?;

    let mut imported = 0;
    let mut skipped = Vec::new();

    for entry in source.entries {
        let (_, title) = entry_id_and_title(&entry);
        let hash = entry.content_hash();
        if existing.contains(&hash) {
            skipped.push(SkippedEntryData { title });
        } else {
            existing.insert(hash);
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
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("existing-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Existing note"),
            content: String::from("already here"),
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

    fn teardown(path: &std::path::PathBuf) {
        let _ = session::lock_vault();
        let _ = std::fs::remove_file(path);
    }

    const SAMPLE_CSV: &str = "\
name,url,login,password,comments,favourite
Example,https://example.com,user,hunter2,my example,yes
Sample,https://example.net,user@example.com,s3cr3t,,no";

    const BITWARDEN_JSON: &str = r#"{
        "encrypted": false,
        "folders": [],
        "items": [
            {"id":"bw-001","folderId":null,"type":1,"name":"Example","notes":null,"favorite":false,"fields":[],"login":{"uris":[{"uri":"https://example.com"}],"username":"user","password":"hunter2"}},
            {"id":"bw-002","folderId":null,"type":2,"name":"SSH Key","notes":"my key passphrase","favorite":false,"fields":[],"secureNote":{}},
            {"id":"bw-003","folderId":null,"type":3,"name":"Visa","notes":null,"favorite":false,"fields":[],"card":{"cardholderName":"Alex","brand":"Visa","number":"4111111111111111","expMonth":"12","expYear":"2028","code":"123"}},
            {"id":"bw-004","folderId":null,"type":4,"name":"Alex Example","notes":null,"favorite":false,"fields":[],"identity":{"firstName":"Alex","lastName":"Example","email":"user@example.com","phone":null,"company":null}},
            {"id":"bw-005","folderId":null,"type":99,"name":"Unknown","notes":null,"favorite":false,"fields":[]}
        ]
    }"#;

    const ENPASS_JSON: &str = r#"{
        "items": [{
            "uuid": "enp-001",
            "title": "Example",
            "category": "login",
            "note": "",
            "favorite": 0,
            "archived": 0,
            "trashed": 0,
            "fields": [
                {"label":"Username","type":"username","value":"user","sensitive":0,"deleted":0},
                {"label":"Password","type":"password","value":"hunter2","sensitive":1,"deleted":0},
                {"label":"Website","type":"url","value":"https://example.com","sensitive":0,"deleted":0}
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
    fn import_from_csv_persists_at_current_version() {
        // Import persists via the standard save dispatch, so the resulting file must
        // be stamped the current format VERSION. Guards against import silently
        // writing an old format after a version bump.
        use crate::vault::file_format::VERSION;
        use crate::vault::io::read_vault;

        let pass = b"import version passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = CsvImportConfigData {
            title_col: Some("name".to_string()),
            password_col: Some("password".to_string()),
            url_col: None,
            username_col: None,
            notes_col: None,
        };

        let _ = run(import_from_csv(SAMPLE_CSV.to_string(), config)).unwrap();

        assert_eq!(
            read_vault(&path).unwrap().version,
            VERSION,
            "import must persist the vault at the current format VERSION"
        );

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_bitwarden_skips_entries_already_in_the_vault() {
        // The first item's content matches the session's own note, whatever id the
        // export gave it — so it must be skipped.
        let bitwarden_with_dupe: &str = r#"{
            "encrypted": false,
            "folders": [],
            "items": [
                {"id":"bw-any-id","folderId":null,"type":2,"name":"Existing note","notes":"already here","favorite":false,"fields":[],"secureNote":{}},
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
        assert_eq!(result.skipped[0].title, "Existing note");

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 1 new imported note
        assert_eq!(summaries.len(), 2);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_never_modifies_an_existing_entry() {
        // Add-only invariant: import adds entries, it never reconciles fields on one
        // already in the vault — that is sync's job. The incoming entry carries the
        // same id as "existing-001" but different content; the stored entry must be
        // byte-identical afterwards.
        let bitwarden_collides_and_differs: &str = r#"{
            "encrypted": false,
            "folders": [],
            "items": [
                {"id":"existing-001","folderId":null,"type":2,"name":"Changed title","notes":"changed content","favorite":false,"fields":[],"secureNote":{}}
            ]
        }"#;

        let pass = b"import add only passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let before = session::get_entry("existing-001").unwrap();
        let _ = run(import_from_bitwarden(
            bitwarden_collides_and_differs.as_bytes().to_vec(),
        ))
        .unwrap();
        let after = session::get_entry("existing-001").unwrap();

        assert_eq!(
            before, after,
            "import must leave an existing entry untouched"
        );

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_bitwarden_adds_entries_to_session() {
        let pass = b"bitwarden test passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_bitwarden(BITWARDEN_JSON.as_bytes().to_vec())).unwrap();
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
    fn import_from_enpass_skips_entries_already_in_the_vault() {
        // The first item's content matches the session's own note, whatever uuid the
        // export gave it — so it must be skipped.
        let enpass_with_dupe: &str = r#"{
            "items": [{
                "uuid": "enp-any-uuid",
                "title": "Existing note",
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
        assert_eq!(result.skipped[0].title, "Existing note");

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
                {"label":"Name on Card","type":"ccName","value":"Alex","sensitive":0,"deleted":0}
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
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("existing-001"), // already in session
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                },
                title: String::from("Existing note"),
                // Same content as the session's own entry, so the content hash
                // matches and import recognises it.
                content: String::from("already here"),
                custom_fields: vec![],
                attachments: vec![],
            }),
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    history: Vec::new(),
                    id: String::from("new-entry-001"), // not in session
                    created_at: String::from("2025-02-01T00:00:00Z"),
                    updated_at: String::from("2025-02-01T00:00:00Z"),
                    folder: String::from("Personal"),
                },
                title: String::from("New note"),
                content: String::from("should be imported"),
                custom_fields: vec![],
                attachments: vec![],
            }),
        ];
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

    #[test]
    #[serial]
    fn import_from_gabbro_skips_entries_already_in_the_vault() {
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

        // "New note" is new -> imported; "Existing note" matches by content -> skipped
        assert_eq!(result.imported, 1, "only the new entry should be imported");
        assert_eq!(result.skipped.len(), 1, "one entry should be skipped");
        assert_eq!(result.skipped[0].title, "Existing note");

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

    const GOOGLE_PM_CSV: &str = "\
name,url,username,password,note
Example,https://example.com,user,hunter2,my example
Sample,https://example.net,user@example.com,s3cr3t,";

    const DASHLANE_CSV: &str = "\
username,username2,username3,url,category,note,password,title
user@example.com,,,https://example.com,Work,my example,hunter2,Example
user@example.com,backup@example.com,,https://example.net,Personal,,s3cr3t,Sample";

    #[test]
    #[serial]
    fn import_from_google_pm_adds_entries_to_session() {
        let pass = b"google pm test passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_google_pm(GOOGLE_PM_CSV.as_bytes().to_vec())).unwrap();
        assert_eq!(result.imported, 2);
        assert!(result.failures.is_empty());

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 2 imported logins
        assert_eq!(summaries.len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_google_pm_locked_vault_returns_error() {
        session::lock_vault().unwrap();
        let result = run(import_from_google_pm(GOOGLE_PM_CSV.as_bytes().to_vec()));
        assert!(result.is_err());
    }

    #[test]
    #[serial]
    fn import_from_dashlane_adds_entries_to_session() {
        let pass = b"dashlane test passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_dashlane(DASHLANE_CSV.as_bytes().to_vec())).unwrap();
        assert_eq!(result.imported, 2);
        assert!(result.failures.is_empty());

        let summaries = session::list_entry_summaries().unwrap();
        // 1 existing note + 2 imported logins
        assert_eq!(summaries.len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn import_from_dashlane_locked_vault_returns_error() {
        session::lock_vault().unwrap();
        let result = run(import_from_dashlane(DASHLANE_CSV.as_bytes().to_vec()));
        assert!(result.is_err());
    }

    // ── S6: re-importing the same file imports nothing ────────────────────────
    // One per source. Dedup is on content, so it holds whether or not the export
    // carries an id — the user gets the same answer from every source.

    #[test]
    #[serial]
    fn google_pm_reimport_imports_nothing() {
        let pass = b"google pm reimport passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let first = run(import_from_google_pm(GOOGLE_PM_CSV.as_bytes().to_vec())).unwrap();
        let second = run(import_from_google_pm(GOOGLE_PM_CSV.as_bytes().to_vec())).unwrap();

        assert_eq!(first.imported, 2);
        assert_eq!(second.imported, 0, "the same rows must not import twice");
        assert_eq!(
            second.skipped.len(),
            2,
            "both rows must be reported skipped"
        );
        // 1 existing note + 2 imported once
        assert_eq!(session::list_entry_summaries().unwrap().len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn dashlane_reimport_imports_nothing() {
        let pass = b"dashlane reimport passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let first = run(import_from_dashlane(DASHLANE_CSV.as_bytes().to_vec())).unwrap();
        let second = run(import_from_dashlane(DASHLANE_CSV.as_bytes().to_vec())).unwrap();

        assert_eq!(first.imported, 2);
        assert_eq!(second.imported, 0, "the same rows must not import twice");
        assert_eq!(
            second.skipped.len(),
            2,
            "both rows must be reported skipped"
        );
        assert_eq!(session::list_entry_summaries().unwrap().len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn csv_reimport_imports_nothing_and_reports_the_skips() {
        let pass = b"csv reimport passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = || CsvImportConfigData {
            title_col: Some("name".to_string()),
            url_col: Some("url".to_string()),
            username_col: Some("login".to_string()),
            password_col: Some("password".to_string()),
            notes_col: Some("comments".to_string()),
        };

        let first = run(import_from_csv(SAMPLE_CSV.to_string(), config())).unwrap();
        let second = run(import_from_csv(SAMPLE_CSV.to_string(), config())).unwrap();

        assert_eq!(first.imported, 2);
        assert!(
            first.skipped.is_empty(),
            "a first import skips nothing on an unrelated vault"
        );
        assert_eq!(second.imported, 0, "the same rows must not import twice");
        assert_eq!(
            second.skipped.len(),
            2,
            "the CSV path must report its skips too"
        );
        assert_eq!(session::list_entry_summaries().unwrap().len(), 3);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn bitwarden_reimport_imports_nothing() {
        let pass = b"bitwarden reimport passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let first = run(import_from_bitwarden(BITWARDEN_JSON.as_bytes().to_vec())).unwrap();
        let second = run(import_from_bitwarden(BITWARDEN_JSON.as_bytes().to_vec())).unwrap();

        assert_eq!(first.imported, 4);
        assert_eq!(second.imported, 0, "the same items must not import twice");
        assert_eq!(second.skipped.len(), 4);
        assert_eq!(session::list_entry_summaries().unwrap().len(), 5);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn enpass_reimport_imports_nothing() {
        let pass = b"enpass reimport passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let first = run(import_from_enpass(ENPASS_JSON.as_bytes().to_vec())).unwrap();
        let second = run(import_from_enpass(ENPASS_JSON.as_bytes().to_vec())).unwrap();

        assert_eq!(first.imported, 1);
        assert_eq!(second.imported, 0, "the same items must not import twice");
        assert_eq!(second.skipped.len(), 1);
        assert_eq!(session::list_entry_summaries().unwrap().len(), 2);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn gabbro_reimport_imports_nothing() {
        let session_pass = b"gabbro reimport session passphrase";
        let session_path = setup_vault(session_pass);
        session::unlock_vault(session_pass, session_path.clone()).unwrap();

        let source_pass = b"gabbro reimport source passphrase";
        let source_path = setup_source_vault(source_pass);
        let source = || source_path.to_str().unwrap().to_string();

        let first = run(import_from_gabbro(source(), source_pass.to_vec())).unwrap();
        let second = run(import_from_gabbro(source(), source_pass.to_vec())).unwrap();

        // The source holds "Existing note" (same content as the session's own entry)
        // plus one genuinely new note.
        assert_eq!(first.imported, 1);
        assert_eq!(second.imported, 0, "the same vault must not import twice");
        assert_eq!(second.skipped.len(), 2);
        assert_eq!(session::list_entry_summaries().unwrap().len(), 2);

        teardown(&session_path);
        let _ = std::fs::remove_file(&source_path);
    }

    // ── S7: a mixed file imports only the entries not already held ────────────
    // The three sources with no id in their export. The other three are covered by
    // `import_from_{bitwarden,enpass,gabbro}_skips_entries_already_in_the_vault`,
    // whose fixtures each pair one duplicate with one new entry.

    #[test]
    #[serial]
    fn google_pm_mixed_file_imports_only_the_new_rows() {
        // Row 1 repeats a row already imported; row 2 is new. A user who adds one
        // password at the source and re-exports must get exactly that one entry.
        const MIXED: &str = "\
name,url,username,password,note
Example,https://example.com,user,hunter2,my example
Third,https://example.org,third,t0ps3cr3t,";

        let pass = b"google pm mixed passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let first = run(import_from_google_pm(GOOGLE_PM_CSV.as_bytes().to_vec())).unwrap();
        assert_eq!(first.imported, 2);

        let second = run(import_from_google_pm(MIXED.as_bytes().to_vec())).unwrap();
        assert_eq!(second.imported, 1, "only the new row imports");
        assert_eq!(second.skipped.len(), 1, "the repeated row is reported");
        assert_eq!(second.skipped[0].title, "Example");

        // 1 existing note + 2 + 1
        assert_eq!(session::list_entry_summaries().unwrap().len(), 4);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn dashlane_mixed_file_imports_only_the_new_rows() {
        const MIXED: &str = "\
username,username2,username3,url,category,note,password,title
user@example.com,,,https://example.com,Work,my example,hunter2,Example
third@example.com,,,https://example.org,Work,,t0ps3cr3t,Third";

        let pass = b"dashlane mixed passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let first = run(import_from_dashlane(DASHLANE_CSV.as_bytes().to_vec())).unwrap();
        assert_eq!(first.imported, 2);

        let second = run(import_from_dashlane(MIXED.as_bytes().to_vec())).unwrap();
        assert_eq!(second.imported, 1, "only the new row imports");
        assert_eq!(second.skipped.len(), 1, "the repeated row is reported");
        assert_eq!(second.skipped[0].title, "Example");

        assert_eq!(session::list_entry_summaries().unwrap().len(), 4);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn csv_mixed_file_imports_only_the_new_rows() {
        const MIXED: &str = "\
name,url,login,password,comments,favourite
Example,https://example.com,user,hunter2,my example,yes
Third,https://example.org,third,t0ps3cr3t,,no";

        let pass = b"csv mixed passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = || CsvImportConfigData {
            title_col: Some("name".to_string()),
            url_col: Some("url".to_string()),
            username_col: Some("login".to_string()),
            password_col: Some("password".to_string()),
            notes_col: Some("comments".to_string()),
        };

        let first = run(import_from_csv(SAMPLE_CSV.to_string(), config())).unwrap();
        assert_eq!(first.imported, 2);

        let second = run(import_from_csv(MIXED.to_string(), config())).unwrap();
        assert_eq!(second.imported, 1, "only the new row imports");
        assert_eq!(second.skipped.len(), 1, "the repeated row is reported");
        assert_eq!(second.skipped[0].title, "Example");

        assert_eq!(session::list_entry_summaries().unwrap().len(), 4);

        teardown(&path);
    }

    // ── S8: duplicate rows within one file ────────────────────────────────────
    // Three tests, one per distinct dedup site: the shape shared by
    // bitwarden/enpass/google_pm/dashlane, `merge_source_into_session`, and the
    // CSV loop. A file listing the same credential twice must leave one entry.

    #[test]
    #[serial]
    fn google_pm_duplicate_rows_in_one_file_import_once() {
        const TWICE: &str = "\
name,url,username,password,note
Example,https://example.com,user,hunter2,my example
Example,https://example.com,user,hunter2,my example";

        let pass = b"google pm self dedup passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_google_pm(TWICE.as_bytes().to_vec())).unwrap();

        assert_eq!(result.imported, 1, "the repeated row must import once");
        assert_eq!(result.skipped.len(), 1, "the repeat is reported");
        // 1 existing note + 1
        assert_eq!(session::list_entry_summaries().unwrap().len(), 2);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn csv_duplicate_rows_in_one_file_import_once() {
        const TWICE: &str = "\
name,url,login,password,comments,favourite
Example,https://example.com,user,hunter2,my example,yes
Example,https://example.com,user,hunter2,my example,yes";

        let pass = b"csv self dedup passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = CsvImportConfigData {
            title_col: Some("name".to_string()),
            url_col: Some("url".to_string()),
            username_col: Some("login".to_string()),
            password_col: Some("password".to_string()),
            notes_col: Some("comments".to_string()),
        };

        let result = run(import_from_csv(TWICE.to_string(), config)).unwrap();

        assert_eq!(result.imported, 1, "the repeated row must import once");
        assert_eq!(result.skipped.len(), 1, "the repeat is reported");
        assert_eq!(session::list_entry_summaries().unwrap().len(), 2);

        teardown(&path);
    }

    #[test]
    #[serial]
    fn gabbro_source_holding_the_same_entry_twice_imports_it_once() {
        // A source vault carrying one note under two different ids. The ids differ,
        // the content does not, so the user should end up with one entry.
        let session_pass = b"gabbro self dedup session passphrase";
        let session_path = setup_vault(session_pass);

        let source_pass = b"gabbro self dedup source passphrase";
        let mut source_path = temp_dir();
        source_path.push("gabbro_self_dedup_source.gabbro");
        let twin = |id: &str| {
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from(id),
                    created_at: String::from("2025-03-01T00:00:00Z"),
                    updated_at: String::from("2025-03-01T00:00:00Z"),
                    folder: String::from("Personal"),
                    ..Default::default()
                },
                title: String::from("Twin note"),
                content: String::from("same content"),
                custom_fields: vec![],
                attachments: vec![],
            })
        };
        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![twin("twin-a"), twin("twin-b")],
                ..Default::default()
            },
            source_pass,
            &source_path,
        )
        .unwrap();

        session::unlock_vault(session_pass, session_path.clone()).unwrap();
        let result = run(import_from_gabbro(
            source_path.to_str().unwrap().to_string(),
            source_pass.to_vec(),
        ))
        .unwrap();

        assert_eq!(result.imported, 1, "the twin must import once");
        assert_eq!(result.skipped.len(), 1, "the twin is reported skipped");
        assert_eq!(session::list_entry_summaries().unwrap().len(), 2);

        teardown(&session_path);
        let _ = std::fs::remove_file(&source_path);
    }

    // ── S9: a colliding id no longer suppresses a genuinely different entry ────

    #[test]
    #[serial]
    fn an_entry_whose_id_collides_but_content_differs_is_imported() {
        // Inverts the old behaviour. Under the UUID check this entry was silently
        // dropped and the user was told a duplicate had been skipped — for an entry
        // they had never seen. Ids from a file are arbitrary strings; content is not.
        let collides_by_id_only: &str = r#"{
            "encrypted": false,
            "folders": [],
            "items": [
                {"id":"existing-001","folderId":null,"type":2,"name":"Different note","notes":"different content","favorite":false,"fields":[],"secureNote":{}}
            ]
        }"#;

        let pass = b"id collision passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_bitwarden(
            collides_by_id_only.as_bytes().to_vec(),
        ))
        .unwrap();

        assert_eq!(result.imported, 1, "different content must import");
        assert!(
            result.skipped.is_empty(),
            "a shared id alone must not report a skip"
        );
        // The original is still there, untouched, alongside the new one.
        assert_eq!(session::list_entry_summaries().unwrap().len(), 2);

        teardown(&path);
    }

    // ── S10: importing into an empty vault ────────────────────────────────────

    fn setup_empty_vault(passphrase: &[u8]) -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_import_empty_test.gabbro");
        save_vault(
            &VaultBody {
                folders: vec![],
                entries: vec![],
                ..Default::default()
            },
            passphrase,
            &path,
        )
        .unwrap();
        path
    }

    #[test]
    #[serial]
    fn importing_into_an_empty_vault_imports_everything() {
        // Nothing to compare against, so dedup must not swallow a first import.
        let pass = b"empty vault import passphrase";
        let path = setup_empty_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let result = run(import_from_bitwarden(BITWARDEN_JSON.as_bytes().to_vec())).unwrap();

        assert_eq!(result.imported, 4, "all four supported items import");
        assert!(result.skipped.is_empty());
        assert_eq!(session::list_entry_summaries().unwrap().len(), 4);

        teardown(&path);
    }

    // ── PROBE: the exact hardware fixture, byte for byte ──────────────────────

    #[test]
    #[serial]
    fn hardware_fixture_csv_reimport_imports_nothing() {
        // The exact file from the hardware matrix, trailing newline included, with
        // the mapping csv_mapping_screen auto-selects for these headers
        // (name->title, url->url, login->username, password->password,
        // comments->notes). Every column is mapped, so custom_fields stays empty —
        // unlike SAMPLE_CSV, which leaves `favourite` unmapped.
        const HW: &str = "name,url,login,password,comments\n\
Alpha,https://alpha.example.com,user@example.com,pw-alpha,first\n\
Beta,https://beta.example.com,user@example.com,pw-beta,second\n";

        let pass = b"hardware fixture passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = || CsvImportConfigData {
            title_col: Some("name".to_string()),
            url_col: Some("url".to_string()),
            username_col: Some("login".to_string()),
            password_col: Some("password".to_string()),
            notes_col: Some("comments".to_string()),
        };

        let first = run(import_from_csv(HW.to_string(), config())).unwrap();
        assert_eq!(first.imported, 2, "first import adds both rows");

        let second = run(import_from_csv(HW.to_string(), config())).unwrap();
        assert_eq!(second.imported, 0, "re-import must add nothing");
        assert_eq!(second.skipped.len(), 2, "both rows reported skipped");
        assert_eq!(session::list_entry_summaries().unwrap().len(), 3);

        teardown(&path);
    }

    // ── PROBE: does a save/reload round trip break the content hash? ──────────

    #[test]
    #[serial]
    fn csv_reimport_after_a_reload_still_imports_nothing() {
        // Hardware found re-import duplicating where the in-session test passes.
        // The app saves, navigates, and can auto-lock between two imports, so the
        // second import compares against entries that went through serialization.
        let pass = b"csv reload reimport passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let config = || CsvImportConfigData {
            title_col: Some("name".to_string()),
            url_col: Some("url".to_string()),
            username_col: Some("login".to_string()),
            password_col: Some("password".to_string()),
            notes_col: Some("comments".to_string()),
        };

        let first = run(import_from_csv(SAMPLE_CSV.to_string(), config())).unwrap();
        assert_eq!(first.imported, 2);

        // Round-trip through disk, exactly as the app does.
        session::lock_vault().unwrap();
        session::unlock_vault(pass, path.clone()).unwrap();

        let second = run(import_from_csv(SAMPLE_CSV.to_string(), config())).unwrap();
        assert_eq!(
            second.imported, 0,
            "a saved-and-reloaded entry must still hash the same"
        );

        teardown(&path);
    }

    // ── S14: the accepted cost of content-based dedup ─────────────────────────

    #[test]
    #[serial]
    fn an_entry_edited_after_import_reimports_as_a_second_copy() {
        // Deliberate, documented behaviour, not a defect. Change the password in
        // Gabbro and the entry no longer matches the file, so a re-import adds it
        // back. Import is add-only by design; sync is the flow that reconciles an
        // edited entry. Pinned so the tradeoff cannot be lost silently.
        let pass = b"edited then reimported passphrase";
        let path = setup_vault(pass);
        session::unlock_vault(pass, path.clone()).unwrap();

        let first = run(import_from_google_pm(GOOGLE_PM_CSV.as_bytes().to_vec())).unwrap();
        assert_eq!(first.imported, 2);

        // The user changes one imported password in Gabbro.
        let summaries = session::list_entry_summaries().unwrap();
        let target = summaries
            .iter()
            .find(|s| s.title == "Example")
            .expect("the imported login should be present");
        let mut entry = session::get_entry(&target.id).unwrap();
        match &mut entry {
            VaultEntry::Login(e) => e.password = String::from("rotated-by-hand"),
            other => panic!("expected a Login, got {other:?}"),
        }
        session::session_update_entry(entry, None).unwrap();

        // Re-importing the same file brings the pre-edit version back.
        let second = run(import_from_google_pm(GOOGLE_PM_CSV.as_bytes().to_vec())).unwrap();

        assert_eq!(
            second.imported, 1,
            "the edited entry no longer matches the file, so it imports again"
        );
        assert_eq!(
            second.skipped.len(),
            1,
            "the untouched entry is still recognised"
        );
        // 1 existing note + 2 imported + 1 re-added
        assert_eq!(session::list_entry_summaries().unwrap().len(), 4);

        teardown(&path);
    }

    // ── Locked-vault error paths for remaining importers ──────────────────────

    #[test]
    #[serial]
    fn import_from_bitwarden_locked_vault_returns_error() {
        session::lock_vault().unwrap();
        let result = run(import_from_bitwarden(BITWARDEN_JSON.as_bytes().to_vec()));
        assert!(result.is_err());
    }

    #[test]
    #[serial]
    fn import_from_enpass_locked_vault_returns_error() {
        session::lock_vault().unwrap();
        let result = run(import_from_enpass(ENPASS_JSON.as_bytes().to_vec()));
        assert!(result.is_err());
    }

    #[test]
    #[serial]
    fn import_from_gabbro_wrong_passphrase_returns_error() {
        let session_pass = b"session passphrase";
        let session_path = setup_vault(session_pass);
        session::unlock_vault(session_pass, session_path.clone()).unwrap();

        let source_pass = b"source passphrase";
        let source_path = setup_source_vault(source_pass);

        let result = run(import_from_gabbro(
            source_path.to_str().unwrap().to_string(),
            b"wrong passphrase".to_vec(),
        ));
        assert!(result.is_err(), "wrong passphrase must fail Gabbro import");

        teardown(&session_path);
        let _ = std::fs::remove_file(&source_path);
    }

    // ── ADR-013: syncing a key-protected export upholds its protection ─────────
    //
    // A vault created with passphrase + YubiKeys, exported with protection
    // preserved (the default), must NOT be syncable with the passphrase alone — a
    // registered key is required. This is the patch for the second-factor bypass
    // found on 2026-06-10. The opt-in passphrase-only downgrade is a separate path.

    /// Build a key-protected source vault (passphrase + YK1 + YK2), export it
    /// PRESERVING protection (ADR-013 default), and return `(artifact, source)`
    /// paths. The artifact retains the YubiKey keyslots, so passphrase alone
    /// cannot open it. YK1 = (hmac `[0x11;32]`, cred `[0xA1;64]`).
    fn export_keyprotected_artifact(
        pass: &[u8],
        suffix: &str,
    ) -> (std::path::PathBuf, std::path::PathBuf) {
        use crate::api::vault::{export_vault_preserving, save_vault_with_keys};
        use crate::crypto::vault_crypto::YubiKeyRegistration;

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
        source.push(format!("gabbro_kp_source_{suffix}.gabbro"));
        let mut artifact = temp_dir();
        artifact.push(format!("gabbro_kp_artifact_{suffix}.gabbro"));

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

    #[test]
    #[serial]
    fn import_from_gabbro_refuses_keyprotected_source_with_passphrase_alone() {
        let pass_a: &[u8] = b"vault A passphrase -- hardware protected";
        let (artifact, source) = export_keyprotected_artifact(pass_a, "refuse");

        let pass_b = b"vault B passphrase -- yubikeyless";
        let path_b = setup_vault(pass_b); // 1 pre-existing note
        session::unlock_vault(pass_b, path_b.clone()).unwrap();

        // Passphrase alone must NOT open a key-protected export → sync refused.
        let result = run(import_from_gabbro(
            artifact.to_str().unwrap().to_string(),
            pass_a.to_vec(),
        ));
        assert!(
            result.is_err(),
            "syncing a key-protected export with passphrase alone must be refused"
        );
        // The session is untouched — nothing leaked in.
        assert_eq!(session::list_entry_summaries().unwrap().len(), 1);

        teardown(&path_b);
        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&artifact);
        let _ = std::fs::remove_file(artifact.with_extension("gabbro.sha256"));
    }

    #[test]
    #[serial]
    fn import_from_gabbro_with_key_syncs_keyprotected_source() {
        let pass_a: &[u8] = b"vault A passphrase -- hardware protected";
        let (artifact, source) = export_keyprotected_artifact(pass_a, "sync");

        let pass_b = b"vault B passphrase -- yubikeyless";
        let path_b = setup_vault(pass_b); // 1 pre-existing note
        session::unlock_vault(pass_b, path_b.clone()).unwrap();

        // Passphrase_A + a registered key (YK1) authorises the sync.
        let result = run(import_from_gabbro_with_key(
            artifact.to_str().unwrap().to_string(),
            pass_a.to_vec(),
            vec![0x11u8; 32], // YK1 hmac-secret output
            vec![0xA1u8; 64], // YK1 credential id
        ))
        .unwrap();

        assert_eq!(result.imported, 1, "A's entry must sync into B");
        assert!(result.skipped.is_empty(), "no UUID collisions expected");

        let summaries = session::list_entry_summaries().unwrap();
        assert_eq!(summaries.len(), 2, "B's own entry + A's synced entry");
        assert!(
            summaries.iter().any(|s| s.id == "from-vault-a-001"),
            "B must hold the entry that originated in key-protected vault A"
        );

        teardown(&path_b);
        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&artifact);
        let _ = std::fs::remove_file(artifact.with_extension("gabbro.sha256"));
    }

    // ── stamp_timestamps unit tests ───────────────────────────────────────────

    #[test]
    fn stamp_timestamps_fills_empty_created_and_updated_at() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("test-id"),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
            },
            title: String::from("test"),
            url: String::new(),
            username: String::new(),
            password: String::new(),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });

        let stamped = stamp_timestamps(entry, "2025-01-01T00:00:00Z");
        match stamped {
            VaultEntry::Login(ref e) => {
                assert_eq!(e.meta.created_at, "2025-01-01T00:00:00Z");
                assert_eq!(e.meta.updated_at, "2025-01-01T00:00:00Z");
            }
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn stamp_timestamps_preserves_existing_timestamps() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entry = VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("test-id"),
                created_at: String::from("2024-01-01T00:00:00Z"),
                updated_at: String::from("2024-06-01T00:00:00Z"),
                folder: String::new(),
            },
            title: String::from("test"),
            url: String::new(),
            username: String::new(),
            password: String::new(),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        });

        let stamped = stamp_timestamps(entry, "2025-01-01T00:00:00Z");
        match stamped {
            VaultEntry::Login(ref e) => {
                assert_eq!(
                    e.meta.created_at, "2024-01-01T00:00:00Z",
                    "existing created_at must not be overwritten"
                );
                assert_eq!(
                    e.meta.updated_at, "2024-06-01T00:00:00Z",
                    "existing updated_at must not be overwritten"
                );
            }
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn stamp_timestamps_non_login_entry_returned_unchanged() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let entry = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("note-id"),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
            },
            title: String::from("A note"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        });

        // stamp_timestamps only modifies Login entries; Notes pass through.
        let result = stamp_timestamps(entry, "2025-01-01T00:00:00Z");
        match result {
            VaultEntry::Note(ref e) => {
                assert_eq!(
                    e.meta.created_at, "",
                    "non-Login created_at must not be stamped"
                );
            }
            _ => panic!("expected Note"),
        }
    }

    // ── entry_id_and_title unit tests ─────────────────────────────────────────

    #[test]
    fn entry_id_and_title_identity_concatenates_names() {
        use crate::vault::entry::{EntryMeta, IdentityEntry, VaultEntry};

        let entry = VaultEntry::Identity(IdentityEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("id-001"),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
            },
            first_name: String::from("Alex"),
            last_name: String::from("Example"),
            email: String::from("user@example.com"),
            phone: None,
            address: None,
            custom_fields: vec![],
            attachments: vec![],
        });

        let (id, title) = entry_id_and_title(&entry);
        assert_eq!(id, "id-001");
        assert_eq!(title, "Alex Example");
    }

    #[test]
    fn entry_id_and_title_file_uses_filename() {
        use crate::vault::entry::{EntryMeta, FileEntry, VaultEntry};

        let entry = VaultEntry::File(FileEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                history: Vec::new(),
                id: String::from("file-001"),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
            },
            filename: String::from("document.pdf"),
            data: vec![],
            notes: None,
            custom_fields: vec![],
        });

        let (id, title) = entry_id_and_title(&entry);
        assert_eq!(id, "file-001");
        assert_eq!(title, "document.pdf");
    }
}
