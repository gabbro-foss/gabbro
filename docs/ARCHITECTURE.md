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
│       │   ├── passphrase_generator.rs
│       │   └── vault.rs        # Vault entry API — DTOs and create_* functions
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
│       │   └── entry.rs        # All 6 entry types and EntryMeta
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
- **Status:** `LoginEntry` and `NoteEntry` implemented in `rust/src/api/vault.rs`,
  6 unit tests passing. 31 Rust tests total across the project.
- Lives in `rust/src/api/vault.rs` — the bridge boundary between Flutter and
  the internal vault domain model.
- **Pattern:** each entry type gets a bridge-facing DTO (`LoginEntryData`,
  `NoteEntryData`, etc.) using only bridge-friendly types (`String`, `Vec`,
  `bool`, `Option<String>`), and a `create_*` function that generates a UUID,
  timestamps, builds the internal type, then converts to the DTO.
- **UUID generation:** uses the `uuid` crate (v1.23.0) with the `v4` feature
  (random UUIDs). Added to `Cargo.toml` this session.
- **Timestamps:** generated in Rust using `std::time` only — no `chrono`
  dependency. Format: ISO 8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`).
- **Remaining entry types to implement:** Identity, Card, File, Custom.
  Identity and Card are next — Card will reuse the `CardEntry::new()`
  validated constructor from the domain model.
- **DTO pattern:** internal domain types never cross the bridge directly.
  Flutter calls `create_login_entry(...)` and receives a `LoginEntryData` —
  it never constructs or holds a `LoginEntry`.

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

- **Next task:** wire the crypto stack into the vault file format —
  implement the `.gabbro` file header (serialization/deserialization
  of `SealedVault` fields to/from bytes), then write the first
  end-to-end vault file write and read test.
- **Test count:** 77 Rust tests passing across the project.

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


### Features & UX

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


### Monetisation

- **GPL-3.0 monetisation model TBD** — ideas include a Yubico partnership
  and a Play Store one-time payment. Needs a dedicated design session;
  must be compatible with GPL-3.0-only licence obligations. See the
  Monetization section above for current high-level thinking.
- Also see [updated monetisation ideas](#trust--transparency)

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