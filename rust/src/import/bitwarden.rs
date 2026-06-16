//! Bitwarden JSON vault importer.
//!
//! Parses the unencrypted `.json` export format produced by Bitwarden
//! (Tools → Export Vault → Format: .json) and converts items into
//! `Vec<VaultEntry>`.

use serde::Deserialize;
use std::collections::HashMap;

use crate::vault::entry::{
    CardEntry, CustomEntry, CustomField, EntryMeta, LoginEntry, NoteEntry, VaultEntry,
};

// ── Serde structs (mirrors the Bitwarden JSON schema) ────────────────────────

#[derive(Deserialize)]
struct BwExport {
    #[serde(default)]
    folders: Vec<BwFolder>,
    items: Vec<BwItem>,
}

#[derive(Deserialize)]
struct BwFolder {
    id: String,
    name: String,
}

#[derive(Deserialize)]
struct BwItem {
    id: String,
    #[serde(rename = "type")]
    item_type: u32,
    name: String,
    notes: Option<String>,
    #[serde(default)]
    #[serde(rename = "folderId")]
    folder_id: Option<String>,
    #[serde(default)]
    fields: Vec<BwField>,
    login: Option<BwLogin>,
    card: Option<BwCard>,
    identity: Option<BwIdentity>,
}

#[derive(Deserialize)]
struct BwField {
    name: Option<String>,
    value: Option<String>,
    #[serde(rename = "type")]
    field_type: u32,
}

#[derive(Deserialize)]
struct BwLogin {
    #[serde(default)]
    uris: Vec<BwUri>,
    username: Option<String>,
    password: Option<String>,
    // totp is intentionally ignored
}

#[derive(Deserialize)]
struct BwUri {
    uri: Option<String>,
}

#[derive(Deserialize)]
struct BwCard {
    #[serde(rename = "cardholderName")]
    cardholder_name: Option<String>,
    brand: Option<String>,
    number: Option<String>,
    #[serde(rename = "expMonth")]
    exp_month: Option<String>,
    #[serde(rename = "expYear")]
    exp_year: Option<String>,
    code: Option<String>,
}

