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
│           │   └── simple.dart
│           ├── frb_generated.dart
│           ├── frb_generated.io.dart
│           └── frb_generated.web.dart
├── rust/                       # Rust crate (all crypto and secrets live here)
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       ├── api/                # Bridge API surface exposed to Flutter
│       │   ├── mod.rs
│       │   └── simple.rs
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
- Two modes: classic password and wordlist-based passphrase
- Colour coded display with symbol markers — character types are
  distinguished by **both colour and symbol** (never colour alone),
  ensuring accessibility for colour-blind users — see ADR-003
- Default palette is colour-blind-friendly (avoids pure red/green
  confusion); user-overridable via colour picker in settings
- Hidden by default, show/hide toggle
- Entropy display (bits)
- Exclude ambiguous characters option (0, O, l, 1, I)
- EFF wordlist for passphrase mode
- All generation happens in Rust
- Accessible from main screen and inline within entry editor
- Remembers user's last settings
- Clipboard auto-clear after 60 seconds

## Vault Storage & Sync
- v1: local path only, chosen during onboarding
- Sync is user's responsibility via export/import
- Export always encrypted, never plaintext
- Export produces two files: `<name>.gabbro` (encrypted vault) and
  `<name>.gabbro.sha256` (detached SHA-256 hash of the whole file)
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

## Testing Strategy
- Rust: native test framework, unit + integration tests
- Flutter: unit and widget tests in `test/`, integration tests in `integration_test/`
- Cross-layer: integration tests in `tests/`
- TDD from day one — untested code is broken code

## Platforms
- v1: Linux (Arch + Mint/deb), Android (F-Droid)
- v2 (future): Windows, macOS, iOS

## Licence

GPL-3.0-only — see ADR-004 for full reasoning.
SPDX identifier: `GPL-3.0-only`

## Monetization (future)
- Freemium model TBD
- Yubico partnership target
- Advanced features (e.g. advanced tags) as premium tier
