//! Vault entry types — the core domain model for Gabbro.
//!
//! All sensitive data lives in Rust. Flutter never constructs
//! these types directly — it calls API functions that build them.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Common metadata shared by every entry, regardless of type.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct EntryMeta {
    /// Stable unique identifier - never reused, even after deletion.
    pub id: String,
    /// ISO 8601 timestamp: when this entry was created
    pub created_at: String,
    /// ISO 8601 timestamp: when this entry was last modified
    pub updated_at: String,
    /// Which folder this entry belongs to (e.g. "Personal").
    pub folder: String,
    /// Per-field last-change times for granular sync (v9+): field key -> ms since
    /// the Unix epoch. Scalar fields are keyed by their serde name (e.g. "password");
    /// custom pairs by "custom_fields:<label>"; attachments by "attachments:<uuid>".
    /// Empty on pre-v9 vaults — an absent key counts as "oldest", so merge falls back
    /// to the whole-entry `updated_at` (today's behaviour).
    #[serde(default)]
    pub field_times: BTreeMap<String, u64>,
    /// Values replaced during sync resolution, kept so the user can recover them
    /// (the sync model's fallback property). Each record names the field key the
    /// value belonged to. Empty on vaults written before this was added.
    #[serde(default)]
    pub history: Vec<HistoryRecord>,
}

/// A value that was overwritten (e.g. the losing side of a sync clash, or a
/// brought-over edit the user kept) and retained so it can be recovered later.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct HistoryRecord {
    /// Field key the value belonged to ("password", "custom_fields:Tag", ...).
    pub field: String,
    /// The replaced value (may be a secret — treat accordingly).
    pub value: String,
    /// ISO 8601 timestamp: when the current value replaced this one.
    pub saved_at: String,
    /// ISO 8601 timestamp: when this record auto-purges.
    /// `None` means keep until manually deleted.
    pub expires_at: Option<String>,
}

// Hand-written Zeroize: BTreeMap has no Zeroize impl, so the derive cannot be used.
// Mirrors the pattern on CustomEntry below.
impl Zeroize for EntryMeta {
    fn zeroize(&mut self) {
        self.id.zeroize();
        self.created_at.zeroize();
        self.updated_at.zeroize();
        self.folder.zeroize();
        // clear() drops all keys and values; timestamps are not secret, but keep
        // the metadata tidy and consistent with the rest of the zeroize discipline.
        self.field_times.clear();
        for h in &mut self.history {
            h.zeroize();
        }
        self.history.clear();
    }
}

impl ZeroizeOnDrop for EntryMeta {}

/// A binary attachment belonging to a vault entry.
///
/// Imported from Enpass exports; data is base64-decoded on import.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct EntryAttachment {
    pub uuid: String,
    pub name: String,
    /// MIME type (e.g. "image/png", "application/pdf").
    pub kind: String,
    /// Raw binary data — decoded from base64 on import.
    pub data: Vec<u8>,
}

/// A login entry - the most common entry type
/// Stores credentials for a website or application
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct LoginEntry {
    /// Shared metadata (id, timestamp, folder).
    pub meta: EntryMeta,
    /// Human-readable item title (e.g. "Example", "Sample").
    /// Distinct from the URL — used as the primary display label in list views.
    pub title: String,
    /// The URL this login belongs to (e.g. "https://example.com").
    pub url: String,
    /// The username or email address.
    pub username: String,
    /// The password - always stored encrypted at rest.
    pub password: String,
    /// Optional free-text notes attached to this entry.
    pub notes: Option<String>,
    /// User-defined extra fields (e.g. "Security question").
    #[serde(default)]
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
    /// Previous password value, retained for typo recovery.
    pub previous_password: Option<PreviousSecret>,
    /// Android application id (package name, e.g. "com.company.app") this login
    /// belongs to, for native-app autofill matching. `None` until the user sets
    /// it; an unset value matches no app (no loose substring matching).
    #[serde(default)]
    pub app_id: Option<String>,
    /// Optional email/identifier, separate from `username`. Autofill routes it to
    /// email-typed fields. `None` if unset.
    #[serde(default)]
    pub email: Option<String>,
}

