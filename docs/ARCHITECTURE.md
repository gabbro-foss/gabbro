# Gabbro Architecture

## Project Overview

A post-quantum password manager built with security as core DNA.
Named after the intrusive igneous rock — hard, stable, enduring.
Cross-platform: Linux (Arch, Mint), Android, later iOS/Windows/macOS.
FOSS, GPL-3.0-only. Potential Yubico partnership.

**Core principle:** if it touches a secret, it lives in Rust. Everything else lives in Flutter. Secrets never cross the Flutter/Rust bridge in plaintext.

## General Information

**Tech stack:** Flutter (Dart) frontend, Rust backend/crypto, flutter_rust_bridge v2 (FFI).

**Encryption (at rest):** Argon2id KDF → X25519 + ML-KEM-1024 hybrid key exchange → HKDF-SHA256 combiner → AES-256-GCM. Post-quantum: belt and suspenders.

**Authentication (app access):** Mandatory FIDO2/WebAuthn hardware key (YubiKey). v1 uses Ed25519 (hardware constraint); target ML-DSA-44 once Yubico ships PQ-capable hardware (ADR-005). Min 2 keys (primary + backup), max 4. Biometric replaces passphrase entry only, never YubiKey tap. Auto-lock: 30s default, configurable.

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce, ML-KEM ciphertext, X25519 ephemeral pubkey) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, 5 languages: EN/FR/DE/ES/IT, EFF-style wordlists embedded at compile time). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text size, high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). v2: Windows, macOS, iOS.

**Versioning:** SemVer. Currently `1.0.0` in pubspec.yaml — must be reset to `0.1.0` before first public tag. `1.0` is a public trust commitment; don't ship it prematurely.

**Licence:** GPL-3.0-only (ADR-004). Play Store one-time payment is licence-compatible; F-Droid free build coexists without conflict.

**Version control:** private GitHub repo at https://github.com/Zabamund/gabbro. SSH auth. `chat_info/` is git-ignored.

## Project Structure

```
gabbro/
├── lib/                        # Flutter app
│   ├── main.dart
│   ├── screens/
│   │   ├── unlock_screen.dart
│   │   ├── export_screen.dart
│   │   ├── import_screen.dart
│   │   ├── csv_mapping_screen.dart
│   │   ├── change_passphrase_screen.dart
│   │   ├── about_screen.dart
│   │   ├── appearance_screen.dart
│   │   ├── generator_screen.dart
│   │   ├── security_screen.dart
│   │   ├── review_changes_screen.dart
│   │   ├── password_history_screen.dart
│   │   ├── alphabet_index_bar.dart
│   │   └── tablet_vault_layout.dart
│   ├── widgets/
│   │   ├── path_field.dart
│   │   ├── segmented_row.dart
│   │   ├── generator_widget.dart
│   │   └── password_breakdown_sheet.dart
│   └── src/rust/               # Auto-generated bridge (do not edit)
├── rust/
│   ├── src/
│   │   ├── api/                # Bridge surface exposed to Flutter
│   │   │   ├── simple.rs
│   │   │   ├── password_generator.rs
│   │   │   ├── passphrase_generator.rs
│   │   │   ├── vault.rs
│   │   │   ├── vault_bridge.rs
│   │   │   ├── import.rs
│   │   │   ├── autofill_bridge.rs
│   │   │   └── entropy.rs
│   │   ├── crypto/             # Internal crypto (not bridge-exposed)
│   │   │   ├── kdf.rs
│   │   │   ├── keypair.rs
│   │   │   ├── ml_kem.rs
│   │   │   ├── hkdf.rs
│   │   │   ├── aes_gcm.rs
│   │   │   └── vault_crypto.rs
│   │   ├── vault/              # Internal domain model
│   │   │   ├── entry.rs
│   │   │   ├── file_format.rs
│   │   │   ├── io.rs
│   │   │   └── session.rs
│   │   ├── import/
│   │   │   ├── enpass.rs
│   │   │   └── csv.rs
│   │   ├── serialization.rs
│   │   ├── bin/bench_kdf.rs
│   │   └── lib.rs
├── android/app/src/main/
│   └── kotlin/app/gabbro/gabbro/
│       ├── GabbroAutofillService.kt
│       ├── UnlockActivity.kt
│       └── RustBridge.kt
├── docs/
│   ├── ARCHITECTURE.md         # This file
│   ├── LEARNINGS.md
│   ├── AI_AUTHORSHIP_AND_IP.md
│   ├── artefacts/
│   └── decisions/              # ADR-001 through ADR-008
├── test/                       # Flutter unit/widget tests
├── integration_test/
└── README.md
```

## Features

