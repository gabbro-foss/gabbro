# Gabbro Architecture

## Project Overview
A post-quantum password manager built with security as core DNA.
Named after the intrusive igneous rock — hard, stable, enduring.
Cross-platform: Linux (Arch, Mint), Android, later iOS/Windows/macOS.
FOSS, GPL-3.0-only licensed, with potential Yubico partnership.

## Tech Stack
- **Frontend:** Flutter (Dart)
- **Backend/Crypto:** Rust
- **Bridge:** flutter_rust_bridge v2 (FFI)
- **Analogy:** Flutter:Rust :: Frontend:Backend

## Core Principle
> If it touches a secret, it lives in Rust. Everything else lives in Flutter.
> Secrets never cross the Flutter/Rust bridge in plaintext.

## Project Structure
The project is scaffolded by `flutter_rust_bridge_codegen create gabbro` and
follows its generated layout. The `rust/` folder name matches the generated
default (not `rust_core/` as originally planned).

```
gabbro/
├── lib/                        # Flutter app entry point and Dart source
│   ├── main.dart
│   ├── screens/                # Hand-written UI screens
│   │   ├── unlock_screen.dart        # Passphrase entry screen
│   │   ├── export_screen.dart        # Export vault — writes .gabbro + .gabbro.sha256
│   │   ├── import_screen.dart        # Import from Enpass / Bitwarden / CSV
│   │   ├── csv_mapping_screen.dart   # CSV column-mapping UI
│   │   ├── change_passphrase_screen.dart  # Change master passphrase
│   │   ├── about_screen.dart              # About screen — version, links, licences
│   │   ├── appearance_screen.dart         # Appearance — theme, text size
│   │   ├── security_screen.dart           # Security — foreground and background lock timeouts
│   │   ├── review_changes_screen.dart     # Safe edit — diff view before saving
│   │   ├── password_history_screen.dart   # Safe edit — previous password with revert
│   │   ├── alphabet_index_bar.dart        # Alphabet index bar — height-adaptive, windowed with chevrons
│   │   └── tablet_vault_layout.dart       # Two-pane layout for ≥600dp — NavigationRail + list pane + detail pane
│   ├── widgets/                      # Reusable UI components
│   │   ├── path_field.dart           # Native file picker field (open + save modes)
│   │   └── segmented_row.dart        # Shared SegmentedRow<T> and SectionHeader widgets
│   └── src/
│       └── rust/               # Auto-generated bridge code (do not edit)
│           ├── api/
│           │   ├── simple.dart
│           │   ├── password_generator.dart
│           │   ├── passphrase_generator.dart
│           │   ├── vault.dart
│           │   ├── vault_bridge.dart
│           │   ├── vault_bridge.freezed.dart
│           │   └── entropy.dart
│           ├── frb_generated.dart
│           ├── frb_generated.io.dart
│           └── frb_generated.web.dart
├── rust/                       # Rust crate (all crypto and secrets live here)
│   ├── Cargo.toml
│   ├── Cargo.lock
│   ├── assets/                 # Embedded wordlists (compile-time inclusion)
│   │   ├── wordlist_en.txt     # EFF large wordlist — 7776 words
│   │   ├── wordlist_fr.txt     # French Diceware — 7776 words
│   │   ├── wordlist_de.txt     # German Diceware — 7776 words
│   │   ├── wordlist_es.txt     # Spanish Diceware — 8192 words
│   │   └── wordlist_it.txt     # Italian Diceware — 8192 words
│   └── src/
│       ├── api/                # Bridge API surface exposed to Flutter
│       │   ├── mod.rs
│       │   ├── simple.rs
│       │   ├── password_generator.rs
│       │   ├── passphrase_generator.rs
│       │   ├── vault.rs        # Vault entry API — DTOs and create_* functions
│       │   ├── vault_bridge.rs # Bridge wrappers — save/load vault
│       │   ├── import.rs       # Import bridge — CSV, Enpass, Bitwarden
│       │   └── entropy.rs
│       ├── crypto/             # Internal crypto stack (not bridge-exposed)
│       │   ├── mod.rs
│       │   ├── kdf.rs          # Argon2id KDF and Argon2idParams struct
│       │   ├── keypair.rs      # X25519 keypair derivation
│       │   ├── ml_kem.rs       # ML-KEM-1024 keypair derivation
│       │   ├── hkdf.rs         # HKDF-SHA256 combiner
│       │   ├── aes_gcm.rs      # AES-256-GCM encrypt/decrypt
│       │   └── vault_crypto.rs # seal_vault() and open_vault()
│       ├── vault/              # Internal domain model (not bridge-exposed)
│       │   ├── mod.rs
│       │   ├── entry.rs        # All 6 entry types and EntryMeta
│       │   ├── file_format.rs  # SealedVault — .gabbro binary format
│       │   ├── io.rs           # Vault file I/O — write/read .gabbro files
│       └── serialization.rs# Entry serialization — Vec<VaultEntry> ↔ JSON bytes
│       ├── import/             # Importers for third-party password managers
│       │   ├── mod.rs
│       │   ├── enpass.rs       # Enpass JSON importer
│       │   └── csv.rs          # Generic CSV importer
│       ├── bin/
│       │   └── bench_kdf.rs    # Argon2id parameter audit tool
│       ├── frb_generated.rs    # Auto-generated bridge code (do not edit)
│       └── lib.rs
├── rust_builder/               # Cargokit build integration (do not edit)
├── android/                    # Android platform files
├── ios/                        # iOS platform files (v2 target)
├── linux/                      # Linux platform files (v1 target)
├── macos/                      # macOS platform files (v2 target)
├── windows/                    # Windows platform files (v2 target)
├── integration_test/           # Flutter integration tests
├── test/                       # Flutter unit/widget tests
├── test_driver/                # Integration test driver
├── docs/                       # Project documentation
│   ├── ARCHITECTURE.md
│   ├── LEARNINGS.md
│   └── decisions/
│       ├── ADR-001-rust-flutter-stack.md
│       ├── ADR-002-export-integrity-hash.md
│       ├── ADR-003-colourblind-password-display.md
│       ├── ADR-004-licence.md
│       ├── ADR-005-pq-authentication-signatures.md
│       └── ADR-006-encryption-implementation.md
├── chat_info/                  # Development session notes and ASCII wireframes
│   └── ascii_art/              # (git-ignored — not versioned)
├── flutter_rust_bridge.yaml    # Bridge configuration
├── pubspec.yaml                # Flutter dependencies
├── pubspec.lock                # Pinned dependency versions
├── analysis_options.yaml       # Dart linting rules
├── .gitignore                  # Git ignore rules (generated + project-specific)
├── LICENSE                     # GPL-3.0-only licence text
└── README.md
```

Note: a `tests/` folder for cross-layer integration tests is not generated
by the scaffold — it will be created manually when cross-layer testing begins.

## Vault File Format
- Extension: `.gabbro`
- Structure:
  - **Header (plaintext):** magic bytes, version, argon2id params,
    argon2id salt, HKDF salt, nonce, ML-KEM ciphertext, X25519 ephemeral public key
  - **Body (encrypted):** all vault entries, JSON serialized,
    encrypted with AES-256-GCM
- Serialization: hand-written binary format with fixed-size fields and
  a length-prefixed body. Implemented in `rust/src/vault/file_format.rs`.
- Self-contained: all decryption parameters travel with the file
- Auth tag detects any tampering

## Encryption Stack (Layer 1 - At Rest)
```
passphrase + random_salt
→ Argon2id (KDF)
→ 256-bit master key
→ ML-KEM (PQC key encapsulation)
→ AES-256-GCM (vault encryption)
→ encrypted vault body + auth tag
```

- **Argon2id:** memory-hard KDF, deliberately slow to resist brute force
- **AES-256-GCM:** fast symmetric encryption + tamper detection
- **ML-KEM:** post-quantum key encapsulation (NIST standard)
- **Hybrid approach:** classical + PQC = belt and suspenders

- **Status:** fully implemented in `rust/src/crypto/`:
  - `kdf.rs` — Argon2id KDF, `Argon2idParams` struct (m=65536, t=25, p=4)
  - `keypair.rs` — X25519 keypair derivation from KDF output
  - `ml_kem.rs` — ML-KEM-1024 keypair derivation from KDF output
  - `hkdf.rs` — HKDF-SHA256 combiner, domain-separated with "gabbro-hybrid-kex-v1"
  - `aes_gcm.rs` — AES-256-GCM encrypt/decrypt with random nonce per operation
  - `vault_crypto.rs` — `seal_vault()` and `open_vault()` orchestrating the full stack
  - `bench_kdf.rs` — repeatable Argon2id parameter audit tool
  - All decisions documented in ADR-006.

## Authentication Stack (Layer 2 - App Access)
- Mandatory FIDO2/WebAuthn hardware key (YubiKey)
- v1 signature algorithm: Ed25519 (hardware constraint — YubiKey 5
  series does not yet support ML-DSA). Target: ML-DSA-44 once
  Yubico ships PQ-capable hardware. See ADR-005.
- Minimum 2 keys required (primary + backup), maximum 4
- Biometric unlock available (replaces passphrase entry only,
  never replaces YubiKey tap)
- Full passphrase always required after cold boot or reinstall
- Auto-lock: 30 seconds default (user configurable)
- Lock triggers: inactivity, app backgrounded, screen off
- Failed attempts:
  - Attempts 1-3: normal retry
  - Attempt 4: warning "2 attempts remaining"
  - Attempt 5: vault locked, requires full passphrase + YubiKey
  - Attempt 10: vault wiped from device

## Vault Contents
Each entry is an instance of a typed class:
- **Types:** Login, Note, Identity, Card, File, Custom
- **Status:** all 6 entry types fully implemented in the domain model
  (`rust/src/vault/entry.rs`) and bridged via DTOs and API functions
  (`rust/src/api/vault.rs`). See ## Testing Strategy → Test Counts.