/// Holds one previous value of a sensitive field, for typo recovery.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct PreviousSecret {
    /// The previous secret value.
    pub value: String,
    /// ISO 8601 timestamp: when the current value replaced this one.
    pub saved_at: String,
    /// ISO 8601 timestamp: when this record auto-purges.
    /// `None` means keep until manually deleted.
    pub expires_at: Option<String>,
}

/// A single user-defined key/value field on an entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct CustomField {
    pub label: String,
    pub value: String,
    /// If true, the value is treated as sensitive and hidden by default.
    pub hidden: bool,
}

/// A secure note - free-text content with no credential fields.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct NoteEntry {
    pub meta: EntryMeta,
    pub title: String,
    pub content: String,
    #[serde(default)]
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
}

/// A personal identity entry - name, address, contact details.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct IdentityEntry {
    pub meta: EntryMeta,
    pub first_name: String,
    pub last_name: String,
    pub email: String,
    pub phone: Option<String>,
    pub address: Option<String>,
    /// User-defined extra fields (e.g. "Maiden name", "Mobile", "Landline").
    #[serde(default)]
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
}

/// A payment card entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct CardEntry {
    pub meta: EntryMeta,
    /// User's own label for this card (e.g. "Visa Platinum"). Optional —
    /// Flutter falls back to payment network or cardholder name if absent.
    pub card_name: Option<String>,
    /// Card status: "active", "lapsed", or "inactive".
    pub status: String,
    pub cardholder_name: String,
    pub card_number: String,
    /// Expiry date in MM/YY format.
    pub expiry: String,
    pub cvv: String,
    /// Credit limit as a string to avoid float precision issues.
    pub credit_limit: Option<String>,
    /// Bank account number associated with this card.
    pub card_account_number: Option<String>,
    /// Payment network (e.g. "Visa", "Mastercard", "Amex").
    /// Flutter maps this to a logo asset — no binary data stored here.
    pub payment_network: Option<String>,
    /// Card PIN.
    pub pin: Option<String>,
    /// Issuing bank name (e.g. "UBS", "Credit Suisse").
    pub bank_name: Option<String>,
    /// Transaction password (used by some banks for online payments).
    pub transaction_password: Option<String>,
    pub notes: Option<String>,
    /// User-defined extra fields — overflow from import (e.g. portal username/password).
    #[serde(default)]
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
    /// Previous CVV value, retained for typo recovery.
    pub previous_cvv: Option<PreviousSecret>,
    /// Previous PIN value, retained for typo recovery.
    pub previous_pin: Option<PreviousSecret>,
}

impl CardEntry {
    /// Creates a new CardEntry, validating that the card number length
    /// is within the range of known real-world card formats (12-19 digits).
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        meta: EntryMeta,
        card_name: Option<String>,
        status: String,
        cardholder_name: String,
        card_number: String,
        expiry: String,
        cvv: String,
        credit_limit: Option<String>,
        card_account_number: Option<String>,
        payment_network: Option<String>,
        pin: Option<String>,
        bank_name: Option<String>,
        transaction_password: Option<String>,
        notes: Option<String>,
        custom_fields: Vec<CustomField>,
        attachments: Vec<EntryAttachment>,
        previous_cvv: Option<PreviousSecret>,
        previous_pin: Option<PreviousSecret>,
    ) -> Result<CardEntry, String> {
        let mut errors: Vec<&str> = Vec::new();

        let digit_count = card_number.chars().filter(|c| c.is_ascii_digit()).count();
        if !(6..=19).contains(&digit_count) {
            errors.push("card number must contain 6–19 digits");
        }
        if cardholder_name.trim().is_empty() {
            errors.push("cardholder name is required");
        }
        if expiry.trim().is_empty() {
            errors.push("expiry is required");
        }
        if !errors.is_empty() {
            return Err(errors.join("; "));
        }

        Ok(CardEntry {
            meta,
            card_name,
            status,
            cardholder_name,
            card_number,
            expiry,
            cvv,
            credit_limit,
            card_account_number,
            payment_network,
            pin,
            bank_name,
            transaction_password,
            notes,
            custom_fields,
            attachments,
            previous_cvv,
            previous_pin,
        })
    }
}

