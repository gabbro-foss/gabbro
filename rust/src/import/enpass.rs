//! Enpass JSON importer.
//!
//! Parses an Enpass `.json` export file and converts each item into a
//! `VaultEntry`. Parsing lives in Rust because untrusted external data
//! mapping into the domain model belongs where the domain model lives.
//!
//! ## What is dropped on import
//! - `archived` / `trashed` — Gabbro has no soft-delete; archived/trashed
//!   items are silently skipped
//! - `auto_submit`, `subtitle`, `category_name`, `icon` — no Gabbro equivalent
//! - `totp` fields — Gabbro deliberately excludes TOTP
//! - `section` fields — Enpass visual dividers, not data
//! - `.Android#` fields — autofill hints, not user data
//! - `deleted` fields — soft-deleted fields inside an item
//! - `history` — password history not yet in Gabbro domain model

use serde::Deserialize;
use crate::vault::entry::{
    CardEntry, CustomEntry, CustomField, EntryMeta,
    LoginEntry, NoteEntry, VaultEntry,
};
use std::collections::HashMap;

// ── Enpass JSON structs ───────────────────────────────────────────────────────

/// Top-level export file: `{ "items": [...] }`
#[derive(Debug, Deserialize)]
struct EnpassExport {
    items: Vec<EnpassItem>,
}

/// One item in the Enpass export.
#[derive(Debug, Deserialize)]
struct EnpassItem {
    uuid: String,
    title: String,
    category: String,
    #[serde(default)]
    note: String,
    #[serde(default)]
    favorite: u8,
    #[serde(default)]
    archived: u8,
    #[serde(default)]
    trashed: u8,
    #[serde(default)]
    fields: Vec<EnpassField>,
}