- **Core fields:** type-specific
- **Common fields:** UUID, created, modified, folder, tags, favourite
- **Login entry:** URL, username, password (hidden by default,
  show/hide toggle), custom fields, notes
- **Display label:** the `Login` entry type is displayed to the user as
  "Password" in the UI — the internal Rust name is `Login` (accurate domain
  term), but "Password" is used in Flutter to avoid implying autofill/browser
  integration that does not yet exist.
- **Attachments:** files and images supported
- **No TOTP** — YubiKey covers 2FA; keeping password manager
  and 2FA separate is more secure

## Organisation & UX
- Folders with defaults: Personal, Work, Social (renamable/deletable)
- Custom tags
- Favourites
- Configurable sorting
- Fast fuzzy search: vault-wide or by field (Kvaesito-inspired)
- Dark mode + light mode (system default, user overridable)
- Screenshot prevention + app switcher blur

## Password Generator
- **Status:** classic password mode fully implemented in Rust
  (`rust/src/api/password_generator.rs`). Passphrase mode fully
  implemented in Rust (`rust/src/api/passphrase_generator.rs`).
  Both bridged to Flutter, Flutter build clean.
  See ## Testing Strategy → Test Counts.
- Two modes: classic password and wordlist-based passphrase
- **Passphrase mode:**
  - 5 languages supported: English, French, German, Spanish, Italian
  - Wordlists embedded at compile time via `include_str!`
  - EN, FR, DE: 7776 words (~12.92 bits entropy/word)
  - ES, IT: 8192 words (exactly 13.00 bits entropy/word)
  - `PassphraseConfig`: word_count (min 4), separator, capitalise,
    append_number, language
  - `Language` enum: English, French, German, Spanish, Italian
  - Language enum is internal/bridge only — display strings handled in Flutter
  - Entropy calculated from actual wordlist size per language
- Colour coded display with symbol markers — character types are
  distinguished by **both colour and symbol** (never colour alone),
  ensuring accessibility for colour-blind users — see ADR-003
- Default palette is colour-blind-friendly (avoids pure red/green
  confusion); user-overridable via colour picker in settings
- Hidden by default, show/hide toggle
- Entropy display (bits)
- Exclude ambiguous characters option (0, O, l, 1, I)
- All generation happens in Rust
- Accessible from main screen and inline within entry editor
- Remembers user's last settings
- Clipboard auto-clear after 60 seconds
- **Length policy:** generator minimum 32 characters, maximum 256 characters,
  default 32. No upper limit enforced for manually typed passwords — user
  agency is respected; the entropy estimator provides feedback instead of
  blocking. Passphrase generator: minimum 4 words (enforced), maximum 20
  words (enforced). Both limits are validated in Rust and return `Err` if
  exceeded.

## Appearance & Settings

- **Status:** implemented. `lib/settings.dart` + `lib/screens/appearance_screen.dart`.
  See ## Testing Strategy → Test Counts.
- **Settings file:** `~/.config/gabbro/settings.jsonc` on Linux,
  `~/Library/Application Support/gabbro/settings.jsonc` on macOS,
  `<app support dir>/settings.jsonc` on Android.
- **Format:** JSONC — standard JSON with `//` and `#` comment lines stripped
  before parsing. All options documented inline. Invalid values fall back to
  defaults silently. Human-editable by design — follows the Arch/qtile
  convention of a config file the user can read and modify directly.
- **`AppSettings` class:** immutable, `const`-constructible. Fields:
  `theme` (`ThemeChoice`: system/light/dark), `textSize` (`TextSizeChoice`:
  small/regular/large/extraLarge), `highContrast` (bool, placeholder).
  `load()` is async (file I/O); `save()` writes the full JSONC with comments.
  `copyWith()` for immutable updates. `fromJson()`/`toJson()` for
  serialisation. Comment stripping exposed via `stripCommentsForTest()` for
  unit testing.
- **Seed colour:** olivine green `#5C7A3E` (`0xFF5C7A3E`). Validated
  against WCAG 1.4.3 (contrast ratio 4.59:1 against white — passes AA)
  and ADR-003 (CVD simulation: shifts to muted gold under deuteranomaly,
  acceptable because colour is never used as the sole information carrier).
  Applied via `ColorScheme.fromSeed` in both `_lightTheme` and `_darkTheme`
  in `main.dart`.
- **Theme:** `GabbroApp` (in `main.dart`) was promoted from `StatelessWidget`
  to `StatefulWidget` to hold `AppSettings` at the app root. `ThemeMode` and
  `TextScaler` are derived from settings and passed down via `MediaQuery` and
  `MaterialApp`. Descendant screens update settings via
  `GabbroApp.of(context).updateSettings(...)` — changes take effect
  immediately app-wide without restart. `GabbroAppState` is a public abstract
  class exposing `settings` and `updateSettings()` — `_GabbroAppState`
  implements it, resolving the `library_private_types_in_public_api` lint.
- **Text scaling:** `TextScaler.linear()` factors: small=0.85, regular=1.0,
  large=1.15, extraLarge=1.3, xxLarge=1.5. Applied via a `MediaQuery` wrapper
  above `MaterialApp` so all text in the app scales uniformly.
- **Appearance screen:** two segmented button rows (theme, text size) plus
  a live preview box showing the current text scale. High-contrast toggle
  enabled — works in both light and dark mode.
- **High-contrast themes:** `gabbroLightTheme({required bool highContrast})`
  and `gabbroDarkTheme({required bool highContrast})` are top-level functions
  in `main.dart` (extracted from `_GabbroAppState` for testability). When
  `highContrast: true`: light variant uses black/white with error `#7A0000`
  (8.2:1 on white); dark variant uses white/black with error `#FF9999`
  (7.3:1 on black). Both pass WCAG 1.4.3 (AA, 4.5:1) and WCAG 1.4.6 (AAA,
  7:1). ADR-003 compliant — error colours remain distinguishable under CVD
  simulation. Verified on Samsung S23 (Android 16). 8 unit tests in
  `test/theme_test.dart`.
- **Accessibility shortcut:** `OutlinedButton.icon` (icon: `Icons.accessibility_new`,
  label: "Accessibility") positioned top-right on `OnboardingScreen` only
  (removed from `UnlockScreen` — settings persist after onboarding so the
  shortcut is not needed there). Toggles `highContrast: true` +
  `textSize: xxLarge` together in one tap — ensures vision-impaired users
  can access accessibility settings before reaching the main UI. Icon is
  highlighted in primary colour when active. Button fades out via
  `AnimatedOpacity` when the keyboard is open to avoid overlapping content.
- **`UnlockScreen` autofocus:** `autofocus: true` added to the passphrase
  `TextField` so the keyboard/cursor is ready immediately on launch.
- **Entry detail timestamps:** `created_at` and `updated_at` are shown
  at the bottom of all six entry type detail views. Rendered by
  `_timestampsRow()` in `entry_detail_screen.dart`. Timestamps are
  display-only — no copy button (metadata, not a secret). Formatting
  handled by `formatTimestamp()` (package-private top-level function):
  parses ISO 8601 UTC, converts to local time, renders as
  `"DD Mon YYYY, HH:MM"`. Falls back to `"Unknown"` for empty or
  unparseable input. Month abbreviations are currently hard-coded in
  English — see i18n backlog item for the migration path.

- **Entry detail — URL open and copy to clipboard:** All copyable fields
  in `EntryDetailScreen` show a copy icon (`Icons.copy_outlined`) that
  copies the plaintext value and shows a `SnackBar` confirmation.
  Clipboard auto-clears after the duration configured in
  `ClipboardClearTimeout` (read from `AppSettings`). Login entries
  additionally show a launch icon (`Icons.open_in_browser_outlined`)
  next to the URL field. Tapping uses a two-step tap-to-dialog →
  "Open in browser" pattern (same as `AboutScreen`) via `url_launcher`
  (`LaunchMode.externalApplication`). `onLaunchUrl` is injectable for
  testability, defaulting to `_defaultLaunchUrl`. Sensitive fields
  (password, CVV, PIN) copy the real value — the user explicitly
  requested it.

- **URL launch on non-Login entries — decided against:** Browser launch
  is intentionally restricted to `LoginEntry.url` only. Adding URL
  detection to custom fields on other entry types would require heuristics
  (scheme inference, string pattern matching) that introduce maintenance
  debt and a potential social engineering surface — a malicious import
  could populate a custom field with a URL pointing to a harmful site.
  Gabbro does not open URLs it did not explicitly receive as a typed URL
  field. Decision is final; do not reopen.

- **Vault deletion from UI:** Menu → Delete vault (previously greyed out)
  triggers a two-step confirmation: (1) warning dialog — Cancel / Continue;
  (2) user must type `DELETE` exactly — Confirm button disabled until matched.
  On confirm: calls `delete_whole_vault` bridge (drops session, wipes `.gabbro`
  file), then `pushAndRemoveUntil` to `OnboardingScreen` clearing the stack.
  `OnboardingScreen` accepts an optional `postDeletionMessage` — rendered as
  an accent-coloured info banner with `Icons.info_outline`. Vault path reused
  as default for the new vault; passphrase guidance shown below the location
  label. `deleteVault` is injectable on `VaultListScreen` for testability.
  Tests in `test/vault_list_delete_vault_test.dart`. Verified on Samsung S23
  (Android 16).

## Auto-lock

- **Foreground inactivity timer:** resets on any user interaction via a
  `GestureDetector` wrapping the entire `MaterialApp`. Fires after the
  configured duration and calls `_lock()`. Managed in `_GabbroAppState`.
- **Background timer:** starts when `AppLifecycleState.paused` is received,
  cancelled if the app resumes before it fires. Lock fires immediately on
  `AppLifecycleState.detached` (app killed).
