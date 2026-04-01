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
│   └── src/
│       └── rust/               # Auto-generated bridge code (do not edit)
│           ├── api/
│           │   ├── simple.dart
│           │   ├── password_generator.dart
│           │   └── passphrase_generator.dart
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
│       │   └── passphrase_generator.rs
│       ├── vault/              # Internal domain model (not bridge-exposed)
│       │   ├── mod.rs
│       │   └── entry.rs        # All 6 entry types and EntryMeta
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
│       └── ADR-003-colourblind-password-display.md
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
    salt, nonce, ML-KEM public key
  - **Body (encrypted):** all vault entries, JSON serialized,
    encrypted with AES-256-GCM
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

## Authentication Stack (Layer 2 - App Access)
- Mandatory FIDO2/WebAuthn hardware key (YubiKey)
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
- **Core fields:** type-specific
- **Common fields:** UUID, created, modified, folder, tags, favourite
- **Login entry:** URL, username, password (hidden by default,
  show/hide toggle), custom fields, notes
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
  (`rust/src/api/password_generator.rs`), 6 unit tests passing.
  Passphrase mode fully implemented in Rust
  (`rust/src/api/passphrase_generator.rs`), 8 unit tests passing.
  Both bridged to Flutter, Flutter build clean. 14 Rust tests total.
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

## Vault Domain Model
- **Status:** all 6 entry types implemented in Rust
  (`rust/src/vault/entry.rs`), 11 unit tests passing. 25 Rust tests total.
- Lives in `rust/src/vault/` — internal module, not exposed to Flutter
  directly. Flutter will call API functions that construct these types;
  it never builds them directly.
- **EntryMeta:** shared metadata struct composed into every entry type —
  id, timestamps, folder, tags, favourite flag.
- **Entry types:** Login, Note, Identity, Card, File, Custom.
- **CustomField:** reusable key/value struct used by LoginEntry (Vec) and
  CustomEntry (HashMap).
- **CardEntry::new():** only entry type with a validated constructor —
  enforces card number digit count (12–19) to reject nonsensical data at
  construction time. Other types use struct literals; validation for those
  will live in the API layer when it is built.
- **Design principle:** invalid state unrepresentable — if a value cannot
  exist in a valid domain, the type system or constructor prevents it from
  being created at all.

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

## Platforms
- v1: Linux (Arch + Mint/deb), Android (F-Droid)
- v2 (future): Windows, macOS, iOS

## Version Control

- Local git repo initialised at project root
- Remote: private GitHub repository at https://github.com/Zabamund/gabbro
- SSH key authentication configured for push access
- Project email: gabbro.app@gmail.com (used in git config user.email)
- `chat_info/` is git-ignored — development session notes are never versioned

## Licence

GPL-3.0-only — see ADR-004 for full reasoning.
SPDX identifier: `GPL-3.0-only`

## Monetization (future)
- Freemium model TBD
- Yubico partnership target
- Advanced features (e.g. advanced tags) as premium tier

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

### Password / Passphrase Generator

- **Non-ASCII wordlist support (v2):** Add CJK and other non-Latin language
  wordlists (e.g. Japanese, Korean). Architecture already supports it —
  `include_str!` handles UTF-8 and entropy math is language-agnostic.
  Key concerns: wordlist sourcing and vetting (EFF-style vetted lists are
  less available for CJK); separator defaults (CJK may want none, or a
  middle dot ・, rather than a hyphen); UI warning that a non-ASCII
  passphrase may be inaccessible on devices lacking the relevant input
  method — this applies with extra force to the master passphrase.

- **Max length policy:** Decide and document the enforced limits.
  Classic passwords — no hard cryptographic cap; sensible generator range
  is 8–64 characters with no upper limit for manual entry. Passphrases —
  generator max ~20 words (entropy is already astronomical beyond that,
  and usability degrades). Verify that the Rust `PasswordConfig` struct
  does not silently truncate values at any boundary.

- **User-typed password/passphrase with entropy feedback:** Allow the user
  to type their own secret rather than generating one; Gabbro returns an
  estimated entropy in bits plus a human-readable strength tier
  (e.g. Terrible / Weak / Fair / Strong / Very Strong / Centuries).
  Rust API: `estimate_entropy(password: &str) -> EntropyResult` returning
  bits (f64) and a `StrengthTier` enum; enum-to-display-string mapping
  handled in Flutter, following the same pattern as the `Language` enum.
  Important: entropy for a user-typed string is a lower-bound estimate
  based on detected character classes (lowercase, uppercase, digits,
  symbols, non-ASCII) — not a true entropy value. Label it clearly as
  "estimated entropy" in the UI to avoid false precision.

### Monetisation

- **GPL-3.0 monetisation model TBD** — ideas include a Yubico partnership
  and a Play Store one-time payment. Needs a dedicated design session;
  must be compatible with GPL-3.0-only licence obligations. See the
  Monetization section above for current high-level thinking.
