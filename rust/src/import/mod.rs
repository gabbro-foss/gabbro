pub mod bitwarden;
pub mod csv;
pub mod dashlane;
pub mod enpass;
pub mod google_pm;

// Import size caps (S-02 / S-03). A malicious export file a victim is sent could
// otherwise drive an unbounded allocation (memory-exhaustion DoS) at parse time.
// These bound it. The Flutter import screen mirrors these values for its pre-read
// check and the on-screen announcement — keep `lib/screens/import_screen.dart` in
// sync if they change.

/// Max accepted size of a text-format export (CSV, Bitwarden, Dashlane, Google
/// Password Manager). Bitwarden's JSON export excludes attachment bytes and the
/// others are CSV, so these are text-only — a 200-entry vault is well under 1 MB.
pub const TEXT_IMPORT_MAX_BYTES: usize = 25 * 1024 * 1024;

/// Max accepted size of an Enpass JSON export, which embeds attachments inline as
/// base64. Larger than the text cap so attachment-bearing vaults still import.
pub const ENPASS_IMPORT_MAX_BYTES: usize = 128 * 1024 * 1024;

/// Max decoded size of a single Enpass attachment. Bounds peak memory and stops
/// one absurd attachment dominating an otherwise-valid import.
pub const ENPASS_ATTACHMENT_MAX_BYTES: usize = 25 * 1024 * 1024;

#[cfg(test)]
mod fuzz_tests;
