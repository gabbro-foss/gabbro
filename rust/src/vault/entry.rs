//! Vault entry types — the core domain model for Gabbro.
//!
//! All sensitive data lives in Rust. Flutter never constructs
//! these types directly — it calls API functions that build them.

use indexmap::IndexMap;
use rand::rngs::OsRng;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Mint a fresh entry id: a random UUID v4, drawn from `OsRng`.
///
/// Every entry id in the vault comes from here. Built on `Builder::from_random_bytes`
/// (which sets the version and variant bits) rather than `Uuid::new_v4`, so the crate
/// does not need uuid's `v4` feature — the only edge pulling a second major version of
/// `getrandom` into the tree. Same entropy source either way.
pub(crate) fn new_entry_id() -> String {
    let mut bytes = [0u8; 16];
    OsRng.fill_bytes(&mut bytes);
    uuid::Builder::from_random_bytes(bytes)
        .into_uuid()
        .to_string()
}

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

impl EntryMeta {
    /// Record `value` as the previous value of `field`, keeping at most one
    /// history record per field: an existing record for the same field is
    /// overwritten. This is the unified history model — one previous value per
    /// field, shared by the sync path and the on-save secret-field capture.
    pub fn record_previous(
        &mut self,
        field: &str,
        value: &str,
        saved_at: &str,
        expires_at: Option<String>,
    ) {
        let record = HistoryRecord {
            field: field.to_string(),
            value: value.to_string(),
            saved_at: saved_at.to_string(),
            expires_at,
        };
        match self.history.iter_mut().find(|h| h.field == field) {
            Some(existing) => *existing = record,
            None => self.history.push(record),
        }
    }
}

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
    /// User-defined fields keyed by label. `IndexMap` (not `HashMap`) so the
    /// order is deterministic and preserved: two Gabbro instances rendering the
    /// same vault must show fields in the same order, and new fields keep their
    /// creation order. Serializes as a JSON object, unchanged from `HashMap`.
    pub fields: IndexMap<String, CustomField>,
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