- **Lock action:** calls `lockVault()` (Rust bridge), then
  `pushAndRemoveUntil` to `UnlockScreen`, clearing the navigation stack.
- **Never option:** setting either timeout to `never` cancels the
  corresponding timer entirely — no lock fires.
- **Settings:** both timeouts are fields on `AppSettings`, persisted to
  `settings.jsonc`. Configurable via Settings → Security in the app menu.
  - `ForegroundLockTimeout`: `thirtySeconds` (default) / `oneMinute` / `fiveMinutes` / `never`
  - `BackgroundLockTimeout`: `fiveMinutes` (default) / `oneMinute` / `fifteenMinutes` / `never`
- **Navigation:** `_GabbroAppState` holds a `GlobalKey<NavigatorState>`
  passed to `MaterialApp` so the lock action can navigate from outside
  the widget tree.
- **Verified on hardware:** Samsung S23 (Android 16) — foreground inactivity,
  background timeout, app kill, resume within timeout, settings persistence,
  interaction reset, and Never option all confirmed.

## Safe Entry Editing

- **Status:** full stack implemented. Verified on Samsung S23 (Android 16).
  See ## Testing Strategy → Test Counts.

- **`PreviousSecret` struct** (`rust/src/vault/entry.rs`): holds `value`,
  `saved_at`, and `expires_at: Option<String>`. Derives `Zeroize` +
  `ZeroizeOnDrop`. Used by `LoginEntry.previous_password`,
  `CardEntry.previous_cvv`, and `CardEntry.previous_pin`.

- **`update_entry`** (`rust/src/api/vault.rs`): before overwriting, snapshots
  the old sensitive value into `previous_*` with `saved_at = now` and
  `expires_at = now + expiry_days` (or `None` for keep-forever). If the
  sensitive field is unchanged, existing history is preserved. `expiry_days:
  Option<u32>` flows from Flutter settings through `session_update_entry` →
  `update_entry`. Date arithmetic is std-only — no chrono dependency.

- **`PreviousSecretData` DTO** (`rust/src/api/vault.rs`): bridge-facing struct
  with `value` (always masked to `"********"` at the bridge boundary),
  `saved_at`, `expires_at`. Present on `LoginEntryData.previous_password`,
  `CardEntryData.previous_cvv`, `CardEntryData.previous_pin`.

- **`PasswordHistoryExpiry` setting** (`lib/settings.dart`): enum with
  `sevenDays` / `thirtyDays` (default) / `ninetyDays` / `keepForever`.
  Persisted to `settings.jsonc`. Surfaced in Settings → Security as a
  `SegmentedRow`. Converted to `int?` (days) in `CreateEntryScreen._expiryDays()`
  before passing to the bridge.

- **Edit flow** (`lib/screens/create_entry_screen.dart`): in edit mode, "Save"
  button is replaced by "Review →" in the app bar. Tapping it validates the
  form, calls `_buildUpdated()` to construct the updated DTO, calls
  `_hasChanges()` to diff original vs updated (uses `listEquals` for custom
  field lists), and pushes `ReviewChangesScreen`. If no changes, shows a
  snackbar and stays. `onUpdateEntry` dependency removed — `ReviewChangesScreen`
  owns the save call directly.

- **`ReviewChangesScreen`** (`lib/screens/review_changes_screen.dart`): shows
  sensitive changes (password/CVV/PIN) in a warning row with show/hide toggle,
  and non-sensitive field diffs in a before→after grid. Only changed fields
  shown. Save calls `updateEntry(entry, expiryDays)` then re-fetches the entry
  via `getEntry(id)` to get the Rust-stamped `updated_at` and populated
  `previous_password` before popping. Verified on Samsung S23 (Android 16).
  See ## Testing Strategy → Test Counts.
  **Bug fixed:** `Custom` and `Identity` entry diffs previously omitted newly
  added fields (fields present in the updated entry but absent in the original).
  Fixed: both branches now iterate to `max(original.length, updated.length)`,
  diffing new fields against an empty string. Verified on Linux (Lenovo tablet).

- **Login notes field — bug found and fixed:** `LoginEntryData.notes` was
  never wired into `CreateEntryScreen`. No controller, no form widget,
  `_buildUpdated()` hardcoded `notes: null` (silently wiping existing notes
  on every edit save), and `_saveCreate()` omitted `notes` entirely (new
  entries never retained notes). Fix: added `_loginNotesController` and
  `_loginNotesFocus`; initialised from `field0.notes ?? ''` in edit mode;
  added optional notes `TextFormField` at the bottom of `_loginFields()`;
  fixed both `_buildUpdated()` and `_saveCreate()` to pass the controller
  value. `_optionalTextField()` extended with an optional `focusNode`
  parameter. 4 tests added to `test/create_entry_screen_test.dart`.
  Verified on Samsung S23 (Android 16): edit preserves notes, clearing notes
  shows diff, adding notes shows diff, new entry retains notes, no-change
  guard fires correctly.

- **`PasswordHistoryScreen`** (`lib/screens/password_history_screen.dart`):
  shows current password (masked, toggleable) and previous password (masked,
  toggleable) with `saved_at` / `expires_at` metadata. "Revert" and "Delete
  previous entry" are stub snackbars pending bridge implementation. Entry point:
  "Password history →" `ListTile` in `EntryDetailScreen._loginView`. 7 widget
  tests. Known UI issue: "Revert" is a `TextButton` inline inside the previous
  password row; "Delete previous entry" is a standalone `OutlinedButton` below
  — inconsistent. Fix: promote "Revert" to a standalone button matching
  "Delete previous entry".

## Vault Domain Model
- **Status:** all 6 entry types implemented in Rust
  (`rust/src/vault/entry.rs`). See ## Testing Strategy → Test Counts.
- Lives in `rust/src/vault/` — internal module, not exposed to Flutter
  directly. Flutter will call API functions that construct these types;
  it never builds them directly.
- **EntryMeta:** shared metadata struct composed into every entry type —
  id, timestamps, folder, tags, favourite flag.
- **Entry types:** Login, Note, Identity, Card, File, Custom.
- **CustomField:** reusable key/value struct used by LoginEntry (Vec) and
  CustomEntry (HashMap).
- **CardEntry::new():** only entry type with a validated constructor —
  enforces card number digit count (12–19), non-empty cardholder name,
  non-empty expiry, and non-empty CVV. All failing validations are
  collected and returned as a single semicolon-joined error string so the
  caller sees every problem at once, not just the first. Fields added for
  Enpass import gap closure: `pin`, `bank_name`, `transaction_password`
  (all `Option<String>`). Other types use struct literals; validation for
  those will live in the API layer when it is built.
- **EntryAttachment** — implemented in `rust/src/vault/entry.rs`.
  Derives `Zeroize` and `ZeroizeOnDrop` — attachment data may be sensitive
  (passport scans, etc.). Fields: `uuid`, `name`, `kind` (MIME type), `data`
  (`Vec<u8>`, decoded from base64 on import). `Vec<EntryAttachment>` is present
  on `LoginEntry`, `NoteEntry`, `IdentityEntry`, `CardEntry`, and `CustomEntry`.
  Not on `FileEntry` — a file entry IS an attachment; adding attachments to it
  would be recursive. Bridge DTO (`EntryAttachmentData`) and Flutter UI deferred
  to a separate session after the importer TDD rewrite is complete.
- **Design principle:** invalid state unrepresentable — if a value cannot
  exist in a valid domain, the type system or constructor prevents it from
  being created at all.

## Vault API Layer
- **Status:** all 6 entry types fully implemented in `rust/src/api/vault.rs`.
  See ## Testing Strategy → Test Counts.
- Lives in `rust/src/api/vault.rs` — the bridge boundary between Flutter and
  the internal vault domain model.
- **Pattern:** each entry type gets a bridge-facing DTO (Data Transfer Object —
  `LoginEntryData`, `NoteEntryData`, etc.) using only bridge-friendly types
  (`String`, `Vec`, `bool`, `Option<String>`), and a `create_*` function that
  generates a UUID, timestamps, builds the internal type, then converts to
  the DTO.
