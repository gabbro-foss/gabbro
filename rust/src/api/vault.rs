//! Vault API — bridge-facing functions for creating and managing vault entries.
//!
//! These functions are the only way Flutter interacts with vault data.
//! Internal domain types (LoginEntry, etc.) are never exposed directly.

use std::path::Path;

use sha2::{Digest, Sha256};

use crate::crypto::vault_crypto::{
    open_vault, open_vault_with_yubikey, seal_vault, seal_vault_with_yubikey,
};
use crate::vault::entry::{
    CardEntry, CustomField, EntryMeta, FileEntry, LoginEntry, NoteEntry, VaultEntry,
};
use crate::vault::io::{atomic_write_0600, read_vault, write_vault};
use crate::vault::serialization::{deserialize_vault_body, serialize_vault_body, VaultBody};
use uuid::Uuid;

// ── Bridge-facing DTOs ────────────────────────────────────────────────────────

/// A custom field as seen by Flutter.
pub struct CustomFieldData {
    pub label: String,
    pub value: String,
    pub hidden: bool,
}

/// A previous sensitive value as seen by Flutter.
/// `value` is always masked at the bridge boundary — Flutter unmasks on toggle.
pub struct PreviousSecretData {
    pub value: String,
    pub saved_at: String,
    pub expires_at: Option<String>,
}

/// A login entry as seen by Flutter.
pub struct LoginEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    /// Human-readable item title (e.g. "Example", "Sample").
    /// Distinct from the URL — used as the primary display label in list views.
    pub title: String,
    pub url: String,
    pub username: String,
    pub password: String,
    pub notes: Option<String>,
    pub custom_fields: Vec<CustomFieldData>,
    /// Previous password, masked by default. `None` if no history exists.
    pub previous_password: Option<PreviousSecretData>,
    /// Android application id for native-app autofill matching; `None` if unset.
    pub app_id: Option<String>,
    /// Email/identifier routed to email-typed fields; `None` if unset.
    pub email: Option<String>,
}

/// A note entry as seen by Flutter.
pub struct NoteEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    pub title: String,
    pub content: String,
    pub custom_fields: Vec<CustomFieldData>,
}

/// An identity entry as seen by Flutter.
pub struct IdentityEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    pub first_name: String,
    pub last_name: String,
    pub email: String,
    pub phone: Option<String>,
    pub address: Option<String>,
    pub custom_fields: Vec<CustomFieldData>,
}

/// A card entry as seen by Flutter.
pub struct CardEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    pub card_name: Option<String>,
    pub status: String,
    pub cardholder_name: String,
    pub card_number: String,
    pub expiry: String,
    pub cvv: String,
    pub credit_limit: Option<String>,
    pub card_account_number: Option<String>,
    pub payment_network: Option<String>,
    pub pin: Option<String>,
    pub bank_name: Option<String>,
    pub transaction_password: Option<String>,
    pub notes: Option<String>,
    pub custom_fields: Vec<CustomFieldData>,
    /// Previous CVV, masked by default. `None` if no history exists.
    pub previous_cvv: Option<PreviousSecretData>,
    /// Previous PIN, masked by default. `None` if no history exists.
    pub previous_pin: Option<PreviousSecretData>,
}

/// A file entry as seen by Flutter.
pub struct FileEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    pub filename: String,
    pub data: Vec<u8>,
    pub notes: Option<String>,
    pub custom_fields: Vec<CustomFieldData>,
}

/// A custom entry as seen by Flutter.
pub struct CustomEntryData {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub folder: String,
    pub title: String,
    pub fields: Vec<CustomFieldData>,
}

/// An entry flagged for user-consent deletion during vault merge.
///
/// Returned when an incoming vault contains a tombstone that matches a local
/// entry. Flutter shows a per-entry Delete/Keep dialog before any deletion occurs.
pub struct PendingDeleteItem {
    pub id: String,
    pub title: String,
}

/// A true field-level clash discovered during vault merge: the same field of the
/// same entry was changed on both devices at the same instant to different values.
/// The local value is kept; Flutter prompts the user to keep mine / keep theirs.
/// `local_value` / `incoming_value` are decrypted plaintext — mask in the UI like
/// any other secret. `field` is the field key (e.g. "password", "custom_fields:PIN").
pub struct FieldConflictItem {
    pub id: String,
    pub title: String,
    pub field: String,
    pub local_value: String,
    pub incoming_value: String,
}

/// An item (custom pair / attachment) the incoming side deleted more recently than
/// the local side last changed it. Surfaced as a keep/delete prompt; the item is
/// kept until the user confirms — never silently dropped. `field` is the item key
/// ("custom_fields:<label>" or "attachments:<uuid>").
pub struct PendingItemDeleteItem {
    pub id: String,
    pub title: String,
    pub field: String,
}

/// A folder assignment conflict discovered during vault merge.
///
/// Returned when the same entry UUID exists in both vaults assigned to different
/// folders. Flutter prompts the user to pick which folder to keep.
pub struct FolderConflictItem {
    pub id: String,
    pub title: String,
    pub local_folder: String,
    pub incoming_folder: String,
}

/// Summary returned to Flutter after a vault merge operation.
pub struct MergeSummary {
    /// Entries added from the incoming vault (UUIDs not present locally).
    pub added: u32,
    /// Entries updated because the incoming version had a newer timestamp.
    pub updated: u32,
    /// Incoming tombstones that matched local entries — awaiting user consent.
    /// Flutter shows a Delete/Keep dialog for each; no deletion occurs automatically.
    pub pending_deletes: Vec<PendingDeleteItem>,
    /// Same-UUID entries with different folder assignments on each device.
    /// Flutter prompts the user to pick which folder to keep.
    pub folder_conflicts: Vec<FolderConflictItem>,
    /// True field-level clashes (same field, same instant, different value). The
    /// local value is kept; Flutter prompts keep mine / keep theirs.
    pub field_conflicts: Vec<FieldConflictItem>,
    /// Items (custom pairs / attachments) the other device deleted more recently
    /// than this side edited them. The item is kept; Flutter prompts keep / delete.
    pub pending_item_deletes: Vec<PendingItemDeleteItem>,
}

// ── Conversion helpers (internal → DTO) ──────────────────────────────────────

// All conversion helpers take references to avoid moving out of types that
// implement Drop (via ZeroizeOnDrop). Fields are cloned explicitly.

fn custom_field_to_data(f: &CustomField) -> CustomFieldData {
    CustomFieldData {
        label: f.label.clone(),
        value: f.value.clone(),
        hidden: f.hidden,
    }
}

fn previous_secret_to_data(p: &crate::vault::entry::PreviousSecret) -> PreviousSecretData {
    PreviousSecretData {
        value: MASKED_VALUE.to_string(),
        saved_at: p.saved_at.clone(),
        expires_at: p.expires_at.clone(),
    }
}