impl VaultEntry {
    /// Hash of the entry's user-visible content, used by import to recognise an
    /// entry it already holds.
    ///
    /// Deliberately excludes everything vault-local or volatile — `meta.id`,
    /// timestamps, `field_times`, `history` and `folder` — so re-filing an entry
    /// or re-importing a file that mints fresh ids still dedupes. See
    /// ARCHITECTURE.md "Current Focus" for the agreed per-type field list.
    pub fn content_hash(&self) -> [u8; 32] {
        use sha2::{Digest, Sha256};

        // Every value is length-prefixed so no two different field splits can
        // produce the same byte stream ("ab" + "c" must not collide with "a" + "bc").
        fn put(h: &mut Sha256, bytes: &[u8]) {
            h.update((bytes.len() as u64).to_le_bytes());
            h.update(bytes);
        }
        fn put_str(h: &mut Sha256, s: &str) {
            put(h, s.as_bytes());
        }
        // A tag byte separates "unset" from "set to empty" — otherwise clearing a
        // field would look identical to blanking it.
        fn put_opt(h: &mut Sha256, v: Option<&String>) {
            match v {
                None => h.update([0u8]),
                Some(s) => {
                    h.update([1u8]);
                    put_str(h, s);
                }
            }
        }
        fn put_custom_fields(h: &mut Sha256, fields: &[CustomField]) {
            h.update((fields.len() as u64).to_le_bytes());
            for f in fields {
                put_str(h, &f.label);
                put_str(h, &f.value);
                h.update([f.hidden as u8]);
            }
        }

        let mut h = Sha256::new();
        match self {
            VaultEntry::Login(e) => {
                put(&mut h, b"login");
                put_str(&mut h, &e.title);
                put_str(&mut h, &e.url);
                put_str(&mut h, &e.username);
                put_str(&mut h, &e.password);
                put_opt(&mut h, e.notes.as_ref());
                put_custom_fields(&mut h, &e.custom_fields);
                put_opt(&mut h, e.app_id.as_ref());
                put_opt(&mut h, e.email.as_ref());
            }
            VaultEntry::Note(e) => {
                put(&mut h, b"note");
                put_str(&mut h, &e.title);
                put_str(&mut h, &e.content);
                put_custom_fields(&mut h, &e.custom_fields);
            }
            VaultEntry::Identity(e) => {
                put(&mut h, b"identity");
                put_str(&mut h, &e.first_name);
                put_str(&mut h, &e.last_name);
                put_str(&mut h, &e.email);
                put_opt(&mut h, e.phone.as_ref());
                put_opt(&mut h, e.address.as_ref());
                put_custom_fields(&mut h, &e.custom_fields);
            }
            VaultEntry::Card(e) => {
                put(&mut h, b"card");
                put_opt(&mut h, e.card_name.as_ref());
                put_str(&mut h, &e.status);
                put_str(&mut h, &e.cardholder_name);
                put_str(&mut h, &e.card_number);
                put_str(&mut h, &e.expiry);
                put_str(&mut h, &e.cvv);
                put_opt(&mut h, e.credit_limit.as_ref());
                put_opt(&mut h, e.card_account_number.as_ref());
                put_opt(&mut h, e.payment_network.as_ref());
                put_opt(&mut h, e.pin.as_ref());
                put_opt(&mut h, e.bank_name.as_ref());
                put_opt(&mut h, e.transaction_password.as_ref());
                put_opt(&mut h, e.notes.as_ref());
                put_custom_fields(&mut h, &e.custom_fields);
            }
            VaultEntry::File(e) => {
                put(&mut h, b"file");
                put_str(&mut h, &e.filename);
                put(&mut h, &e.data);
                put_opt(&mut h, e.notes.as_ref());
                put_custom_fields(&mut h, &e.custom_fields);
            }
            VaultEntry::Custom(e) => {
                put(&mut h, b"custom");
                put_str(&mut h, &e.title);
                // `fields` is an order-preserving IndexMap, so sort by key first:
                // the same fields entered in a different order are the same entry.
                let mut keys: Vec<&String> = e.fields.keys().collect();
                keys.sort();
                h.update((keys.len() as u64).to_le_bytes());
                for k in keys {
                    let f = &e.fields[k];
                    put_str(&mut h, k);
                    put_str(&mut h, &f.label);
                    put_str(&mut h, &f.value);
                    h.update([f.hidden as u8]);
                }
            }
        }
        h.finalize().into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_entry_id_is_a_valid_v4_uuid() {
        let id = uuid::Uuid::parse_str(&new_entry_id()).expect("must be a valid UUID");
        assert_eq!(id.get_version_num(), 4, "entry ids must be UUID v4");
        assert_eq!(id.get_variant(), uuid::Variant::RFC4122);
    }

    #[test]
    fn new_entry_id_differs_across_calls() {
        assert_ne!(new_entry_id(), new_entry_id());
    }

    fn default_meta() -> EntryMeta {
        EntryMeta {
            id: String::from("test-id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
            ..Default::default()
        }
    }

    // ── content hash: identifies an entry by what it holds, not by its id ─────

    fn sample_login() -> LoginEntry {
        LoginEntry {
            meta: default_meta(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("hunter2"),
            notes: Some(String::from("a note")),
            custom_fields: vec![],
            attachments: vec![],
            app_id: None,
            email: None,
        }
    }

    fn sample_note() -> NoteEntry {
        NoteEntry {
            meta: default_meta(),
            title: String::from("Example"),
            content: String::from("some content"),
            custom_fields: vec![],
            attachments: vec![],
        }
    }

    fn sample_identity() -> IdentityEntry {
        IdentityEntry {
            meta: default_meta(),
            first_name: String::from("Alex"),
            last_name: String::from("Example"),
            email: String::from("user@example.com"),
            phone: Some(String::from("555-0100")),
            address: Some(String::from("1 Example Street")),
            custom_fields: vec![],
            attachments: vec![],
        }
    }

    fn sample_card() -> CardEntry {
        CardEntry {
            meta: default_meta(),
            card_name: Some(String::from("Example Card")),
            status: String::from("active"),
            cardholder_name: String::from("Alex Example"),
            card_number: String::from("4111111111111111"),
            expiry: String::from("12/28"),
            cvv: String::from("123"),
            credit_limit: Some(String::from("1000")),
            card_account_number: Some(String::from("acct-1")),
            payment_network: Some(String::from("Visa")),
            pin: Some(String::from("0000")),
            bank_name: Some(String::from("Example Bank")),
            transaction_password: Some(String::from("txpw")),
            notes: Some(String::from("a note")),
            custom_fields: vec![],
            attachments: vec![],
        }
    }

    fn sample_file() -> FileEntry {
        FileEntry {
            meta: default_meta(),
            filename: String::from("example.pdf"),
            data: vec![1, 2, 3],
            notes: Some(String::from("a note")),
            custom_fields: vec![],
        }
    }

    fn sample_custom() -> CustomEntry {
        let mut fields = IndexMap::new();
        fields.insert(
            String::from("Alpha"),
            CustomField {
                label: String::from("Alpha"),
                value: String::from("one"),
                hidden: false,
            },
        );
        CustomEntry {
            meta: default_meta(),
            title: String::from("Example"),
            fields,
            attachments: vec![],
        }
    }

    fn a_custom_field() -> CustomField {
        CustomField {
            label: String::from("Extra"),
            value: String::from("value"),
            hidden: false,
        }
    }

    /// Asserts every mutation changes the hash. Each entry in `mutations` is a
    /// (field name, already-mutated entry) pair.
    fn assert_each_mutation_changes_the_hash(
        base: &VaultEntry,
        mutations: Vec<(&str, VaultEntry)>,
    ) {
        let base_hash = base.content_hash();
        for (field, mutated) in mutations {
            assert_ne!(
                base_hash,
                mutated.content_hash(),
                "changing `{field}` must change the content hash, or import \
                 silently treats a different entry as a duplicate"
            );
        }
    }

    #[test]
    fn identical_content_hashes_the_same() {
        // Import dedup rests on this: two entries the user would call the same
        // entry must produce the same hash, or a re-import duplicates them.
        let a = VaultEntry::Login(sample_login());
        let b = VaultEntry::Login(sample_login());
        assert_eq!(a.content_hash(), b.content_hash());
    }

    /// The six sample entries, one per type, each built fresh.
    fn one_of_each_type() -> Vec<(&'static str, VaultEntry)> {
        vec![
            ("Login", VaultEntry::Login(sample_login())),
            ("Note", VaultEntry::Note(sample_note())),
            ("Identity", VaultEntry::Identity(sample_identity())),
            ("Card", VaultEntry::Card(sample_card())),
            ("File", VaultEntry::File(sample_file())),
            ("Custom", VaultEntry::Custom(sample_custom())),
        ]
    }

    fn meta_mut(entry: &mut VaultEntry) -> &mut EntryMeta {
        match entry {
            VaultEntry::Login(e) => &mut e.meta,
            VaultEntry::Note(e) => &mut e.meta,
            VaultEntry::Identity(e) => &mut e.meta,
            VaultEntry::Card(e) => &mut e.meta,
            VaultEntry::File(e) => &mut e.meta,
            VaultEntry::Custom(e) => &mut e.meta,
        }
    }

    #[test]
    fn vault_local_metadata_is_excluded_from_the_hash() {
        // The hash answers "is this the same entry?", not "is this the same record?".
        // Re-filing an entry into another folder, or a source minting a fresh id on
        // every export, must not make a re-import add a second copy.
        type MetaMutation = (&'static str, fn(&mut EntryMeta));
        let mutations: Vec<MetaMutation> = vec![
            ("id", |m| m.id = String::from("a-completely-different-id")),
            ("created_at", |m| {
                m.created_at = String::from("2030-06-06T06:06:06Z")
            }),
            ("updated_at", |m| {
                m.updated_at = String::from("2030-06-06T06:06:06Z")
            }),
            ("folder", |m| m.folder = String::from("Work")),
            ("field_times", |m| {
                m.field_times.insert(String::from("password"), 42);
            }),
            ("history", |m| {
                m.record_previous("password", "old", "2025-01-01T00:00:00Z", None)
            }),
        ];

        for (type_name, base) in one_of_each_type() {
            let base_hash = base.content_hash();
            for (field, mutate) in &mutations {
                let mut variant = base.clone();
                mutate(meta_mut(&mut variant));
                assert_eq!(
                    base_hash,
                    variant.content_hash(),
                    "{type_name}: `meta.{field}` must not affect the content hash"
                );
            }
        }
    }

    #[test]
    fn custom_entry_field_order_does_not_change_the_hash() {
        // `fields` is an order-preserving IndexMap, so two vaults holding the same
        // custom entry can carry its fields in different orders. The user sees one
        // entry either way; a re-import must not add a second copy.
        let field = |label: &str, value: &str| CustomField {
            label: String::from(label),
            value: String::from(value),
            hidden: false,
        };

        let mut forward = IndexMap::new();
        forward.insert(String::from("Alpha"), field("Alpha", "one"));
        forward.insert(String::from("Beta"), field("Beta", "two"));

        let mut reversed = IndexMap::new();
        reversed.insert(String::from("Beta"), field("Beta", "two"));
        reversed.insert(String::from("Alpha"), field("Alpha", "one"));

        let mut a = sample_custom();
        a.fields = forward;
        let mut b = sample_custom();
        b.fields = reversed;

        assert_eq!(
            VaultEntry::Custom(a).content_hash(),
            VaultEntry::Custom(b).content_hash()
        );
    }

    #[test]
    fn entry_type_is_part_of_the_hash() {
        // Every type carries the same text here, so only the type tag separates
        // them. Without it a Note could be mistaken for the Login of the same name
        // and one of them would vanish from an import.
        let shared = String::from("Example");

        let mut login = sample_login();
        login.title = shared.clone();
        login.url = shared.clone();
        login.username = shared.clone();
        login.password = shared.clone();
        login.notes = Some(shared.clone());

        let mut note = sample_note();
        note.title = shared.clone();
        note.content = shared.clone();

        let mut identity = sample_identity();
        identity.first_name = shared.clone();
        identity.last_name = shared.clone();
        identity.email = shared.clone();
        identity.phone = Some(shared.clone());
        identity.address = Some(shared.clone());

        let mut card = sample_card();
        card.card_name = Some(shared.clone());
        card.cardholder_name = shared.clone();

        let mut file = sample_file();
        file.filename = shared.clone();
        file.notes = Some(shared.clone());

        let mut custom = sample_custom();
        custom.title = shared.clone();

        let entries = [
            ("Login", VaultEntry::Login(login)),
            ("Note", VaultEntry::Note(note)),
            ("Identity", VaultEntry::Identity(identity)),
            ("Card", VaultEntry::Card(card)),
            ("File", VaultEntry::File(file)),
            ("Custom", VaultEntry::Custom(custom)),
        ];

        for (i, (name_a, a)) in entries.iter().enumerate() {
            for (name_b, b) in entries.iter().skip(i + 1) {
                assert_ne!(
                    a.content_hash(),
                    b.content_hash(),
                    "{name_a} and {name_b} must not share a content hash"
                );
            }
        }
    }

    #[test]
    fn changing_any_login_field_changes_the_hash() {
        let base = VaultEntry::Login(sample_login());
        let m = |f: fn(&mut LoginEntry)| {
            let mut e = sample_login();
            f(&mut e);
            VaultEntry::Login(e)
        };
        assert_each_mutation_changes_the_hash(
            &base,
            vec![
                ("title", m(|e| e.title = String::from("Other"))),
                ("url", m(|e| e.url = String::from("https://other.example"))),
                ("username", m(|e| e.username = String::from("other"))),
                ("password", m(|e| e.password = String::from("other"))),
                ("notes", m(|e| e.notes = Some(String::from("other")))),
                ("notes cleared", m(|e| e.notes = None)),
                (
                    "custom_fields",
                    m(|e| e.custom_fields = vec![a_custom_field()]),
                ),
                (
                    "app_id",
                    m(|e| e.app_id = Some(String::from("com.company.app"))),
                ),
                (
                    "email",
                    m(|e| e.email = Some(String::from("other@example.com"))),
                ),
            ],
        );
    }

    #[test]
    fn changing_any_note_field_changes_the_hash() {
        let base = VaultEntry::Note(sample_note());
        let m = |f: fn(&mut NoteEntry)| {
            let mut e = sample_note();
            f(&mut e);
            VaultEntry::Note(e)
        };
        assert_each_mutation_changes_the_hash(
            &base,
            vec![
                ("title", m(|e| e.title = String::from("Other"))),
                ("content", m(|e| e.content = String::from("other"))),
                (
                    "custom_fields",
                    m(|e| e.custom_fields = vec![a_custom_field()]),
                ),
            ],
        );
    }

    #[test]
    fn changing_any_identity_field_changes_the_hash() {
        let base = VaultEntry::Identity(sample_identity());
        let m = |f: fn(&mut IdentityEntry)| {
            let mut e = sample_identity();
            f(&mut e);
            VaultEntry::Identity(e)
        };
        assert_each_mutation_changes_the_hash(
            &base,
            vec![
                ("first_name", m(|e| e.first_name = String::from("Other"))),
                ("last_name", m(|e| e.last_name = String::from("Other"))),
                ("email", m(|e| e.email = String::from("other@example.com"))),
                ("phone", m(|e| e.phone = Some(String::from("555-0199")))),
                ("phone cleared", m(|e| e.phone = None)),
                ("address", m(|e| e.address = Some(String::from("2 Other")))),
                ("address cleared", m(|e| e.address = None)),
                (
                    "custom_fields",
                    m(|e| e.custom_fields = vec![a_custom_field()]),
                ),
            ],
        );
    }

    #[test]
    fn changing_any_card_field_changes_the_hash() {
        let base = VaultEntry::Card(sample_card());
        let m = |f: fn(&mut CardEntry)| {
            let mut e = sample_card();
            f(&mut e);
            VaultEntry::Card(e)
        };
        assert_each_mutation_changes_the_hash(
            &base,
            vec![
                (
                    "card_name",
                    m(|e| e.card_name = Some(String::from("Other"))),
                ),
                ("card_name cleared", m(|e| e.card_name = None)),
                ("status", m(|e| e.status = String::from("lapsed"))),
                (
                    "cardholder_name",
                    m(|e| e.cardholder_name = String::from("Other Name")),
                ),
                (
                    "card_number",
                    m(|e| e.card_number = String::from("4222222222222")),
                ),
                ("expiry", m(|e| e.expiry = String::from("01/30"))),
                ("cvv", m(|e| e.cvv = String::from("999"))),
                (
                    "credit_limit",
                    m(|e| e.credit_limit = Some(String::from("2000"))),
                ),
                ("credit_limit cleared", m(|e| e.credit_limit = None)),
                (
                    "card_account_number",
                    m(|e| e.card_account_number = Some(String::from("acct-2"))),
                ),
                (
                    "payment_network",
                    m(|e| e.payment_network = Some(String::from("Mastercard"))),
                ),
                ("pin", m(|e| e.pin = Some(String::from("1111")))),
                (
                    "bank_name",
                    m(|e| e.bank_name = Some(String::from("Other Bank"))),
                ),
                (
                    "transaction_password",
                    m(|e| e.transaction_password = Some(String::from("other"))),
                ),
                ("notes", m(|e| e.notes = Some(String::from("other")))),
                (
                    "custom_fields",
                    m(|e| e.custom_fields = vec![a_custom_field()]),
                ),
            ],
        );
    }

    #[test]
    fn changing_any_file_field_changes_the_hash() {
        let base = VaultEntry::File(sample_file());
        let m = |f: fn(&mut FileEntry)| {
            let mut e = sample_file();
            f(&mut e);
            VaultEntry::File(e)
        };
        assert_each_mutation_changes_the_hash(
            &base,
            vec![
                ("filename", m(|e| e.filename = String::from("other.pdf"))),
                ("data", m(|e| e.data = vec![9, 9, 9])),
                ("notes", m(|e| e.notes = Some(String::from("other")))),
                (
                    "custom_fields",
                    m(|e| e.custom_fields = vec![a_custom_field()]),
                ),
            ],
        );
    }

    #[test]
    fn changing_any_custom_field_changes_the_hash() {
        let base = VaultEntry::Custom(sample_custom());
        let m = |f: fn(&mut CustomEntry)| {
            let mut e = sample_custom();
            f(&mut e);
            VaultEntry::Custom(e)
        };
        assert_each_mutation_changes_the_hash(
            &base,
            vec![
                ("title", m(|e| e.title = String::from("Other"))),
                (
                    "a field's value",
                    m(|e| {
                        e.fields.get_mut("Alpha").unwrap().value = String::from("two");
                    }),
                ),
                (
                    "a field's hidden flag",
                    m(|e| {
                        e.fields.get_mut("Alpha").unwrap().hidden = true;
                    }),
                ),
                (
                    "an added field",
                    m(|e| {
                        e.fields.insert(String::from("Beta"), a_custom_field());
                    }),
                ),
            ],
        );
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
    fn record_previous_keeps_one_record_per_field() {
        // The unified history model: at most one previous value per field. A
        // second change to the same field overwrites its record rather than
        // appending a new one.
        let mut meta = default_meta();
        meta.record_previous("password", "old-1", "2026-01-01T00:00:00Z", None);
        meta.record_previous("password", "old-2", "2026-01-02T00:00:00Z", None);
        assert_eq!(meta.history.len(), 1);
        assert_eq!(meta.history[0].value, "old-2");
        assert_eq!(meta.history[0].saved_at, "2026-01-02T00:00:00Z");
    }

    #[test]
    fn record_previous_tracks_distinct_fields_separately() {
        let mut meta = default_meta();
        meta.record_previous("password", "pw-old", "2026-01-01T00:00:00Z", None);
        meta.record_previous("content", "note-old", "2026-01-01T00:00:00Z", None);
        assert_eq!(meta.history.len(), 2);
        assert!(meta
            .history
            .iter()
            .any(|h| h.field == "password" && h.value == "pw-old"));
        assert!(meta
            .history
            .iter()
            .any(|h| h.field == "content" && h.value == "note-old"));
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
    fn custom_entry_stores_fields_in_map() {
        let mut fields = IndexMap::new();
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