- **UUID generation:** uses the `uuid` crate with the `v4` feature (random UUIDs).
- **Timestamps:** generated in Rust using `std::time` only — no `chrono`
  dependency. Format: ISO 8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`).
- **DTO pattern:** internal domain types never cross the bridge directly.
  Flutter calls `create_login_entry(...)` and receives a `LoginEntryData` —
  it never constructs or holds a `LoginEntry`.
- **Full API surface (all implemented):**
  - `create_*()` — one per entry type; generates UUID and timestamps
  - `get_entry_by_id()` — fetch a single entry by UUID
  - `update_entry()` — replace an entry by UUID; stamps `updated_at`
  - `delete_entry()` — remove a single entry by UUID
  - `delete_whole_vault()` — wipe the `.gabbro` file from disk
  - `list_entries()` — return all entries, optionally masked
  - `save_vault()` — serialize → encrypt → write to disk
  - `load_vault()` — read from disk → decrypt → deserialize
  - `change_passphrase()` — re-seal under a new passphrase
  - `export_vault()` — write `.gabbro` + `.gabbro.sha256` pair
- **Password masking:** `list_entries(masked: true)` replaces password, CVV,
  and hidden custom field values with a fixed 8-character placeholder
  (`"********"`). Length is deliberately decoupled from the actual value
  to prevent shoulder-surfing attacks based on character count.

## Vault Session Model
The bridge layer uses a **Rust-owned session model**: Rust holds the
decrypted vault in memory between bridge calls rather than passing the
whole vault back and forth across the bridge on every operation.

### Rationale
The alternative — Flutter owning the full decrypted vault in its memory —
was explicitly considered and rejected for three reasons:

1. **Minimal plaintext exposure.** Dart is a garbage-collected language
   running on the Dart VM. There is no mechanism to zero memory in Dart:
   the VM controls object lifetimes, may intern strings, and makes no
   zeroing guarantee before reuse. Any secret that crosses the bridge into
   Dart is, from a strict security standpoint, uncontrolled. The session
   model minimises what crosses the bridge: summaries for list views, one
   full entry on demand, never the whole vault.

2. **Natural auto-lock.** When the vault locks, Rust drops the session
   state. Future `zeroize` integration (see Bikeshed) will ensure the
   memory is actively cleared at that point. Flutter's lock event simply
   calls `lock_vault()` — it does not need to zero its own copy because
   it never held one.

3. **Lazy loading.** A vault with hundreds of entries and file attachments
   should not be loaded across the bridge in full on unlock. The session
   model makes lazy loading the natural default: Flutter requests summaries
   to display a list, then fetches one full entry when the user taps it.

### Memory security honesty
Zeroing memory is not a guarantee of non-recovery. Swap, hibernation, cold
boot attacks, and OS memory snapshots can all preserve data after an
in-process zero. `zeroize` narrows the time window during which secrets
are recoverable in RAM — it does not eliminate the risk. The practical
threat for Gabbro's users (device seizure while unlocked, memory forensics
on a running device) is meaningfully reduced by a short window; it is not
eliminated. Full-disk encryption (FDE) is a stated prerequisite for the
full security model — on Android this is enforced by the OS; on Linux it
is the user's responsibility (dm-crypt/LUKS). Gabbro documents this
dependency rather than papering over it.

Dart cannot zeroize. This is a known, accepted limitation shared by every
password manager built on a managed runtime. The session model limits
Dart's exposure by design; it cannot eliminate it.

### Session API (bridge-facing, in `vault_bridge.rs`)
```
unlock_vault(passphrase, path)  → Result<(), String>
  Runs Argon2id + decryption, stores Vec<VaultEntry> in Mutex.
  Async — Flutter awaits it (~667ms on target hardware).

lock_vault()                    → ()
  Drops (and eventually zeroizes) the session state.
  Sync — instant.

list_entry_summaries()          → Result<Vec<EntrySummaryData>, String>
  Returns lightweight DTOs: id, entry type, title/name, folder, tags,
  favourite. No passwords, no file data, no CVVs.
  Sync — reads from in-memory session, no I/O.

get_entry(id)                   → Result<VaultEntryData, String>
  Returns one full entry DTO by UUID.
  Sync — reads from in-memory session, no I/O.

create_entry(entry)             → Result<EntrySummaryData, String>
  Adds a new entry to the session and persists the vault to disk.
  Async — triggers a full vault save (Argon2id + encryption).

update_entry(entry)             → Result<(), String>
  Replaces an existing entry by UUID, stamps updated_at, persists.
  Async — triggers a full vault save.

delete_entry(id)                → Result<(), String>
  Removes an entry by UUID, persists.
  Async — triggers a full vault save.

delete_whole_vault()            → Result<(), String>
  Drops session state, wipes .gabbro file from disk.
  Async — filesystem operation.

change_passphrase(old, new)     → Result<(), String>
  Re-seals the vault under a new passphrase. Session remains live.
  Async — triggers a full vault save under new key.

export_vault(path)              → Result<(), String>
  Writes .gabbro + .gabbro.sha256 from current session state.
  Async — filesystem operation.
