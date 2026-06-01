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
    CardEntry, CustomEntry, CustomField, EntryMeta, FileEntry, IdentityEntry, LoginEntry,
    NoteEntry, VaultEntry,
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
    /// Human-readable item title (e.g. "GitHub", "Netflix").
    /// Distinct from the URL — used as the primary display label in list views.
    pub title: String,
    pub url: String,
    pub username: String,
    pub password: String,
    pub notes: Option<String>,
    pub custom_fields: Vec<CustomFieldData>,
    /// Previous password, masked by default. `None` if no history exists.
    pub previous_password: Option<PreviousSecretData>,
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
    }
}

fn note_entry_to_data(e: &NoteEntry) -> NoteEntryData {
    NoteEntryData {
        id: e.meta.id.clone(),
        created_at: e.meta.created_at.clone(),
        updated_at: e.meta.updated_at.clone(),
        folder: e.meta.folder.clone(),
        title: e.title.clone(),
        content: e.content.clone(),
        custom_fields: e.custom_fields.iter().map(custom_field_to_data).collect(),
    }
}

fn identity_entry_to_data(e: &IdentityEntry) -> IdentityEntryData {
    IdentityEntryData {
        id: e.meta.id.clone(),
        created_at: e.meta.created_at.clone(),
        updated_at: e.meta.updated_at.clone(),
        folder: e.meta.folder.clone(),
        first_name: e.first_name.clone(),
        last_name: e.last_name.clone(),
        email: e.email.clone(),
        phone: e.phone.clone(),
        address: e.address.clone(),
        custom_fields: e.custom_fields.iter().map(custom_field_to_data).collect(),
    }
}

fn card_entry_to_data(e: &CardEntry) -> CardEntryData {
    CardEntryData {
        id: e.meta.id.clone(),
        created_at: e.meta.created_at.clone(),
        updated_at: e.meta.updated_at.clone(),
        folder: e.meta.folder.clone(),
        card_name: e.card_name.clone(),
        status: e.status.clone(),
        cardholder_name: e.cardholder_name.clone(),
        card_number: e.card_number.clone(),
        expiry: e.expiry.clone(),
        cvv: e.cvv.clone(),
        credit_limit: e.credit_limit.clone(),
        card_account_number: e.card_account_number.clone(),
        payment_network: e.payment_network.clone(),
        pin: e.pin.clone(),
        bank_name: e.bank_name.clone(),
        transaction_password: e.transaction_password.clone(),
        notes: e.notes.clone(),
        custom_fields: e.custom_fields.iter().map(custom_field_to_data).collect(),
        previous_cvv: e.previous_cvv.as_ref().map(previous_secret_to_data),
        previous_pin: e.previous_pin.as_ref().map(previous_secret_to_data),
    }
}

fn file_entry_to_data(e: &FileEntry) -> FileEntryData {
    FileEntryData {
        id: e.meta.id.clone(),
        created_at: e.meta.created_at.clone(),
        updated_at: e.meta.updated_at.clone(),
        folder: e.meta.folder.clone(),
        filename: e.filename.clone(),
        data: e.data.clone(),
        notes: e.notes.clone(),
        custom_fields: e.custom_fields.iter().map(custom_field_to_data).collect(),
    }
}

fn custom_entry_to_data(e: &CustomEntry) -> CustomEntryData {
    CustomEntryData {
        id: e.meta.id.clone(),
        created_at: e.meta.created_at.clone(),
        updated_at: e.meta.updated_at.clone(),
        folder: e.meta.folder.clone(),
        title: e.title.clone(),
        fields: e.fields.values().map(custom_field_to_data).collect(),
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
    };
    login_entry_to_data(&entry)
}

