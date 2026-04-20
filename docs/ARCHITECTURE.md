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
│   │   └── unlock_screen.dart  # Passphrase entry screen
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
│       │   └── serialization.rs# Entry serialization — Vec<VaultEntry> ↔ JSON bytes
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
  (`rust/src/api/vault.rs`). 39 Rust tests passing across the project.
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
  (`rust/src/api/password_generator.rs`), 6 unit tests passing.
  Passphrase mode fully implemented in Rust
  (`rust/src/api/passphrase_generator.rs`), 8 unit tests passing.
  Both bridged to Flutter, Flutter build clean.
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

## Vault Domain Model
- **Status:** all 6 entry types implemented in Rust
  (`rust/src/vault/entry.rs`), 11 unit tests passing.
- Lives in `rust/src/vault/` — internal module, not exposed to Flutter
  directly. Flutter will call API functions that construct these types;
  it never builds them directly.
- **EntryMeta:** shared metadata struct composed into every entry type —
  id, timestamps, folder, tags, favourite flag.
- **Entry types:** Login, Note, Identity, Card, File, Custom.
- **CustomField:** reusable key/value struct used by LoginEntry (Vec) and
  CustomEntry (HashMap).
- **CardEntry::new():** only entry type with a validated constructor —
  enforces card number digit digit count (12–19) to reject nonsensical data at
  construction time. Other types use struct literals; validation for those
  will live in the API layer when it is built.
- **Design principle:** invalid state unrepresentable — if a value cannot
  exist in a valid domain, the type system or constructor prevents it from
  being created at all.

## Vault API Layer
- **Status:** all 6 entry types fully implemented in `rust/src/api/vault.rs`.
  112 Rust tests passing across the project.
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

## Current Focus

> Update this section at the end of each session. One or two bullets max.
> It is the first thing to check at the start of the next session.

- **Completed:** All 6 entry types fully implemented in Flutter UI
  (Identity, Card, File, Custom create/edit/detail screens). CardEntry
  and IdentityEntry extended with new fields. File export added.
  CVV validation and show/hide toggles added. file_picker removed.
- **Next task:** Entropy indicator on UnlockScreen and change passphrase
  screen, then Android build verification.

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

### Security

- **`zeroize` integration:** Add the `zeroize` crate to explicitly clear
  secret material from Rust heap memory when the vault locks. Specifically:
  the `Vec<VaultEntry>` inside `VaultSession`, and the plaintext bytes from
  `seal_vault`/`open_vault`. This narrows the window during which secrets
  are recoverable in RAM after a lock event. Not a guarantee of
  non-recovery (swap, cold boot, OS snapshots all remain possible), but a
  meaningful reduction for the realistic threat of device seizure while
  unlocked. Prerequisite: session model must be implemented first.
  See the **Memory Security** discussion in the Vault Session Model section.

- **Pre-release security review — AI pass:** Before v1 public release,
  run a full AI-assisted security review of `rust/src/crypto/` and
  `rust/src/vault/` using Claude Opus (the highest-capability model).
  Share source via the GitHub integration and request a targeted review
  covering: memory handling, crypto parameter choices, serialization edge
  cases, untrusted input paths, and any deviation from RustCrypto crate
  best practices. AI review is a first pass — it complements but does not
  replace human expert review (see item below).

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

- **Entropy indicator on all passphrase inputs:** The onboarding screen
  already shows a real-time entropy indicator. Audit all other passphrase
  input fields (unlock screen, change passphrase screen) and add the same
  indicator consistently. Users choosing their own passphrase deserve the
  same entropy feedback as the generator provides. Implement using the
  existing `entropy` bridge function already exposed from Rust.

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

- **Native file picker (desktop):** Both the vault location picker on
  `OnboardingScreen` and the file entry picker on `CreateEntryScreen`
  currently use plain text path input on Linux desktop. Replace with a
  native GTK file dialog when desktop polish work begins. On Android,
  use the `file_picker` package (re-add as a dependency at that point —
  it was removed because the Linux backend was not yet set up). The
  path-based fallback must be retained for headless/CI environments.

- **Themes — dark / light / custom:** Dark and light modes are already noted
  as system-default with user override. Open questions: should Gabbro offer
  additional high-contrast or accessibility-focused themes beyond dark/light?
  Any colour theme must be validated against ADR-003 (colour-blind safety) and
  WCAG 1.4.1. Consider whether custom accent colours (already noted for the
  password display palette) generalise to a broader theming system, or whether
  that adds complexity for little gain.

