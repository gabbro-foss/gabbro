//! Google Password Manager CSV importer.
//!
//! Parses the fixed-schema CSV exported from passwords.google.com.
//!
//! ## Expected header row
//! `name,url,username,password,note`
//!
//! Additional columns (e.g. a `type` column added in some export variants)
//! are accepted and carried over as custom fields rather than causing a
//! parse error.
//!
//! ## What is dropped on import
//! - Empty rows
//! - Entries where both `name` and `url` are absent (title falls back
//!   to `"MISSING TITLE"` rather than being dropped)

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

/// Parse raw Google Password Manager CSV bytes into vault entries.
///
/// Returns `Err` only if the CSV is structurally invalid (no header row,
/// or missing the required `name`/`password` columns). Individual rows
/// that have no parseable data are silently skipped.
pub(crate) fn parse(data: &[u8]) -> Result<(Vec<VaultEntry>, Vec<ParseFailure>), String> {
    let text =
        std::str::from_utf8(data).map_err(|e| format!("Google PM CSV is not valid UTF-8: {e}"))?;
    let text = text.strip_prefix('\u{FEFF}').unwrap_or(text);

    let mut lines = text.lines();
    let header_line = lines.next().ok_or("Google PM CSV is empty")?;
    let headers = parse_csv_line(header_line);

    let col = |name: &str| -> Result<usize, String> {
        headers
            .iter()
            .position(|h| h.eq_ignore_ascii_case(name))
            .ok_or_else(|| format!("Google PM CSV missing required column '{name}'"))
    };

    let name_idx = col("name")?;
    let url_idx = col("url")?;
    let username_idx = col("username")?;
    let password_idx = col("password")?;
    let note_idx = col("note").ok();

    let required: Vec<usize> = {
        let mut v = vec![name_idx, url_idx, username_idx, password_idx];
        if let Some(i) = note_idx {
            v.push(i);
        }
        v
    };

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

        let name = get(name_idx);
        let url = get(url_idx);
        let title = if !name.is_empty() {
            name
        } else if !url.is_empty() {
            url.clone()
        } else {
            "MISSING TITLE".to_string()
        };

        let notes = note_idx.map(get).filter(|s| !s.is_empty());

        let custom_fields: Vec<CustomField> = headers
            .iter()
            .enumerate()
            .filter(|(i, _)| !required.contains(i))
            .filter_map(|(i, header)| {
                let value = fields.get(i).map(|s| s.as_str()).unwrap_or("").to_string();
                if value.is_empty() {
                    None
                } else {
                    Some(CustomField {
                        label: header.clone(),
                        value,
                        hidden: false,
                    })
                }
            })
            .collect();

        entries.push(VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: Uuid::new_v4().to_string(),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
            },
            title,
            url: get(url_idx),
            username: get(username_idx),
            password: get(password_idx),
            notes,
            custom_fields,
            attachments: vec![],
            previous_password: None,
            app_id: None,
        }));
        let _ = &failures; // suppress unused-variable warning while failures stays empty
    }

    Ok((entries, failures))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_CSV: &str = "\
name,url,username,password,note
GitHub,https://github.com,rob,hunter2,my github account
Google,https://google.com,rob@gmail.com,s3cr3t,";

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
        assert_eq!(e.title, "GitHub");
        assert_eq!(e.url, "https://github.com");
        assert_eq!(e.username, "rob");
        assert_eq!(e.password, "hunter2");
        assert_eq!(e.notes, Some("my github account".to_string()));
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
    fn missing_name_falls_back_to_url() {
        let csv = "name,url,username,password,note\n,https://example.com,rob,s3cr3t,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "https://example.com");
    }

    #[test]
    fn missing_name_and_url_gives_missing_title() {
        let csv = "name,url,username,password,note\n,,rob,s3cr3t,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "MISSING TITLE");
    }

    #[test]
    fn extra_columns_become_custom_fields() {
        let csv =
            "name,url,username,password,note,type\nGitHub,https://github.com,rob,hunter2,,password";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert!(
            e.custom_fields
                .iter()
                .any(|f| f.label == "type" && f.value == "password"),
            "extra column 'type' should become a custom field"
        );
    }

    #[test]
    fn empty_extra_column_is_not_a_custom_field() {
        let csv = "name,url,username,password,note,type\nGitHub,https://github.com,rob,hunter2,,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert!(
            !e.custom_fields.iter().any(|f| f.label == "type"),
            "empty extra column should not produce a custom field"
        );
    }

    #[test]
    fn empty_rows_are_skipped() {
        let csv = "name,url,username,password,note\nGitHub,https://github.com,rob,hunter2,\n\n\nGoogle,https://google.com,x,y,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        assert_eq!(entries.len(), 2);
    }

    #[test]
    fn utf8_bom_is_stripped() {
        let csv = "\u{FEFF}name,url,username,password,note\nGitHub,https://github.com,rob,s3cr3t,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        assert_eq!(entries.len(), 1);
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "GitHub");
    }

    #[test]
    fn missing_required_column_returns_err() {
        // No 'password' column
        let csv = "name,url,username,note\nGitHub,https://github.com,rob,";
        let result = parse(csv.as_bytes());
        assert!(result.is_err(), "missing 'password' column must return Err");
    }

    #[test]
    fn quoted_field_with_comma_is_handled() {
        let csv = "name,url,username,password,note\n\"Bank, Gold\",https://bank.com,rob,s3cr3t,";
        let (entries, _) = parse(csv.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!("expected Login")
        };
        assert_eq!(e.title, "Bank, Gold");
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
        assert_ne!(
            e0.meta.id, e1.meta.id,
            "every entry must have a unique UUID"
        );
    }

    #[test]
    fn folder_is_empty_on_import() {
        let (entries, _) = parse(SAMPLE_CSV.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else {
            panic!()
        };
        assert_eq!(e.meta.folder, "");
    }
}
