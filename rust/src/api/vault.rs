//! Vault API — bridge-facing functions for creating and managing vault entries.
//!
//! These functions are the only way Flutter interacts with vault data.
//! Internal domain types (LoginEntry, etc.) are never exposed directly.

use crate::vault::entry::{
    CustomField, EntryMeta, LoginEntry, NoteEntry,
};
use uuid::Uuid;

// ── Bridge-facing DTOs ────────────────────────────────────────────────────────

/// A custom field as seen by Flutter.
pub struct CustomFieldData {
    pub label: String,
    pub value: String,
    pub hidden: bool,
}

/// A login entry as seen by Flutter.
pub struct LoginEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    pub tags: Vec<String>,
    pub favourite: bool,
    pub url: String,
    pub username: String,
    pub password: String,
    pub notes: Option<String>,
    pub custom_fields: Vec<CustomFieldData>,
}

/// A note entry as seen by Flutter.
pub struct NoteEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    pub tags: Vec<String>,
    pub favourite: bool,
    pub title: String,
    pub content: String,
}

// ── Conversion helpers (internal → DTO) ──────────────────────────────────────

fn custom_field_to_data(f: CustomField) -> CustomFieldData {
    CustomFieldData {
        label: f.label,
        value: f.value,
        hidden: f.hidden,
    }
}

fn login_entry_to_data(e: LoginEntry) -> LoginEntryData {
    LoginEntryData {
        id: e.meta.id,
        created_at: e.meta.created_at,
        updated_at: e.meta.updated_at,
        folder: e.meta.folder,
        tags: e.meta.tags,
        favourite: e.meta.favourite,
        url: e.url,
        username: e.username,
        password: e.password,
        notes: e.notes,
        custom_fields: e.custom_fields.into_iter().map(custom_field_to_data).collect(),
    }
}

fn note_entry_to_data(e: NoteEntry) -> NoteEntryData {
    NoteEntryData {
        id: e.meta.id,
        created_at: e.meta.created_at,
        updated_at: e.meta.updated_at,
        folder: e.meta.folder,
        tags: e.meta.tags,
        favourite: e.meta.favourite,
        title: e.title,
        content: e.content,
    }
}
// ── Public API ────────────────────────────────────────────────────────────────

/// Creates a new login entry with a generated UUID and current timestamp.
///
/// Called by Flutter when the user saves a new login. Returns a
/// `LoginEntryData` DTO — the internal `LoginEntry` never crosses the bridge.
pub fn create_login_entry(
    folder: String,
    tags: Vec<String>,
    favourite: bool,
    url: String,
    username: String,
    password: String,
    notes: Option<String>,
    custom_fields: Vec<CustomFieldData>,
) -> LoginEntryData {
    let now = chrono_now();
    let meta = EntryMeta {
        id: Uuid::new_v4().to_string(),
        created_at: now.clone(),
        updated_at: now,
        folder,
        tags,
        favourite,
    };
    let internal_fields = custom_fields
        .into_iter()
        .map(|f| CustomField {
            label: f.label,
            value: f.value,
            hidden: f.hidden,
        })
        .collect();
    let entry = LoginEntry {
        meta,
        url,
        username,
        password,
        notes,
        custom_fields: internal_fields,
    };
    login_entry_to_data(entry)
}

/// Creates a new note entry with a generated UUID and current timestamp.
pub fn create_note_entry(
    folder: String,
    tags: Vec<String>,
    favourite: bool,
    title: String,
    content: String,
) -> NoteEntryData {
    let now = chrono_now();
    let meta = EntryMeta {
        id: Uuid::new_v4().to_string(),
        created_at: now.clone(),
        updated_at: now,
        folder,
        tags,
        favourite,
    };
    let entry = NoteEntry { meta, title, content };
    note_entry_to_data(entry)
}

// ── Timestamp helper ──────────────────────────────────────────────────────────