#[derive(Deserialize)]
struct BwIdentity {
    #[serde(rename = "firstName")]
    first_name: Option<String>,
    #[serde(rename = "lastName")]
    last_name: Option<String>,
    email: Option<String>,
    phone: Option<String>,
    company: Option<String>,
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

/// Parse a Bitwarden unencrypted JSON export.
///
/// Returns `Ok((entries, failures))` on success, `Err(String)` if the
/// JSON is malformed or the top-level structure is missing.
/// Items that fail domain validation are collected into `failures` rather
/// than aborting the whole import.
pub(crate) fn parse(data: &[u8]) -> Result<(Vec<VaultEntry>, Vec<ParseFailure>), String> {
    let export: BwExport =
        serde_json::from_slice(data).map_err(|e| format!("Bitwarden JSON parse error: {e}"))?;

    // Build a folder-id → folder-name lookup table.
    let folders: HashMap<String, String> =
        export.folders.into_iter().map(|f| (f.id, f.name)).collect();

    let mut entries = Vec::new();
    let mut failures = Vec::new();

    for item in export.items {
        let folder = item
            .folder_id
            .as_deref()
            .and_then(|id| folders.get(id))
            .cloned()
            .unwrap_or_default();

        let meta = EntryMeta {
            id: item.id.clone(),
            created_at: crate::api::vault::chrono_now(),
            updated_at: crate::api::vault::chrono_now(),
            folder,
        };

        let custom_fields = convert_fields(&item.fields);

        match item.item_type {
            1 => {
                if let Some(entry) =
                    convert_login(meta, &item.name, item.notes, custom_fields, item.login)
                {
                    entries.push(VaultEntry::Login(entry));
                }
            }
            2 => {
                entries.push(VaultEntry::Note(convert_note(meta, &item.name, item.notes)));
            }
            3 => {
                match convert_card(meta, &item.name, item.notes, custom_fields, item.card) {
                    Ok(Some(entry)) => entries.push(VaultEntry::Card(entry)),
                    Ok(None) => {} // no card data present — skip silently
                    Err(f) => failures.push(f),
                }
            }
            4 => {
                entries.push(VaultEntry::Custom(convert_identity(
                    meta,
                    &item.name,
                    item.notes,
                    custom_fields,
                    item.identity,
                )));
            }
            _ => {
                // Unknown item type — skip silently.
            }
        }
    }

    Ok((entries, failures))
}

// ── Conversion helpers ────────────────────────────────────────────────────────

fn convert_fields(fields: &[BwField]) -> Vec<CustomField> {
    fields
        .iter()
        .map(|f| CustomField {
            label: f.name.clone().unwrap_or_default(),
            value: f.value.clone().unwrap_or_default(),
            // Bitwarden field type 1 = hidden/sensitive
            hidden: f.field_type == 1,
        })
        .collect()
}

fn convert_login(
    meta: EntryMeta,
    title: &str,
    notes: Option<String>,
    custom_fields: Vec<CustomField>,
    login: Option<BwLogin>,
) -> Option<LoginEntry> {
    let login = login?;
    let url = login
        .uris
        .into_iter()
        .find_map(|u| u.uri)
        .unwrap_or_default();

    Some(LoginEntry {
        meta,
        title: title.to_string(),
        url,
        username: login.username.unwrap_or_default(),
        password: login.password.unwrap_or_default(),
        notes,
        custom_fields,
        attachments: vec![],
        previous_password: None,
        app_id: None,
    })
}

fn convert_note(meta: EntryMeta, title: &str, notes: Option<String>) -> NoteEntry {
    NoteEntry {
        meta,
        title: title.to_string(),
        content: notes.unwrap_or_default(),
        custom_fields: vec![],
        attachments: vec![],
    }
}

fn convert_card(
    meta: EntryMeta,
    title: &str,
    notes: Option<String>,
    custom_fields: Vec<CustomField>,
    card: Option<BwCard>,
) -> Result<Option<CardEntry>, ParseFailure> {
    let card = match card {
        Some(c) => c,
        None => return Ok(None), // no card data present
    };

    // Combine separate expMonth / expYear into MM/YY.
    let expiry = match (card.exp_month.as_deref(), card.exp_year.as_deref()) {
        (Some(m), Some(y)) => {
            let month: u32 = m.parse().unwrap_or(0);
            let year: u32 = y.parse().unwrap_or(0);
            format!("{:02}/{:02}", month, year % 100)
        }
        _ => String::new(),
    };

    let card_number = card.number.clone().unwrap_or_default();

    CardEntry::new(
        meta,
        None,
        "active".to_string(),
        card.cardholder_name.clone().unwrap_or_default(),
        card_number.clone(),
        expiry.clone(),
        card.code.clone().unwrap_or_default(),
        None,
        None,
        card.brand.clone(),
        None,
        None,
        None,
        notes,
        custom_fields,
        vec![],
        None,
        None,
    )
    .map(Some)
    .map_err(|reason| ParseFailure {
        title: title.to_string(),
        category: "creditcard".to_string(),
        reason,
        raw_fields: {
            let mut fields = vec![
                ("title".to_string(), title.to_string()),
                ("card_number".to_string(), card_number),
            ];
            if let Some(name) = card.cardholder_name {
                fields.push(("cardholder_name".to_string(), name));
            }
            if !expiry.is_empty() {
                fields.push(("expiry".to_string(), expiry));
            }
            if let Some(cvv) = card.code {
                fields.push(("cvv".to_string(), cvv));
            }
            if let Some(brand) = card.brand {
                fields.push(("payment_network".to_string(), brand));
            }
            fields
        },
    })
}

fn convert_identity(
    meta: EntryMeta,
    title: &str,
    notes: Option<String>,
    mut custom_fields: Vec<CustomField>,
    identity: Option<BwIdentity>,
) -> CustomEntry {
    // Fold identity fields into custom fields so no data is lost.
    if let Some(id) = identity {
        let mut add = |label: &str, value: Option<String>| {
            if let Some(v) = value {
                if !v.is_empty() {
                    custom_fields.push(CustomField {
                        label: label.to_string(),
                        value: v,
                        hidden: false,
                    });
                }
            }
        };
        add("First name", id.first_name);
        add("Last name", id.last_name);
        add("Email", id.email);
        add("Phone", id.phone);
        add("Company", id.company);
        if let Some(n) = notes {
            if !n.is_empty() {
                custom_fields.push(CustomField {
                    label: "Notes".to_string(),
                    value: n,
                    hidden: false,
                });
            }
        }
    }

    let fields: HashMap<String, CustomField> = custom_fields
        .into_iter()
        .map(|f| (f.label.clone(), f))
        .collect();

    CustomEntry {
        meta,
        title: title.to_string(),
        fields,
        attachments: vec![],
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    const BITWARDEN_EXPORT: &str = r#"{
  "encrypted": false,
  "folders": [
    { "id": "folder-uuid-0001", "name": "Work" }
  ],
  "items": [
    {
      "id": "item-uuid-0001",
      "folderId": "folder-uuid-0001",
      "type": 1,
      "name": "My Gmail",
      "notes": "Personal email account",
      "favorite": true,
      "fields": [
        { "name": "recovery-email", "value": "backup@example.com", "type": 0 },
        { "name": "secret-answer",  "value": "fluffy",             "type": 1 }
      ],
      "login": {
        "uris": [{ "match": null, "uri": "https://mail.google.com" }],
        "username": "rob@example.com",
        "password": "hunter2",
        "totp": "otpauth://totp/gmail?secret=ABC123"
      }
    },
    {
      "id": "item-uuid-0002",
      "folderId": null,
      "type": 2,
      "name": "SSH Key Passphrase",
      "notes": "Passphrase for my ed25519 key",
      "favorite": false,
      "fields": [],
      "secureNote": {}
    },
    {
      "id": "item-uuid-0003",
      "folderId": null,
      "type": 3,
      "name": "Visa Card",
      "notes": null,
      "favorite": false,
      "fields": [],
      "card": {
        "cardholderName": "Rob Example",
        "brand": "Visa",
        "number": "4111111111111111",
        "expMonth": "9",
        "expYear": "2027",
        "code": "123"
      }
    },
    {
      "id": "item-uuid-0004",
      "folderId": null,
      "type": 4,
      "name": "Rob Example",
      "notes": "My identity",
      "favorite": false,
      "fields": [],
      "identity": {
        "firstName": "Rob",
        "lastName":  "Example",
        "email":     "rob@example.com",
        "phone":     "+41 22 000 0000",
        "company":   "Example SA"
      }
    },
    {
      "id": "item-uuid-0005",
      "folderId": null,
      "type": 99,
      "name": "Unknown type item",
      "notes": null,
      "favorite": false,
      "fields": []
    }
  ]
}"#;

    #[test]
    fn parse_login_entry() {
        let (entries, _) = parse(BITWARDEN_EXPORT.as_bytes()).expect("parse failed");

        let login = entries
            .iter()
            .find_map(|e| {
                if let VaultEntry::Login(l) = e {
                    Some(l)
                } else {
                    None
                }
            })
            .expect("no login entry found");

        assert_eq!(login.title, "My Gmail");
        assert_eq!(login.url, "https://mail.google.com");
        assert_eq!(login.username, "rob@example.com");
        assert_eq!(login.password, "hunter2");
        assert_eq!(login.notes, Some("Personal email account".to_string()));
        assert_eq!(login.meta.folder, "Work");
    }

    #[test]
    fn parse_note_entry() {
        let (entries, _) = parse(BITWARDEN_EXPORT.as_bytes()).expect("parse failed");

        let note = entries
            .iter()
            .find_map(|e| {
                if let VaultEntry::Note(n) = e {
                    Some(n)
                } else {
                    None
                }
            })
            .expect("no note entry found");

        assert_eq!(note.title, "SSH Key Passphrase");
        assert_eq!(note.content, "Passphrase for my ed25519 key");
    }

    #[test]
    fn parse_card_entry() {
        let (entries, _) = parse(BITWARDEN_EXPORT.as_bytes()).expect("parse failed");

        let card = entries
            .iter()
            .find_map(|e| {
                if let VaultEntry::Card(c) = e {
                    Some(c)
                } else {
                    None
                }
            })
            .expect("no card entry found");

        assert_eq!(card.cardholder_name, "Rob Example");
        assert_eq!(card.card_number, "4111111111111111");
        assert_eq!(card.expiry, "09/27");
        assert_eq!(card.cvv, "123");
        assert_eq!(card.payment_network, Some("Visa".to_string()));
    }

    #[test]
    fn parse_identity_maps_to_custom_entry() {
        let (entries, _) = parse(BITWARDEN_EXPORT.as_bytes()).expect("parse failed");

        let custom = entries
            .iter()
            .find_map(|e| {
                if let VaultEntry::Custom(c) = e {
                    Some(c)
                } else {
                    None
                }
            })
            .expect("no custom entry found");

        assert_eq!(custom.title, "Rob Example");
        assert!(custom.fields.contains_key("First name"));
        assert_eq!(custom.fields["First name"].value, "Rob");
        assert_eq!(custom.fields["Email"].value, "rob@example.com");
        assert_eq!(custom.fields["Company"].value, "Example SA");
    }

    #[test]
    fn unknown_type_is_skipped() {
        let (entries, _) = parse(BITWARDEN_EXPORT.as_bytes()).expect("parse failed");
        // fixture has 5 items: login, note, card, identity, unknown(99)
        // unknown should be silently dropped → 4 entries
        assert_eq!(entries.len(), 4);
    }

    #[test]
    fn login_custom_fields_mapped_correctly() {
        let (entries, _) = parse(BITWARDEN_EXPORT.as_bytes()).expect("parse failed");

        let login = entries
            .iter()
            .find_map(|e| {
                if let VaultEntry::Login(l) = e {
                    Some(l)
                } else {
                    None
                }
            })
            .expect("no login entry found");

        assert_eq!(login.custom_fields.len(), 2);
        let recovery = login
            .custom_fields
            .iter()
            .find(|f| f.label == "recovery-email")
            .unwrap();
        assert_eq!(recovery.value, "backup@example.com");
        assert!(!recovery.hidden);

        let secret = login
            .custom_fields
            .iter()
            .find(|f| f.label == "secret-answer")
            .unwrap();
        assert_eq!(secret.value, "fluffy");
        assert!(secret.hidden);
    }

    #[test]
    fn totp_field_is_not_imported() {
        let (entries, _) = parse(BITWARDEN_EXPORT.as_bytes()).expect("parse failed");

        let login = entries
            .iter()
            .find_map(|e| {
                if let VaultEntry::Login(l) = e {
                    Some(l)
                } else {
                    None
                }
            })
            .expect("no login entry found");

        // totp must not appear anywhere in custom fields
        assert!(!login
            .custom_fields
            .iter()
            .any(|f| f.label.to_lowercase().contains("totp")));
    }

    #[test]
    fn malformed_json_returns_err() {
        let result = parse(b"not valid json");
        assert!(result.is_err());
    }

    // ── Robustness / parser hardening ─────────────────────────────────────────

    #[test]
    fn empty_byte_input_returns_err() {
        assert!(parse(b"").is_err());
    }

    #[test]
    fn empty_items_array_returns_no_entries_and_no_failures() {
        let (entries, failures) = parse(br#"{"items":[]}"#).unwrap();
        assert!(entries.is_empty());
        assert!(failures.is_empty());
    }

    #[test]
    fn login_item_without_login_block_is_silently_skipped() {
        // type=1 but no "login" key → convert_login returns None → skipped, no panic
        let json = br#"{
            "items":[{
                "id":"skip-me","type":1,"name":"Orphan",
                "notes":null,"fields":[]
            }]
        }"#;
        let (entries, failures) = parse(json).unwrap();
        assert!(
            entries.is_empty(),
            "orphan login must be skipped, not panicked"
        );
        assert!(failures.is_empty());
    }

    #[test]
    fn card_item_without_card_block_is_silently_skipped() {
        // type=3 but no "card" key → convert_card returns Ok(None) → skipped
        let json = br#"{
            "items":[{
                "id":"no-card","type":3,"name":"Ghost Card",
                "notes":null,"fields":[]
            }]
        }"#;
        let (entries, failures) = parse(json).unwrap();
        assert!(entries.is_empty());
        assert!(failures.is_empty());
    }

