//! Dashlane CSV importer.
//!
//! Parses the credentials CSV exported from Dashlane's export feature
//! (Settings → Export Data → Credentials).
//!
//! ## Expected header row
//! `username,username2,username3,url,category,note,password,title`
//!
//! Column order is determined by position in the header row, not by index,
//! so minor column reordering in future Dashlane versions is handled
//! gracefully.
//!
//! ## What is dropped on import
//! - `category` — Dashlane categories have no direct Gabbro equivalent
//! - Empty rows
//!
//! ## What becomes custom fields
//! - `username2` and `username3` when non-empty (alternate credentials)

use crate::import::csv::parse_csv_line;
use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
use uuid::Uuid;

// ── Public API ────────────────────────────────────────────────────────────────

/// An item that failed parsing during import.
pub(crate) struct ParseFailure {
    pub(crate) title: String,
    pub(crate) category: String,
    pub(crate) reason: String,
    pub(crate) raw_fields: Vec<(String, String)>,
}

/// Parse raw Dashlane credentials CSV bytes into vault entries.
///
/// Returns `Err` only if the CSV is structurally invalid (missing required
/// columns). Individual empty rows are silently skipped.
pub(crate) fn parse(data: &[u8]) -> Result<(Vec<VaultEntry>, Vec<ParseFailure>), String> {
    if data.len() > super::TEXT_IMPORT_MAX_BYTES {
        return Err(format!(
            "Dashlane file exceeds {} MB limit",
            super::TEXT_IMPORT_MAX_BYTES / (1024 * 1024)
        ));
    }
    let text =
        std::str::from_utf8(data).map_err(|e| format!("Dashlane CSV is not valid UTF-8: {e}"))?;
    let text = text.strip_prefix('\u{FEFF}').unwrap_or(text);

    let mut lines = text.lines();
    let header_line = lines.next().ok_or("Dashlane CSV is empty")?;
    let headers = parse_csv_line(header_line);

    let col = |name: &str| -> Result<usize, String> {
        headers
            .iter()
            .position(|h| h.eq_ignore_ascii_case(name))
            .ok_or_else(|| format!("Dashlane CSV missing required column '{name}'"))
    };

    let username_idx = col("username")?;
    let url_idx = col("url")?;
    let password_idx = col("password")?;
    let title_idx = col("title")?;

    // Optional columns — absent in some export variants
    let username2_idx = col("username2").ok();
    let username3_idx = col("username3").ok();
    let note_idx = col("note").ok();
    // category intentionally ignored — no Gabbro equivalent

    let mut entries = Vec::new();
    let failures = Vec::new();

    for line in lines {
        if line.trim().is_empty() {
            continue;
        }
        let fields = parse_csv_line(line);

        let get = |idx: usize| -> String {
            fields
                .get(idx)
                .map(|s| s.as_str())
                .unwrap_or("")
                .to_string()
        };

        let title_val = get(title_idx);
        let url_val = get(url_idx);
        let title = if !title_val.is_empty() {
            title_val
        } else if !url_val.is_empty() {
            url_val.clone()
        } else {
            "MISSING TITLE".to_string()
        };

        let notes = note_idx.map(get).filter(|s| !s.is_empty());

        let mut custom_fields = Vec::new();
        if let Some(idx) = username2_idx {
            let v = get(idx);
            if !v.is_empty() {
                custom_fields.push(CustomField {
                    label: "username2".to_string(),
                    value: v,
                    hidden: false,
                });
            }
        }
        if let Some(idx) = username3_idx {
            let v = get(idx);
            if !v.is_empty() {
                custom_fields.push(CustomField {
                    label: "username3".to_string(),
                    value: v,
                    hidden: false,
                });
            }
        }

        entries.push(VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: Uuid::new_v4().to_string(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
            },
            title,
            url: url_val,
            username: get(username_idx),
            password: get(password_idx),
            notes,
            custom_fields,
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        }));
        let _ = &failures;
    }

    Ok((entries, failures))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn oversized_input_returns_err() {
        // S-02: an input over the text-import cap is rejected before parsing.
        let big = vec![b'a'; crate::import::TEXT_IMPORT_MAX_BYTES + 1];
        let err = parse(&big).err().expect("expected size-limit error");
        assert!(
            err.contains("exceeds"),
            "expected size-limit error, got: {err}"
        );
    }

    const SAMPLE_CSV: &str = "\
username,username2,username3,url,category,note,password,title
user@example.com,,,https://example.com,Work,my example account,hunter2,Example
user@example.com,backup@example.com,,https://example.net,Personal,,s3cr3t,Sample";

    #[test]
    fn parse_basic_entries() {
        let (entries, failures) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        assert_eq!(entries.len(), 2);
        assert!(failures.is_empty());
    }

    #[test]
    fn login_fields_are_mapped_correctly() {
        let (entries, _) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "Example");
        assert_eq!(e.url, "https://example.com");
        assert_eq!(e.username, "user@example.com");
        assert_eq!(e.password, "hunter2");
        assert_eq!(e.notes, Some("my example account".to_string()));
    }

    #[test]
    fn empty_note_becomes_none() {
        let (entries, _) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[1] else {
            panic!("expected Login")
        };
        assert_eq!(e.notes, None, "empty note column should produce None");
    }

    #[test]
    fn username2_becomes_custom_field_when_non_empty() {
        let (entries, _) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[1] else {
            panic!("expected Login")
        };
        assert!(
            e.custom_fields
                .iter()
                .any(|f| f.label == "username2" && f.value == "backup@example.com"),
            "non-empty username2 should become a custom field"
        );
    }

    #[test]
    fn empty_username2_is_not_a_custom_field() {
        let (entries, _) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert!(
            !e.custom_fields.iter().any(|f| f.label == "username2"),
            "empty username2 must not produce a custom field"
        );
    }

    #[test]
    fn category_is_not_imported() {
        let (entries, _) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert!(
            !e.custom_fields.iter().any(|f| f.label == "category"),
            "category column must be dropped"
        );
        assert_eq!(e.meta.folder, "", "category must not become folder");
    }

    #[test]
    fn missing_title_falls_back_to_url() {
        let csv = "username,username2,username3,url,category,note,password,title\nuser,,, https://example.com,,,s3cr3t,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        // normalise_field trims whitespace, so " https://example.com" → "https://example.com"
        assert!(!e.title.is_empty());
        assert_ne!(e.title, "MISSING TITLE");
    }

    #[test]
    fn missing_title_and_url_gives_missing_title() {
        let csv =
            "username,username2,username3,url,category,note,password,title\nuser,,,,,, s3cr3t,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "MISSING TITLE");
    }

    #[test]
    fn empty_rows_are_skipped() {
        let csv = "username,username2,username3,url,category,note,password,title\nuser,,,https://example.com,,,hunter2,Example\n\n\nuser,,,https://example.net,,,s3cr3t,Sample";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        assert_eq!(entries.len(), 2);
    }

    #[test]
    fn utf8_bom_is_stripped() {
        let csv = "\u{FEFF}username,username2,username3,url,category,note,password,title\nuser,,,https://example.com,,,hunter2,Example";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        assert_eq!(entries.len(), 1);
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "Example");
    }

    #[test]
    fn missing_required_column_returns_err() {
        // No 'password' column
        let csv = "username,url,title\nuser,https://example.com,Example";
        let result = parse(csv.as_bytes());
        assert!(result.is_err(), "missing 'password' column must return Err");
    }

    #[test]
    fn each_entry_gets_unique_uuid() {
        let (entries, _) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        let VaultEntry::Login(ref e0) = entries[0] else {
            panic!()
        };
        let VaultEntry::Login(ref e1) = entries[1] else {
            panic!()
        };
        assert_ne!(e0.meta.id, e1.meta.id);
    }

    #[test]
    fn quoted_field_with_comma_is_handled() {
        let csv = "username,username2,username3,url,category,note,password,title\nuser@example.com,,,https://bank.com,,,s3cr3t,\"Bank, Gold Card\"";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "Bank, Gold Card");
    }

    #[test]
    fn minimal_export_without_optional_columns_parses_ok() {
        // Some Dashlane export variants omit username2/username3/note
        let csv = "username,url,password,title\nuser,https://example.com,hunter2,Example";
        let (entries, failures) = parse(csv.as_bytes()).unwrap();
        assert_eq!(entries.len(), 1);
        assert!(failures.is_empty());
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "Example");
        assert_eq!(e.notes, None);
    }
}