```

### Implementation plan
- Add `rust/src/vault/session.rs` — `VaultSession` struct wrapping
  `Mutex<Option<(Vec<VaultEntry>, PathBuf)>>` in a `once_cell` static.
  The path is stored alongside the entries so bridge functions don't
  require it on every call after unlock.
- Add `EntrySummaryData` DTO to `vault_bridge.rs` — lightweight struct
  with id, entry_type (String), title, folder, tags, favourite.
- Rewrite `vault_bridge.rs` — replace the stateless `save_vault_to_disk`
  / `load_vault_from_disk` pair with the session API above.
- All internal `vault.rs` functions remain unchanged — they become the
  implementation called by the session layer.
- The existing `vault_bridge.rs` tests are superseded by new session
  tests in the same file.

## Vault Storage & Sync
- v1: local path only, chosen during onboarding
- Sync is user's responsibility via export/import
- Export always encrypted, never plaintext
- Export produces two files: `<n>.gabbro` (encrypted vault) and
  `<n>.gabbro.sha256` (detached SHA-256 hash of the whole file)
- The detached hash allows integrity verification before decryption,
  following the familiar Linux ISO convention users already know
- Note: AES-256-GCM's auth tag already guarantees tamper-detection
  during decryption; the detached hash is a UX complement, not a
  cryptographic necessity — see ADR-002
- v2 (future): built-in sync option

## Backup Strategy
- 3-2-1 rule enforced via onboarding and periodic reminders:
  3 copies, 2 different media, 1 offsite
- Vault wipe after 10 failed attempts makes backup critical
- Development repo backup: local NAS sync + Synology HyperBackup
  offsite — project already respects the 3-2-1+1 paradigm

## Testing Strategy
- Rust: native test framework, unit + integration tests
- Flutter: unit and widget tests in `test/`, integration tests in `integration_test/`
- Cross-layer: integration tests in `tests/`
- TDD from day one — untested code is broken code

### Test Counts
> Single authoritative location. Update here only; do not repeat counts
> elsewhere in this document.

| Suite | Passing | Skipped / Ignored |
|-------|---------|-------------------|
| Rust (`cargo test -q`) | 193 | 1 ignored |
| Flutter (`flutter test`) | 183 | 1 skipped |

## Platforms

- v1: Linux (Arch + Mint/deb), Android (F-Droid)
- v2 (future): Windows, macOS, iOS

## Android Toolchain Setup (Arch Linux)

### Approach
Android Studio is used as a self-contained toolchain manager. The manual
approach (individual AUR packages for `android-sdk`, `android-ndk`, etc.)
was evaluated and rejected: package names on Arch diverge from upstream
documentation, the correct JDK version conflicts with a modern system JDK,
and the maintenance burden is high for little reward. Android Studio bundles
and manages the SDK, NDK, and JDK internally without touching system packages.

Android Studio may be removed after a successful build
(`doas pacman -Rns android-studio`). Note that the SDK it downloads lives
separately — typically `~/Android/Sdk` — and must be cleaned manually if
no longer needed. If Gabbro reaches a point of active Android support,
keep it installed.

### Installation
Install from the AUR. Read AUR comments before installing.

### Rust cross-compilation targets
Add the Android targets via rustup (run from anywhere — rustup is user-global):
```bash
rustup target add aarch64-linux-android   # ARM 64-bit — primary target
rustup target add armv7-linux-androideabi # ARM 32-bit — older devices
rustup target add x86_64-linux-android    # x86_64 — emulator
```

### Verification
```bash
flutter doctor -v   # should show Android toolchain ✓
rustup target list --installed   # should show the three targets above
```

## Version Control

- Local git repo initialised at project root
- Remote: private GitHub repository at https://github.com/Zabamund/gabbro
- SSH key authentication configured for push access
- Project email: gabbro.app@gmail.com (used in git config user.email)
- `chat_info/` is git-ignored — development session notes are never versioned
- **GitHub integration (active):** Anthropic's GitHub integration connects
  the private repository to this Claude Project. Selected files are synced
  and available in context automatically, eliminating the need to upload
  `ARCHITECTURE.md`, `LEARNINGS.md`, and source files at the start of each
  session.

  **Setup procedure (for reference):**
  1. Open the Claude chat toolbar → Customize → Add from GitHub
  2. Install the Claude GitHub App on your GitHub profile and grant access
     to the private repository
  3. Select which files to include, being mindful of context window usage
  4. See: https://support.claude.com/en/articles/10167454-using-the-github-integration
- **AI development partner access:** Claude cannot be added as a GitHub
  collaborator and has no persistent access to the repo. The GitHub
  integration (above) is the mechanism for sharing repo context with Claude.

## Licence

GPL-3.0-only — see ADR-004 for full reasoning.
SPDX identifier: `GPL-3.0-only`

## Monetization (future)
- Freemium model TBD
- Yubico partnership target
- Advanced features (e.g. advanced tags) as premium tier

---

## Tablet Two-Pane Layout

### Wireframe decisions (session 05 May 2026 — approved)

- **Breakpoint:** ≥600dp activates two-pane layout. Below 600dp: current
  single-pane phone behaviour unchanged.
- **Pane structure (left to right):**
  1. Navigation rail (≈68dp, fixed) — icon + text label pairs matching the
     phone's bottom nav bar destinations exactly (Vault, Security, Settings,
     About). Same destinations, different widget. Selected item highlighted.
  2. Alphabet index bar (≈28dp, fixed) — full A–Z + # column, same
     height-adaptive and windowed logic as phone. Position (left-of-list)
     follows the phone setting: if the user moves the bar to the right in
     Settings → Appearance, the bar moves to the right edge of the list
     pane on tablet too. One setting, consistent across form factors.
  3. Vault list pane (≈200–240dp, fixed) — search bar, filter chips,
     alphabetical groups, selected entry highlighted with left-border accent.
  4. Detail pane (flex: 1) — entry detail view, filling remaining width.

- **Four interaction states:**
  - **Browse (default):** list selection active, detail shows selected entry.
    Empty state (no entry selected): lock icon + "select an entry" placeholder.
  - **Edit in place:** pencil tapped on detail pane header. Detail pane
    becomes edit form in place. List pane dimmed and non-interactive.
    Header shows Cancel and Review → buttons. Exits via Cancel or Review →.
  - **New entry (+ button):** full-screen modal overlaying both panes.
    Existing list/detail visible but non-interactive behind modal. Consistent
    with phone behaviour; avoids conflicts with list selection.
  - **Unlock screen:** centred single-column form, two-pane layout not
    active. Same layout as phone unlock — no list or detail pane shown.

- **Sub-screen navigation (Option 2 — approved):** Screens other than the
  vault list (`CreateEntryScreen`, `EntryDetailScreen`, `SecurityScreen`,
  `AppearanceScreen`, etc.) use full-screen push navigation, replacing the
  two-pane shell entirely. Two-pane layout is the vault list screen's
  layout, not persistent app chrome. Simplest implementation; reuses all
  existing navigation code.

- **Nav rail vs bottom nav bar:** Flutter's `NavigationRail` widget at
  ≥600dp; `NavigationBar` (bottom) below 600dp. Destination list defined
  once, shared between both. `LayoutBuilder` or
  `MediaQuery.of(context).size.width` to switch.

### Implementation plan

1. **Wrap `VaultListScreen` in a `LayoutBuilder`** — read available width.
   Below 600dp: render current layout unchanged. At ≥600dp: render
   `_TabletVaultLayout` (new private widget in the same file or a
   dedicated `tablet_vault_layout.dart`).

2. **`NavigationRail` widget** — replace `NavigationBar` with
   `NavigationRail` at ≥600dp. Extract destination definitions to a
   shared list so phone and tablet stay in sync. `NavigationRailLabelType.all`
   to show labels below icons.

3. **`AlphabetIndexBar` position** — the existing widget already takes a
   position parameter (left/right from settings). On tablet, pass the same
   setting value; the widget renders in the appropriate position relative to
   the list pane. No new parameter needed.

4. **List pane interaction lock** — in edit state, wrap the list pane in
   `IgnorePointer(ignoring: _isEditing)` and apply `Opacity(opacity: _isEditing ? 0.4 : 1.0)`. `_isEditing` is a `bool` on the tablet layout
   widget, set true when the pencil is tapped, false on Cancel or
   successful Review →.

5. **New entry modal** — `+` button calls `showModalBottomSheet` or
   `showDialog` with `CreateEntryScreen` as full-screen content. Same
   call site as phone; no tablet-specific code needed if the existing
   modal fills the screen.

6. **Empty state** — when `_selectedEntryId == null` in the detail pane,
   render a centred `Column` with `Icons.lock_outline` and the string
   "Select an entry". Auto-selects the first entry on initial load if
   the vault is non-empty.

7. **Tests** — widget tests using `MediaQuery` overrides to simulate
   ≥600dp and <600dp widths. Verify: rail visible at ≥600dp, bottom nav
   visible below; list dims on edit; detail pane updates on list tap;
   empty state shown when nothing selected.

---

## Current Focus

> Update this section at the end of each session. One or two bullets max.
> It is the first thing to check at the start of the next session.

- **Completed:** Three bug fixes hardware-verified on Linux and Lenovo tablet:
  (1) `TabletVaultLayout` stale `_selectedEntryId` — reset via `didUpdateWidget`
  when the selected UUID is no longer present in `filteredEntries` after a vault
  reload or import. Test 10 added to `test/vault_list_tablet_test.dart`.
  (2) `ReviewChangesScreen` empty-new-fields diff — `Custom` and `Identity`
  branches now show newly added fields (empty → value) in the diff.
  Test added to `test/review_changes_screen_test.dart`.
  (3) Vault deletion from UI — already implemented in a prior session; tests
  confirmed passing (8/8).

- **Next tasks (in order):**
  1. Alphabet bar left/right position toggle — Settings → Appearance, phone
     layout only. See Bikeshed → Features & UX.
  2. Tablet edit-mode dim (phase 2) — wire `_isEditing` in
     `TabletVaultLayout`; unskip test 6.
  3. `zeroize` integration — see Bikeshed → Security.

---

## Bikeshed / Backlog

### Procedure

This section is a lightweight kanban backlog, used across development sessions.
Follow this procedure exactly:

1. **To-do:** add ideas here as bullet points under the relevant subsection,
   with enough context to pick them up cold in a future session.
2. **Doing:** when work begins on an item, mark it `[IN PROGRESS]` here.
   Remove it from this section once the session is complete.
3. **Done:** remove the item from this section entirely. Document it properly
   in the relevant section of ARCHITECTURE.md and/or LEARNINGS.md, exactly
   as all other completed work is documented.

Both the developer and the AI assistant are expected to follow this procedure.
New ideas that arise mid-session should be added here immediately rather than
discussed and forgotten.

---

### Versioning scheme

Both Gabbro and wellpathpy use **SemVer** (Semantic Versioning):
`MAJOR.MINOR.PATCH`

**Why SemVer over CalVer or sequential numbering:**
CalVer (e.g. `2025.04.1`) communicates release date, not stability — unhelpful
for a security tool where the question users ask is "is this ready to trust?"
Sequential numbering gives no information about compatibility. SemVer is also
what F-Droid, the Arch AUR, Debian, and PyPI all expect — fighting it adds
friction for packagers.

**What the numbers mean:**

| Part | Gabbro (app) | wellpathpy (library) |
|------|-------------|---------------------|
| **Major 0→1** | "We stand behind this" — public trust milestone | API is now stable |
| **Major 1→2** | Breaking change (vault format, auth model) | Breaking API change |
| **Minor x→x+1** | New user-facing feature shipped | New function / method added |
| **Patch x.y→x.y+1** | Bug or security fix | Bug or docs fix |

**Key difference between the two projects:**
The Major bump carries heavier weight for Gabbro than for wellpathpy. For a
password manager, `0.x` signals "not yet stable — use with caution" and `1.0`
is a public commitment. For a Python library the same signal exists, but users
expect `0.x` libraries in their toolchains — the stakes are lower.

**Current state:** Gabbro is at `1.0.0` in `pubspec.yaml` but has not had a
public release. The version should remain `0.x` until the v1 feature set
(Linux + Android, YubiKey auth, full vault encryption) is complete and
the pre-release security review has been passed. Reset to `0.1.0` before
the first public tag.

**Action items:**
- Add a `CHANGELOG.md` at the project root (keep it; do not auto-generate)
- Apply the same scheme and table to `wellpathpy` docs when next updated

### Dependencies

- **Dependency licence audit for About screen:** Before v1, verify that
  every entry in `_kComponents` in `about_screen.dart` is accurate and
  complete against the actual `Cargo.toml` and `pubspec.yaml` at that
  time. Dependencies added or removed during development will not
  automatically update the About screen. Also verify licence strings
  against each project's own `LICENSE` file — dual-licence projects
  (Apache-2.0 / MIT) should be listed as such. The three language/runtime
  entries (Rust, Dart, Flutter) are stable and unlikely to change.
  Low effort; do as a pre-release gate, not before.

- **Audit direct Flutter dependencies before v1:** Current direct deps in
  `pubspec.yaml`: `flutter`, `flutter_rust_bridge`, `rust_lib_gabbro`,
  `freezed_annotation`, `path_provider`, `scrollable_positioned_list`,
  `file_picker`, `url_launcher`. All are load-bearing and cannot be removed
  without architectural change. `scrollable_positioned_list` was chosen
  deliberately for the alphabet index bar (lazy-list scroll-to-index problem —
  no Flutter std solution). `url_launcher` added for About screen links —
  opens system browser via `LaunchMode.externalApplication`, no in-app webview,
  no outbound connections from Gabbro itself. Before adding any new dependency,
  apply the same standard: can this be solved with what we already have? Dev
  deps (`flutter_lints`, `freezed`, `build_runner`) have no attack surface and
  are fine.

### Testing

- **Cross-layer integration tests:** Widget tests cover UI behaviour; Rust
  tests cover domain logic. The bridge boundary is not yet tested end-to-end.
  Add a `tests/` folder with integration tests that run the full app against
  a real Rust binary before v1. See LEARNINGS.md testing pyramid for context.

### Import

- **Duplicate import detection — implemented:** Two distinct strategies by
  import type:

  **Third-party → Gabbro (Enpass, Bitwarden, CSV — one-time migration):**
  Keep-all (union). Fresh UUIDs generated for every imported entry; no
  deduplication performed. A persistent warning card is shown at the top of
  `ImportScreen`: "If you have imported this file before, duplicate entries
  may be created. Duplicate cleanup is your responsibility."

  **Gabbro → Gabbro (device sync via `.gabbro` file):** UUID-based skip.
  If an incoming entry's UUID already exists in the session it is skipped —
  the local version is preserved. New entries (UUID not present) are added.
  After import, the user is shown `import_skipped_dialog.dart` listing
  skipped entries (title + reason: "UUID already exists"). Single save at
  the end. Bridge function: `import_from_gabbro(path, passphrase)` in
  `rust/src/api/import.rs`. Hardware-verified on Linux and Samsung S23
  (Android 16) — both directions, all four test rounds passed.

  Content-hash deduplication and entry-level merge remain v2 candidates.

- **Export path picker — resolved:** `FilePicker.getDirectoryPath()` (SAF)
  implemented on Android. User picks destination directory; export writes
  `vault.gabbro` + `vault.gabbro.sha256` there. Hardware verified on
  Samsung S23 (Android 16). `PathField` unchanged — Android bypasses it.
  Gabbro → Gabbro sync round-trip hardware verification is the next step.


### Security

- **Pre-release security review — AI pass:** Before v1 public release,
  run a full AI-assisted security review of `rust/src/crypto/` and
  `rust/src/vault/` using Claude Opus (the highest-capability model).
  Share source via the GitHub integration and request a targeted review
  covering: memory handling, crypto parameter choices, serialization edge
  cases, untrusted input paths, and any deviation from RustCrypto crate
  best practices. AI review is a first pass — it complements but does not
  replace human expert review (see item below).

- **Supply-chain attack surface review:** Triggered by the May 2026
  bitwarden-cli npm supply-chain compromise. Before v1, conduct a full
  review covering four areas:
  (1) **Rust dependencies** — run `cargo audit` against the RustSec
  advisory database; pin all crates to exact versions in `Cargo.lock`;
  verify `cargo tree` for unexpected transitive deps; prefer crates from
  the RustCrypto organisation (already the case for crypto stack) as they
  have documented security policies.
  (2) **Flutter/Dart dependencies** — run `flutter pub outdated` and
  `dart pub audit`; verify each direct dep's GitHub repo for recent
  suspicious commits or maintainer changes; check pub.dev for any
  security advisories.
  (3) **IDE extensions (CODE OSS / VS Code)** — audit every installed
  extension: publisher identity, install count, last update, permissions
  requested. Remove any extension that is not strictly necessary.
  Extensions with filesystem or network access are the highest risk.
  Treat extension updates as untrusted code updates — review changelogs.
  (4) **Build and CI supply chain** — the current build is local-only
  (no CI). When CI is added, pin all GitHub Actions to commit SHAs, not
  tags. Never `uses: actions/checkout@v4` — use the full SHA. Audit the
  flutter_rust_bridge_codegen binary provenance.
  **Mitigation principles:** minimise dependency count (already a project
  goal), prefer dependencies with reproducible builds, never run
  `cargo install` or `pub global activate` from untrusted sources, and
  treat any dependency update as a code review event — read the diff
  before accepting. The fact that Gabbro is local-first with no network
  connections significantly reduces the blast radius of a compromised
  dependency, but does not eliminate it — a malicious dep could still
  exfiltrate secrets via the filesystem or corrupt the vault.

- **Pre-release security review — human expert:** Seek external
  cryptography review of `rust/src/crypto/` before any v1 public security
  claim. Accessible routes for a FOSS project:
  (1) Academic outreach — cryptography PhD students/postdocs at nearby
  institutions (ETH Zürich, EPFL) often review interesting open-source
  PQC work pro-bono; it is relevant to their research.
  (2) RustCrypto maintainers — reachable on GitHub; a scoped
  "security review request" issue for usage of their own crates is
  reasonable.
  (3) Formal audit (Cure53, Trail of Bits) — money, likely v2 territory.
  This is a prerequisite for credible v1 security claims given the PQC angle.

### Code Quality

- **Dependency audit:** Keep the dependency surface minimal — only add a
  crate when it solves a problem that cannot be reasonably solved with `std`.
  Before v1, audit `Cargo.toml` and remove or replace any crate that has
  outlived its purpose or could be substituted with a small `std`-only
  implementation. Pay particular attention to transitive dependencies
  (`cargo tree`). A smaller dependency surface means less attack surface,
  faster compile times, and fewer supply-chain risks. Reference: the same
  philosophy applied successfully in `wellpathpy` (numpy-only).

### Password / Passphrase Generator

- **Non-ASCII wordlist support (v2):** Add CJK and other non-Latin language
  wordlists (e.g. Japanese, Korean). Architecture already supports it —
  `include_str!` handles UTF-8 and entropy math is language-agnostic.
  Key concerns: wordlist sourcing and vetting (EFF-style vetted lists are
  less available for CJK); separator defaults (CJK may want none, or a
  middle dot ・, rather than a hyphen); UI warning that a non-ASCII
  passphrase may be inaccessible on devices lacking the relevant input
  method — this applies with extra force to the master passphrase.


### Features & UX

- **Vault sync across devices:** Moving or merging a `.gabbro` vault file
  between devices. Distinct from both "Import entries" (from other password
  managers) and "Add vault" (multiple vaults on one device). Three
  sub-cases to design for:

  (i) **Export → import (one-shot overwrite):** User exports `.gabbro`
  from device A, imports to device B. Simple: decrypt both, discard B's
  entries, replace with A's, re-encrypt. No conflict resolution needed.
  Requires passphrase available on B (same passphrase — the common case
  for personal sync).

  (ii) **File-level sync via NAS / cloud (automated):** User syncs the
  `.gabbro` file itself using rsync, Syncthing, etc. Gabbro does not need
  to do anything here — the file is the unit of sync. The risk: concurrent
  edits on two devices produce two diverged files. Gabbro should detect
  this (file modified-time newer than last-loaded timestamp) and warn the
  user rather than silently overwriting. A "last writer wins" policy is
  acceptable for v1 with an explicit warning.

  (iii) **Entry-level merge (full sync):** Decrypt both vaults, diff entry
  sets by UUID, apply a merge strategy. Analogous to a database
  `MERGE`/`UPSERT` keyed on UUID. Conflict resolution options (to expose
  as user-configurable sync settings):
  - Last-write-wins per entry (compare `updated_at`)
  - Union (keep all entries from both — no deletions propagated)
  - rsync `--delete` style (source is authoritative; deletions propagate)
  - Interactive (prompt user per conflict)

  Key questions: which sub-cases are in scope for v1? Sub-case (i) is low
  effort and high value — a good v1 target. Sub-case (ii) requires only
  a staleness check. Sub-case (iii) is a full session (or several) on its
  own. Does merge require a new bridge function `merge_vaults(path_a,
  path_b, strategy)`? How does the UI surface sync settings so they persist
  and are reusable (sync is a regular operation, not a one-off)?

  This is at minimum one full session; sub-case (iii) likely several.
  Do not start without a design doc agreed first.

- **URL launch icon on non-Login entries:** Currently the launch icon
  (`Icons.open_in_browser_outlined`) only appears on the URL field of
  Login entries. Custom entries and custom fields on any entry type may
  also contain URL-shaped values. Two design options: (1) auto-detect
  URL-shaped values heuristically (check for scheme or bare domain
  pattern) and show the launch icon automatically — fragile, may produce
  false positives; (2) add an explicit `field_type: url` variant to the
  custom field domain model in Rust, and render the launch icon only for
  fields so typed — requires a domain model change and bridge update but
  is precise. Decide approach before implementing.

- **Timestamp localisation (i18n):** `formatTimestamp()` in
  `entry_detail_screen.dart` uses a hand-rolled English month
  abbreviations array. When internationalisation (i18n) is added,
  replace with `DateFormat('dd MMM yyyy, HH:mm').format(dt)` from
  `package:intl` — one-line change, picks up device locale automatically.

- **Autofill:** How will autofill work across platforms? On desktop,
  browser extensions (Chrome/Firefox/etc.) are the standard approach —
  requires building and maintaining separate extension(s). On mobile there
  are no extensions; Android exposes an Autofill Framework (AccessibilityService
  or the dedicated AutofillService API) and iOS has a Password AutoFill
  extension point. These are fundamentally different integration models per
  platform. Key questions: which platforms get autofill in v1 vs v2? Is a
  browser extension in scope at all given the GPL-3.0 and FOSS distribution
  model? Does autofill change the security model (secrets closer to the
  browser boundary)?

- **Themes — dark / light / custom:** Dark and light modes are already noted
  as system-default with user override. Open questions: should Gabbro offer
  additional high-contrast or accessibility-focused themes beyond dark/light?
  Any colour theme must be validated against ADR-003 (colour-blind safety) and
  WCAG 1.4.1. Consider whether custom accent colours (already noted for the
  password display palette) generalise to a broader theming system, or whether
  that adds complexity for little gain.

- **Panic button / app hiding on mobile:** A visible "hide app" mechanism —
  e.g. disguise Gabbro as a calculator or notes app, or a panic button that
  instantly locks and hides it. Relevant threat model: physical coercion or
  device inspection. Key questions: how does this interact with the existing
  auto-lock and wipe logic? Is disguise-as-another-app feasible on Android
  (custom launcher icon/label, yes; hiding from app drawer is limited) and iOS
  (more restricted)? Does offering this create a false sense of security?

- **Remote app / vault deletion:** Allow the user to trigger a remote wipe of
  the vault (and optionally the app) from another device or a web interface.
  Requires some form of out-of-band communication channel — which conflicts
  with the current fully-local, no-server v1 model. Key questions: what
  transport mechanism? (push notification, SMS, email?) Who operates the
  server? Does this require Gabbro to have a backend service, and if so what
  are the privacy and cost implications? Likely a v2+ feature; capture the
  threat it addresses (device lost/stolen) in the meantime.

- **Coercion resistance / duress / decoy vault:** If a user is forced to unlock
  the vault, a separate decoy passphrase returns a believable but fake set of
  entries. Known as a "duress password" or "hidden volume" (cf. VeraCrypt).
  Non-trivial to implement correctly — the decoy vault must be
  cryptographically indistinguishable from the real one, otherwise it provides
  no protection. Key questions: does this fit the current single-vault file
  model? Would it require two encrypted blobs in the same `.gabbro` file?
  How does it interact with YubiKey auth (does the duress path also require
  a tap)? High complexity, high value for high-risk users. Needs a dedicated
  design session before any implementation.

- **Passkey support:** Passkeys (FIDO2 discoverable credentials / WebAuthn
  resident keys) are increasingly used as a password replacement on websites.
  Should Gabbro store passkeys alongside passwords? This is a different
  credential type — not a secret string but a public/private keypair managed
  by an authenticator. Key questions: is this in scope for Gabbro's vault
  model (new entry type: `PasskeyEntry`)? How does passkey storage interact
  with the YubiKey requirement — are we storing credentials for sites that
  themselves use YubiKeys? What do competing tools (Bitwarden, 1Password) do
  here? Likely v2+; note that autofill (above) is a prerequisite for passkeys
  to be useful.

- **Data breach alerts / HaveIBeenPwned integration:** Notify the user if a
  stored credential appears in a known data breach. HIBP offers a free
  k-anonymity API for password hash prefix lookups (no full hash sent) and a
  separate paid API for email breach lookups. Key questions: is the free
  password API sufficient for v1? What is the cost model for email breach
  alerts at scale? Does calling an external API conflict with the privacy
  model (even k-anonymity leaks query timing and frequency)? Should checks
  be on-demand only, or periodic background checks? FOSS/GPL compatibility
  of the API terms of service should be verified.

- **Support model:** How will users get help? Options range from a GitHub
  Issues tracker (FOSS-standard, no cost) to a dedicated support email,
  community forum (Discourse, Matrix/Element), or paid support tier. Key
  questions: what is sustainable for a solo developer? Does the monetisation
  model (see below) create any support obligations? A minimal v1 approach:
  GitHub Issues + a SUPPORT.md file. Revisit when the user base exists.

- **De-Googled Android compatibility:** Gabbro targets F-Droid as its
  Android distribution channel, which enforces no proprietary dependencies
  and no anti-features. The Rust backend has zero Google dependencies by
  design. However, explicit testing on a de-Googled device (GrapheneOS or
  CalyxOS) is needed before v1 ships to confirm the Flutter layer and
  YubiKey FIDO2 integration work without Google Play Services or with
  microG only.

  This matters because Google's ongoing erosion of Android's open
  platform is pushing privacy-conscious users toward custom ROMs — exactly
  the users Gabbro is built for. Context:
  - [Plexus](https://plexus.techlore.tech/) — crowdsourced de-Googled app
    compatibility ratings, maintained by the community for the community.
  - [Carl Sagan — Pale Blue Dot](https://www.planetary.org/worlds/pale-blue-dot)
    — a reminder of what actually matters and why petty exercises of power
    by present elites are historically self-defeating.

  Plan: find a willing community member with a de-Googled device to test
  a beta build before v1 release. Do not buy hardware prematurely.

- **Responsive layout — desktop:** The tablet two-pane layout (≥600dp) is
  now designed and planned — see ## Tablet Two-Pane Layout. Remaining
  open question is Linux desktop specifically: unlike Android, desktop
  windows are freely resizable. The app must be tested across a range of
  window sizes — from a narrow tiling WM column to a maximised widescreen
  window — before v1 ships. Font size scaling and layout are coupled: a
  button that fits at Regular may overflow at Extra Large; test both
  together. No extra dependencies needed; this is a testing discipline.
  Reference: WCAG 1.4.4 (Resize Text).

- **Block copy/paste on master passphrase fields:** On `OnboardingScreen`
  and `UnlockScreen`, the master passphrase fields should block clipboard
  paste to prevent accidental exposure via clipboard history tools.
  Implement with a custom `TextInputFormatter` or by intercepting
  `onChanged` to detect paste events. Default behaviour: block paste.
  User-configurable via a toggle in Settings → Security (default: block).
  Defer until pre-release — current behaviour is acceptable for development
  and testing.

- **Clean up legacy vault on first launch:** When the app launches and no
  vault exists at the current app ID path (`app.gabbro.gabbro`), check for
  a vault at the old `com.example.gabbro` path and offer to migrate or delete
  it. Prevents silent accumulation of orphaned vault files on the user's device
  during development, and will matter for any user who installed a pre-rename
  build. Implement in `main.dart` during the vault existence check.

- **Custom filter chips:** Allow users to add new filter chips based on
  folders or custom tags, beyond the fixed entry-type chips. YAGNI risk is
  real — the fixed chips cover the common case and custom ones add UI
  complexity. Revisit after v1 ships and user feedback exists.

- **Hide filter chips:** Allow users to hide individual filter chips they
  never use (e.g. a user who has no Card entries). YAGNI risk same as
  above — defer until there is evidence users want this.

- **Multiple vaults:** Allow users to create and switch between more than
  one vault. Key questions: how does the session model handle multiple
  open vaults? Does the UI need a vault switcher, or is open/close
  sufficient? Does each vault get its own passphrase and KDF parameters?
  Significant architecture change — v2 at earliest.

- **Alphabet bar left/right setting (accessibility):** Add a toggle in
  Settings → Appearance to move the alphabet index bar from its default
  left position to the right. Applies in <600dp (phone) mode only —
  one-handed mobile use is the ergonomic case this serves; tablet users
  almost never hold and manipulate the device one-handed so the setting
  is not exposed there. Tablet layout always positions the bar on the left
  (between nav rail and list pane), regardless of the phone setting.
  Implement after the tablet two-pane layout is shipped.

- **Enpass-style password detail view:** In the entry detail screen,
  show a character-by-character breakdown of the password beneath the
  masked field: a number under each character, colour-coded by type
  (uppercase, lowercase, digit, symbol), using an unambiguous font for
  visually similar characters (0/O, l/1/I). Colour must never be the
  sole differentiator — ADR-003 applies. Design in a dedicated session.

- **Tablet list pane width:** The list pane is currently fixed at 260dp.
  Options: (1) widen the fixed value, or (2) make the divider draggable
  so the user can adjust it. Option 2 is more flexible but adds
  complexity. Revisit after other tablet polish is complete.

- **Tablet edit-mode dim (phase 2):** Wire `_isEditing` state in
  `TabletVaultLayout` — set true when pencil tapped on detail pane
  header, false on Cancel or Review →. List pane dims to 0.4 opacity and
  is blocked by `IgnorePointer` during editing. Unskip test 6 in
  `test/vault_list_tablet_test.dart` once implemented.

- **App logo:** When a logo exists, add it to `OnboardingScreen`,
  `UnlockScreen`, and the centred tablet unlock layout. Defer until logo
  is designed.

- **Verify Android storage permissions:** Gabbro currently declares no
  storage permissions in `AndroidManifest.xml`. This is correct as long
  as: (1) the vault file lives in app-private storage via
  `getApplicationDocumentsDirectory()` (no permission needed on any
  Android version); and (2) export/import uses `file_picker` which
  operates via the Storage Access Framework (SAF), granting URI-scoped
  access without a blanket storage permission. Verify both assumptions
  hold on Android 11+ before v1. If any code path writes outside
  app-private storage without SAF, `MANAGE_EXTERNAL_STORAGE` would be
  required — a heavily restricted permission that draws Play Store
  scrutiny.

- **Copy to clipboard from detail screen:** Implemented and hardware-verified
  on Linux and Samsung S23 (Android 16). No further action needed.

- **Detail view — created/modified timestamps:** Show `created_at` and
  `updated_at` on the detail screen so users can audit when an entry was
  created or last changed. Data is already present in all entry DTOs.
  Low effort, high audit value.

- **Autofill:** Autofill does not use the OS clipboard — credentials go
  directly from the autofill service into the target field via the OS
  autofill framework, bypassing clipboard history managers entirely. This
  is a meaningful security advantage over copy-paste and worth building
  in v2. On Android: AutofillService API. On desktop: browser extension
  (separate distribution). Prerequisite for passkey support.
  Document the clipboard-vs-autofill security distinction in `docs/SECURITY.md`.

- **Release builds for UI/UX testing:** Debug builds run Argon2id unoptimised
  (~20s per vault operation on Linux, worse on Android emulator). Always use
  `flutter build linux --release` and `flutter build apk --release` for any
  user-facing performance assessment or UI/UX testing. Never tune Argon2id
  parameters or assess UX based on debug build timings.

## Import / Migration

### Rationale — why not write N importers?

Before writing any import code, we thought carefully about who actually
migrates password managers and why. The analysis shaped the scope
significantly.

**The user archetypes considered:**

1. **Free-tier user** — uses a password manager for convenience. Low
   switching cost, but also low motivation: the free tier is working fine.
   Unlikely to migrate.
2. **Paid-tier user** — already invested, likely has autofill and browser
   integration set up. Switching has a real cost. Unlikely to migrate.
3. **Browser built-in user** — convenience and laziness driven. No
   subscription to escape from, but also no urgency to change. Unlikely
   to migrate.
4. **The post-event migrant** — the user whose subscription lapsed, who
   got burned by a breach (LastPass 2022 is the concrete example), or who
   has already decided to leave and is sitting on an exported file wondering
   what to do next. This user is *actively looking* for a migration path.
   Migration is triggered by a specific event, not gradual dissatisfaction.
   This is Gabbro's target demographic for importers.

**The conclusion:** importers are not about pulling users away from active
subscriptions — they are about catching people at the moment they decide
to leave. That reframe changes the priority order completely. We do not
need to cover every password manager speculatively. We need to cover the
ones most likely to be the prior home of a privacy-conscious user who has
just decided to move on.

**Maintenance honesty:** every importer is a maintenance liability. Any
time an upstream app changes its export format, the importer breaks silently
or noisily. Keeping the importer surface small is not laziness — it is
sustainable engineering.

### Agreed scope

Three importers, in implementation order:

1. **Enpass** — required by the project author; also a natural fit for
   Gabbro's audience (privacy-conscious, FOSS-adjacent users). Enpass
   exports to JSON with a documented schema. Implement first.

2. **Bitwarden** — the most likely prior home for someone who discovers
   Gabbro. The values overlap is high: FOSS, self-hostable, privacy-focused.
   If someone is leaving Bitwarden for Gabbro, that path should be
   frictionless. Bitwarden's JSON export format is well-documented and
   stable. Implement second.

3. **Generic CSV / JSON importer** — covers the long tail: browser built-in
   exports, lesser-known managers, and any manager not explicitly supported.
   Most password managers export to CSV. The main design challenge is field
   mapping: a simple UI step asking the user to map their columns to Gabbro
   fields is more honest than silent guessing. Implement third.

Everything else (1Password, LastPass, Dashlane, Keeper, etc.) — defer to
the generic importer and document it clearly.

### Generic CSV importer — design and status

**Status: complete.** Implemented in
`rust/src/import/csv.rs`. No new dependencies — hand-rolled parser,
consistent with the project's minimal dependency philosophy.

**Design decisions:**
- All CSV input is treated as untrusted: 10 MB size limit enforced
  before parsing; BOM (`\u{FEFF}`) stripped silently (Excel on Windows
  prepends this to every CSV export); `"None"` values normalised to
  empty string.
- `sniff_csv()` returns headers and up to 3 preview rows as a
  `CsvPreview` struct — for Flutter's mapping UI to display before
  import begins.
- `import_csv()` takes a `CsvImportConfig` struct with six optional
  column mappings (`title_col`, `url_col`, `username_col`,
  `password_col`, `notes_col`, `favourite_col`). Any column not
  explicitly mapped becomes a `CustomField` on the resulting entry.
- All rows produce `LoginEntry` — generic CSV has no type system.
  Type information from the source manager (if any) lands in a
  custom field.
- Title fallback chain: mapped title column → mapped URL column →
  `"MISSING TITLE"`. Title is the only required field; all others
  are optional.
- Favourite normalisation: `"1"`, `"yes"`, `"true"` (case-insensitive)
  → `true`; everything else → `false`.
- Quoted fields containing commas handled correctly by the hand-rolled
  parser.
- Rows with fewer columns than headers: missing fields default to
  empty string. Rows with more columns than headers: extra fields
  silently ignored.
- A one-sentence warning is shown on the Flutter import screen:
  "Only import CSV files you exported yourself from a trusted
  password manager." Non-blocking, inline.

### Implementation order

The correct sequence, regardless of which importers we build:

1. **Build a mock vault** — create a representative set of test entries
   covering all six Gabbro entry types (Login, Note, Identity, Card, File,
   Custom), with realistic field values. Load this into each target password
   manager via their free tier and export it back out.

2. **Field gap analysis** — compare what each manager exports against
   Gabbro's current domain model. Identify any fields present in the export
   that have no home in Gabbro's entry types. Document the gaps explicitly
   before writing a single line of import code.

3. **Domain model updates** — add any missing fields to the relevant entry
   types in `rust/src/vault/entry.rs`. Do this before writing importers, not
   after — retrofitting import code around a domain model change is messy.

4. **Generic CSV / JSON importer** — implement last, once the field surface
   is stable.

### Import validation failures — resolved bugs

Three bugs were found and fixed during the full hardware test matrix:

1. **Card name required** — `CreateEntryScreen` card form allowed saving
   without a card name, leaving cards with no label in the vault list view.
   Fixed: required validator added to `_cardNameController` in `_cardFields()`.
   Test added to `test/create_entry_screen_test.dart`.

2. **Multi-field validation in `CardEntry::new()`** — the constructor only
   validated card number digit count; missing cardholder name, expiry, and
   CVV were silently accepted as empty strings. Fixed: all four fields now
   validated; all failures collected and returned as a single joined error
   string. Test added to `rust/src/vault/entry.rs`.

3. **Tablet list pane not refreshed after entry edit** — editing an entry
   via `EntryDetailScreen` in the tablet two-pane layout updated the detail
   pane but not the list pane. Root cause: `EntryDetailScreen` had no
   `onEdited` callback; the inline detail pane had no mechanism to trigger
   `VaultListScreen._loadEntries()`. Fixed: `onEdited: VoidCallback?` added
   to `EntryDetailScreen`; wired in `TabletVaultLayout._buildDetailPane()`
   to call `widget.onRefresh()`. Verified on Linux and Lenovo tablet.

   Note: a fourth suspected bug (tablet blank screen after Bitwarden import)
   could not be reproduced during the hardware test matrix. Tablet Bitwarden
   import passed on all three test paths (valid, invalid–Skip, invalid–Edit).
   Monitor in future sessions.

### Enpass — what we know from analysis of a real export (247 items)

**Settled decisions:**
- Parsing lives in Rust — untrusted external data mapping into the domain
  model belongs where the domain model lives. Decided and implemented.
- Attachments are preserved — imported as `Vec<EntryAttachment>` on the
  entry they belong to. Not dropped, not split into separate FileEntries.
  Attachment `data` is base64-encoded in the export; decode to `Vec<u8>` on import.
- Archived and trashed items are silently skipped.
- Deleted fields within an item are silently skipped.
- `totp`, `section`, `.Android#`, `ccType` fields are dropped.
- `numeric`, `date`, `phone`, `pin`, `text` fields not mapped to a canonical
  field become `CustomField` entries on the parent entry.

