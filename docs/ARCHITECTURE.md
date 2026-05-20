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
- Export: `.gabbro` + `.gabbro.sha256`; file entry export uses native file picker (folder picker on Android, save dialog on Linux)
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

**Not yet implemented (see Bikeshed):**
- YubiKey / FIDO2 authentication
- Autofill save requests (`onSaveRequest`)
- Passkey support, breach alerts, vault sync

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 246 | 3 |
| Flutter (`flutter test`) | 285 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 0 | 4 |

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`; cross-layer integration tests in `tests/` (not yet created — before v1).

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

- **YubiKey session 4b COMPLETE: Flutter UI for YubiKey vault create + unlock**
  - `unlock_screen.dart`: auto-detects YubiKey records from vault header in `initState`; switches to YubiKey mode (PIN field + "Insert your YubiKey" instruction) when records are present; DI via `yubikeyRecords` (null = auto-detect) and `onUnlockWithYubikey` callbacks; passphrase-only mode unchanged
  - `onboarding_screen.dart`: Android-gated YubiKey opt-in section (SwitchListTile + PIN field + instruction); `isAndroid` DI param (default `Platform.isAndroid`) for testability; `onInitVaultWithYubikey` DI callback; branches `_createVault()` on `_useYubikey` flag
  - `YubiKeyManager.kt`: added `registerAndGetHmac` — does `makeCredential` + `getAssertions` in a single YubiKey connection (single tap for onboarding registration)
  - `MainActivity.kt`: renamed channel `yubikey_test` → `yubikey`; added `register_and_get_hmac` handler returning `{credentialId, hmacSecret}` map
  - `YubiKeyManagerTest.kt`: added ignored hardware test for `registerAndGetHmac`
  - Bridge codegen: ran `flutter_rust_bridge_codegen generate` to expose `listVaultYubikeyRecords`, `unlockVaultWithYubikey`, `initVaultWithYubikey`, `YubikeyRecordData` to Dart
  - **Key design decisions:** single YubiKey tap for onboarding (`registerAndGetHmac` in one connection); YubiKey mode detected at screen init (sync, graceful fallback to passphrase-only); autofill unlock left passphrase-only (autofill runs in `UnlockActivity`, not `MainActivity` — YubiKey MethodChannel not wired there; deferred); Linux FIDO2 UI deferred (separate session); hex helpers duplicated in each screen file (no premature shared utility)
  - Flutter tests: +8 new widget tests (4 unlock, 4 onboarding); `tester.runAsync` used for the onboarding vault-creation test (real file I/O via `File.parent.create` doesn't settle through `pump()` alone)
  - Flutter: 285 passing (+8), Rust: 246 passing (unchanged), Android: 0 passing / 4 ignored (+1)

- **Previous sessions:**
  - Session 4a complete: Rust + bridge layer (`seal/open_vault_with_yubikey`, `YubikeyMaterial`, bridge functions)
  - Session 3 complete: `YubiKeyManager.kt` hardware-verified on Samsung S23 + YubiKey 5C
  - Session 2 complete: `rust/src/fido/` — libfido2 FFI, hardware-verified on Linux
  - Session 1 complete: vault format v2 `YubiKeyRecord`; `combine_yubikey` HKDF combiner

- **Next: Session 5 — Change passphrase with YubiKey**
  - `change_passphrase_screen.dart`: detect YubiKey vault, add PIN field, call YubiKey-aware change-passphrase bridge function
  - Session 6: Vault delete with YubiKey
  - Session 7: NFC support

  **Build environment notes (critical for Android sessions):**
  - System Java is 26.0.1 — incompatible with Kotlin compiler. Fix: `org.gradle.java.home=/opt/android-studio/jbr` in `android/gradle.properties` (points to Java 21).
  - AGP pinned to 8.9.1 in `android/settings.gradle.kts` (8.7.0 too old for transitive deps; 8.11+ breaks Flutter's `compileSdkVersion` string API).
  - `libfido2-sys` and `pub mod fido` are gated behind `cfg(not(target_os = "android"))` — libfido2 is Linux-only; Android uses yubikit-android via Kotlin.
  - yubikit-android 3.1.0: use `Ctap2Session` (raw CTAP2) not `Ctap2Client` (WebAuthn wrapper). `Ctap2Client` enforces WebAuthn domain validation — rejects `"app.gabbro.gabbro"` as RP ID. `Ctap2Session` has no such restriction.
  - USB transport: `UsbFidoConnection` (HID interface), not `SmartCardConnection` (CCID). FIDO2 over USB uses HID.
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

### Testing (pre-v1 gates)
- Cross-layer integration tests in `tests/` — bridge boundary not yet tested end-to-end.

### Features & UX
- YubiKey / FIDO2 authentication:
  - Design complete: ADR-010 documents the hmac-secret mechanism
  - Implementation progress:
    1. Vault format extension + HKDF combiner (pure Rust) ✓
    2. Linux libfido2 binding (Rust FFI) ✓
    3. Android yubikit-android integration (Kotlin) ✓
    4a. Rust + bridge: `seal/open_vault_with_yubikey`, `YubikeyMaterial` session, all bridge functions ✓
    4b. Flutter UI: unlock screen YubiKey detect/prompt, onboarding YubiKey opt-in ✓
    5. Change passphrase with YubiKey
    6. Vault delete with YubiKey
    7. NFC support
- Multiple vaults.
- Vault sync across devices (one-shot overwrite is v1 candidate; file-level sync warning is v1 candidate; entry-level merge is v2).
- Export vault to JSON - consistent with gabbro stance: we don't lock the user in. Include warning about user's responsibility with a decrypted vault file.
- Search improvement: currently only searches title, needs an option to also search all fields and notes
- Multiple app languages (v1: en,fr,de,it,es)
- App logo (OnboardingScreen, UnlockScreen) — defer until designed.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).
- `CHANGELOG.md` at project root; reset `pubspec.yaml` version to `0.1.0` before first public tag.
- Audit and standardise app version display: `pubspec.yaml` currently shows `1.0.0`, About screen must match; both must be reset to `0.1.0` before first public tag.
- Clean up legacy vault on first launch (`com.example.gabbro` → `app.gabbro.gabbro` migration offer).
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Dependency licence audit for About screen (`_kComponents`) against actual Cargo.toml + pubspec.yaml at release time.
- Bug noticed: an v1 vault cannot be opened once the app is updated to v2 vault - not an issue now so probably YAGNI

### Code Quality
- Dependency surface audit: remove any crate that can be replaced with `std` before v1 (`cargo tree`).

### V2+ / Defer
- Data breach alerts / HaveIBeenPwned integration.
- Coercion resistance / duress / decoy vault. -Y fixed by multiple vaults, onus on the user to use this feature
- Panic button / app hiding on mobile.
- Remote app / vault deletion.
- Non-ASCII wordlists (CJK) for passphrase generator.
- Custom and hideable filter chips (post-v1 user feedback gate).
- Tablet list pane width: draggable divider option.
- Draggable divider for tablet list pane width.
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