**Implemented:**
- Vault create, unlock, lock, change passphrase
- 6 entry types: Login (Password), Note, Identity, Card, File, Custom
- Entry create, edit, delete with safe-edit diff review
- Password history with revert
- Fast fuzzy search, entry type filter chips
- Alphabet index bar (height-adaptive, windowed, left/right configurable)
- Tablet two-pane layout (≥600dp): NavigationRail + list pane + detail pane
- Password/passphrase generator (screen + inline widget)
- Password breakdown sheet (long-press revealed password; colour + symbol encoding per ADR-003)
- Export: `.gabbro` + `.gabbro.sha256`
- Import: Gabbro vault, Enpass JSON, Bitwarden JSON, generic CSV (with column-mapping UI)
  - All importers: validation failures surfaced via ImportFailuresDialog (Skip/Edit)
  - UUID dedup for Gabbro/Enpass/Bitwarden; fresh UUIDs for CSV
- Android autofill service (fill path; eTLD+1 domain matching; Chromium/Brave compatible)
- Appearance: theme (system/light/dark), text size, high-contrast, alphabet bar position
- Security: foreground + background lock timeouts
- Dark + light mode, WCAG AA colour scheme (olivine green `#5C7A3E`)

**Not yet implemented (see Bikeshed):**
- Folders, tags, favourites, configurable sort order
- YubiKey / FIDO2 authentication
- Screenshot prevention + app switcher blur
- Autofill save requests (`onSaveRequest`)
- Generator UI polish (entropy display, hidden by default, clipboard auto-clear)
- Passkey support, breach alerts, vault sync

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 198 | 1 |
| Flutter (`flutter test`) | 229 | 0 |

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`; cross-layer integration tests in `tests/` (not yet created — before v1).

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

- **Completed (13 May 2026):** Icons added to all popup menu items in `VaultListScreen` (Material Icons, `Expanded` text to prevent overflow); Delete vault icon + label styled with `colorScheme.error` (ADR-003 compliant, light + dark). `_kComponents` list in `about_screen.dart` sorted case-insensitively alphabetically. `vault_list_menu_test.dart` extended with icon presence and error colour tests (229 Flutter tests passing).

- **Next:** To be decided — generator UI polish, YubiKey design, or other backlog item.

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1 gates)
- AI-assisted security review of `rust/src/crypto/` and `rust/src/vault/` using Claude Opus before public release.
- Human expert cryptography review of `rust/src/crypto/` (ETH/EPFL academic outreach, RustCrypto maintainers, or formal audit).
- Supply-chain audit: `cargo audit`, `flutter pub audit`, IDE extension review, pin CI Actions to commit SHAs when CI is added.
- Verify Android storage permissions hold on Android 11+ (app-private storage + SAF — no `MANAGE_EXTERNAL_STORAGE`).
- Test on de-Googled Android (GrapheneOS/CalyxOS) before v1 — find a willing community tester, don't buy hardware.
- Block copy/paste on master passphrase fields (default: block; user toggle in Settings → Security).

### Testing (pre-v1 gates)
- Cross-layer integration tests in `tests/` — bridge boundary not yet tested end-to-end.

### Features & UX
- YubiKey / FIDO2 auth — design session first (ADR-005, Ed25519 v1 interim).
- Folders, tags, favourites, configurable sort order — design as a group in one session.
- Screenshot prevention + app switcher blur — `FLAG_SECURE` on Android; assess Linux separately.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).
- Generator UI: entropy display, password hidden by default, clipboard auto-clear (60s), exclude ambiguous chars, remember last settings.
- File picker for all export paths (audit for consistency).
- `CHANGELOG.md` at project root; reset `pubspec.yaml` version to `0.1.0` before first public tag.
- Clean up legacy vault on first launch (`com.example.gabbro` → `app.gabbro.gabbro` migration offer).
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Responsive layout testing on Linux desktop across window sizes (tiling WM column → maximised widescreen); test with all text sizes.
- Dependency licence audit for About screen (`_kComponents`) against actual Cargo.toml + pubspec.yaml at release time.

### Code Quality
- Dependency surface audit: remove any crate that can be replaced with `std` before v1 (`cargo tree`).

### V2+ / Defer
- Vault sync across devices (one-shot overwrite is v1 candidate; file-level sync warning is v1 candidate; entry-level merge is v2).
- Multiple vaults.
- Passkey support (`PasskeyEntry`).
- Data breach alerts / HaveIBeenPwned integration.
- Coercion resistance / duress / decoy vault.
- Panic button / app hiding on mobile.
- Remote app / vault deletion.
- Non-ASCII wordlists (CJK) for passphrase generator.
- Custom and hideable filter chips (post-v1 user feedback gate).
- Tablet list pane width: draggable divider option.
- Draggable divider for tablet list pane width.
- App logo (OnboardingScreen, UnlockScreen) — defer until designed.
- iOS, Windows, macOS support.
- Yubico partnership.
- Destination Linux podcast outreach (when approaching public release).
- Donation/sustainability model (GitHub Sponsors + Liberapay + Monero — dedicated session near release).
- `docs/SECURITY.md` user-facing doc (encryption ELI5, local-first argument, comparison table, honest caveats).
- No-telemetry verification guide (ripgrep scan, Wireshark, NetGuard, iOS caveat).
- Support model (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).
- i18n: replace hand-rolled month array in `formatTimestamp()` with `package:intl` `DateFormat`.
- Import: content-hash deduplication and entry-level merge.
- Native app autofill matching by package name (v2).