**Category → Gabbro type mapping:**
- `login`, `computer`, `finance` → `LoginEntry`
- `creditcard` → `CardEntry`
- `note` → `NoteEntry`
- `travel`, `misc`, and any unknown category → `CustomEntry`
- `identity` → `CustomEntry` (no dedicated identity template in Enpass)

**Field type → LoginEntry field mapping:**
- `username`, `email` → `username` (prefer first non-empty value)
- `url` → `url`
- `password` → `password`
- Everything else → `custom_fields`

**Enpass export structure (confirmed from real data):**
- Top-level: `{ "items": [...] }`
- Each item has: `uuid`, `title`, `category`, `note`, `favorite`, `archived`,
  `trashed`, `fields`, `attachments`, `template_type`
- Each field has: `label`, `type`, `value`, `sensitive`, `deleted`, `order`, `uid`
- Each attachment has: `uuid`, `name`, `kind` (mime type), `data` (base64)

**Status: complete.** The TDD strategy was followed:
anonymised test data, failing tests first, parser fixed until all passed.
See `rust/src/import/enpass.rs` for the full test suite.

## Monetisation

- **GPL-3.0 monetisation — confirmed approach:** GPL-3.0-only explicitly
  permits commercial distribution. Charging on the Play Store while
  distributing free on Arch/Debian/F-Droid is fully licence-compatible —
  the buyer receives source and redistribution rights per the GPL bargain,
  but in practice almost nobody rebuilds from source. F-Droid lists the
  free build without conflict; it does not object to a paid Play Store
  version of the same app existing. No licence change required.
  One-time payment on Play Store is the recommended model to recoup the
  $25 registration fee; no ongoing subscription complexity.
  Yubico partnership remains a separate future discussion.

