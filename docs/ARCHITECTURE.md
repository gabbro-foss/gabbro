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

**YubiKey NFC prerequisite — NDEF OTP:** YubiKeys ship with OTP slot 1 configured as an NDEF URI (`https://my.yubico.com/yk/...`). When the Android NFC reader is active, the key broadcasts this URI and Android opens a browser tab — even foreground-dispatch and manifest intent-filter mitigations cannot suppress it, because yubikit's `enableReaderMode` owns the NFC stack. **Workaround (one-time, per key):** run `ykman config nfc --disable OTP`. This disables the OTP application over NFC only; FIDO2/CTAP2 over NFC and all USB functions are unaffected. See LEARNINGS.md for full collateral-effects analysis.

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce, ML-KEM ciphertext, X25519 ephemeral pubkey) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, 5 languages: EN/FR/DE/ES/IT, EFF-style wordlists embedded at compile time). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text size, high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). v2: Windows, macOS, iOS.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html). `pubspec.yaml` is `0.1.0+1`. `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

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
│   │   ├── tablet_vault_layout.dart
│   │   └── manage_folders_screen.dart
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
│   │   │   ├── fido_bridge.rs      # Linux FIDO2 bridge (fido_list_devices, fido_register, fido_get_hmac_secret)
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
│   │   │   ├── serialization.rs
│   │   │   └── session.rs
│   │   ├── fido/               # FIDO2/libfido2 FFI binding
│   │   │   ├── mod.rs
│   │   │   └── device.rs
│   │   ├── import/
│   │   │   ├── enpass.rs
│   │   │   └── csv.rs
│   │   ├── bin/bench_kdf.rs
│   │   └── lib.rs
├── android/app/src/main/
│   └── kotlin/app/gabbro/gabbro/
│       ├── GabbroAutofillService.kt
│       ├── UnlockActivity.kt
│       ├── RustBridge.kt
│       └── YubiKeyManager.kt      # USB FIDO2 hmac-secret (register + getHmacSecret)
├── android/app/src/test/
│   └── kotlin/app/gabbro/gabbro/
│       └── YubiKeyManagerTest.kt
├── docs/
│   ├── ARCHITECTURE.md         # This file
│   ├── LEARNINGS.md
│   ├── AI_AUTHORSHIP_AND_IP.md
│   ├── artefacts/
│   └── decisions/              # ADR documents
├── test/                       # Flutter unit/widget tests
├── integration_test/
├── CHANGELOG.md
└── README.md
```

## Features

**Implemented:**
- Vault create, unlock, lock, change passphrase
- 6 entry types: Login (Password), Note, Identity, Card, File, Custom
- Entry create, edit, delete with safe-edit diff review
- Password history with revert
- Vault list search: title-only (default) or full-field toggle (`Icons.search` / `Icons.manage_search` prefix button); full-field searches username, URL, notes, custom field labels/values (non-hidden) via `search_blob` built in Rust at list time
- Alphabet index bar (height-adaptive, windowed, left/right configurable)
- Tablet two-pane layout (≥600dp): NavigationRail + list pane + detail pane
- Password/passphrase generator (screen + inline widget)
- Password breakdown sheet (long-press revealed password; colour + symbol encoding per ADR-003)
- Export: `.gabbro` + `.gabbro.sha256`; JSON (plaintext) with prominent unencrypted warning and format selector; file entry export uses native file picker (folder picker on Android, save dialog on Linux)
- Import: Gabbro vault, Enpass JSON, Bitwarden JSON, generic CSV (with column-mapping UI)
  - All importers: validation failures surfaced via ImportFailuresDialog (Skip/Edit)
  - UUID dedup for Gabbro/Enpass/Bitwarden; fresh UUIDs for CSV
- Android autofill service (fill path; eTLD+1 domain matching; Chromium/Brave compatible)
- Folder display in entry detail (alongside timestamps; shows "None" when unfoldered)
- Folder filter dropdown on vault list screen (independent of type filter chips; unfoldered entries hidden when a folder is active)
- Folder picker on CreateEntryScreen and EntryDetailScreen (injected `listFolders` DI pattern; edit mode pre-selects existing folder)
- Manage folders screen: add, rename, delete folders; delete offers reassign to another folder or clear to "None"; accessible from settings menu
- Multi-select assign to folder: select entries in vault list, assign all to a folder in one operation
- Folder changes shown in review screen diff (all entry types)
- Enpass import: entries correctly land in "None" folder (category name was incorrectly used as folder name)
- Appearance: theme (system/light/dark), text size, high-contrast, alphabet bar position
- Security: foreground + background lock timeouts
- Android screenshot prevention + app switcher blur (`FLAG_SECURE` on `MainActivity` and `UnlockActivity`)
- Copy/paste blocking on master passphrase fields (default on; user toggle in Settings → Security; keyboard inline paste is a platform limitation, documented in UI)
- Dark + light mode, WCAG AA colour scheme (olivine green `#5C7A3E`)
- YubiKey / FIDO2 authentication: Android (USB + NFC via yubikit) and Linux (USB via libfido2); minimum-2-keys enforcement (ADR-010, VERSION 4 vault format); multi-key unlock, vault delete, and change_passphrase YubiKey wiring (CTAP2 one-tap any-key); manage YubiKeys screen (add, remove, alias edit); hardware-validated on Linux and Android (USB + NFC)