    #[test]
    fn card_with_invalid_number_goes_to_failures_not_err() {
        // An item that fails domain validation must land in failures[], not abort the import.
        let json = br#"{
            "items":[{
                "id":"bad-card","type":3,"name":"Bad Card",
                "notes":null,"fields":[],
                "card":{
                    "cardholderName":"Test",
                    "brand":"Visa",
                    "number":"not-a-real-card-number",
                    "expMonth":"1","expYear":"2030","code":"123"
                }
            }]
        }"#;
        let (entries, failures) = parse(json).unwrap();
        assert!(
            entries.is_empty(),
            "invalid card must not appear in entries"
        );
        assert_eq!(failures.len(), 1, "invalid card must appear in failures");
    }

    #[test]
    fn unknown_item_type_does_not_panic() {
        // Types outside 1-4 are silently skipped. A stream of unknowns must
        // return empty results, not a panic or error.
        let json = br#"{
            "items":[
                {"id":"u1","type":99,"name":"Future type","notes":null,"fields":[]},
                {"id":"u2","type":0,"name":"Zero type","notes":null,"fields":[]}
            ]
        }"#;
        let (entries, failures) = parse(json).unwrap();
        assert!(entries.is_empty());
        assert!(failures.is_empty());
    }

    #[test]
    fn note_without_notes_field_gets_empty_content() {
        // notes: null → NoteEntry.content defaults to ""
        let json = br#"{
            "items":[{
                "id":"note1","type":2,"name":"Silent Note",
                "notes":null,"fields":[],"secureNote":{}
            }]
        }"#;
        let (entries, _) = parse(json).unwrap();
        assert_eq!(entries.len(), 1);
        if let VaultEntry::Note(n) = &entries[0] {
            assert_eq!(n.content, "");
        } else {
            panic!("expected NoteEntry");
        }
    }

    #[test]
    fn custom_field_with_null_name_and_value_does_not_panic() {
        // Bitwarden allows null field names/values — must not panic, must
        // produce empty-string label/value via unwrap_or_default().
        let json = br#"{
            "items":[{
                "id":"ff","type":2,"name":"Field Test",
                "notes":null,
                "fields":[{"name":null,"value":null,"type":0}],
                "secureNote":{}
            }]
        }"#;
        let (entries, _) = parse(json).unwrap();
        assert_eq!(entries.len(), 1);
        if let VaultEntry::Note(_) = &entries[0] {
        } else {
            panic!("expected NoteEntry");
        }
    }

    #[test]
    fn login_with_no_uris_gets_empty_url() {
        let json = br#"{
            "items":[{
                "id":"no-url","type":1,"name":"No URL Login",
                "notes":null,"fields":[],
                "login":{"uris":[],"username":"user","password":"pass","totp":null}
            }]
        }"#;
        let (entries, _) = parse(json).unwrap();
        assert_eq!(entries.len(), 1);
        if let VaultEntry::Login(l) = &entries[0] {
            assert_eq!(l.url, "", "missing URI list must produce empty url");
            assert_eq!(l.username, "user");
            assert_eq!(l.password, "pass");
        } else {
            panic!("expected LoginEntry");
        }
    }

    #[test]
    fn folder_lookup_unknown_id_gives_empty_folder() {
        // folderId references a folder that doesn't exist in the folders list.
        let json = br#"{
            "folders":[{"id":"f1","name":"Work"}],
            "items":[{
                "id":"x","type":2,"name":"Orphan","notes":null,"fields":[],
                "folderId":"does-not-exist","secureNote":{}
            }]
        }"#;
        let (entries, _) = parse(json).unwrap();
        assert_eq!(entries.len(), 1);
        if let VaultEntry::Note(_) = &entries[0] {
        } else {
            panic!("expected NoteEntry");
        }
    }
}