fn login_entry_to_data(e: &LoginEntry) -> LoginEntryData {
    LoginEntryData {
        id: e.meta.id.clone(),
        created_at: e.meta.created_at.clone(),
        updated_at: e.meta.updated_at.clone(),
        folder: e.meta.folder.clone(),
        title: e.title.clone(),
        url: e.url.clone(),
        username: e.username.clone(),
        password: e.password.clone(),
        notes: e.notes.clone(),
        custom_fields: e.custom_fields.iter().map(custom_field_to_data).collect(),
        previous_password: e.previous_password.as_ref().map(previous_secret_to_data),
        app_id: e.app_id.clone(),
        email: e.email.clone(),
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Creates a new login entry with a generated UUID and current timestamp.
///
/// Called by Flutter when the user saves a new login. Returns a
/// `LoginEntryData` DTO — the internal `LoginEntry` never crosses the bridge.
pub fn create_login_entry(
    folder: String,
    title: String,
    url: String,
    username: String,
    password: String,
    notes: Option<String>,
    custom_fields: Vec<CustomFieldData>,
) -> LoginEntryData {
    let now = chrono_now();
    let meta = EntryMeta {
        field_times: Default::default(),
        id: Uuid::new_v4().to_string(),
        created_at: now.clone(),
        updated_at: now,
        folder,
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
        title,
        url,
        username,
        password,
        notes,
        custom_fields: internal_fields,
        attachments: vec![],
        previous_password: None,
        app_id: None,
        email: None,
    };
    login_entry_to_data(&entry)
}

// ── Entry retrieval ───────────────────────────────────────────────────────────

/// Fixed placeholder used instead of the real value when masked display
/// is requested. Length is intentionally decoupled from actual value length
/// to prevent shoulder-surfing attacks based on character count.
pub const MASKED_VALUE: &str = "********";

/// Returns a helper that extracts the UUID from any VaultEntry variant.
fn entry_id(entry: &VaultEntry) -> &str {
    match entry {
        VaultEntry::Login(e) => &e.meta.id,
        VaultEntry::Note(e) => &e.meta.id,
        VaultEntry::Identity(e) => &e.meta.id,
        VaultEntry::Card(e) => &e.meta.id,
        VaultEntry::File(e) => &e.meta.id,
        VaultEntry::Custom(e) => &e.meta.id,
    }
}

/// Current time in milliseconds since the Unix epoch. Std-only (no date crate):
/// per-field change-times are only ever generated and compared as integers, never
/// parsed, so a real date library buys nothing here.
pub fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn entry_meta(entry: &VaultEntry) -> &crate::vault::entry::EntryMeta {
    match entry {
        VaultEntry::Login(e) => &e.meta,
        VaultEntry::Note(e) => &e.meta,
        VaultEntry::Identity(e) => &e.meta,
        VaultEntry::Card(e) => &e.meta,
        VaultEntry::File(e) => &e.meta,
        VaultEntry::Custom(e) => &e.meta,
    }
}

fn entry_meta_mut(entry: &mut VaultEntry) -> &mut crate::vault::entry::EntryMeta {
    match entry {
        VaultEntry::Login(e) => &mut e.meta,
        VaultEntry::Note(e) => &mut e.meta,
        VaultEntry::Identity(e) => &mut e.meta,
        VaultEntry::Card(e) => &mut e.meta,
        VaultEntry::File(e) => &mut e.meta,
        VaultEntry::Custom(e) => &mut e.meta,
    }
}

/// Field keys that differ between `old` and `new` (assumed same entry type).
/// Scalar fields are keyed by their serde name; custom pairs by
/// "custom_fields:<label>"; attachments by "attachments:<uuid>". Derived secrets
/// (`previous_*`) are intentionally excluded — they follow their parent field.
fn changed_field_keys(old: &VaultEntry, new: &VaultEntry) -> Vec<String> {
    use crate::vault::entry::{CustomField, EntryAttachment};

    fn push_if(out: &mut Vec<String>, key: &str, changed: bool) {
        if changed {
            out.push(key.to_string());
        }
    }

    // Custom pairs are identified by label: an added or value/hidden-changed pair
    // stamps "custom_fields:<label>". (Removal is handled by the merge layer.)
    fn diff_custom(old: &[CustomField], new: &[CustomField], out: &mut Vec<String>) {
        let by: std::collections::HashMap<&str, &CustomField> =
            old.iter().map(|f| (f.label.as_str(), f)).collect();
        for nf in new {
            let unchanged = by
                .get(nf.label.as_str())
                .map(|of| of.value == nf.value && of.hidden == nf.hidden)
                .unwrap_or(false);
            if !unchanged {
                out.push(format!("custom_fields:{}", nf.label));
            }
        }
    }

    fn diff_attachments(old: &[EntryAttachment], new: &[EntryAttachment], out: &mut Vec<String>) {
        let by: std::collections::HashMap<&str, &EntryAttachment> =
            old.iter().map(|a| (a.uuid.as_str(), a)).collect();
        for na in new {
            let unchanged = by
                .get(na.uuid.as_str())
                .map(|oa| oa.name == na.name && oa.kind == na.kind && oa.data == na.data)
                .unwrap_or(false);
            if !unchanged {
                out.push(format!("attachments:{}", na.uuid));
            }
        }
    }

    let mut out = Vec::new();
    match (old, new) {
        (VaultEntry::Login(o), VaultEntry::Login(n)) => {
            push_if(&mut out, "title", o.title != n.title);
            push_if(&mut out, "url", o.url != n.url);
            push_if(&mut out, "username", o.username != n.username);
            push_if(&mut out, "password", o.password != n.password);
            push_if(&mut out, "notes", o.notes != n.notes);
            push_if(&mut out, "app_id", o.app_id != n.app_id);
            push_if(&mut out, "email", o.email != n.email);
            diff_custom(&o.custom_fields, &n.custom_fields, &mut out);
            diff_attachments(&o.attachments, &n.attachments, &mut out);
        }
        (VaultEntry::Note(o), VaultEntry::Note(n)) => {
            push_if(&mut out, "title", o.title != n.title);
            push_if(&mut out, "content", o.content != n.content);
            diff_custom(&o.custom_fields, &n.custom_fields, &mut out);
            diff_attachments(&o.attachments, &n.attachments, &mut out);
        }
        (VaultEntry::Identity(o), VaultEntry::Identity(n)) => {
            push_if(&mut out, "first_name", o.first_name != n.first_name);
            push_if(&mut out, "last_name", o.last_name != n.last_name);
            push_if(&mut out, "email", o.email != n.email);
            push_if(&mut out, "phone", o.phone != n.phone);
            push_if(&mut out, "address", o.address != n.address);
            diff_custom(&o.custom_fields, &n.custom_fields, &mut out);
            diff_attachments(&o.attachments, &n.attachments, &mut out);
        }
        (VaultEntry::Card(o), VaultEntry::Card(n)) => {
            push_if(&mut out, "card_name", o.card_name != n.card_name);
            push_if(&mut out, "status", o.status != n.status);
            push_if(
                &mut out,
                "cardholder_name",
                o.cardholder_name != n.cardholder_name,
            );
            push_if(&mut out, "card_number", o.card_number != n.card_number);
            push_if(&mut out, "expiry", o.expiry != n.expiry);
            push_if(&mut out, "cvv", o.cvv != n.cvv);
            push_if(&mut out, "credit_limit", o.credit_limit != n.credit_limit);
            push_if(
                &mut out,
                "card_account_number",
                o.card_account_number != n.card_account_number,
            );
            push_if(
                &mut out,
                "payment_network",
                o.payment_network != n.payment_network,
            );
            push_if(&mut out, "pin", o.pin != n.pin);
            push_if(&mut out, "bank_name", o.bank_name != n.bank_name);
            push_if(
                &mut out,
                "transaction_password",
                o.transaction_password != n.transaction_password,
            );
            push_if(&mut out, "notes", o.notes != n.notes);
            diff_custom(&o.custom_fields, &n.custom_fields, &mut out);
            diff_attachments(&o.attachments, &n.attachments, &mut out);
        }
        (VaultEntry::File(o), VaultEntry::File(n)) => {
            push_if(&mut out, "filename", o.filename != n.filename);
            push_if(&mut out, "data", o.data != n.data);
            push_if(&mut out, "notes", o.notes != n.notes);
            diff_custom(&o.custom_fields, &n.custom_fields, &mut out);
        }
        (VaultEntry::Custom(o), VaultEntry::Custom(n)) => {
            push_if(&mut out, "title", o.title != n.title);
            for (k, nf) in &n.fields {
                let unchanged = o
                    .fields
                    .get(k)
                    .map(|of| {
                        of.value == nf.value && of.hidden == nf.hidden && of.label == nf.label
                    })
                    .unwrap_or(false);
                if !unchanged {
                    out.push(format!("custom_fields:{k}"));
                }
            }
            diff_attachments(&o.attachments, &n.attachments, &mut out);
        }
        _ => {}
    }
    out
}

/// All item keys ("custom_fields:<label>" / "attachments:<uuid>") present on an
/// entry — used to detect item deletions for granular-sync tombstones.
fn item_keys(entry: &VaultEntry) -> std::collections::HashSet<String> {
    use crate::vault::entry::{CustomField, EntryAttachment};
    fn add_custom(keys: &mut std::collections::HashSet<String>, fields: &[CustomField]) {
        for f in fields {
            keys.insert(format!("custom_fields:{}", f.label));
        }
    }
    fn add_att(keys: &mut std::collections::HashSet<String>, atts: &[EntryAttachment]) {
        for a in atts {
            keys.insert(format!("attachments:{}", a.uuid));
        }
    }
    let mut keys = std::collections::HashSet::new();
    match entry {
        VaultEntry::Login(e) => {
            add_custom(&mut keys, &e.custom_fields);
            add_att(&mut keys, &e.attachments);
        }
        VaultEntry::Note(e) => {
            add_custom(&mut keys, &e.custom_fields);
            add_att(&mut keys, &e.attachments);
        }
        VaultEntry::Identity(e) => {
            add_custom(&mut keys, &e.custom_fields);
            add_att(&mut keys, &e.attachments);
        }
        VaultEntry::Card(e) => {
            add_custom(&mut keys, &e.custom_fields);
            add_att(&mut keys, &e.attachments);
        }
        VaultEntry::File(e) => {
            add_custom(&mut keys, &e.custom_fields);
        }
        VaultEntry::Custom(e) => {
            for k in e.fields.keys() {
                keys.insert(format!("custom_fields:{k}"));
            }
            add_att(&mut keys, &e.attachments);
        }
    }
    keys
}

/// Mutable access to an entry's `custom_fields` vec (None for Custom, which keys
/// its fields in a map).
fn entry_custom_fields_mut(
    entry: &mut VaultEntry,
) -> Option<&mut Vec<crate::vault::entry::CustomField>> {
    match entry {
        VaultEntry::Login(e) => Some(&mut e.custom_fields),
        VaultEntry::Note(e) => Some(&mut e.custom_fields),
        VaultEntry::Identity(e) => Some(&mut e.custom_fields),
        VaultEntry::Card(e) => Some(&mut e.custom_fields),
        VaultEntry::File(e) => Some(&mut e.custom_fields),
        VaultEntry::Custom(_) => None,
    }
}

/// Set a scalar field by its serde-name key. Unknown keys are ignored; Option
/// fields become `Some(value)`. File `data` (binary) is intentionally not set here.
fn set_entry_scalar(entry: &mut VaultEntry, key: &str, value: &str) {
    let s = value.to_string();
    match entry {
        VaultEntry::Login(e) => match key {
            "title" => e.title = s,
            "url" => e.url = s,
            "username" => e.username = s,
            "password" => e.password = s,
            "notes" => e.notes = Some(s),
            "app_id" => e.app_id = Some(s),
            "email" => e.email = Some(s),
            _ => {}
        },
        VaultEntry::Note(e) => match key {
            "title" => e.title = s,
            "content" => e.content = s,
            _ => {}
        },
        VaultEntry::Identity(e) => match key {
            "first_name" => e.first_name = s,
            "last_name" => e.last_name = s,
            "email" => e.email = s,
            "phone" => e.phone = Some(s),
            "address" => e.address = Some(s),
            _ => {}
        },
        VaultEntry::Card(e) => match key {
            "card_name" => e.card_name = Some(s),
            "status" => e.status = s,
            "cardholder_name" => e.cardholder_name = s,
            "card_number" => e.card_number = s,
            "expiry" => e.expiry = s,
            "cvv" => e.cvv = s,
            "credit_limit" => e.credit_limit = Some(s),
            "card_account_number" => e.card_account_number = Some(s),
            "payment_network" => e.payment_network = Some(s),
            "pin" => e.pin = Some(s),
            "bank_name" => e.bank_name = Some(s),
            "transaction_password" => e.transaction_password = Some(s),
            "notes" => e.notes = Some(s),
            _ => {}
        },
        VaultEntry::File(e) => match key {
            "filename" => e.filename = s,
            "notes" => e.notes = Some(s),
            _ => {}
        },
        VaultEntry::Custom(e) => {
            if key == "title" {
                e.title = s;
            }
        }
    }
}

/// Apply a value to an entry field by merge key (a scalar name or
/// "custom_fields:<label>"). "attachments:<uuid>" and File "data" carry no
/// applyable string and are left unchanged. Used by "keep theirs" resolution.
pub(crate) fn set_entry_field_by_key(entry: &mut VaultEntry, key: &str, value: &str) {
    use crate::vault::entry::CustomField;
    if let Some(label) = key.strip_prefix("custom_fields:") {
        match entry {
            VaultEntry::Custom(e) => {
                e.fields
                    .entry(label.to_string())
                    .and_modify(|f| f.value = value.to_string())
                    .or_insert_with(|| CustomField {
                        label: label.to_string(),
                        value: value.to_string(),
                        hidden: false,
                    });
            }
            _ => {
                if let Some(v) = entry_custom_fields_mut(entry) {
                    if let Some(f) = v.iter_mut().find(|f| f.label == label) {
                        f.value = value.to_string();
                    } else {
                        v.push(CustomField {
                            label: label.to_string(),
                            value: value.to_string(),
                            hidden: false,
                        });
                    }
                }
            }
        }
        return;
    }
    if key.starts_with("attachments:") {
        return;
    }
    set_entry_scalar(entry, key, value);
}

/// Remove an item (custom pair / attachment) from an entry by merge key. Used by
/// the "delete" resolution of a pending item-delete.
pub(crate) fn remove_entry_item_by_key(entry: &mut VaultEntry, key: &str) {
    if let Some(label) = key.strip_prefix("custom_fields:") {
        match entry {
            VaultEntry::Custom(e) => {
                e.fields.remove(label);
            }
            _ => {
                if let Some(v) = entry_custom_fields_mut(entry) {
                    v.retain(|f| f.label != label);
                }
            }
        }
        return;
    }
    if let Some(uuid) = key.strip_prefix("attachments:") {
        let atts = match entry {
            VaultEntry::Login(e) => Some(&mut e.attachments),
            VaultEntry::Note(e) => Some(&mut e.attachments),
            VaultEntry::Identity(e) => Some(&mut e.attachments),
            VaultEntry::Card(e) => Some(&mut e.attachments),
            VaultEntry::Custom(e) => Some(&mut e.attachments),
            VaultEntry::File(_) => None,
        };
        if let Some(atts) = atts {
            atts.retain(|a| a.uuid != uuid);
        }
    }
}

/// Replace an existing entry in the vault with an updated version.
///
/// Matches by UUID — the updated entry must carry the same id as the
/// one being replaced. Updates `updated_at` to the current timestamp.
/// For Login and Card entries, snapshots any changed sensitive field
/// (password, CVV, PIN) into the corresponding `previous_*` field.
/// `expiry_days`: `Some(n)` sets `expires_at` to now + n days;
/// `None` means keep until manually deleted.
/// Returns `Err` if no entry with that id exists.
#[flutter_rust_bridge::frb(ignore)]
pub fn update_entry(
    entries: &mut [VaultEntry],
    mut updated: VaultEntry,
    expiry_days: Option<u32>,
) -> Result<(), String> {
    let id = entry_id(&updated).to_string();
    let pos = entries
        .iter()
        .position(|e| entry_id(e) == id)
        .ok_or_else(|| format!("No entry found with id: {id}"))?;

    let now = chrono_now();
    let expires_at = expiry_days.map(|days| add_days_to_timestamp(&now, days));

    // Per-field change-times (granular sync, v9). Flutter does not round-trip
    // field_times across the bridge, so the existing entry is the source of truth:
    // start from its map and stamp only the fields whose value actually changed.
    let now_ms = now_ms();
    let mut new_field_times = entry_meta(&entries[pos]).field_times.clone();
    for key in changed_field_keys(&entries[pos], &updated) {
        new_field_times.insert(key, now_ms);
    }
    // Per-item deletion tombstones: an item (custom pair / attachment) present
    // before but gone now is a deletion; a re-added item clears its tombstone.
    let old_items = item_keys(&entries[pos]);
    let new_items = item_keys(&updated);
    for removed in old_items.difference(&new_items) {
        new_field_times.insert(format!("del:{removed}"), now_ms);
    }
    for present in &new_items {
        new_field_times.remove(&format!("del:{present}"));
    }

    // Snapshot sensitive fields that have changed, then stamp updated_at.
    match (&entries[pos], &mut updated) {
        (VaultEntry::Login(old), VaultEntry::Login(ref mut new)) => {
            new.meta.updated_at = now.clone();
            if old.password != new.password {
                new.previous_password = Some(crate::vault::entry::PreviousSecret {
                    value: old.password.clone(),
                    saved_at: now.clone(),
                    expires_at: expires_at.clone(),
                });
            } else {
                // Password unchanged — preserve existing history.
                new.previous_password = old.previous_password.clone();
            }
        }
        (VaultEntry::Card(old), VaultEntry::Card(ref mut new)) => {
            new.meta.updated_at = now.clone();
            if old.cvv != new.cvv {
                new.previous_cvv = Some(crate::vault::entry::PreviousSecret {
                    value: old.cvv.clone(),
                    saved_at: now.clone(),
                    expires_at: expires_at.clone(),
                });
            } else {
                new.previous_cvv = old.previous_cvv.clone();
            }
            if old.pin != new.pin {
                new.previous_pin = Some(crate::vault::entry::PreviousSecret {
                    value: old.pin.clone().unwrap_or_default(),
                    saved_at: now.clone(),
                    expires_at: expires_at.clone(),
                });
            } else {
                new.previous_pin = old.previous_pin.clone();
            }
        }
        (_, VaultEntry::Note(ref mut e)) => {
            e.meta.updated_at = now;
        }
        (_, VaultEntry::Identity(ref mut e)) => {
            e.meta.updated_at = now;
        }
        (_, VaultEntry::File(ref mut e)) => {
            e.meta.updated_at = now;
        }
        (_, VaultEntry::Custom(ref mut e)) => {
            e.meta.updated_at = now;
        }
        _ => return Err(String::from("Entry type mismatch during update")),
    }

    entry_meta_mut(&mut updated).field_times = new_field_times;
    entries[pos] = updated;
    Ok(())
}

/// Adds `days` to an ISO 8601 UTC timestamp string, returning a new timestamp.
/// Falls back to the input string unchanged if parsing fails.
fn add_days_to_timestamp(timestamp: &str, days: u32) -> String {
    if timestamp.len() < 10 {
        return timestamp.to_string();
    }
    let year: u64 = timestamp[0..4].parse().unwrap_or(2025);
    let month: u64 = timestamp[5..7].parse().unwrap_or(1);
    let day: u64 = timestamp[8..10].parse().unwrap_or(1);
    let time_suffix = if timestamp.len() > 10 {
        &timestamp[10..]
    } else {
        "T00:00:00Z"
    };

    let total_days = days_from_ymd(year, month, day) + days as u64;
    let (ny, nm, nd) = days_to_ymd(total_days);
    format!("{:04}-{:02}-{:02}{}", ny, nm, nd, time_suffix)
}

/// Converts a (year, month, day) triple to a count of days since 1970-01-01.
fn days_from_ymd(year: u64, month: u64, day: u64) -> u64 {
    let mut d = 0u64;
    for y in 1970..year {
        d += if is_leap(y) { 366 } else { 365 };
    }
    let days_in_month = [
        31u64,
        if is_leap(year) { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    for days in days_in_month.iter().take(month as usize - 1) {
        d += days;
    }
    d + day - 1
}

/// Remove a single entry from the vault by UUID.
///
/// Returns `Err` if no entry with that id exists.
#[flutter_rust_bridge::frb(ignore)]
pub fn delete_entry(entries: &mut Vec<VaultEntry>, id: &str) -> Result<(), String> {
    let pos = entries
        .iter()
        .position(|e| entry_id(e) == id)
        .ok_or_else(|| format!("No entry found with id: {id}"))?;
    entries.remove(pos);
    Ok(())
}

/// Wipe the vault file from disk permanently.
///
/// This is a destructive, irreversible operation. The confirmation
/// logic (two explicit user confirmations) lives in Flutter — Rust
/// executes the deletion unconditionally when this is called.
#[flutter_rust_bridge::frb(ignore)]
pub fn delete_whole_vault(path: &Path) -> Result<(), String> {
    std::fs::remove_file(path).map_err(|e| format!("Failed to delete vault: {e}"))?;
    // R-03: the .bak safety copy must not survive the vault it copies.
    crate::vault::io::remove_backup(path)
}

/// Return all entries from the vault, optionally masking sensitive values.
///
/// When `masked` is true, password and CVV fields are replaced with
/// `MASKED_VALUE` — a fixed-length placeholder that deliberately reveals
/// nothing about the actual value's length.
#[flutter_rust_bridge::frb(ignore)]
pub fn list_entries(entries: &[VaultEntry], masked: bool) -> Vec<VaultEntry> {
    if !masked {
        return entries.to_vec();
    }
    entries.iter().map(|e| mask_entry(e)).collect()
}

/// Returns a clone of a single entry with sensitive fields replaced
/// by `MASKED_VALUE`.
fn mask_entry(entry: &VaultEntry) -> VaultEntry {
    match entry {
        VaultEntry::Login(e) => VaultEntry::Login(LoginEntry {
            meta: e.meta.clone(),
            title: e.title.clone(),
            url: e.url.clone(),
            username: e.username.clone(),
            password: MASKED_VALUE.to_string(),
            notes: e.notes.clone(),
            custom_fields: e
                .custom_fields
                .iter()
                .map(|f| CustomField {
                    label: f.label.clone(),
                    value: if f.hidden {
                        MASKED_VALUE.to_string()
                    } else {
                        f.value.clone()
                    },
                    hidden: f.hidden,
                })
                .collect(),
            attachments: e.attachments.clone(),
            previous_password: e.previous_password.clone(),
            app_id: e.app_id.clone(),
            email: e.email.clone(),
        }),
        VaultEntry::Card(e) => VaultEntry::Card(CardEntry {
            meta: e.meta.clone(),
            card_name: e.card_name.clone(),
            status: e.status.clone(),
            cardholder_name: e.cardholder_name.clone(),
            card_number: e.card_number.clone(),
            expiry: e.expiry.clone(),
            cvv: MASKED_VALUE.to_string(),
            credit_limit: e.credit_limit.clone(),
            card_account_number: e.card_account_number.clone(),
            payment_network: e.payment_network.clone(),
            pin: e.pin.clone(),
            bank_name: e.bank_name.clone(),
            transaction_password: e.transaction_password.clone(),
            notes: e.notes.clone(),
            custom_fields: e.custom_fields.clone(),
            attachments: e.attachments.clone(),
            previous_cvv: e.previous_cvv.clone(),
            previous_pin: e.previous_pin.clone(),
        }),
        VaultEntry::Note(e) => VaultEntry::Note(NoteEntry {
            meta: e.meta.clone(),
            title: e.title.clone(),
            content: e.content.clone(),
            custom_fields: e
                .custom_fields
                .iter()
                .map(|f| CustomField {
                    label: f.label.clone(),
                    value: if f.hidden {
                        MASKED_VALUE.to_string()
                    } else {
                        f.value.clone()
                    },
                    hidden: f.hidden,
                })
                .collect(),
            attachments: e.attachments.clone(),
        }),
        VaultEntry::File(e) => VaultEntry::File(FileEntry {
            meta: e.meta.clone(),
            filename: e.filename.clone(),
            data: e.data.clone(),
            notes: e.notes.clone(),
            custom_fields: e
                .custom_fields
                .iter()
                .map(|f| CustomField {
                    label: f.label.clone(),
                    value: if f.hidden {
                        MASKED_VALUE.to_string()
                    } else {
                        f.value.clone()
                    },
                    hidden: f.hidden,
                })
                .collect(),
        }),
        // Identity and Custom carry no password-class fields — return a plain clone.
        other => other.clone(),
    }
}

/// Re-encrypt the vault under a new passphrase.
///
/// Reads and decrypts the vault with the old passphrase, then
/// re-seals and writes it under the new passphrase. The vault body
/// is not re-encrypted from scratch — only the key encapsulation
/// layer changes, which is the standard pattern for passphrase changes.
#[flutter_rust_bridge::frb(ignore)]
pub fn change_passphrase(
    path: &Path,
    old_passphrase: &[u8],
    new_passphrase: &[u8],
) -> Result<(), String> {
    let entries = load_vault(old_passphrase, path)?;
    save_vault(&entries, new_passphrase, path)
}

/// Export a vault as a passphrase-only `.gabbro` artifact + `.gabbro.sha256`
/// companion — the opt-in security **downgrade** path (ADR-013).
///
/// Re-seals `body` under `passphrase` alone, dropping any YubiKey requirement, so
/// the resulting file opens with the passphrase only. This is reached only via the
/// explicit, warned export toggle; the default export ([`export_vault_preserving`])
/// keeps the source's protection. The alias is not carried into this standalone copy.
///
/// The hash is computed over the raw bytes of the encrypted vault file, following
/// the Linux ISO verification convention (ADR-002), so integrity can be verified
/// before decryption with standard tools (`sha256sum`, `certutil`).
#[flutter_rust_bridge::frb(ignore)]
pub fn export_vault(body: &VaultBody, passphrase: &[u8], export_path: &Path) -> Result<(), String> {
    let vault_bytes = build_passphrase_only_bytes(body, passphrase)?;
    atomic_write_0600(export_path, &vault_bytes)?;
    write_sha256_companion(export_path, &vault_bytes)
}

/// Build the passphrase-only export ciphertext for `body` (ADR-013 downgrade),
/// without touching the filesystem. Re-seals under `passphrase` alone — no
/// YubiKey requirement, no alias (a standalone copy). Shared by the Linux
/// path-write ([`export_vault`]) and the Android byte-return path so neither can
/// drift from the other.
#[flutter_rust_bridge::frb(ignore)]
pub fn build_passphrase_only_bytes(body: &VaultBody, passphrase: &[u8]) -> Result<Vec<u8>, String> {
    let plaintext = zeroize::Zeroizing::new(serialize_vault_body(body)?);
    let sealed = seal_vault(passphrase, &plaintext, None)?;
    Ok(sealed.to_bytes())
}

/// Format the detached SHA-256 companion line for `vault_bytes` (ADR-002):
/// one `sha256sum`-style line `"<hex>  <filename>\n"` naming the vault file.
/// The companion file itself is `<filename>.sha256`.
#[flutter_rust_bridge::frb(ignore)]
pub fn sha256_line(vault_bytes: &[u8], filename: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(vault_bytes);
    let hash_bytes: [u8; 32] = hasher.finalize().into();
    format!(
        "{}  {}\n",
        hash_bytes
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>(),
        filename
    )
}

/// Export a vault preserving its exact on-disk protection (ADR-013).
///
/// This is the DEFAULT export path. It copies the sealed `.gabbro` file at
/// `source_path` to `export_path` **byte-for-byte**, so the registered YubiKey
/// keyslots and the vault alias are retained — a key-protected vault stays
/// key-protected and the copy is provably no weaker than the original. The
/// detached `.gabbro.sha256` companion (ADR-002) is written alongside.
///
/// Callers in a live session must ensure committed mutations are persisted before
/// calling this — every CRUD op already saves, so the on-disk file is current.
#[flutter_rust_bridge::frb(ignore)]
pub fn export_vault_preserving(source_path: &Path, export_path: &Path) -> Result<(), String> {
    let vault_bytes =
        std::fs::read(source_path).map_err(|e| format!("Failed to read vault for export: {e}"))?;
    atomic_write_0600(export_path, &vault_bytes)?;
    write_sha256_companion(export_path, &vault_bytes)
}

/// Write the detached `<export>.gabbro.sha256` companion for `vault_bytes`
/// (ADR-002). One-line hex digest in `sha256sum` format, naming the `.gabbro` file.
fn write_sha256_companion(export_path: &Path, vault_bytes: &[u8]) -> Result<(), String> {
    let filename = export_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("vault.gabbro");
    let hash_hex = sha256_line(vault_bytes, filename);
    let hash_path = export_path.with_extension("gabbro.sha256");
    atomic_write_0600(&hash_path, hash_hex.as_bytes())
}

// ── Vault persistence ─────────────────────────────────────────────────────────

/// Serialize, encrypt, and write a vault to disk in one operation.
///
/// This is the top-level save operation Flutter will call.
/// Entries → JSON → AES-256-GCM encrypted → .gabbro file on disk.
#[flutter_rust_bridge::frb(ignore)]
pub fn save_vault(body: &VaultBody, passphrase: &[u8], path: &Path) -> Result<(), String> {
    // Preserve the alias from the existing on-disk vault so CRUD saves do not
    // silently clear an alias that was set at creation or via set_vault_alias.
    let existing_alias = read_vault(path).ok().and_then(|v| v.alias);
    let plaintext = zeroize::Zeroizing::new(serialize_vault_body(body)?);
    let sealed = seal_vault(passphrase, &plaintext, existing_alias)?;
    write_vault(&sealed, path)
}

/// Read, decrypt, and deserialize a vault from disk in one operation.
///
/// This is the top-level load operation Flutter will call.
/// .gabbro file → AES-256-GCM decrypt → JSON → VaultBody.
#[flutter_rust_bridge::frb(ignore)]
pub fn load_vault(passphrase: &[u8], path: &Path) -> Result<VaultBody, String> {
    let sealed = read_vault(path)?;
    let plaintext = zeroize::Zeroizing::new(open_vault(passphrase, &sealed)?);
    deserialize_vault_body(&plaintext)
}

/// Serialize, encrypt with YubiKey, and write a vault to disk.
#[flutter_rust_bridge::frb(ignore)]
pub fn save_vault_with_yubikey(
    body: &VaultBody,
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: Vec<u8>,
    yubikey_salt: [u8; 32],
    path: &Path,
) -> Result<(), String> {
    let existing_alias = read_vault(path).ok().and_then(|v| v.alias);
    let plaintext = zeroize::Zeroizing::new(serialize_vault_body(body)?);
    let sealed = seal_vault_with_yubikey(
        passphrase,
        hmac_secret,
        credential_id,
        yubikey_salt,
        &plaintext,
        existing_alias,
    )?;
    write_vault(&sealed, path)
}

/// Read, decrypt with YubiKey, and deserialize a vault from disk.
#[flutter_rust_bridge::frb(ignore)]
pub fn load_vault_with_yubikey(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    yubikey_salt: &[u8; 32],
    path: &Path,
) -> Result<VaultBody, String> {
    let sealed = read_vault(path)?;
    let plaintext = zeroize::Zeroizing::new(open_vault_with_yubikey(
        passphrase,
        hmac_secret,
        yubikey_salt,
        &sealed,
    )?);
    deserialize_vault_body(&plaintext)
}

/// Serialize, encrypt with multiple YubiKeys, and write a vault to disk.
/// Requires at least 2 keys (enforces ADR-010 minimum).
#[flutter_rust_bridge::frb(ignore)]
pub fn save_vault_with_keys(
    body: &VaultBody,
    passphrase: &[u8],
    keys: &[crate::crypto::vault_crypto::YubiKeyRegistration],
    path: &Path,
) -> Result<(), String> {
    let existing_alias = read_vault(path).ok().and_then(|v| v.alias);
    let plaintext = zeroize::Zeroizing::new(serialize_vault_body(body)?);
    let sealed = crate::crypto::vault_crypto::seal_vault_with_keys(
        passphrase,
        keys,
        &plaintext,
        existing_alias,
    )?;
    write_vault(&sealed, path)
}

/// Read a vault from disk, decrypt using one registered key, and return the body,
/// `vault_key_master` (for CRUD re-seals), and `wrapping_key` (for key add/remove).
/// `wrapping_key` is `None` for legacy VERSION 2 vaults.
#[allow(clippy::type_complexity)]
#[flutter_rust_bridge::frb(ignore)]
pub fn load_vault_with_key_record(
    passphrase: &[u8],
    hmac_secret: &[u8; 32],
    credential_id: &[u8],
    path: &Path,
) -> Result<
    (
        VaultBody,
        zeroize::Zeroizing<[u8; 32]>,
        Option<zeroize::Zeroizing<[u8; 32]>>,
    ),
    String,
> {
    let sealed = read_vault(path)?;
    let (plaintext, master, wrapping_key) =
        crate::crypto::vault_crypto::open_vault_with_key_record(
            passphrase,
            hmac_secret,
            credential_id,
            &sealed,
        )?;
    let plaintext = zeroize::Zeroizing::new(plaintext);
    let body = deserialize_vault_body(&plaintext)?;
    Ok((body, master, wrapping_key))
}

/// Add a new YubiKey record to a VERSION 4 vault on disk and re-seal the body
/// so the new header (with the additional record) is bound to the ciphertext.
#[flutter_rust_bridge::frb(ignore)]
pub fn add_yubikey_to_vault(
    body_plaintext: &[u8],
    wrapping_key: &[u8; 32],
    vault_key_master: &[u8; 32],
    new_cred_id: Vec<u8>,
    new_hmac: &[u8; 32],
    new_salt: [u8; 32],
    path: &Path,
) -> Result<(), String> {
    let sealed = read_vault(path)?;
    let mut new_sealed = crate::crypto::vault_crypto::add_key_to_sealed(
        &sealed,
        new_cred_id,
        new_hmac,
        new_salt,
        wrapping_key,
        vault_key_master,
    )?;
    crate::crypto::vault_crypto::reseal_vault_body(
        &mut new_sealed,
        vault_key_master,
        body_plaintext,
    )?;
    write_vault(&new_sealed, path)
}

/// Remove a YubiKey record from a vault on disk and re-seal the body so the
/// updated header (fewer records) is bound to the ciphertext.
#[flutter_rust_bridge::frb(ignore)]
pub fn remove_yubikey_from_vault(
    body_plaintext: &[u8],
    vault_key_master: &[u8; 32],
    cred_id: &[u8],
    path: &Path,
) -> Result<(), String> {
    let sealed = read_vault(path)?;
    let mut new_sealed = crate::crypto::vault_crypto::remove_key_from_sealed(&sealed, cred_id)?;
    crate::crypto::vault_crypto::reseal_vault_body(
        &mut new_sealed,
        vault_key_master,
        body_plaintext,
    )?;
    write_vault(&new_sealed, path)
}

/// Re-seal only the vault body using a cached `vault_key_master`, leaving all
/// YubiKey records intact.  Used for CRUD saves in a multi-key session.
#[flutter_rust_bridge::frb(ignore)]
pub fn reseal_vault_body(
    body: &VaultBody,
    vault_key_master: &[u8; 32],
    path: &Path,
) -> Result<(), String> {
    use crate::vault::io::read_vault;
    let mut sealed = read_vault(path)?;
    let plaintext = zeroize::Zeroizing::new(serialize_vault_body(body)?);
    crate::crypto::vault_crypto::reseal_vault_body(&mut sealed, vault_key_master, &plaintext)?;
    write_vault(&sealed, path)
}

/// Change the passphrase on a VERSION 4 multi-key vault.
///
/// Reads the vault from disk, verifies the old passphrase via `passphrase_blob`,
/// generates fresh PQ material for the new passphrase, re-encrypts `wrapping_key`
/// as the new `passphrase_blob`, then re-seals the body so the updated header
/// (new argon2_salt, hkdf_salt, ml_kem_ciphertext, passphrase_blob) is committed
/// as AES-GCM AAD for VERSION 7+ vaults.
#[flutter_rust_bridge::frb(ignore)]
pub fn change_passphrase_with_keys(
    old_passphrase: &[u8],
    new_passphrase: &[u8],
    vault_key_master: &[u8; 32],
    body_plaintext: &[u8],
    path: &Path,
) -> Result<(), String> {
    let sealed = read_vault(path)?;
    let mut new_sealed = crate::crypto::vault_crypto::change_vault_passphrase_with_keys(
        &sealed,
        old_passphrase,
        new_passphrase,
    )?;
    crate::crypto::vault_crypto::reseal_vault_body(
        &mut new_sealed,
        vault_key_master,
        body_plaintext,
    )?;
    write_vault(&new_sealed, path)
}

// ── Timestamp helper ──────────────────────────────────────────────────────────

/// Returns the current UTC time as an ISO 8601 string.
/// Uses std only — no chrono dependency needed at this stage.
pub fn chrono_now() -> String {
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
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hour, min, sec
    )
}

fn days_to_ymd(mut days: u64) -> (u64, u64, u64) {
    let mut year = 1970u64;
    loop {
        let days_in_year = if is_leap(year) { 366 } else { 365 };
        if days < days_in_year {
            break;
        }
        days -= days_in_year;
        year += 1;
    }
    let months = [
        31,
        if is_leap(year) { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    let mut month = 1u64;
    for &m in &months {
        if days < m {
            break;
        }
        days -= m;
        month += 1;
    }
    (year, month, days + 1)
}

fn is_leap(year: u64) -> bool {
    (year.is_multiple_of(4) && !year.is_multiple_of(100)) || year.is_multiple_of(400)
}

/// Returns `true` if `expires_at` is set and the timestamp is in the past.
///
/// `None` means keep-forever — never expired.
/// An unparseable string is treated as not expired (conservative).
pub(crate) fn is_expired(expires_at: Option<&str>) -> bool {
    use std::time::{SystemTime, UNIX_EPOCH};
    let ts = match expires_at {
        Some(s) if s.len() >= 10 => s,
        _ => return false,
    };
    let year: u64 = ts[0..4].parse().unwrap_or(9999);
    let month: u64 = ts[5..7].parse().unwrap_or(12);
    let day: u64 = ts[8..10].parse().unwrap_or(31);
    let expires_days = days_from_ymd(year, month, day);
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let now_days = now_secs / 86400;
    // Expired if the expiry day is strictly before today.
    expires_days < now_days
}

/// Purge expired `previous_password`, `previous_cvv`, and `previous_pin`
/// from all entries in the session.
///
/// Called on every unlock — silent, no-op for entries with no history
/// or future/keep-forever expiry.
pub(crate) fn purge_expired_history(entries: &mut [VaultEntry]) {
    for entry in entries.iter_mut() {
        match entry {
            VaultEntry::Login(ref mut e) => {
                if is_expired(
                    e.previous_password
                        .as_ref()
                        .and_then(|p| p.expires_at.as_deref()),
                ) {
                    e.previous_password = None;
                }
            }
            VaultEntry::Card(ref mut e) => {
                if is_expired(
                    e.previous_cvv
                        .as_ref()
                        .and_then(|p| p.expires_at.as_deref()),
                ) {
                    e.previous_cvv = None;
                }
                if is_expired(
                    e.previous_pin
                        .as_ref()
                        .and_then(|p| p.expires_at.as_deref()),
                ) {
                    e.previous_pin = None;
                }
            }
            _ => {}
        }
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // R-03: deleting a vault must not leak a copy via the .bak sibling
    #[test]
    fn delete_whole_vault_removes_bak_too() {
        let dir = std::env::temp_dir();
        let path = dir.join("gabbro_api_delete_bak_test.gabbro");
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        std::fs::write(&path, b"vault bytes").unwrap();
        std::fs::write(&bak, b"backup bytes").unwrap();

        let result = delete_whole_vault(&path);
        let main_gone = !path.exists();
        let bak_gone = !bak.exists();
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&bak);

        result.expect("delete must succeed");
        assert!(main_gone, "vault file must be deleted");
        assert!(
            bak_gone,
            ".bak must be deleted with the vault (no copy may survive)"
        );
    }

    // R-03: deletion must not fail just because no .bak was ever created
    #[test]
    fn delete_whole_vault_succeeds_without_bak() {
        let dir = std::env::temp_dir();
        let path = dir.join("gabbro_api_delete_nobak_test.gabbro");
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&bak);
        std::fs::write(&path, b"vault bytes").unwrap();

        let result = delete_whole_vault(&path);
        let _ = std::fs::remove_file(&path);
        result.expect("delete must succeed when no .bak exists");
    }

    // R-03 P0 (failure #4 characterization): a YubiKey-sealed vault whose bytes
    // have been overwritten with garbage must NOT open — not silently, and never
    // to an empty-but-valid vault. Proves the AES-GCM auth-tag / parse gate holds
    // on the YubiKey unlock path, ruling out the Rust layer as the source of the
    // device report "garbage both files -> unlocks fine to an EMPTY vault."
    #[test]
    fn garbaged_yubikey_vault_does_not_open() {
        use crate::crypto::vault_crypto::seal_vault_with_yubikey;
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use crate::vault::io::write_vault;
        use crate::vault::serialization::{serialize_vault_body, VaultBody};

        let dir = std::env::temp_dir();
        let path = dir.join("gabbro_p0_garbage_yk_test.gabbro");
        let bak = std::path::PathBuf::from(format!("{}.bak", path.display()));
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&bak);

        let passphrase = b"p0 yk passphrase";
        let hmac_secret = [7u8; 32];
        let salt = [9u8; 32];
        let credential_id = vec![1u8, 2, 3, 4];

        // A real, non-empty body — so "opened empty" would be a detectable change.
        let body = VaultBody {
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    id: String::from("p0-note-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from(""),
                },
                title: String::from("secret note"),
                content: String::from("must never be reachable from garbage"),
                custom_fields: vec![],
                attachments: vec![],
            })],
            ..Default::default()
        };
        let plaintext = serialize_vault_body(&body).unwrap();
        let sealed = seal_vault_with_yubikey(
            passphrase,
            &hmac_secret,
            credential_id,
            salt,
            &plaintext,
            None,
        )
        .unwrap();
        write_vault(&sealed, &path).unwrap();

        // Setup sanity: with the correct credentials it opens and the entry is there.
        let good = load_vault_with_yubikey(passphrase, &hmac_secret, &salt, &path)
            .expect("sealed vault must open with correct credentials");
        assert_eq!(
            good.entries.len(),
            1,
            "setup sanity: the entry must be present"
        );

        // the maintainer's printf scenario: overwrite the sealed bytes with garbage.
        std::fs::write(&path, b"rubbish").unwrap();

        let result = load_vault_with_yubikey(passphrase, &hmac_secret, &salt, &path);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&bak);

        assert!(
            result.is_err(),
            "a garbaged YubiKey vault must fail to open, never unlock to an empty vault"
        );
    }

    #[test]
    fn create_login_entry_returns_correct_fields() {
        let entry = create_login_entry(
            String::from("Personal"),
            String::from("Example"),
            String::from("https://example.com"),
            String::from("user"),
            String::from("hunter2"),
            None,
            vec![],
        );

        assert_eq!(entry.title, "Example");
        assert_eq!(entry.folder, "Personal");
        assert_eq!(entry.url, "https://example.com");
        assert_eq!(entry.username, "user");
        assert_eq!(entry.password, "hunter2");
        assert!(entry.notes.is_none());
    }

    #[test]
    fn create_login_entry_generates_unique_ids() {
        let a = create_login_entry(
            String::from("Work"),
            String::from("Site A"),
            String::from("https://a.com"),
            String::from("user"),
            String::from("pass"),
            None,
            vec![],
        );
        let b = create_login_entry(
            String::from("Work"),
            String::from("Site B"),
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
            value: String::from("user@example.com"),
            hidden: false,
        };
        let entry = create_login_entry(
            String::from("Personal"),
            String::from("Example"),
            String::from("https://example.com"),
            String::from("user"),
            String::from("s3cr3t"),
            Some(String::from("main account")),
            vec![field],
        );

        assert!(entry.notes.is_some());
        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Recovery email");
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
    fn save_and_load_vault_roundtrip() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_api_test.gabbro");

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Test note"),
            content: String::from("secret content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        let passphrase = b"correct horst battery staple";
        save_vault(
            &VaultBody {
                folders: vec![],
                entries: entries.clone(),
                ..Default::default()
            },
            passphrase,
            &path,
        )
        .unwrap();
        let recovered = load_vault(passphrase, &path).unwrap();

        assert_eq!(recovered.entries.len(), 1);
        match &recovered.entries[0] {
            VaultEntry::Note(e) => assert_eq!(e.content, "secret content"),
            _ => panic!("Expected Note variant"),
        }

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn load_vault_wrong_passphrase_fails() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_api_wrong_pass_test.gabbro");

        let entries: Vec<VaultEntry> = vec![];
        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
                ..Default::default()
            },
            b"correct passphrase",
            &path,
        )
        .unwrap();
        let result = load_vault(b"wrong passphrase", &path);

        let _ = std::fs::remove_file(&path);
        assert!(result.is_err());
    }

    #[test]
    fn update_entry_replaces_correct_entry() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let mut entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Original title"),
            content: String::from("original content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        let updated = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Updated title"),
            content: String::from("updated content"),
            custom_fields: vec![],
            attachments: vec![],
        });

        update_entry(&mut entries, updated, Some(30)).unwrap();
        assert_eq!(entries.len(), 1);
        match &entries[0] {
            VaultEntry::Note(e) => {
                assert_eq!(e.title, "Updated title");
                assert_eq!(e.content, "updated content");
            }
            _ => panic!("Expected Note variant"),
        }
    }

    #[test]
    fn update_entry_stamps_updated_at() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let mut entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Note"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        let updated = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Note"),
            content: String::from("new content"),
            custom_fields: vec![],
            attachments: vec![],
        });

        update_entry(&mut entries, updated, Some(30)).unwrap();
        match &entries[0] {
            VaultEntry::Note(e) => assert_ne!(e.meta.updated_at, "2025-01-01T00:00:00Z"),
            _ => panic!("Expected Note variant"),
        }
    }

    // ── per-field change-time stamping (granular sync, v9) ────────────────────

    fn note_with(id: &str, title: &str, content: &str) -> crate::vault::entry::VaultEntry {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                id: id.to_string(),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::new(),
                ..Default::default()
            },
            title: title.to_string(),
            content: content.to_string(),
            custom_fields: vec![],
            attachments: vec![],
        })
    }

    fn note_field_times(
        e: &crate::vault::entry::VaultEntry,
    ) -> std::collections::BTreeMap<String, u64> {
        match e {
            crate::vault::entry::VaultEntry::Note(n) => n.meta.field_times.clone(),
            _ => panic!("expected Note"),
        }
    }

    #[test]
    fn update_entry_stamps_field_time_for_changed_scalar() {
        let mut entries = vec![note_with("id-1", "Title", "old")];
        let updated = note_with("id-1", "Title", "new");
        update_entry(&mut entries, updated, None).unwrap();
        let times = note_field_times(&entries[0]);
        assert!(times.contains_key("content"), "changed content must stamp");
        assert!(*times.get("content").unwrap() > 0);
    }

    #[test]
    fn update_entry_does_not_stamp_unchanged_scalar() {
        let mut entries = vec![note_with("id-1", "Title", "old")];
        let updated = note_with("id-1", "Title", "new");
        update_entry(&mut entries, updated, None).unwrap();
        let times = note_field_times(&entries[0]);
        assert!(
            !times.contains_key("title"),
            "unchanged title must not stamp"
        );
    }

    #[test]
    fn update_entry_stamps_only_the_changed_field() {
        let mut entries = vec![note_with("id-1", "Title", "old")];
        let updated = note_with("id-1", "Title", "new");
        update_entry(&mut entries, updated, None).unwrap();
        let times = note_field_times(&entries[0]);
        assert_eq!(times.len(), 1, "exactly one field changed");
        assert!(times.contains_key("content"));
    }

    #[test]
    fn update_entry_preserves_prior_field_times() {
        // A field stamped on an earlier edit must survive a later edit to a
        // different field — field_times accumulates, it is never reset.
        let mut entries = vec![note_with("id-1", "Title", "old")];
        if let crate::vault::entry::VaultEntry::Note(n) = &mut entries[0] {
            n.meta.field_times.insert(String::from("title"), 100);
        }
        let updated = note_with("id-1", "Title", "new");
        update_entry(&mut entries, updated, None).unwrap();
        let times = note_field_times(&entries[0]);
        assert_eq!(times.get("title"), Some(&100), "prior stamp preserved");
        assert!(times.contains_key("content"), "new change stamped");
    }

    #[test]
    fn update_entry_stamps_custom_pair_by_label() {
        use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
        let base_login = |cf_value: &str| {
            VaultEntry::Login(LoginEntry {
                meta: EntryMeta {
                    id: String::from("login-1"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::new(),
                    ..Default::default()
                },
                title: String::from("Acct"),
                url: String::new(),
                username: String::from("user"),
                password: String::from("pw"),
                notes: None,
                custom_fields: vec![CustomField {
                    label: String::from("PIN"),
                    value: cf_value.to_string(),
                    hidden: true,
                }],
                attachments: vec![],
                previous_password: None,
                app_id: None,
                email: None,
            })
        };
        let mut entries = vec![base_login("1234")];
        update_entry(&mut entries, base_login("5678"), None).unwrap();
        match &entries[0] {
            VaultEntry::Login(e) => {
                assert!(
                    e.meta.field_times.contains_key("custom_fields:PIN"),
                    "changed custom pair must stamp by label, got {:?}",
                    e.meta.field_times
                );
            }
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn update_entry_removing_custom_pair_stamps_deletion_tombstone() {
        use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
        let login = |custom: Vec<CustomField>| {
            VaultEntry::Login(LoginEntry {
                meta: EntryMeta {
                    id: String::from("l1"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::new(),
                    ..Default::default()
                },
                title: String::from("Acct"),
                url: String::new(),
                username: String::from("u"),
                password: String::from("p"),
                notes: None,
                custom_fields: custom,
                attachments: vec![],
                previous_password: None,
                app_id: None,
                email: None,
            })
        };
        let mut entries = vec![login(vec![CustomField {
            label: String::from("PIN"),
            value: String::from("1"),
            hidden: true,
        }])];
        update_entry(&mut entries, login(vec![]), None).unwrap();
        match &entries[0] {
            VaultEntry::Login(e) => assert!(
                e.meta.field_times.contains_key("del:custom_fields:PIN"),
                "removal stamps a tombstone, got {:?}",
                e.meta.field_times
            ),
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn update_entry_readding_item_clears_deletion_tombstone() {
        use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};
        let login = |custom: Vec<CustomField>| {
            VaultEntry::Login(LoginEntry {
                meta: EntryMeta {
                    id: String::from("l1"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::new(),
                    ..Default::default()
                },
                title: String::from("Acct"),
                url: String::new(),
                username: String::from("u"),
                password: String::from("p"),
                notes: None,
                custom_fields: custom,
                attachments: vec![],
                previous_password: None,
                app_id: None,
                email: None,
            })
        };
        let mut entries = vec![login(vec![])];
        if let VaultEntry::Login(e) = &mut entries[0] {
            e.meta
                .field_times
                .insert(String::from("del:custom_fields:PIN"), 100);
        }
        update_entry(
            &mut entries,
            login(vec![CustomField {
                label: String::from("PIN"),
                value: String::from("1"),
                hidden: true,
            }]),
            None,
        )
        .unwrap();
        match &entries[0] {
            VaultEntry::Login(e) => assert!(
                !e.meta.field_times.contains_key("del:custom_fields:PIN"),
                "re-adding clears the tombstone"
            ),
            _ => panic!("expected Login"),
        }
    }

    fn sample_login_for_resolve() -> crate::vault::entry::VaultEntry {
        use crate::vault::entry::{
            CustomField, EntryAttachment, EntryMeta, LoginEntry, VaultEntry,
        };
        VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                id: String::from("l"),
                created_at: String::new(),
                updated_at: String::new(),
                folder: String::new(),
                ..Default::default()
            },
            title: String::from("T"),
            url: String::new(),
            username: String::from("u"),
            password: String::from("old"),
            notes: None,
            custom_fields: vec![CustomField {
                label: String::from("PIN"),
                value: String::from("1234"),
                hidden: true,
            }],
            attachments: vec![EntryAttachment {
                uuid: String::from("att-1"),
                name: String::from("a"),
                kind: String::from("text"),
                data: vec![],
            }],
            previous_password: None,
            app_id: None,
            email: None,
        })
    }

    #[test]
    fn set_entry_field_by_key_sets_scalar() {
        let mut e = sample_login_for_resolve();
        set_entry_field_by_key(&mut e, "password", "new-pw");
        match &e {
            VaultEntry::Login(l) => assert_eq!(l.password, "new-pw"),
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn set_entry_field_by_key_sets_custom_pair() {
        let mut e = sample_login_for_resolve();
        set_entry_field_by_key(&mut e, "custom_fields:PIN", "9999");
        match &e {
            VaultEntry::Login(l) => assert_eq!(
                l.custom_fields
                    .iter()
                    .find(|f| f.label == "PIN")
                    .unwrap()
                    .value,
                "9999"
            ),
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn remove_entry_item_by_key_removes_custom_pair() {
        let mut e = sample_login_for_resolve();
        remove_entry_item_by_key(&mut e, "custom_fields:PIN");
        match &e {
            VaultEntry::Login(l) => assert!(l.custom_fields.iter().all(|f| f.label != "PIN")),
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn remove_entry_item_by_key_removes_attachment() {
        let mut e = sample_login_for_resolve();
        remove_entry_item_by_key(&mut e, "attachments:att-1");
        match &e {
            VaultEntry::Login(l) => assert!(l.attachments.is_empty()),
            _ => panic!("expected Login"),
        }
    }

    #[test]
    fn update_entry_missing_id_returns_error() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let mut entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Note"),
            content: String::from("content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        let ghost = VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("does-not-exist"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Ghost"),
            content: String::from("ghost content"),
            custom_fields: vec![],
            attachments: vec![],
        });

        assert!(update_entry(&mut entries, ghost, Some(30)).is_err());
    }

    #[test]
    fn delete_entry_removes_correct_entry() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let mut entries = vec![
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    id: String::from("id-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                },
                title: String::from("First"),
                content: String::from("first content"),
                custom_fields: vec![],
                attachments: vec![],
            }),
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    id: String::from("id-002"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                },
                title: String::from("Second"),
                content: String::from("second content"),
                custom_fields: vec![],
                attachments: vec![],
            }),
        ];

        delete_entry(&mut entries, "id-001").unwrap();
        assert_eq!(entries.len(), 1);
        match &entries[0] {
            VaultEntry::Note(e) => assert_eq!(e.meta.id, "id-002"),
            _ => panic!("Expected Note variant"),
        }
    }

    #[test]
    fn delete_entry_missing_id_returns_error() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let mut entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("A note"),
            content: String::from("some content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        assert!(delete_entry(&mut entries, "does-not-exist").is_err());
    }

    #[test]
    fn delete_whole_vault_removes_file() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_delete_test.gabbro");

        // Create a real vault file first
        save_vault(&VaultBody::empty(), b"passphrase", &path).unwrap();
        assert!(path.exists());

        delete_whole_vault(&path).unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn delete_whole_vault_missing_file_returns_error() {
        let path = std::path::Path::new("/tmp/does_not_exist_gabbro_delete.gabbro");
        assert!(delete_whole_vault(path).is_err());
    }

    #[test]
    fn list_entries_unmasked_returns_plaintext() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entries = vec![VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
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
        })];

        let result = list_entries(&entries, false);
        match &result[0] {
            VaultEntry::Login(e) => assert_eq!(e.password, "s3cr3t"),
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn list_entries_masked_hides_password() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let entries = vec![VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("correct horst battery staple"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.password, MASKED_VALUE);
                assert_eq!(e.username, "user"); // non-sensitive field unchanged
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn list_entries_masked_hides_cvv() {
        use crate::vault::entry::{CardEntry, EntryMeta, VaultEntry};

        let entries = vec![VaultEntry::Card(CardEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            card_name: Some(String::from("Visa Platinum")),
            status: String::from("active"),
            cardholder_name: String::from("Alex Smith"),
            card_number: String::from("4111111111111111"),
            expiry: String::from("12/28"),
            cvv: String::from("123"),
            credit_limit: None,
            card_account_number: None,
            payment_network: Some(String::from("Visa")),
            pin: None,
            bank_name: None,
            transaction_password: None,
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_cvv: None,
            previous_pin: None,
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::Card(e) => {
                assert_eq!(e.cvv, MASKED_VALUE);
                assert_eq!(e.expiry, "12/28"); // non-sensitive field unchanged
            }
            _ => panic!("Expected Card variant"),
        }
    }

    #[test]
    fn list_entries_masked_hides_hidden_custom_fields() {
        use crate::vault::entry::{CustomField, EntryMeta, LoginEntry, VaultEntry};

        let entries = vec![VaultEntry::Login(LoginEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![
                CustomField {
                    label: String::from("API key"),
                    value: String::from("sk-abc123"),
                    hidden: true,
                },
                CustomField {
                    label: String::from("Region"),
                    value: String::from("eu-west-1"),
                    hidden: false,
                },
            ],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.custom_fields[0].value, MASKED_VALUE); // hidden
                assert_eq!(e.custom_fields[1].value, "eu-west-1"); // not hidden
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn update_entry_captures_previous_password() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let meta = EntryMeta {
            field_times: Default::default(),
            id: String::from("id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        let mut entries = vec![VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("old_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        })];

        let updated = VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("new_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        });

        update_entry(&mut entries, updated, Some(30)).unwrap();

        match &entries[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.password, "new_password");
                let prev = e
                    .previous_password
                    .as_ref()
                    .expect("previous_password should be set");
                assert_eq!(prev.value, "old_password");
                assert!(prev.expires_at.is_some());
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn update_entry_no_expiry_keeps_forever() {
        use crate::vault::entry::{EntryMeta, LoginEntry, VaultEntry};

        let meta = EntryMeta {
            field_times: Default::default(),
            id: String::from("id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        let mut entries = vec![VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("old_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        })];

        let updated = VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("new_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        });

        update_entry(&mut entries, updated, None).unwrap();

        match &entries[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.password, "new_password");
                let prev = e
                    .previous_password
                    .as_ref()
                    .expect("previous_password should be set");
                assert_eq!(prev.value, "old_password");
                assert!(prev.expires_at.is_none());
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn update_entry_unchanged_password_does_not_overwrite_history() {
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let meta = EntryMeta {
            field_times: Default::default(),
            id: String::from("id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        let existing_prev = PreviousSecret {
            value: String::from("even_older"),
            saved_at: String::from("2024-12-01T00:00:00Z"),
            expires_at: Some(String::from("2024-12-31T00:00:00Z")),
        };
        let mut entries = vec![VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("same_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(existing_prev),
            app_id: None,
            email: None,
        })];

        let updated = VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example — updated title"),
            url: String::from("https://example.com"),
            username: String::from("user"),
            password: String::from("same_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        });

        update_entry(&mut entries, updated, Some(30)).unwrap();

        match &entries[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.title, "Example — updated title");
                // password unchanged — existing history must be preserved as-is
                let prev = e
                    .previous_password
                    .as_ref()
                    .expect("history should be preserved");
                assert_eq!(prev.value, "even_older");
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn update_keeps_only_the_most_recent_previous_password() {
        // Single-slot history: an entry that already holds a previous password, then
        // one password change, keeps exactly one previous (the value it just replaced)
        // and drops the pre-existing one — history is a slot, not a growing stack.
        use crate::vault::entry::{EntryMeta, LoginEntry, PreviousSecret, VaultEntry};

        let meta = EntryMeta {
            field_times: Default::default(),
            id: String::from("id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        let pre_existing = PreviousSecret {
            value: String::from("older_pw"),
            saved_at: String::from("2024-12-01T00:00:00Z"),
            expires_at: Some(String::from("2024-12-31T00:00:00Z")),
        };
        let mut entries = vec![VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("alice"),
            password: String::from("current_pw"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(pre_existing),
            app_id: None,
            email: None,
        })];

        let updated = VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("alice"),
            password: String::from("new_pw"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
            app_id: None,
            email: None,
        });

        update_entry(&mut entries, updated, Some(30)).unwrap();

        match &entries[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.password, "new_pw");
                let prev = e
                    .previous_password
                    .as_ref()
                    .expect("previous_password should hold the just-replaced value");
                // The just-replaced current becomes the one previous...
                assert_eq!(prev.value, "current_pw");
                // ...and the pre-existing previous is dropped (single slot, not a stack).
                assert_ne!(prev.value, "older_pw");
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn list_entries_masked_does_not_alter_note() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("My note"),
            content: String::from("sensitive note content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::Note(e) => assert_eq!(e.content, "sensitive note content"),
            _ => panic!("Expected Note variant"),
        }
    }

    #[test]
    fn list_entries_masked_hides_hidden_custom_fields_on_note() {
        use crate::vault::entry::{CustomField, EntryMeta, NoteEntry, VaultEntry};

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("My note"),
            content: String::from("content"),
            custom_fields: vec![
                CustomField {
                    label: String::from("Secret key"),
                    value: String::from("sk-xyz"),
                    hidden: true,
                },
                CustomField {
                    label: String::from("Category"),
                    value: String::from("finance"),
                    hidden: false,
                },
            ],
            attachments: vec![],
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::Note(e) => {
                assert_eq!(e.custom_fields[0].value, MASKED_VALUE);
                assert_eq!(e.custom_fields[1].value, "finance");
            }
            _ => panic!("Expected Note variant"),
        }
    }

    #[test]
    fn list_entries_masked_hides_hidden_custom_fields_on_file() {
        use crate::vault::entry::{CustomField, EntryMeta, FileEntry, VaultEntry};

        let entries = vec![VaultEntry::File(FileEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            filename: String::from("report.pdf"),
            data: vec![],
            notes: None,
            custom_fields: vec![
                CustomField {
                    label: String::from("Password"),
                    value: String::from("s3cr3t"),
                    hidden: true,
                },
                CustomField {
                    label: String::from("Author"),
                    value: String::from("Alex"),
                    hidden: false,
                },
            ],
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::File(e) => {
                assert_eq!(e.custom_fields[0].value, MASKED_VALUE);
                assert_eq!(e.custom_fields[1].value, "Alex");
            }
            _ => panic!("Expected File variant"),
        }
    }

    #[test]
    fn change_passphrase_allows_open_with_new_passphrase() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_change_pass_test.gabbro");

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Test note"),
            content: String::from("secret content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        let old = b"old passphrase";
        let new = b"new passphrase";

        save_vault(
            &VaultBody {
                folders: vec![],
                entries,
                ..Default::default()
            },
            old,
            &path,
        )
        .unwrap();
        change_passphrase(&path, old, new).unwrap();

        // Old passphrase must no longer work
        assert!(load_vault(old, &path).is_err());

        // New passphrase must work and content must be preserved
        let recovered = load_vault(new, &path).unwrap();
        assert_eq!(recovered.entries.len(), 1);
        match &recovered.entries[0] {
            VaultEntry::Note(e) => assert_eq!(e.content, "secret content"),
            _ => panic!("Expected Note variant"),
        }

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn change_passphrase_preserves_folders() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_change_pass_folders_test.gabbro");

        let body = VaultBody {
            folders: vec![
                String::from("Work"),
                String::from("Private"),
                String::from("Other"),
            ],
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    id: String::from("id-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Work"),
                },
                title: String::from("Test note"),
                content: String::from("secret content"),
                custom_fields: vec![],
                attachments: vec![],
            })],
            ..Default::default()
        };

        let old = b"old passphrase";
        let new = b"new passphrase";

        save_vault(&body, old, &path).unwrap();
        change_passphrase(&path, old, new).unwrap();

        let recovered = load_vault(new, &path).unwrap();
        assert_eq!(
            recovered.folders,
            vec!["Work", "Private", "Other"],
            "folders must survive a passphrase change"
        );

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn change_passphrase_wrong_old_passphrase_fails() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_change_pass_wrong_test.gabbro");

        save_vault(&VaultBody::empty(), b"correct passphrase", &path).unwrap();

        let result = change_passphrase(&path, b"wrong passphrase", b"new passphrase");

        let _ = std::fs::remove_file(&path);
        assert!(result.is_err());
    }

    #[test]
    fn export_vault_creates_both_files() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_export_test.gabbro");
        let hash_path = path.with_extension("gabbro.sha256");

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Export test"),
            content: String::from("exported content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        export_vault(
            &VaultBody {
                entries,
                ..Default::default()
            },
            b"correct horst battery staple",
            &path,
        )
        .unwrap();

        assert!(path.exists(), ".gabbro file should exist");
        assert!(hash_path.exists(), ".gabbro.sha256 file should exist");

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&hash_path);
    }

    #[test]
    fn export_vault_hash_file_contains_filename() {
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_export_hash_test.gabbro");
        let hash_path = path.with_extension("gabbro.sha256");

        export_vault(&VaultBody::default(), b"passphrase", &path).unwrap();

        let hash_contents = std::fs::read_to_string(&hash_path).unwrap();
        assert!(hash_contents.contains("gabbro_export_hash_test.gabbro"));
        assert!(hash_contents.ends_with('\n'));

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&hash_path);
    }

    #[test]
    fn export_vault_can_be_loaded_back() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_export_reload_test.gabbro");
        let hash_path = path.with_extension("gabbro.sha256");

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
                field_times: Default::default(),
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Reload test"),
            content: String::from("reloaded content"),
            custom_fields: vec![],
            attachments: vec![],
        })];

        let passphrase = b"correct horst battery staple";
        export_vault(
            &VaultBody {
                entries,
                ..Default::default()
            },
            passphrase,
            &path,
        )
        .unwrap();
        let recovered = load_vault(passphrase, &path).unwrap();

        assert_eq!(recovered.entries.len(), 1);
        match &recovered.entries[0] {
            VaultEntry::Note(e) => assert_eq!(e.content, "reloaded content"),
            _ => panic!("Expected Note variant"),
        }

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&hash_path);
    }

    // ── export_vault_preserving — ADR-013 default (protection-preserving) ──────
    //
    // The security boundary: exporting a key-protected vault must keep the YubiKey
    // requirement (byte-for-byte copy of the sealed file), and exporting any vault
    // must produce a faithful, integrity-checkable copy.

    use crate::crypto::vault_crypto::YubiKeyRegistration;
    use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

    fn note_body(id: &str, content: &str) -> VaultBody {
        VaultBody {
            entries: vec![VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    field_times: Default::default(),
                    id: String::from(id),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::new(),
                },
                title: String::from("preserve test"),
                content: String::from(content),
                custom_fields: vec![],
                attachments: vec![],
            })],
            ..Default::default()
        }
    }

    #[test]
    fn export_preserving_keyprotected_vault_keeps_key_requirement() {
        use std::env::temp_dir;

        let pass: &[u8] = b"key-protected source passphrase";
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
        source.push("gabbro_preserve_keyprot_src.gabbro");
        let mut export = temp_dir();
        export.push("gabbro_preserve_keyprot_out.gabbro");

        save_vault_with_keys(
            &note_body("kp-001", "hardware secret"),
            pass,
            &[yk1, yk2],
            &source,
        )
        .unwrap();

        export_vault_preserving(&source, &export).unwrap();

        // The exported artifact must NOT open with the passphrase alone...
        assert!(
            load_vault(pass, &export).is_err(),
            "preserving export of a key-protected vault must stay key-protected"
        );
        // ...but a registered key (+ passphrase) opens it, contents intact.
        let (body, _m, _w) =
            load_vault_with_key_record(pass, &[0x11u8; 32], &[0xA1u8; 64], &export).unwrap();
        assert!(
            body.entries.iter().any(|e| matches!(e, VaultEntry::Note(n)
                if n.meta.id == "kp-001" && n.content == "hardware secret")),
            "registered key must open the exported artifact with contents intact"
        );

        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&export);
        let _ = std::fs::remove_file(source.with_extension("gabbro.sha256"));
        let _ = std::fs::remove_file(export.with_extension("gabbro.sha256"));
    }

    #[test]
    fn export_preserving_passphrase_only_vault_opens_with_passphrase() {
        use std::env::temp_dir;

        let pass: &[u8] = b"passphrase-only source";
        let mut source = temp_dir();
        source.push("gabbro_preserve_passonly_src.gabbro");
        let mut export = temp_dir();
        export.push("gabbro_preserve_passonly_out.gabbro");

        save_vault(&note_body("po-001", "plain secret"), pass, &source).unwrap();
        export_vault_preserving(&source, &export).unwrap();

        let body =
            load_vault(pass, &export).expect("passphrase-only export must open with passphrase");
        assert!(body
            .entries
            .iter()
            .any(|e| matches!(e, VaultEntry::Note(n) if n.meta.id == "po-001")));

        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&export);
        let _ = std::fs::remove_file(source.with_extension("gabbro.sha256"));
        let _ = std::fs::remove_file(export.with_extension("gabbro.sha256"));
    }

    #[test]
    fn sha256_line_hashes_bytes_and_names_file() {
        // Known SHA-256 of the empty input, sha256sum format: "<hex>  <name>\n".
        let line = sha256_line(b"", "Gabbro.gabbro");
        assert_eq!(
            line,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  Gabbro.gabbro\n"
        );
        // Different bytes hash differently; the filename is echoed verbatim.
        let other = sha256_line(b"abc", "vault.json");
        assert!(other.ends_with("  vault.json\n"));
        assert_ne!(line, other);
    }

    #[test]
    fn export_preserving_is_byte_identical_to_source() {
        use std::env::temp_dir;

        let pass: &[u8] = b"byte identity passphrase";
        let mut source = temp_dir();
        source.push("gabbro_preserve_identity_src.gabbro");
        let mut export = temp_dir();
        export.push("gabbro_preserve_identity_out.gabbro");

        save_vault(&note_body("bi-001", "verbatim"), pass, &source).unwrap();
        export_vault_preserving(&source, &export).unwrap();

        let src_bytes = std::fs::read(&source).unwrap();
        let out_bytes = std::fs::read(&export).unwrap();
        assert_eq!(
            src_bytes, out_bytes,
            "preserving export must copy the sealed vault byte-for-byte (keyslots + alias retained)"
        );

        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&export);
        let _ = std::fs::remove_file(export.with_extension("gabbro.sha256"));
    }

    #[test]
    fn export_preserving_writes_matching_sha256_companion() {
        use std::env::temp_dir;

        let pass: &[u8] = b"sha companion passphrase";
        let mut source = temp_dir();
        source.push("gabbro_preserve_sha_src.gabbro");
        let mut export = temp_dir();
        export.push("gabbro_preserve_sha_out.gabbro");
        let hash_path = export.with_extension("gabbro.sha256");

        save_vault(&note_body("sh-001", "hashed"), pass, &source).unwrap();
        export_vault_preserving(&source, &export).unwrap();

        let out_bytes = std::fs::read(&export).unwrap();
        let mut hasher = Sha256::new();
        hasher.update(&out_bytes);
        let digest: [u8; 32] = hasher.finalize().into();
        let expected_hex: String = digest.iter().map(|b| format!("{:02x}", b)).collect();

        let contents = std::fs::read_to_string(&hash_path).unwrap();
        assert!(
            contents.starts_with(&expected_hex),
            "companion hash must match the exported bytes"
        );
        assert!(contents.contains("gabbro_preserve_sha_out.gabbro"));
        assert!(contents.ends_with('\n'));

        let _ = std::fs::remove_file(&source);
        let _ = std::fs::remove_file(&export);
        let _ = std::fs::remove_file(&hash_path);
        let _ = std::fs::remove_file(source.with_extension("gabbro.sha256"));
    }
}