**Not yet implemented (see Bikeshed):**
- Autofill save requests (`onSaveRequest`)
- Passkey support, breach alerts, vault sync

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 330 | 8 |
| Flutter (`flutter test`) | 340 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 0 | 10 |

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`. Cross-layer integration tests deferred (see V2+/YAGNI note in Bikeshed).

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Multiple Vaults — implementation ready (plan approved, ~3–4 sessions)

**Agreed design decisions:**
- One vault active at a time (lock → switch → unlock). No Rust session refactor.
- Alias stored in the `.gabbro` plaintext header (VERSION 5 format bump). Also kept in Flutter registry. Alias travels with the file.
- Login screen shows last-used vault + discreet "switch" link (coercion mode is the default — vault list hidden).
- Android: numbered app-storage paths (`gabbro_2.gabbro`, `gabbro_3.gabbro` …).
- Must ship before app languages and before cross-layer integration tests.

---

#### Phase 1 — Rust: VERSION 5 format + alias bridge

Files: `rust/src/vault/file_format.rs`, `rust/src/vault/io.rs`, `rust/src/api/vault_bridge.rs`

- `file_format.rs`: add `VERSION_5 = 5`; extend header write/read: after YubiKey records, before `passphrase_blob`, write `alias_len: u16` + UTF-8 alias bytes (0 = no alias). VERSION 4 read path → alias = `None`.
- `io.rs`: add `read_vault_header(path) -> Result<VaultHeader, VaultError>` — reads alias + YubiKey records without decrypting.
- `vault_bridge.rs`:
  - New DTO: `VaultHeaderData { alias: Option<String>, yubikey_records: Vec<YubikeyRecordData> }`
  - New bridge fn: `read_vault_header(path: String) -> Result<VaultHeaderData, String>`
  - `init_vault`, `init_vault_with_yubikey`, `init_vault_with_keys`: add `alias: Option<String>` param
  - `set_vault_alias(path: String, alias: String) -> Result<(), String>`: patch alias field in header in-place
- TDD: VERSION 5 round-trip; VERSION 4 backward compat; `set_vault_alias` leaves ciphertext intact.

#### Phase 2 — Flutter: VaultRegistry + settings migration

Files: `lib/vault_registry.dart` (new), `lib/settings.dart`

- New `lib/vault_registry.dart`: `VaultRecord { path, alias, lastUsedAt }` + `VaultRegistry` with `load()`, `save()`, `add()`, `remove()`, `updateAlias()`, `touchLastUsed()`, `lastUsed` getter.
- Storage: same directory as `settings.jsonc` → `vaults.jsonc`.
- Migration (one-time in `load()`): if `vaults.jsonc` absent AND `gabbro.gabbro` exists → create registry with one entry `{path: gabbro.gabbro, alias: "Gabbro"}`.
- `lib/settings.dart`: add `showVaultList: bool` (default `false`) to `AppSettings`.
- TDD: load/save round-trip; migration; empty state; `lastUsed` ordering.

#### Phase 3 — Flutter: Login + vault switching UI

Files: `lib/main.dart`, `lib/screens/unlock_screen.dart`, `lib/screens/vault_selector_screen.dart` (new), `lib/screens/onboarding_screen.dart`, `lib/screens/security_screen.dart`

- `main.dart`: load `VaultRegistry` at startup; route to `OnboardingScreen` if empty, else `UnlockScreen` with `lastUsed` vault.
- `unlock_screen.dart`: show vault alias below app title; discreet "switch" icon in AppBar; replace `list_vault_yubikey_records` call with `read_vault_header` (returns alias + YubiKey records in one call).
- `vault_selector_screen.dart` (new): if `showVaultList == true` shows alias list; always shows "Add vault" button → `OnboardingScreen`; allows removing from registry (no file delete); each vault row has an edit (pencil) icon that opens an inline rename dialog — pre-filled with current alias, empty-alias guard, calls `set_vault_alias` bridge then `VaultRegistry.updateAlias()`.
- `onboarding_screen.dart`: add required alias text field; after creation call `VaultRegistry.add()`; Android path generation scans registry for first unused numbered path; pass alias to `init_vault*` bridge calls.
- `security_screen.dart`: add "Show vault list on login" toggle (`showVaultList`).
- TDD: `VaultSelectorScreen` list shown/hidden; `UnlockScreen` alias + switch link; `OnboardingScreen` alias field + empty-alias guard; rename dialog pre-fills alias, rejects empty input, updates registry and bridge.

#### Phase 4 — Export + Android autofill

Files: `lib/screens/export_screen.dart`, `android/.../GabbroAutofillService.kt`, `android/.../UnlockActivity.kt`

- Export default filename: `{alias}_YYYY-MM-DD.gabbro` (sanitise alias: spaces → `_`, strip non-alphanum except `-_`).
- Autofill service + UnlockActivity: read last-used vault path from registry (or via shared preferences set by Flutter on unlock) instead of hardcoded path.

---

#### Hardware test checklist (after all phases)
1. Existing vault migrates into registry on first launch; alias "Gabbro"; unlocks normally.
2. Create second vault with alias "Work" → lands in registry; can unlock it.
3. Switch vaults: lock "Work", switch to "Gabbro", unlock.
4. Rename alias via `set_vault_alias`; new alias shown on unlock screen.
5. `showVaultList = false` (default): switch link present but list hidden.
6. `showVaultList = true`: list shown in selector.
7. Export filename contains alias.
8. Open VERSION 4 vault on VERSION 5 build: unlocks; alias shows registry fallback.

---

## Build Environment

**Critical notes — read before Android or Kotlin sessions.**

- System Java is 26.0.1 — incompatible with Kotlin compiler. Fix: `org.gradle.java.home=/opt/android-studio/jbr` in `android/gradle.properties` (points to Java 21).
- AGP 8.11.1 in `android/settings.gradle.kts`. Java and Kotlin JVM target both set to 21 in `app/build.gradle.kts`.
- `libfido2-sys` and `pub mod fido` are gated behind `cfg(not(target_os = "android"))` — libfido2 is Linux-only; Android uses yubikit-android via Kotlin.
- yubikit-android 3.1.0: use `Ctap2Session` (raw CTAP2) not `Ctap2Client` (WebAuthn wrapper). `Ctap2Client` enforces WebAuthn domain validation — rejects `"app.gabbro.gabbro"` as RP ID. `Ctap2Session` has no such restriction.
- `Ctap2Session` has no unified `YubiKeyConnection` constructor — use the `ctap2Session()` private helper in `YubiKeyManager` which dispatches on `SmartCardConnection` (NFC) vs `FidoConnection` (USB HID).
- USB transport: `UsbFidoConnection` (HID interface). NFC transport: `SmartCardConnection` (ISO 7816). Both produce a `YubiKeyConnection` usable with `ctap2Session()`.
- RP ID `"app.gabbro.gabbro"` is correct at CTAP2 level — it is just an identifier string, no domain required.

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1 gates)
- AI-assisted security review of `rust/src/crypto/` and `rust/src/vault/` using Claude Opus before public release.
- Human expert cryptography review of `rust/src/crypto/` (ETH/EPFL academic outreach, RustCrypto maintainers, or formal audit).
- Supply-chain audit: `cargo audit`, `flutter pub audit`, IDE extension review, pin CI Actions to commit SHAs when CI is added.
- Verify Android storage permissions hold on Android 11+ (app-private storage + SAF — no `MANAGE_EXTERNAL_STORAGE`).
- Test on de-Googled Android (GrapheneOS/CalyxOS) before v1 — find a willing community tester, don't buy hardware.
- test/measure code test coverage before launch
- read https://drive.proton.me/urls/11VHB59C60#CVCj696Qxkxd to see if any learnings can be transferred to gabbro to increase security

### Features & UX
- Multiple app languages (v1: en,fr,de,it,es) — after Multiple Vaults.
- App logo (OnboardingScreen, UnlockScreen) — defer until designed.
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).
- Dependency licence audit for About screen (`_kComponents`) against actual Cargo.toml + pubspec.yaml at release time.

### Code Quality
- Dependency surface audit: remove any crate that can be replaced with `std` before v1 (`cargo tree`).
- fix: `14 packages have newer versions incompatible with dependency constraints.
Try `dart pub outdated` for more information.`

### V2+ / Defer
- Data breach alerts / HaveIBeenPwned integration.
- Panic button / app hiding on mobile.
- Remote app / vault deletion.
- Non-ASCII wordlists (CJK) for passphrase generator.
- Custom and hideable filter chips (post-v1 user feedback gate).
- Tablet list pane width: draggable divider.
- Cross-layer integration tests (`integration_test/` + Rust `tests/` crate). YAGNI: if users file bugs, those become the organic integration test suite.
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
- ensure no webpage opens with yubico OTP enabled in `ykman info`