- **High-contrast mode:** Flutter can read the OS-level high-contrast signal via
  `MediaQuery.of(context).highContrast` and honour it automatically — worth doing
  for free. However, an in-app toggle is the more important piece: Linux tiling WM
  users have no OS-level signal to send, and some users want high contrast only
  inside their password manager. Implement as a toggle in Settings → Accessibility,
  alongside the accessible font sizing item. Any high-contrast theme must be
  validated against ADR-003 (colour-blind safety) and WCAG 1.4.3 (Contrast,
  minimum) and WCAG 1.4.6 (Contrast, enhanced). Pairs naturally with the
  Themes — dark / light / custom item above.

- **Accessible font sizing:** Gabbro should offer a font size setting with
  3–5 steps, e.g. Small / Regular / Large / Extra Large (avoid
  "tiny"/"huge" — these have negative connotations for the people who need
  them most). Implemented as a slider or segmented control in Settings →
  Accessibility. Onboarding should default to Regular+1 (one step above
  the base) and surface the option prominently on first launch — defaulting
  to the smallest readable size would exclude users with declining vision
  before they ever reach the settings screen. Pairs with the existing
  colour-blind safety work (ADR-003) as part of a broader accessibility
  commitment. Consider testing against WCAG 1.4.4 (Resize Text).

- **Panic button / app hiding on mobile:** A visible "hide app" mechanism —
  e.g. disguise Gabbro as a calculator or notes app, or a panic button that
  instantly locks and hides it. Relevant threat model: physical coercion or
  device inspection. Key questions: how does this interact with the existing
  auto-lock and wipe logic? Is disguise-as-another-app feasible on Android
  (custom launcher icon/label, yes; hiding from app drawer is limited) and iOS
  (more restricted)? Does offering this create a false sense of security?

- **Safe entry editing — confirmation and password history:** The edit
  action should use a recognisable affordance (pencil icon) and require
  an explicit confirmation step before saving, to prevent accidental
  overwrites. For password fields specifically, the previous value should
  be retained for a configurable window — either n days (e.g. 7, 30) or
  n vault unlocks (e.g. 5, 10) — so a user who saves a typo or a rejected
  new credential can recover without a support path. The retained value
  should be stored encrypted in the vault alongside the entry, never
  plaintext, and automatically purged once the retention window expires.
  Open questions: how many historical values to keep (probably 1 is enough
  for v1); whether the retention window is global or per-entry; whether
  history is shown in the UI or only accessible via an explicit "show
  previous password" action.

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

- **Responsive layout — mobile and desktop:** Flutter's layout system
  (flex widgets, `MediaQuery`, `LayoutBuilder`) handles most screen-size
  variation automatically, but deliberate decisions are still required.
  Avoid hardcoded pixel values in favour of relative sizing and
  constraints. The gap between a compact phone (~360dp wide) and a tablet
  or desktop window (~800dp+) may warrant distinct layouts for some
  screens — not just scaling, but restructuring (e.g. side panel on
  desktop, bottom nav on phone). Font size scaling (see Accessible font
  sizing above) and layout are coupled: a button that fits at Regular may
  overflow at Extra Large, so both must be tested together.

  Linux desktop requires particular attention: unlike Android, desktop
  windows are freely resizable. The app must be tested across a range of
  window sizes — from a narrow tiling WM column to a maximised widescreen
  window — before v1 ships. No extra dependencies needed; this is a
  testing discipline, not an architecture change. Reference: WCAG 1.4.4
  (Resize Text) applies here alongside the font sizing work.

- **Stale detail view after edit:** After editing an entry and saving,
  navigating back to `EntryDetailScreen` still shows the pre-edit content
  until the user returns to the list and re-taps the entry. Fix: pass the
  updated entry back to the detail screen after a successful save, or
  refresh the detail screen's state from the session on return from the
  edit screen. One approach: use `Navigator.pop(updatedEntry)` from
  `CreateEntryScreen` and have the detail screen await the push result
  and reload if non-null.

- **Clean up legacy vault on first launch:** When the app launches and no
  vault exists at the current app ID path (`app.gabbro.gabbro`), check for
  a vault at the old `com.example.gabbro` path and offer to migrate or delete
  it. Prevents silent accumulation of orphaned vault files on the user's device
  during development, and will matter for any user who installed a pre-rename
  build. Implement in `main.dart` during the vault existence check.

### Monetisation

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

### Trust & Transparency

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