/// One field inside an Enpass item.
#[derive(Debug, Deserialize)]
struct EnpassField {
    label: String,
    #[serde(rename = "type")]
    field_type: String,
    #[serde(default)]
    value: String,
    #[serde(default)]
    sensitive: u8,
    #[serde(default)]
    deleted: u8,
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Parse raw Enpass JSON export bytes into a list of vault entries.
///
/// Returns `Err` if the JSON is malformed. Individual items that cannot
/// be mapped are skipped with a warning rather than failing the whole import.
pub fn parse(data: &[u8]) -> Result<Vec<VaultEntry>, String> {
    let export: EnpassExport = serde_json::from_slice(data)
        .map_err(|e| format!("Failed to parse Enpass JSON: {}", e))?;

    let entries = export
        .items
        .into_iter()
        .filter(|item| item.archived == 0 && item.trashed == 0)
        .filter_map(|item| match convert_item(item) {
            Ok(entry) => Some(entry),
            Err(e) => {
                eprintln!("[enpass import] skipping item: {}", e);
                None
            }
        })
        .collect();

    Ok(entries)
}

// ── Item conversion ───────────────────────────────────────────────────────────

fn convert_item(item: EnpassItem) -> Result<VaultEntry, String> {
    // Active fields only — drop soft-deleted fields before any mapping.
    let fields: Vec<&EnpassField> = item
        .fields
        .iter()
        .filter(|f| f.deleted == 0)
        .filter(|f| !should_drop_field(&f.field_type))
        .collect();

    let meta = make_meta(&item.uuid, &item.category, item.favorite);

    match item.category.as_str() {
        "login" | "computer" | "finance" => {
            Ok(VaultEntry::Login(convert_login(meta, &item.title, &item.note, &fields)))
        }
        "creditcard" => {
            convert_card(meta, &item.note, &fields)
                .map(VaultEntry::Card)
        }
        "note" => {
            Ok(VaultEntry::Note(NoteEntry {
                meta,
                title: item.title,
                content: item.note,
            }))
        }
        "identity" | "travel" | "misc" | _ => {
            Ok(VaultEntry::Custom(convert_custom(meta, &item.title, &item.note, &fields)))
        }
    }
}

// ── Per-type converters ───────────────────────────────────────────────────────

fn convert_login(
    meta: EntryMeta,
    _title: &str,
    note: &str,
    fields: &[&EnpassField],
) -> LoginEntry {
    let url      = find_field_value(fields, &["url"]);
    let username = find_field_value(fields, &["username", "email"]);
    let password = find_field_value(fields, &["password"]);

    // Everything that isn't a canonical login field becomes a custom field.
    let skip = ["url", "username", "email", "password"];
    let custom_fields = fields
        .iter()
        .filter(|f| !skip.contains(&f.field_type.as_str()))
        .map(|f| enpass_field_to_custom(*f))
        .collect();

    LoginEntry {
        meta,
        url,
        username,
        password,
        notes: non_empty(note),
        custom_fields,
    }
}

fn convert_card(
    meta: EntryMeta,
    note: &str,
    fields: &[&EnpassField],
) -> Result<CardEntry, String> {
    let card_number = find_field_value(fields, &["ccNumber"]);

    CardEntry::new(
        meta,
        None,                                                          // card_name
        String::from("active"),                                        // status
        find_field_value(fields, &["ccName"]),                        // cardholder_name
        card_number,
        find_field_value(fields, &["ccExpiry"]),                      // expiry
        find_field_value(fields, &["ccCvc"]),                         // cvv
        None,                                                          // credit_limit
        None,                                                          // card_account_number
        None,                                                          // payment_network
        opt_field_value(fields, &["ccPin"]),                          // pin
        opt_field_value(fields, &["ccBankname"]),                     // bank_name
        opt_field_value(fields, &["ccTxnpassword"]),                  // transaction_password
        non_empty(note),                                               // notes
    )
}

fn convert_custom(
    meta: EntryMeta,
    title: &str,
    note: &str,
    fields: &[&EnpassField],
) -> CustomEntry {
    let mut field_map: HashMap<String, CustomField> = HashMap::new();

    for f in fields {
        let key = sanitise_key(&f.label);
        field_map.insert(key, enpass_field_to_custom(f));
    }

    if let Some(note_text) = non_empty(note) {
        field_map.insert(
            String::from("notes"),
            CustomField { label: String::from("Notes"), value: note_text, hidden: false },
        );
    }

    CustomEntry {
        meta,
        title: title.to_string(),
        fields: field_map,
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Fields that carry no user data and should be dropped before mapping.
fn should_drop_field(field_type: &str) -> bool {
    matches!(field_type,
        "totp" | "section" | "ccType"
    ) || field_type.starts_with(".Android")
}

/// Find the first matching field value by type; return empty string if absent.
fn find_field_value(fields: &[&EnpassField], types: &[&str]) -> String {
    fields
        .iter()
        .find(|f| types.contains(&f.field_type.as_str()))
        .map(|f| f.value.clone())
        .unwrap_or_default()
}

/// Like `find_field_value` but returns `None` when the field is absent or empty.
fn opt_field_value(fields: &[&EnpassField], types: &[&str]) -> Option<String> {
    fields
        .iter()
        .find(|f| types.contains(&f.field_type.as_str()))
        .map(|f| f.value.clone())
        .filter(|v| !v.is_empty())
}

fn enpass_field_to_custom(f: &EnpassField) -> CustomField {
    CustomField {
        label: f.label.clone(),
        value: f.value.clone(),
        hidden: f.sensitive == 1,
    }
}

/// Produce a valid HashMap key from an arbitrary label string.
/// Lowercases, replaces spaces and special characters with underscores.
fn sanitise_key(label: &str) -> String {
    label
        .to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '_' })
        .collect()
}

/// Return `Some(s)` only if the string is non-empty, `None` otherwise.
fn non_empty(s: &str) -> Option<String> {
    if s.is_empty() { None } else { Some(s.to_string()) }
}

/// Build an `EntryMeta` from Enpass item-level fields.
/// Timestamps are left empty — Rust will stamp them on first save.
fn make_meta(uuid: &str, folder: &str, favorite: u8) -> EntryMeta {
    EntryMeta {
        id: uuid.to_string(),
        created_at: String::new(),
        updated_at: String::new(),
        folder: folder.to_string(),
        tags: vec![],
        favourite: favorite == 1,
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn login_json() -> &'static str {
        r#"{
          "items": [{
            "uuid": "aaa-111",
            "title": "GitHub",
            "category": "login",
            "note": "",
            "favorite": 0,
            "archived": 0,
            "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "rob", "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "h4x0r", "sensitive": 1, "deleted": 0},
              {"label": "Website",  "type": "url",      "value": "https://github.com", "sensitive": 0, "deleted": 0}
            ]
          }]
        }"#
    }

    fn card_json() -> &'static str {
        r#"{
          "items": [{
            "uuid": "bbb-222",
            "title": "Visa Platinum",
            "category": "creditcard",
            "note": "",
            "favorite": 1,
            "archived": 0,
            "trashed": 0,
            "fields": [
              {"label": "Name on card", "type": "ccName",   "value": "Rob Smith",        "sensitive": 0, "deleted": 0},
              {"label": "Card number",  "type": "ccNumber", "value": "4111111111111111", "sensitive": 1, "deleted": 0},
              {"label": "Expiry",       "type": "ccExpiry", "value": "12/28",            "sensitive": 0, "deleted": 0},
              {"label": "CVV",          "type": "ccCvc",    "value": "123",              "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#
    }

    #[test]
    fn parse_login_entry() {
        let entries = parse(login_json().as_bytes()).unwrap();
        assert_eq!(entries.len(), 1);
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.meta.id, "aaa-111");
        assert_eq!(e.username, "rob");
        assert_eq!(e.password, "h4x0r");
        assert_eq!(e.url, "https://github.com");
        assert_eq!(e.meta.favourite, false);
    }

    #[test]
    fn parse_card_entry() {
        let entries = parse(card_json().as_bytes()).unwrap();
        assert_eq!(entries.len(), 1);
        let VaultEntry::Card(ref e) = entries[0] else { panic!("expected Card") };
        assert_eq!(e.meta.id, "bbb-222");
        assert_eq!(e.cardholder_name, "Rob Smith");
        assert_eq!(e.card_number, "4111111111111111");
        assert_eq!(e.meta.favourite, true);
    }

    #[test]
    fn archived_items_are_skipped() {
        let json = r#"{
          "items": [{
            "uuid": "ccc-333", "title": "Old entry", "category": "login",
            "note": "", "favorite": 0, "archived": 1, "trashed": 0, "fields": []
          }]
        }"#;
        let entries = parse(json.as_bytes()).unwrap();
        assert_eq!(entries.len(), 0);
    }

    #[test]
    fn trashed_items_are_skipped() {
        let json = r#"{
          "items": [{
            "uuid": "ddd-444", "title": "Deleted entry", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 1, "fields": []
          }]
        }"#;
        let entries = parse(json.as_bytes()).unwrap();
        assert_eq!(entries.len(), 0);
    }

    #[test]
    fn deleted_fields_are_dropped() {
        let json = r#"{
          "items": [{
            "uuid": "eee-555", "title": "Test", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "rob",   "sensitive": 0, "deleted": 0},
              {"label": "Old pass", "type": "password", "value": "old",   "sensitive": 1, "deleted": 1},
              {"label": "New pass", "type": "password", "value": "new",   "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let entries = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.password, "new");
    }

    #[test]
    fn malformed_json_returns_err() {
        let result = parse(b"not json at all");
        assert!(result.is_err());
    }
}