- **Monetisation outreach — Destination Linux podcast:** Contact the
  Destination Linux podcast (https://destinationlinux.org/) when Gabbro
  is approaching a public release. Their audience is exactly Gabbro's
  target demographic: privacy-conscious, FOSS-native Linux users. A
  guest appearance or mention would provide credible organic reach at
  zero cost. Prepare a short project summary and a working demo build
  before reaching out.

## Trust & Transparency

- **Donation / sustainability model**
  Gabbro should adopt a QGIS-style voluntary donation model: prominent but non-coercive, shown on the download/landing page before the user proceeds. No payment data ever touches the project. Recommended combination: GitHub Sponsors (low friction, familiar to the FOSS audience), Liberapay (FOSS-native non-profit platform, privacy-friendlier than Patreon, no platform fee), and a Monero (XMR) wallet address (genuinely private, no transaction graph, well-trusted by the security-conscious audience Gabbro targets). Bitcoin can be added for reach with a note that it is pseudonymous not anonymous. Patreon explicitly excluded — US company, collects significant user data, wrong values signal. Cash excluded — requires publishing a physical address. This needs a dedicated session when the project is closer to public release: set up the three channels, write the donation page copy, and decide whether to publish donor acknowledgements (opt-in only, given the privacy context).

- **No-telemetry verification guide (README)**
  Gabbro makes no outbound network connections during normal operation. This should be independently verifiable by users, documented honestly in the README with five sections:

  1. **Static scan** (`rg`) — a documented ripgrep command that scans the repository for known network primitives in both Rust (`TcpStream`, `reqwest`, `hyper`, `ureq`, `tokio::net`) and Dart/Flutter (`http`, `dio`, `HttpClient`, `WebSocket`). Verifies intent in the source code. Limitation: does not cover transitive dependencies. Cross-platform, low barrier.
  2. **Wireshark** (desktop) — step-by-step guide for Linux (Arch and Debian/Ubuntu), macOS, and Windows. Links to official downloads. Honest about the skill requirement: this is for technically confident users who understand network interfaces and capture filters. The expected result is zero outbound packets during normal vault operations.
  3. **Android** (NetGuard) — NetGuard is a FOSS (GPL-licensed), no-root Android firewall that shows per-app traffic. Lower barrier than Wireshark, appropriate for non-developer mobile users. Document the setup and what a clean result looks like.
  4. **iOS** — document honestly: iOS makes independent traffic verification difficult without jailbreaking or developer tooling. Proxyman for iOS (local VPN, no root required) is the most accessible option but is proprietary and paid, which sits awkwardly in a FOSS trust guide. State this plainly. Do not pretend the platform limitation does not exist.
  5. **Reference screenshots** — include screenshots of clean results on Arch Linux (Wireshark) and Android (NetGuard) as a reference baseline. Note explicitly in the README that these require the reader to trust the project, which partially defeats the purpose — they are included only so users who cannot or will not run the tools themselves can see what a clean result looks like. Zero-risk verification is not possible on all platforms; we document the gap rather than paper over it.

  This guide should be written when Gabbro is approaching public release and the UI is stable enough that the screenshots will not need frequent updating.

- **`docs/SECURITY.md` — user-facing security document:** Create a single
  `docs/SECURITY.md` covering: (1) encryption explained in plain language
  (ELI5 — what the passphrase does, what Argon2id does, what AES-256-GCM does,
  what ML-KEM adds); (2) why local-first matters — the server breach argument,
  with LastPass 2022 as the concrete example; (3) a comparison table of
  Gabbro's encryption stack vs Bitwarden / LastPass / Enpass / KeePass across
  KDF, authenticated encryption, post-quantum, storage model, and open-source
  status; (4) honest caveats — Ed25519 in v1 auth layer (not yet ML-DSA),
  FDE as a prerequisite, zeroize not yet integrated. The no-telemetry
  verification guide (see above) should be folded into this document rather
  than maintained separately. Write when the UI is stable enough that
  screenshots won't need frequent updating.
