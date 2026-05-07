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

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use serde::Deserialize;
use crate::vault::entry::{
    CardEntry, CustomEntry, CustomField, EntryAttachment, EntryMeta,
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
    #[serde(default)]
    attachments: Vec<EnpassAttachment>,
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

/// One attachment inside an Enpass item.
#[derive(Debug, Deserialize)]
struct EnpassAttachment {
    uuid: String,
    name: String,
    kind: String,
    /// Base64-encoded binary data.
    data: String,
}

// ── Public API ────────────────────────────────────────────────────────────────

/// An item that failed domain validation during parsing.
///
/// Kept internal to this module — the bridge layer maps it to
/// `ImportFailureData` in `api/import.rs`.
pub(crate) struct ParseFailure {
    pub(crate) title: String,
    pub(crate) category: String,
    pub(crate) reason: String,
    /// Raw `(key, value)` pairs using Gabbro canonical key names where
    /// mappable, falling back to the source label otherwise.
    pub(crate) raw_fields: Vec<(String, String)>,
}

/// Parse raw Enpass JSON export bytes into a list of vault entries and a list
/// of validation failures.
///
/// Returns `Err` only if the JSON itself is malformed. Individual items that
/// fail domain validation are collected into the second element of the tuple
/// rather than aborting the whole import.
pub(crate) fn parse(data: &[u8]) -> Result<(Vec<VaultEntry>, Vec<ParseFailure>), String> {
    let export: EnpassExport = serde_json::from_slice(data)
        .map_err(|e| format!("Failed to parse Enpass JSON: {}", e))?;

    let mut entries = Vec::new();
    let mut failures = Vec::new();

    for item in export.items {
        if item.archived != 0 || item.trashed != 0 {
            continue;
        }
        match convert_item(item) {
            Ok(entry) => entries.push(entry),
            Err(f) => failures.push(f),
        }
    }

    Ok((entries, failures))
}

// ── Item conversion ───────────────────────────────────────────────────────────

/// Convert active Enpass fields into raw `(key, value)` pairs for failure reporting.
///
/// Uses Gabbro canonical key names for known field types so Flutter can map
/// them directly to `CreateEntryScreen` form fields. Unknown types fall back
/// to the source label.
fn extract_raw_fields(fields: &[&EnpassField]) -> Vec<(String, String)> {
    fields
        .iter()
        .filter(|f| !f.value.is_empty())
        .map(|f| {
            let key = match f.field_type.as_str() {
                "ccNumber"      => "card_number".to_string(),
                "ccName"        => "cardholder_name".to_string(),
                "ccExpiry"      => "expiry".to_string(),
                "ccCvc"         => "cvv".to_string(),
                "ccPin"         => "pin".to_string(),
                "ccBankname"    => "bank_name".to_string(),
                "ccTxnpassword" => "transaction_password".to_string(),
                "username"      => "username".to_string(),
                "email"         => "username".to_string(),
                "password"      => "password".to_string(),
                "url"           => "url".to_string(),
                _               => f.label.clone(),
            };
            (key, f.value.clone())
        })
        .collect()
}

fn convert_item(item: EnpassItem) -> Result<VaultEntry, ParseFailure> {
    // Active fields only — drop soft-deleted fields before any mapping.
    let fields: Vec<&EnpassField> = item
        .fields
        .iter()
        .filter(|f| f.deleted == 0)
        .filter(|f| !should_drop_field(&f.field_type))
        .collect();

    let attachments = decode_attachments(&item.attachments);
    let meta = make_meta(&item.uuid, &item.category, item.favorite);

    match item.category.as_str() {
        "login" | "computer" | "finance" => {
            Ok(VaultEntry::Login(convert_login(meta, &item.title, &item.note, &fields, attachments)))
        }
        "creditcard" => {
            convert_card(meta, &item.title, &item.note, &fields, attachments)
                .map(VaultEntry::Card)
                .map_err(|reason| {
                    let mut raw = vec![("title".to_string(), item.title.clone())];
                    raw.extend(extract_raw_fields(&fields));
                    ParseFailure {
                        title: item.title.clone(),
                        category: item.category.clone(),
                        reason,
                        raw_fields: raw,
                    }
                })
        }
        "note" => {
            Ok(VaultEntry::Note(NoteEntry {
                meta,
                title: item.title,
                content: item.note,
                attachments,
            }))
        }
        _ => {
            Ok(VaultEntry::Custom(convert_custom(meta, &item.title, &item.note, &fields, attachments)))
        }
    }
}

// ── Per-type converters ───────────────────────────────────────────────────────

fn convert_login(
    meta: EntryMeta,
    title: &str,
    note: &str,
    fields: &[&EnpassField],
    attachments: Vec<EntryAttachment>,
) -> LoginEntry {
    let url      = find_field_value(fields, &["url"]);
    let username = find_field_value(fields, &["username", "email"]);
    let password = find_field_value(fields, &["password"]);

    // Everything that isn't a canonical login field becomes a custom field.
    // The skip list contains only field types that actually appear in real
    // Enpass exports and map to dedicated LoginEntry slots.
    let skip = ["url", "username", "email", "password"];
    let custom_fields = fields
        .iter()
        .filter(|f| !skip.contains(&f.field_type.as_str()))
        .map(|f| enpass_field_to_custom(*f))
        .collect();

    LoginEntry {
        meta,
        title: title.to_string(),
        url,
        username,
        password,
        notes: non_empty(note),
        custom_fields,
        attachments,
        previous_password: None,
    }
}

fn convert_card(
    meta: EntryMeta,
    title: &str,
    note: &str,
    fields: &[&EnpassField],
    attachments: Vec<EntryAttachment>,
) -> Result<CardEntry, String> {
    let card_number = find_field_value(fields, &["ccNumber"]);

    // Fields that map to dedicated CardEntry slots — everything else overflows
    // to custom_fields so no data is silently dropped on import.
    let cc_skip = ["ccName", "ccNumber", "ccExpiry", "ccCvc", "ccPin",
                   "ccBankname", "ccTxnpassword", "ccType"];
    let custom_fields = fields
        .iter()
        .filter(|f| !cc_skip.contains(&f.field_type.as_str()))
        .map(|f| enpass_field_to_custom(*f))
        .collect();

    CardEntry::new(
        meta,
        Some(title.to_string()),                                       // card_name from item title
        String::from("active"),                                        // status
        find_field_value(fields, &["ccName"]),                        // cardholder_name
        card_number,
        normalise_expiry(&find_field_value(fields, &["ccExpiry"])),   // expiry
        find_field_value(fields, &["ccCvc"]),                         // cvv
        None,                                                          // credit_limit
        None,                                                          // card_account_number
        None,                                                          // payment_network
        opt_field_value(fields, &["ccPin"]),                          // pin
        opt_field_value(fields, &["ccBankname"]),                     // bank_name
        opt_field_value(fields, &["ccTxnpassword"]),                  // transaction_password
        non_empty(note),                                               // notes
        custom_fields,
        attachments,
        None,
        None,
    )
}

fn convert_custom(
    meta: EntryMeta,
    title: &str,
    note: &str,
    fields: &[&EnpassField],
    attachments: Vec<EntryAttachment>,
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
        attachments,
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Decode a list of Enpass attachments into `EntryAttachment` values.
///
/// Attachments whose base64 `data` field cannot be decoded are silently
/// skipped — a corrupt attachment should not fail the whole import.
fn decode_attachments(raw: &[EnpassAttachment]) -> Vec<EntryAttachment> {
    raw.iter()
        .filter_map(|a| {
            match BASE64.decode(&a.data) {
                Ok(bytes) => Some(EntryAttachment {
                    uuid: a.uuid.clone(),
                    name: a.name.clone(),
                    kind: a.kind.clone(),
                    data: bytes,
                }),
                Err(e) => {
                    eprintln!("[enpass import] skipping attachment {}: {}", a.name, e);
                    None
                }
            }
        })
        .collect()
}

/// Fields that carry no user data and should be dropped before mapping.
fn should_drop_field(field_type: &str) -> bool {
    matches!(field_type,
        "totp" | "section" | "ccType"
    ) || field_type.starts_with(".Android")
}

/// Find the first non-empty matching field value by type.
/// If all matching fields are empty, returns empty string.
fn find_field_value(fields: &[&EnpassField], types: &[&str]) -> String {
    // Prefer first non-empty match across all specified types.
    fields
        .iter()
        .filter(|f| types.contains(&f.field_type.as_str()))
        .map(|f| f.value.clone())
        .find(|v| !v.is_empty())
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

/// Normalise an Enpass expiry string from `MM/YYYY` to `MM/YY`.
/// If the format is already `MM/YY` or unrecognised, returns it unchanged.
fn normalise_expiry(expiry: &str) -> String {
    let parts: Vec<&str> = expiry.splitn(2, '/').collect();
    if parts.len() == 2 && parts[1].len() == 4 {
        format!("{}/{}", parts[0], &parts[1][2..])
    } else {
        expiry.to_string()
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
        let (entries, _) = parse(login_json().as_bytes()).unwrap();
        assert_eq!(entries.len(), 1);
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.meta.id, "aaa-111");
        assert_eq!(e.title, "GitHub");
        assert_eq!(e.username, "rob");
        assert_eq!(e.password, "h4x0r");
        assert_eq!(e.url, "https://github.com");
        assert_eq!(e.meta.favourite, false);
    }

    #[test]
    fn parse_card_entry() {
        let (entries, _) = parse(card_json().as_bytes()).unwrap();
        assert_eq!(entries.len(), 1);
        let VaultEntry::Card(ref e) = entries[0] else { panic!("expected Card") };
        assert_eq!(e.meta.id, "bbb-222");
        assert_eq!(e.card_name, Some(String::from("Visa Platinum")));
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
        let (entries, _) = parse(json.as_bytes()).unwrap();
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
        let (entries, _) = parse(json.as_bytes()).unwrap();
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
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.password, "new");
    }

    #[test]
    fn malformed_json_returns_err() {
        let result = parse(b"not json at all");
        assert!(result.is_err());
    }

    // ── TDD tests for field mapping against real export schema ────────────────

    #[test]
    fn login_username_field_populates_username() {
        let json = r#"{
          "items": [{
            "uuid": "f01-001", "title": "Test Login", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "gabbro_user", "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "s3cr3t",      "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.username, "gabbro_user");
    }

    #[test]
    fn login_email_used_when_username_empty() {
        let json = r#"{
          "items": [{
            "uuid": "f01-002", "title": "Test Login", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "",                    "sensitive": 0, "deleted": 0},
              {"label": "Email",    "type": "email",    "value": "user@example.com",    "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "s3cr3t",              "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.username, "user@example.com");
    }

    #[test]
    fn login_username_preferred_over_email_when_both_present() {
        let json = r#"{
          "items": [{
            "uuid": "f01-003", "title": "Test Login", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "gabbro_user",      "sensitive": 0, "deleted": 0},
              {"label": "Email",    "type": "email",    "value": "user@example.com", "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "s3cr3t",           "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.username, "gabbro_user",
            "username field should be preferred over email when both are non-empty");
    }

    #[test]
    fn login_title_comes_from_item_title_not_url() {
        let json = r#"{
          "items": [{
            "uuid": "f01-004", "title": "My Bank", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "rob",                    "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "s3cr3t",                 "sensitive": 1, "deleted": 0},
              {"label": "Website",  "type": "url",      "value": "https://mybank.example", "sensitive": 0, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.title, "My Bank",
            "title field should come from item.title");
        assert_eq!(e.url, "https://mybank.example",
            "url should come from the url field, not the item title");
        assert_eq!(e.meta.id, "f01-004");
    }

    #[test]
    fn computer_category_maps_to_login() {
        let json = r#"{
          "items": [{
            "uuid": "f01-005", "title": "SSH Server", "category": "computer",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "root",   "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "toor",   "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        assert!(matches!(entries[0], VaultEntry::Login(_)),
            "computer category should map to LoginEntry");
    }

    #[test]
    fn finance_category_maps_to_login() {
        let json = r#"{
          "items": [{
            "uuid": "f01-006", "title": "E-Banking", "category": "finance",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "rob",    "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "s3cr3t", "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        assert!(matches!(entries[0], VaultEntry::Login(_)),
            "finance category should map to LoginEntry");
    }

    #[test]
    fn creditcard_username_and_password_fields_become_custom_fields() {
        let json = r#"{
          "items": [{
            "uuid": "f02-001", "title": "Visa", "category": "creditcard",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Name on card", "type": "ccName",   "value": "Rob Smith",        "sensitive": 0, "deleted": 0},
              {"label": "Card number",  "type": "ccNumber", "value": "4111111111111111", "sensitive": 1, "deleted": 0},
              {"label": "Expiry",       "type": "ccExpiry", "value": "12/28",            "sensitive": 0, "deleted": 0},
              {"label": "CVV",          "type": "ccCvc",    "value": "123",              "sensitive": 1, "deleted": 0},
              {"label": "Portal user",  "type": "username", "value": "rob",              "sensitive": 0, "deleted": 0},
              {"label": "Portal pass",  "type": "password", "value": "s3cr3t",           "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Card(ref e) = entries[0] else { panic!("expected Card") };
        assert_eq!(e.cardholder_name, "Rob Smith");
        assert_eq!(e.card_number, "4111111111111111");
        assert!(
            e.custom_fields.iter().any(|f| f.label == "Portal user"),
            "username field on a card should become a custom field"
        );
        assert!(
            e.custom_fields.iter().any(|f| f.label == "Portal pass" && f.hidden),
            "password field on a card should become a hidden custom field"
        );
    }

    #[test]
    fn travel_category_maps_to_custom() {
        let json = r#"{
          "items": [{
            "uuid": "f03-001", "title": "Passport", "category": "travel",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Full name",     "type": "text", "value": "Rob Smith", "sensitive": 0, "deleted": 0},
              {"label": "Passport no.",  "type": "text", "value": "X1234567",  "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        assert!(matches!(entries[0], VaultEntry::Custom(_)),
            "travel category should map to CustomEntry");
    }

    #[test]
    fn numeric_field_type_becomes_custom_field() {
        let json = r#"{
          "items": [{
            "uuid": "f04-001", "title": "Bank Account", "category": "finance",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username",       "type": "username", "value": "rob",        "sensitive": 0, "deleted": 0},
              {"label": "Password",       "type": "password", "value": "s3cr3t",     "sensitive": 1, "deleted": 0},
              {"label": "Account number", "type": "numeric",  "value": "123456789",  "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert!(
            e.custom_fields.iter().any(|f| f.label == "Account number"),
            "numeric field type should become a custom field on the login entry"
        );
    }

    #[test]
    fn section_fields_are_dropped() {
        let json = r#"{
          "items": [{
            "uuid": "f05-001", "title": "Test", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username",      "type": "username", "value": "rob",          "sensitive": 0, "deleted": 0},
              {"label": "Password",      "type": "password", "value": "s3cr3t",       "sensitive": 1, "deleted": 0},
              {"label": "Section header","type": "section",  "value": "Extra fields", "sensitive": 0, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert!(
            !e.custom_fields.iter().any(|f| f.label == "Section header"),
            "section fields should be dropped and never appear as custom fields"
        );
    }

    #[test]
    fn totp_fields_are_dropped() {
        let json = r#"{
          "items": [{
            "uuid": "f06-001", "title": "Test", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "rob",            "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "s3cr3t",         "sensitive": 1, "deleted": 0},
              {"label": "TOTP",     "type": "totp",     "value": "otpauth://...",   "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert!(
            !e.custom_fields.iter().any(|f| f.label == "TOTP"),
            "totp fields should be dropped and never appear as custom fields"
        );
    }

    #[test]
    fn card_expiry_mm_yyyy_is_normalised_to_mm_yy() {
        let json = r#"{
          "items": [{
            "uuid": "f08-001", "title": "Visa", "category": "creditcard",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Name on card", "type": "ccName",   "value": "Rob Smith",        "sensitive": 0, "deleted": 0},
              {"label": "Card number",  "type": "ccNumber", "value": "4111111111111111", "sensitive": 1, "deleted": 0},
              {"label": "Expiry",       "type": "ccExpiry", "value": "12/2028",          "sensitive": 0, "deleted": 0},
              {"label": "CVV",          "type": "ccCvc",    "value": "123",              "sensitive": 1, "deleted": 0}
            ]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Card(ref e) = entries[0] else { panic!("expected Card") };
        assert_eq!(e.expiry, "12/28",
            "MM/YYYY expiry from Enpass should be normalised to MM/YY");
    }

    #[test]
    fn attachment_is_imported_and_decoded() {
        // "aGVsbG8=" is base64 for "hello"
        let json = r#"{
          "items": [{
            "uuid": "f07-001", "title": "Test", "category": "login",
            "note": "", "favorite": 0, "archived": 0, "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "rob",    "sensitive": 0, "deleted": 0},
              {"label": "Password", "type": "password", "value": "s3cr3t", "sensitive": 1, "deleted": 0}
            ],
            "attachments": [{
              "uuid": "att-001",
              "name": "photo.jpg",
              "kind": "image/jpeg",
              "data": "aGVsbG8="
            }]
          }]
        }"#;
        let (entries, _) = parse(json.as_bytes()).unwrap();
        let VaultEntry::Login(ref e) = entries[0] else { panic!("expected Login") };
        assert_eq!(e.attachments.len(), 1, "attachment should be imported");
        assert_eq!(e.attachments[0].name, "photo.jpg");
        assert_eq!(e.attachments[0].kind, "image/jpeg");
        assert_eq!(e.attachments[0].data, b"hello",
            "attachment data should be base64-decoded to raw bytes");
    }
}
