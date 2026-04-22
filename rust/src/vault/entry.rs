//! Vault entry types — the core domain model for Gabbro.
//!
//! All sensitive data lives in Rust. Flutter never constructs
//! these types directly — it calls API functions that build them.

use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// The six entry types Gabbro support.
/// Not yet referenced outside this module — will be used for vault
/// filtering and sorting. Suppressing dead_code until that layer is built.
#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum EntryType {
    Login,
    Note,
    Identity,
    Card,
    File,
    Custom,
}

/// Common metadata shared by every entry, regardless of type.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct EntryMeta {
    /// Stable unique identifier - never reused, even after deletion.
    pub id: String,
    /// ISO 8601 timestamp: when this entry was created
    pub created_at: String,
    /// ISO 8601 timestamp: when this entry was last modified
    pub updated_at: String,
    /// Which folder this entry belongs to (e.g. "Personal").
    pub folder: String,
    /// Free-form tags for filtering and organisation.
    pub tags: Vec<String>,
    /// Whether this entry appears in the favourites list.
    pub favourite: bool,
}

/// A binary attachment belonging to a vault entry.
///
/// Imported from Enpass exports; data is base64-decoded on import.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct EntryAttachment {
    pub uuid: String,
    pub name: String,
    /// MIME type (e.g. "image/png", "application/pdf").
    pub kind: String,
    /// Raw binary data — decoded from base64 on import.
    pub data: Vec<u8>,
}

/// A login entry - the most common entry type
/// Stores credentials for a wehsite or application
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct LoginEntry {
    /// Shared metadata (id, timestamp, folder, tags, favourite).
    pub meta: EntryMeta,
    /// The URL this login belongs to (e.g. "https://github.com").
    pub url: String,
    /// The username or email address.
    pub username: String,
    /// The password - always stored encrypted at rest.
    pub password: String,
    /// Optional free-text notes attached to this entry.
    pub notes: Option<String>,
    /// User-defined extra fields (e.g. "Security question").
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
}

/// A single user-defined key/value field on an entry.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct CustomField {
    pub label: String,
    pub value: String,
    /// If true, the value is treated as sensitive and hidden by default.
    pub hidden: bool,
}

/// A secure note - free-text content with no crendential fields.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct NoteEntry {
    pub meta: EntryMeta,
    pub title: String,
    pub content: String,
    pub attachments: Vec<EntryAttachment>,
}

/// A personal identity entry - name, address, contact details.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct IdentityEntry {
    pub meta: EntryMeta,
    pub first_name: String,
    pub last_name: String,
    pub email: String,
    pub phone: Option<String>,
    pub address: Option<String>,
    /// User-defined extra fields (e.g. "Maiden name", "Mobile", "Landline").
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
}

/// A payment card entry.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
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
    pub attachments: Vec<EntryAttachment>,
}

impl CardEntry {
    /// Creates a new CardEntry, validating that the card number length
    /// is within the range of known real-world card formats (12-19 digits).
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
        attachments: Vec<EntryAttachment>,
    ) -> Result<CardEntry, String> {
        let digit_count = card_number.chars().filter(|c| c.is_ascii_digit()).count();
        if digit_count < 12 || digit_count > 19 {
            return Err(format!(
                "Card number must contain 12-19 digits, got {}",
                digit_count
            ));
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
                attachments,
            })
    }
}

/// A file attachement entry - stores a binary payload.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct FileEntry {
    pub meta: EntryMeta,
    pub filename: String,
    /// Raw file bytes - encrypted at rest as part of the vault body
    pub data: Vec<u8>,
    pub notes: Option<String>,
}

/// A fully custom entry - user-defined fields only.
#[derive(Debug, Clone, Serialize, Deserialize)]
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
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
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
            tags: vec![],
            favourite: false,
        }
    }

    #[test]
    fn login_entry_stores_basic_fields() {
        let entry = LoginEntry {
            meta: default_meta(),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("hunter2"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
        };

        assert_eq!(entry.url, "https://github.com");
        assert_eq!(entry.username, "rob");
        assert_eq!(entry.meta.id, "test-id-001");
        assert_eq!(entry.meta.favourite, false);
    }

    #[test]
    fn login_entry_notes_can_be_absent() {
        let entry = LoginEntry {
            meta: default_meta(),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
        };

        assert!(entry.notes.is_none());
    }

    #[test]
    fn login_entry_notes_can_be_present() {
        let entry = LoginEntry {
            meta: default_meta(),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: Some(String::from("my github account")),
            custom_fields: vec![],
            attachments: vec![],
        };

        assert!(entry.notes.is_some());
        assert_eq!(entry.notes.clone().unwrap(), "my github account");
    }

    #[test]
    fn login_entry_supports_custom_fields() {
        let field = CustomField {
            label: String::from("Recovery email"),
            value: String::from("rob@example.com"),
            hidden: false,
        };
        let entry = LoginEntry {
            meta: default_meta(),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![field],
            attachments: vec![],
        };

        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Recovery email");
        assert_eq!(entry.custom_fields[0].hidden, false);
    }

    #[test]
    fn note_entry_stores_content() {
        let entry = NoteEntry {
            meta: default_meta(),
            title: String::from("Shopping list"),
            content: String::from("Milk, eggs, bread"),
            attachments: vec![],
        };

        assert_eq!(entry.title, "Shopping list");
        assert_eq!(entry.content, "Milk, eggs, bread");
    }

    #[test]
    fn identity_entry_optional_fields_can_be_absent() {
        let entry = IdentityEntry {
            meta: default_meta(),
            first_name: String::from("Rob"),
            last_name: String::from("Smith"),
            email: String::from("rob@example.com"),
            phone: None,
            address: None,
            custom_fields: vec![],
            attachments: vec![],
        };

        assert_eq!(entry.first_name, "Rob");
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
            String::from("Rob Smith"),
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
        ).unwrap();

        assert_eq!(entry.cardholder_name, "Rob Smith");
        assert_eq!(entry.expiry, "12/28");
        assert_eq!(entry.status, "active");
        assert_eq!(entry.card_name, Some(String::from("Visa Platinum")));
    }

    #[test]
    fn card_entry_short_number_fails() {
        let result = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Rob Smith"),
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
        );

        assert!(result.is_err());
    }

    #[test]
    fn card_entry_long_number_fails() {
        let result = CardEntry::new(
            default_meta(),
            None,
            String::from("active"),
            String::from("Rob Smith"),
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
        };

        assert_eq!(entry.filename, "secret.pdf");
        assert_eq!(entry.data.len(), 4);
        assert_eq!(entry.data[3], 255u8);
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