/// Returns the current UTC time as an ISO 8601 string.
/// Uses std only — no chrono dependency needed at this stage.
fn chrono_now() -> String {
    // std::time gives us seconds since UNIX epoch; format manually.
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    // Format as a valid ISO 8601 UTC string: YYYY-MM-DDTHH:MM:SSZ
    let s = secs;
    let sec = s % 60;
    let min = (s / 60) % 60;
    let hour = (s / 3600) % 24;
    let days = s / 86400; // days since 1970-01-01
    let (year, month, day) = days_to_ymd(days);
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", year, month, day, hour, min, sec)
}

fn days_to_ymd(mut days: u64) -> (u64, u64, u64) {
    let mut year = 1970u64;
    loop {
        let days_in_year = if is_leap(year) { 366 } else { 365 };
        if days < days_in_year { break; }
        days -= days_in_year;
        year += 1;
    }
    let months = [31, if is_leap(year) { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut month = 1u64;
    for &m in &months {
        if days < m { break; }
        days -= m;
        month += 1;
    }
    (year, month, days + 1)
}

fn is_leap(year: u64) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_login_entry_returns_correct_fields() {
        let entry = create_login_entry(
            String::from("Personal"),
            vec![String::from("web")],
            false,
            String::from("https://github.com"),
            String::from("rob"),
            String::from("hunter2"),
            None,
            vec![],
        );

        assert_eq!(entry.folder, "Personal");
        assert_eq!(entry.url, "https://github.com");
        assert_eq!(entry.username, "rob");
        assert_eq!(entry.password, "hunter2");
        assert!(entry.notes.is_none());
        assert_eq!(entry.tags, vec!["web"]);
        assert!(!entry.favourite);
    }

    #[test]
    fn create_login_entry_generates_unique_ids() {
        let a = create_login_entry(
            String::from("Work"),
            vec![],
            false,
            String::from("https://a.com"),
            String::from("user"),
            String::from("pass"),
            None,
            vec![],
        );
        let b = create_login_entry(
            String::from("Work"),
            vec![],
            false,
            String::from("https://b.com"),
            String::from("user"),
            String::from("pass"),
            None,
            vec![],
        );
        assert_ne!(a.id, b.id);
    }

    #[test]
    fn create_login_entry_with_notes_and_custom_fields() {
        let field = CustomFieldData {
            label: String::from("Recovery email"),
            value: String::from("rob@example.com"),
            hidden: false,
        };
        let entry = create_login_entry(
            String::from("Personal"),
            vec![],
            true,
            String::from("https://example.com"),
            String::from("rob"),
            String::from("s3cr3t"),
            Some(String::from("main account")),
            vec![field],
        );

        assert!(entry.notes.is_some());
        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Recovery email");
        assert!(entry.favourite);
    }

    #[test]
    fn timestamp_is_valid_iso8601_format() {
        let ts = chrono_now();
        // Basic structural check: YYYY-MM-DDTHH:MM:SSZ = 20 chars
        assert_eq!(ts.len(), 20);
        assert!(ts.ends_with('Z'));
        assert_eq!(&ts[4..5], "-");
        assert_eq!(&ts[7..8], "-");
        assert_eq!(&ts[10..11], "T");
    }

    #[test]
    fn create_note_entry_returns_correct_fields() {
        let entry = create_note_entry(
            String::from("Personal"),
            vec![],
            false,
            String::from("Shopping list"),
            String::from("Milk, eggs, bread"),
        );

        assert_eq!(entry.title, "Shopping list");
        assert_eq!(entry.content, "Milk, eggs, bread");
        assert_eq!(entry.folder, "Personal");
        assert!(!entry.favourite);
    }

    #[test]
    fn create_note_entry_generates_unique_ids() {
        let a = create_note_entry(
            String::from("Work"),
            vec![],
            false,
            String::from("Note A"),
            String::from("content a"),
        );
        let b = create_note_entry(
            String::from("Work"),
            vec![],
            false,
            String::from("Note B"),
            String::from("content b"),
        );
        assert_ne!(a.id, b.id);
    }
}