/// A file attachment entry - stores a binary payload.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct FileEntry {
    pub meta: EntryMeta,
    pub filename: String,
    /// Raw file bytes - encrypted at rest as part of the vault body
    pub data: Vec<u8>,
    pub notes: Option<String>,
    #[serde(default)]
    pub custom_fields: Vec<CustomField>,
}

/// A fully custom entry - user-defined fields only.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomEntry {
    pub meta: EntryMeta,
    pub title: String,
    pub fields: HashMap<String, CustomField>,
    pub attachments: Vec<EntryAttachment>,
}

impl Zeroize for CustomEntry {
    fn zeroize(&mut self) {
        self.meta.zeroize();
        self.title.zeroize();
        // HashMap has no zeroize impl — clear() drops all keys and values promptly.
        // Each CustomField value is ZeroizeOnDrop so memory is cleared on drop.
        self.fields.clear();
    }
}

impl ZeroizeOnDrop for CustomEntry {}

/// A single vault entry — wraps all six entry types into one enum.
///
/// This is the type that gets serialized to JSON and encrypted into
/// the vault body. A `Vec<VaultEntry>` represents the full vault contents.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
#[allow(clippy::large_enum_variant)]
pub enum VaultEntry {
    Login(LoginEntry),
    Note(NoteEntry),
    Identity(IdentityEntry),
    Card(CardEntry),
    File(FileEntry),
    Custom(CustomEntry),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_meta() -> EntryMeta {
        EntryMeta {
            id: String::from("test-id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
            ..Default::default()
        }
    }

    // ── per-field change-times for granular sync (v9) ─────────────────────────

    #[test]
    fn field_times_defaults_empty_when_absent_from_json() {
        // Pre-v9 vaults have no field_times: the missing field deserializes to an
        // empty map (serde default), never an error.
        let json = r#"{
            "id": "x",
            "created_at": "2025-01-01T00:00:00Z",
            "updated_at": "2025-01-01T00:00:00Z",
            "folder": "Personal"
        }"#;
        let meta: EntryMeta = serde_json::from_str(json).unwrap();
        assert!(meta.field_times.is_empty());
    }

    #[test]
    fn field_times_round_trips_through_json() {
        let mut meta = default_meta();
        meta.field_times
            .insert(String::from("password"), 1_700_000_000_123);
        let json = serde_json::to_string(&meta).unwrap();
        let back: EntryMeta = serde_json::from_str(&json).unwrap();
        assert_eq!(back.field_times.get("password"), Some(&1_700_000_000_123));
    }

    #[test]
    fn entrymeta_zeroize_clears_field_times() {
        let mut meta = default_meta();
        meta.field_times.insert(String::from("password"), 42);
        meta.zeroize();
        assert!(meta.field_times.is_empty());
        assert!(meta.id.is_empty());
    }

    fn sample_history(value: &str) -> HistoryRecord {
        HistoryRecord {
            field: String::from("password"),
            value: value.to_string(),
            saved_at: String::from("2026-01-01T00:00:00Z"),
            expires_at: None,
        }
    }