/// Creates a new note entry with a generated UUID and current timestamp.
pub fn create_note_entry(
    folder: String,
    title: String,
    content: String,
    custom_fields: Vec<CustomFieldData>,
) -> NoteEntryData {
    let now = chrono_now();
    let meta = EntryMeta {
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
    let entry = NoteEntry {
        meta,
        title,
        content,
        custom_fields: internal_fields,
        attachments: vec![],
    };
    note_entry_to_data(&entry)
}

/// Creates a new identity entry with a generated UUID and current timestamp.
pub fn create_identity_entry(
    folder: String,
    first_name: String,
    last_name: String,
    email: String,
    phone: Option<String>,
    address: Option<String>,
) -> IdentityEntryData {
    let now = chrono_now();
    let meta = EntryMeta {
        id: Uuid::new_v4().to_string(),
        created_at: now.clone(),
        updated_at: now,
        folder,
    };
    let entry = IdentityEntry {
        meta,
        first_name,
        last_name,
        email,
        phone,
        address,
        custom_fields: vec![],
        attachments: vec![],
    };
    identity_entry_to_data(&entry)
}

/// Creates a new card entry with a generated UUID and current timestamp.
///
/// Returns an error if the card number does not contain 12-19 digits.
#[allow(clippy::too_many_arguments)]
pub fn create_card_entry(
    folder: String,
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
) -> Result<CardEntryData, String> {
    let now = chrono_now();
    let meta = EntryMeta {
        id: Uuid::new_v4().to_string(),
        created_at: now.clone(),
        updated_at: now,
        folder,
    };
    let entry = CardEntry::new(
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
        vec![],
        vec![],
        None,
        None,
    )?;
    Ok(card_entry_to_data(&entry))
}

/// Creates a new file entry with a generated UUID and current timestamp.
pub fn create_file_entry(
    folder: String,
    filename: String,
    data: Vec<u8>,
    notes: Option<String>,
    custom_fields: Vec<CustomFieldData>,
) -> FileEntryData {
    let now = chrono_now();
    let meta = EntryMeta {
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
    let entry = FileEntry {
        meta,
        filename,
        data,
        notes,
        custom_fields: internal_fields,
    };
    file_entry_to_data(&entry)
}

/// Creates a new custom entry with a generated UUID and current timestamp.
pub fn create_custom_entry(
    folder: String,
    title: String,
    fields: Vec<CustomFieldData>,
) -> CustomEntryData {
    let now = chrono_now();
    let meta = EntryMeta {
        id: Uuid::new_v4().to_string(),
        created_at: now.clone(),
        updated_at: now,
        folder,
    };
    let internal_fields = fields
        .into_iter()
        .map(|f| {
            (
                f.label.clone(),
                CustomField {
                    label: f.label,
                    value: f.value,
                    hidden: f.hidden,
                },
            )
        })
        .collect();
    let entry = CustomEntry {
        meta,
        title,
        fields: internal_fields,
        attachments: vec![],
    };
    custom_entry_to_data(&entry)
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

/// Fetch a single entry by UUID from a loaded vault.
///
/// Returns a clone of the matching entry, or `Err` if no entry with
/// that id exists.
#[flutter_rust_bridge::frb(ignore)]
pub fn get_entry_by_id(entries: &[VaultEntry], id: &str) -> Result<VaultEntry, String> {
    entries
        .iter()
        .find(|e| entry_id(e) == id)
        .cloned()
        .ok_or_else(|| format!("No entry found with id: {id}"))
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
    std::fs::remove_file(path).map_err(|e| format!("Failed to delete vault: {e}"))
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

/// Export the vault to a `.gabbro` file and a companion `.gabbro.sha256`
/// detached hash file.
///
/// The hash is computed over the raw bytes of the encrypted vault file,
/// following the Linux ISO verification convention documented in ADR-002.
/// This allows integrity verification before decryption using standard
/// tools (`sha256sum` on Linux, `certutil` on Windows).
///
/// `export_path` should point to the desired `.gabbro` output file.
/// The `.sha256` file is written alongside it automatically.
#[flutter_rust_bridge::frb(ignore)]
pub fn export_vault(body: &VaultBody, passphrase: &[u8], export_path: &Path) -> Result<(), String> {
    let plaintext = serialize_vault_body(body)?;
    let sealed = seal_vault(passphrase, &plaintext)?;
    let vault_bytes = sealed.to_bytes();

    // Write the .gabbro file
    atomic_write_0600(export_path, &vault_bytes)?;

    // Compute SHA-256 over the vault bytes
    let mut hasher = Sha256::new();
    hasher.update(&vault_bytes);
    let hash_bytes: [u8; 32] = hasher.finalize().into();
    let hash_hex = format!(
        "{}  {}\n",
        hash_bytes
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>(),
        export_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("vault.gabbro")
    );

    // Write the .sha256 companion file
    let hash_path = export_path.with_extension("gabbro.sha256");
    atomic_write_0600(&hash_path, hash_hex.as_bytes())?;

    Ok(())
}

// ── Vault persistence ─────────────────────────────────────────────────────────

/// Serialize, encrypt, and write a vault to disk in one operation.
///
/// This is the top-level save operation Flutter will call.
/// Entries → JSON → AES-256-GCM encrypted → .gabbro file on disk.
#[flutter_rust_bridge::frb(ignore)]
pub fn save_vault(body: &VaultBody, passphrase: &[u8], path: &Path) -> Result<(), String> {
    let plaintext = serialize_vault_body(body)?;
    let sealed = seal_vault(passphrase, &plaintext)?;
    write_vault(&sealed, path)
}

/// Read, decrypt, and deserialize a vault from disk in one operation.
///
/// This is the top-level load operation Flutter will call.
/// .gabbro file → AES-256-GCM decrypt → JSON → VaultBody.
#[flutter_rust_bridge::frb(ignore)]
pub fn load_vault(passphrase: &[u8], path: &Path) -> Result<VaultBody, String> {
    let sealed = read_vault(path)?;
    let plaintext = open_vault(passphrase, &sealed)?;
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
    let plaintext = serialize_vault_body(body)?;
    let sealed = seal_vault_with_yubikey(
        passphrase,
        hmac_secret,
        credential_id,
        yubikey_salt,
        &plaintext,
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
    let plaintext = open_vault_with_yubikey(passphrase, hmac_secret, yubikey_salt, &sealed)?;
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
    let plaintext = serialize_vault_body(body)?;
    let sealed = crate::crypto::vault_crypto::seal_vault_with_keys(passphrase, keys, &plaintext)?;
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
    let body = deserialize_vault_body(&plaintext)?;
    Ok((body, master, wrapping_key))
}

/// Add a new YubiKey record to a VERSION 4 vault on disk, without re-sealing the body.
#[flutter_rust_bridge::frb(ignore)]
pub fn add_yubikey_to_vault(
    wrapping_key: &[u8; 32],
    vault_key_master: &[u8; 32],
    new_cred_id: Vec<u8>,
    new_hmac: &[u8; 32],
    new_salt: [u8; 32],
    path: &Path,
) -> Result<(), String> {
    let sealed = read_vault(path)?;
    let new_sealed = crate::crypto::vault_crypto::add_key_to_sealed(
        &sealed,
        new_cred_id,
        new_hmac,
        new_salt,
        wrapping_key,
        vault_key_master,
    )?;
    write_vault(&new_sealed, path)
}

/// Remove a YubiKey record from a vault on disk, without re-sealing the body.
#[flutter_rust_bridge::frb(ignore)]
pub fn remove_yubikey_from_vault(cred_id: &[u8], path: &Path) -> Result<(), String> {
    let sealed = read_vault(path)?;
    let new_sealed = crate::crypto::vault_crypto::remove_key_from_sealed(&sealed, cred_id)?;
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
    let plaintext = serialize_vault_body(body)?;
    crate::crypto::vault_crypto::reseal_vault_body(&mut sealed, vault_key_master, &plaintext)?;
    write_vault(&sealed, path)
}

/// Change the passphrase on a VERSION 4 multi-key vault.
///
/// Reads the vault from disk, verifies the old passphrase via `passphrase_blob`,
/// generates fresh PQ material for the new passphrase, re-encrypts `wrapping_key`
/// as the new `passphrase_blob`, and writes back.  All `key_blob`s and the vault
/// body are unchanged — any single registered key continues to work.
#[flutter_rust_bridge::frb(ignore)]
pub fn change_passphrase_with_keys(
    old_passphrase: &[u8],
    new_passphrase: &[u8],
    path: &Path,
) -> Result<(), String> {
    let sealed = read_vault(path)?;
    let new_sealed = crate::crypto::vault_crypto::change_vault_passphrase_with_keys(
        &sealed,
        old_passphrase,
        new_passphrase,
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

    #[test]
    fn create_login_entry_returns_correct_fields() {
        let entry = create_login_entry(
            String::from("Personal"),
            String::from("GitHub"),
            String::from("https://github.com"),
            String::from("rob"),
            String::from("hunter2"),
            None,
            vec![],
        );

        assert_eq!(entry.title, "GitHub");
        assert_eq!(entry.folder, "Personal");
        assert_eq!(entry.url, "https://github.com");
        assert_eq!(entry.username, "rob");
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
            value: String::from("rob@example.com"),
            hidden: false,
        };
        let entry = create_login_entry(
            String::from("Personal"),
            String::from("Example"),
            String::from("https://example.com"),
            String::from("rob"),
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
    fn create_note_entry_returns_correct_fields() {
        let entry = create_note_entry(
            String::from("Personal"),
            String::from("Shopping list"),
            String::from("Milk, eggs, bread"),
            vec![],
        );

        assert_eq!(entry.title, "Shopping list");
        assert_eq!(entry.content, "Milk, eggs, bread");
        assert_eq!(entry.folder, "Personal");
    }

    #[test]
    fn create_note_entry_generates_unique_ids() {
        let a = create_note_entry(
            String::from("Work"),
            String::from("Note A"),
            String::from("content a"),
            vec![],
        );
        let b = create_note_entry(
            String::from("Work"),
            String::from("Note B"),
            String::from("content b"),
            vec![],
        );
        assert_ne!(a.id, b.id);
    }

    #[test]
    fn create_note_entry_with_custom_fields() {
        let field = CustomFieldData {
            label: String::from("Source"),
            value: String::from("my own recipe"),
            hidden: false,
        };
        let entry = create_note_entry(
            String::from("Personal"),
            String::from("Shopping list"),
            String::from("Milk, eggs, bread"),
            vec![field],
        );

        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Source");
        assert!(!entry.custom_fields[0].hidden);
    }

    #[test]
    fn create_identity_entry_returns_correct_fields() {
        let entry = create_identity_entry(
            String::from("Personal"),
            String::from("Rob"),
            String::from("Smith"),
            String::from("rob@example.com"),
            Some(String::from("+41 79 123 45 67")),
            Some(String::from("123 Main St")),
        );

        assert_eq!(entry.first_name, "Rob");
        assert_eq!(entry.last_name, "Smith");
        assert_eq!(entry.email, "rob@example.com");
        assert!(entry.phone.is_some());
        assert!(entry.address.is_some());
        assert_eq!(entry.folder, "Personal");
    }

    #[test]
    fn create_identity_entry_optional_fields_can_be_absent() {
        let entry = create_identity_entry(
            String::from("Personal"),
            String::from("Rob"),
            String::from("Smith"),
            String::from("rob@example.com"),
            None,
            None,
        );

        assert!(entry.phone.is_none());
        assert!(entry.address.is_none());
    }

    #[test]
    fn create_card_entry_valid_number_succeeds() {
        let result = create_card_entry(
            String::from("Personal"),
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
        );

        assert!(result.is_ok());
        let entry = result.unwrap();
        assert_eq!(entry.cardholder_name, "Rob Smith");
        assert_eq!(entry.expiry, "12/28");
        assert_eq!(entry.folder, "Personal");
        assert_eq!(entry.status, "active");
        assert_eq!(entry.card_name, Some(String::from("Visa Platinum")));
    }

    #[test]
    fn create_card_entry_invalid_number_returns_error() {
        let result = create_card_entry(
            String::from("Personal"),
            None,
            String::from("active"),
            String::from("Rob Smith"),
            String::from("1234"), // too short
            String::from("12/28"),
            String::from("123"),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        );

        assert!(result.is_err());
    }

    #[test]
    fn create_file_entry_returns_correct_fields() {
        let payload = vec![0u8, 1u8, 2u8, 255u8];
        let entry = create_file_entry(
            String::from("Personal"),
            String::from("secret.pdf"),
            payload,
            Some(String::from("my secret doc")),
            vec![],
        );

        assert_eq!(entry.filename, "secret.pdf");
        assert_eq!(entry.data.len(), 4);
        assert_eq!(entry.data[3], 255u8);
        assert!(entry.notes.is_some());
        assert_eq!(entry.folder, "Personal");
    }

    #[test]
    fn create_file_entry_generates_unique_ids() {
        let a = create_file_entry(
            String::from("Work"),
            String::from("a.pdf"),
            vec![],
            None,
            vec![],
        );
        let b = create_file_entry(
            String::from("Work"),
            String::from("b.pdf"),
            vec![],
            None,
            vec![],
        );
        assert_ne!(a.id, b.id);
    }

    #[test]
    fn create_file_entry_with_custom_fields() {
        let field = CustomFieldData {
            label: String::from("Classification"),
            value: String::from("confidential"),
            hidden: true,
        };
        let entry = create_file_entry(
            String::from("Work"),
            String::from("report.pdf"),
            vec![],
            None,
            vec![field],
        );

        assert_eq!(entry.custom_fields.len(), 1);
        assert_eq!(entry.custom_fields[0].label, "Classification");
        assert!(entry.custom_fields[0].hidden);
    }

    #[test]
    fn create_custom_entry_returns_correct_fields() {
        let fields = vec![
            CustomFieldData {
                label: String::from("API Key"),
                value: String::from("sk-abc123"),
                hidden: true,
            },
            CustomFieldData {
                label: String::from("Region"),
                value: String::from("eu-west-1"),
                hidden: false,
            },
        ];
        let entry = create_custom_entry(
            String::from("Work"),
            String::from("AWS credentials"),
            fields,
        );

        assert_eq!(entry.title, "AWS credentials");
        assert_eq!(entry.fields.len(), 2);
        assert_eq!(entry.folder, "Work");
    }

    #[test]
    fn create_custom_entry_empty_fields_succeeds() {
        let entry = create_custom_entry(
            String::from("Personal"),
            String::from("Empty custom"),
            vec![],
        );

        assert_eq!(entry.title, "Empty custom");
        assert_eq!(entry.fields.len(), 0);
    }

    #[test]
    fn save_and_load_vault_roundtrip() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};
        use std::env::temp_dir;

        let mut path = temp_dir();
        path.push("gabbro_api_test.gabbro");

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
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
    fn get_entry_by_id_returns_correct_entry() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let entries = vec![
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from("id-001"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                },
                title: String::from("First note"),
                content: String::from("content one"),
                custom_fields: vec![],
                attachments: vec![],
            }),
            VaultEntry::Note(NoteEntry {
                meta: EntryMeta {
                    id: String::from("id-002"),
                    created_at: String::from("2025-01-01T00:00:00Z"),
                    updated_at: String::from("2025-01-01T00:00:00Z"),
                    folder: String::from("Personal"),
                },
                title: String::from("Second note"),
                content: String::from("content two"),
                custom_fields: vec![],
                attachments: vec![],
            }),
        ];

        let found = get_entry_by_id(&entries, "id-001").unwrap();
        match found {
            VaultEntry::Note(ref e) => assert_eq!(e.content, "content one"),
            _ => panic!("Expected Note variant"),
        }
    }

    #[test]
    fn get_entry_by_id_missing_returns_error() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
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

        assert!(get_entry_by_id(&entries, "does-not-exist").is_err());
    }

    #[test]
    fn update_entry_replaces_correct_entry() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let mut entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
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

    #[test]
    fn update_entry_missing_id_returns_error() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let mut entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
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
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("s3cr3t"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
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
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("rob"),
            password: String::from("correct horst battery staple"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.password, MASKED_VALUE);
                assert_eq!(e.username, "rob"); // non-sensitive field unchanged
            }
            _ => panic!("Expected Login variant"),
        }
    }

    #[test]
    fn list_entries_masked_hides_cvv() {
        use crate::vault::entry::{CardEntry, EntryMeta, VaultEntry};

        let entries = vec![VaultEntry::Card(CardEntry {
            meta: EntryMeta {
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            card_name: Some(String::from("Visa Platinum")),
            status: String::from("active"),
            cardholder_name: String::from("Rob Smith"),
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
                id: String::from("id-001"),
                created_at: String::from("2025-01-01T00:00:00Z"),
                updated_at: String::from("2025-01-01T00:00:00Z"),
                folder: String::from("Personal"),
            },
            title: String::from("Example"),
            url: String::from("https://example.com"),
            username: String::from("rob"),
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
            id: String::from("id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        let mut entries = vec![VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("old_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        })];

        let updated = VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("new_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
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
            id: String::from("id-001"),
            created_at: String::from("2025-01-01T00:00:00Z"),
            updated_at: String::from("2025-01-01T00:00:00Z"),
            folder: String::from("Personal"),
        };
        let mut entries = vec![VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("old_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        })];

        let updated = VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("new_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
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
            title: String::from("GitHub"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("same_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: Some(existing_prev),
        })];

        let updated = VaultEntry::Login(LoginEntry {
            meta: meta.clone(),
            title: String::from("GitHub — updated title"),
            url: String::from("https://github.com"),
            username: String::from("rob"),
            password: String::from("same_password"),
            notes: None,
            custom_fields: vec![],
            attachments: vec![],
            previous_password: None,
        });

        update_entry(&mut entries, updated, Some(30)).unwrap();

        match &entries[0] {
            VaultEntry::Login(e) => {
                assert_eq!(e.title, "GitHub — updated title");
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
    fn list_entries_masked_does_not_alter_note() {
        use crate::vault::entry::{EntryMeta, NoteEntry, VaultEntry};

        let entries = vec![VaultEntry::Note(NoteEntry {
            meta: EntryMeta {
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
                    value: String::from("Rob"),
                    hidden: false,
                },
            ],
        })];

        let result = list_entries(&entries, true);
        match &result[0] {
            VaultEntry::File(e) => {
                assert_eq!(e.custom_fields[0].value, MASKED_VALUE);
                assert_eq!(e.custom_fields[1].value, "Rob");
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
}