    #[test]
    fn history_defaults_empty_when_absent_from_json() {
        // Vaults written before history existed deserialize to an empty list
        // (serde default), never an error.
        let json = r#"{
            "id": "x",
            "created_at": "2025-01-01T00:00:00Z",
            "updated_at": "2025-01-01T00:00:00Z",
            "folder": "Personal"
        }"#;
        let meta: EntryMeta = serde_json::from_str(json).unwrap();
        assert!(meta.history.is_empty());
    }

    #[test]
    fn history_round_trips_through_json() {
        let mut meta = default_meta();
        meta.history.push(sample_history("old-pw"));
        let json = serde_json::to_string(&meta).unwrap();
        let back: EntryMeta = serde_json::from_str(&json).unwrap();
        assert_eq!(back.history.len(), 1);
        assert_eq!(back.history[0].value, "old-pw");
        assert_eq!(back.history[0].field, "password");
    }

    #[test]
    fn entrymeta_zeroize_clears_history() {
        let mut meta = default_meta();
        meta.history.push(sample_history("secret"));
        meta.zeroize();
        assert!(meta.history.is_empty());
    }

    #[test]
    fn login_entry_stores_basic_fields() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("hunter2"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        };

        assert_eq!(entry.title, "Example");
        assert_eq!(entry.url, "https://example.com");
        assert_eq!(entry.username, "user");
        assert_eq!(entry.meta.id, "test-id-001");
    }

    #[test]
    fn login_entry_notes_can_be_absent() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        };

        assert!(entry.notes.is_none());
    }

    #[test]
    fn login_entry_notes_can_be_present() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: Some(String::from("my example account")),
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        };

        assert!(entry.notes.is_some());
        assert_eq!(entry.notes.clone().unwrap(), "my example account");
    }

    #[test]
    fn login_entry_supports_custom_fields() {
        let field = CustomField {
            label: String::from("Recovery email"),
            value: String::from("user@example.com"),
            hidden: false,
        };
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![field],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        };

        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Recovery email");
        assert!(!entry.custom_fields[0].hidden);
    }

    #[test]
    fn login_entry_can_store_app_id() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("secret"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: Some(String::from("com.company.app")),
            email: None,
        };
        assert_eq!(entry.app_id, Some(String::from("com.company.app")));
    }

    #[test]
    fn login_entry_app_id_round_trips_through_json() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("secret"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: Some(String::from("com.example.app")),
            email: None,
        };
        let json = serde_json::to_string(&entry).unwrap();
        let back: LoginEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(back.app_id, Some(String::from("com.example.app")));
    }

    #[test]
    fn login_entry_deserializes_old_json_without_app_id_to_none() {
        // A vault entry serialized before app_id existed must still load: the
        // missing field deserializes to None (serde default), never an error.
        let json = r#"{
            "meta": {
                "id": "x",
                "created_at": "2025-01-01T00:00:00Z",
                "updated_at": "2025-01-01T00:00:00Z",
                "folder": "Personal"
            },
            "title": "Example",
            "url": "https://example.com",
            "username": "user",
            "password": "secret",
            "notes": null,
            "custom_fields": [],
            "attachments": [],
            "previous_password": null
        }"#;
        let entry: LoginEntry = serde_json::from_str(json).unwrap();
        assert!(entry.app_id.is_none());
    }

    #[test]
    fn login_entry_can_store_email() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("secret"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: Some(String::from("user@example.com")),
        };
        assert_eq!(entry.email, Some(String::from("user@example.com")));
    }

    #[test]
    fn login_entry_email_round_trips_through_json() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("secret"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: Some(String::from("user@example.com")),
        };
        let json = serde_json::to_string(&entry).unwrap();
        let back: LoginEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(back.email, Some(String::from("user@example.com")));
    }

    #[test]
    fn login_entry_deserializes_old_json_without_email_to_none() {
        // A vault entry serialized before email existed must still load: the
        // missing field deserializes to None (serde default), never an error.
        let json = r#"{
            "meta": {
                "id": "x",
                "created_at": "2025-01-01T00:00:00Z",
                "updated_at": "2025-01-01T00:00:00Z",
                "folder": "Personal"
            },
            "title": "Example",
            "url": "https://example.com",
            "username": "user",
            "password": "secret",
            "notes": null,
            "custom_fields": [],
            "attachments": [],
            "previous_password": null
        }"#;
        let entry: LoginEntry = serde_json::from_str(json).unwrap();
        assert!(entry.email.is_none());
    }

    #[test]
    fn note_entry_stores_content() {
        let entry = NoteEntry {
            meta: default_meta(),
            title: String::from("Shopping list"),
            content: String::from("Milk, eggs, bread"),
            custom_fields: vec![],
            attachments: vec![],
        };

        assert_eq!(entry.title, "Shopping list");
        assert_eq!(entry.content, "Milk, eggs, bread");
    }

    #[test]
    fn note_entry_supports_custom_fields() {
        let field = CustomField {
            label: String::from("Source"),
            value: String::from("my own recipe"),
            hidden: false,
        };
        let entry = NoteEntry {
            meta: default_meta(),
            title: String::from("Shopping list"),
            content: String::from("Milk, eggs, bread"),
            custom_fields: vec![field],
            attachments: vec![],
        };

        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Source");
        assert!(!entry.custom_fields[0].hidden);
    }

    #[test]
    fn identity_entry_optional_fields_can_be_absent() {
        let entry = IdentityEntry {
            meta: default_meta(),
            first_name: String::from("Alex"),
            last_name: String::from("Smith"),
            email: String::from("user@example.com"),
            phone: None,
            address: None,
            custom_fields: vec![],
            attachments: vec![],
        };

        assert_eq!(entry.first_name, "Alex");
        assert!(entry.phone.is_none());
        assert!(entry.address.is_none());
        assert!(entry.custom_fields.is_empty());
    }

    #[test]
    fn card_entry_valid_number_succeeds() {
        let entry = CardEntry::new(
            default_meta(),
            Some(String::from("Visa Platinum")),
            String::from("active"),
            String::from("Alex Smith"),
            String::from("4111111111111111"), // 16 digits
            String::from("12/28"),
            String::from("123"),
            None,
            None,
            Some(String::from("Visa")),
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            None,
            None,
        )
        .unwrap();

        assert_eq!(entry.cardholder_name, "Alex Smith");
        assert_eq!(entry.expiry, "12/28");
        assert_eq!(entry.status, "active");
        assert_eq!(entry.card_name, Some(String::from("Visa Platinum")));
    }

    #[test]
    fn card_entry_six_digit_number_succeeds() {
        let result = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Alex Smith"),
            String::from("123456"), // 6 digits — minimum for debit cards
            String::from("12/28"),
            String::from("123"),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            None,
            None,
        );
        assert!(result.is_ok(), "6-digit card number should be accepted");
    }

    #[test]
    fn card_entry_short_number_fails() {
        let result = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Alex Smith"),
            String::from("1234"),
            String::from("12/28"),
            String::from("123"),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            None,
            None,
        );

        assert!(result.is_err());
    }

    #[test]
    fn card_entry_missing_required_fields_reports_all_failures() {
        let result = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from(""),     // cardholder_name missing
            String::from("1234"), // card_number too short
            String::from(""),     // expiry missing
            String::from(""),     // cvv missing
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            None,
            None,
        );
        let err = result.unwrap_err();
        assert!(
            err.contains("card number"),
            "should mention card number: {err}"
        );
        assert!(
            err.contains("cardholder name"),
            "should mention cardholder name: {err}"
        );
        assert!(err.contains("expiry"), "should mention expiry: {err}");
    }

    #[test]
    fn card_entry_cvv_optional() {
        let result = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Alex Smith"),
            String::from("4111111111111111"),
            String::from("12/28"),
            String::from(""), // empty CVV — should be accepted for debit cards
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            None,
            None,
        );
        assert!(result.is_ok(), "empty CVV should be accepted");
    }

    #[test]
    fn card_entry_long_number_fails() {
        let result = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Alex Smith"),
            String::from("12345678901234567890"), // 20 digits
            String::from("12/28"),
            String::from("123"),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            None,
            None,
        );

        assert!(result.is_err());
    }

    #[test]
    fn file_entry_stores_binary_data() {
        let payload = vec![0u8, 1u8, 2u8, 255u8];
        let entry = FileEntry {
            meta: default_meta(),
            filename: String::from("secret.pdf"),
            data: payload,
            notes: None,
            custom_fields: vec![],
        };

        assert_eq!(entry.filename, "secret.pdf");
        assert_eq!(entry.data.len(), 4);
        assert_eq!(entry.data[3], 255u8);
    }

    #[test]
    fn file_entry_supports_custom_fields() {
        let field = CustomField {
            label: String::from("Classification"),
            value: String::from("confidential"),
            hidden: false,
        };
        let entry = FileEntry {
            meta: default_meta(),
            filename: String::from("report.pdf"),
            data: vec![],
            notes: Some(String::from("annual report")),
            custom_fields: vec![field],
        };

        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Classification");
        assert!(!entry.custom_fields[0].hidden);
    }

    #[test]
    fn previous_secret_is_none_by_default_on_login() {
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("hunter2"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        };
        assert!(entry.previous_password.is_none());
    }

    #[test]
    fn previous_secret_stores_expires_at() {
        let prev = PreviousSecret {
            value: String::from("old_hunter2"),
            saved_at: String::from("2025-01-01T00:00:00Z"),
            expires_at: Some(String::from("2025-01-31T00:00:00Z")),
        };
        assert_eq!(prev.expires_at, Some(String::from("2025-01-31T00:00:00Z")));

        let prev_forever = PreviousSecret {
            value: String::from("old_hunter2"),
            saved_at: String::from("2025-01-01T00:00:00Z"),
            expires_at: None,
        };
        assert!(prev_forever.expires_at.is_none());
    }

    #[test]
    fn login_entry_can_store_previous_password() {
        let prev = PreviousSecret {
            value: String::from("old_hunter2"),
            saved_at: String::from("2025-01-01T00:00:00Z"),
            expires_at: Some(String::from("2025-01-31T00:00:00Z")),
        };
        let entry = LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("new_hunter2"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(prev),
            app_id: None,
            email: None,
        };
        assert!(entry.previous_password.is_some());
        assert_eq!(
            entry.previous_password.clone().unwrap().value,
            "old_hunter2"
        );
    }

    #[test]
    fn card_entry_can_store_previous_cvv() {
        let entry = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Alex Smith"),
            String::from("4111111111111111"),
            String::from("12/28"),
            String::from("999"),
            None,
            None,
            Some(String::from("Visa")),
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            Some(PreviousSecret {
                value: String::from("123"),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: Some(String::from("2025-01-31T00:00:00Z")),
            }),
            None,
        )
        .unwrap();
        assert!(entry.previous_cvv.is_some());
        assert_eq!(entry.previous_cvv.clone().unwrap().value, "123");
    }

    #[test]
    fn card_entry_can_store_previous_pin() {
        let entry = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Alex Smith"),
            String::from("4111111111111111"),
            String::from("12/28"),
            String::from("123"),
            None,
            None,
            Some(String::from("Visa")),
            None,
            None,
            None,
            None,
            vec![],
            vec![],
            None,
            Some(PreviousSecret {
                value: String::from("4321"),
                saved_at: String::from("2025-01-01T00:00:00Z"),
                expires_at: Some(String::from("2025-01-31T00:00:00Z")),
            }),
        )
        .unwrap();
        assert!(entry.previous_pin.is_some());
        assert_eq!(entry.previous_pin.clone().unwrap().value, "4321");
    }

    #[test]
    fn custom_entry_stores_fields_in_map() {
        let mut fields = HashMap::new();
        fields.insert(
            String::from("api_key"),
            CustomField {
                label: String::from("API Key"),
                value: String::from("sk-abc123"),
                hidden: true,
            },
        );
        let entry = CustomEntry {
            meta: default_meta(),
            title: String::from("My API credentials"),
            fields,
            attachments: vec![],
        };

        assert_eq!(entry.title, "My API credentials");
        assert_eq!(entry.fields.len(), 1);
        assert!(entry.fields["api_key"].hidden);
    }
}
