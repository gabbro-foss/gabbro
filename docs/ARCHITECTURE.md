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
- YubiKey / FIDO2 authentication: Android (USB + NFC via yubikit) and Linux (USB via libfido2) implemented; minimum-2-keys enforcement (ADR-010, VERSION 4 vault format) implemented; multi-key unlock, vault delete, and change_passphrase YubiKey wiring complete (CTAP2 one-tap any-key, hardware-validated on Linux + Android USB + Android NFC); manage YubiKeys screen pending
- Autofill save requests (`onSaveRequest`)
- Passkey support, breach alerts, vault sync

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | pending — run at session start | 8 |
| Flutter (`flutter test`) | 308 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 0 | 10 |

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`; cross-layer integration tests in `tests/` (not yet created — before v1).

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

- **Next task — add manage YubiKeys screen (add/remove keys)**
  - Accessible from Settings menu on `VaultListScreen`.
  - Allow adding a new YubiKey (up to max 4): register credential, update vault header with new `YubiKeyRecord`, require existing-key tap to authorise.
  - Allow removing a YubiKey: tap remaining key to authorise, update vault header.
  - Enforce minimum-2-keys invariant from ADR-010: cannot remove below 2 registered keys.
  - Both Linux (libfido2) and Android (yubikit) transports.


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

### Testing (pre-v1 gates)
- Cross-layer integration tests in `tests/` — bridge boundary not yet tested end-to-end.

### Features & UX
- `onboarding_screen.dart` — accessibility button (top-right) partially hidden behind "Welcome to Gabbro" headline on some screen sizes; fix layout so button is never obscured. **Priority: needed for accessibility.**
- Search improvement: currently only searches title, needs an option to also search all fields and notes
- Multiple vaults.
  - multiple vaults should not be listed on login screen -> allows better obfuscation and coercion resistance
    - add security toggle to show vault alias list on login screen or not if user wants to bypass this
  - remove add vault button from settings
  - add vault button on login screen that togggles to onboarding screen
  - add vault alias to name each vault (avoids collisions) -> update vault file entry
  - export vault includes alias in name to avoid collision
- Vault sync across devices (one-shot overwrite is v1 candidate; file-level sync warning is v1 candidate; entry-level merge is v2).
- Export vault to JSON - consistent with gabbro stance: we don't lock the user in. Include warning about user's responsibility with a decrypted vault file.
- Export/import security note: `.gabbro` exports are AES-256-GCM encrypted (passphrase-only — YubiKey not required to import, by design; passphrase is the durable recovery factor, YubiKey is the live-vault second factor). JSON exports are plaintext — no encryption at all. Add visible warnings in the export UI distinguishing the two: `.gabbro` ("protected by your passphrase only") and JSON ("completely unencrypted — store securely").
- Multiple app languages (v1: en,fr,de,it,es)
- `onboarding_screen.dart` — keyboard slides up when PIN field is focused during YubiKey vault creation, obscuring the step indicator card; fix so step indicator remains visible.
- App logo (OnboardingScreen, UnlockScreen) — defer until designed.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).
- `CHANGELOG.md` at project root; reset `pubspec.yaml` version to `0.1.0` before first public tag.
- Audit and standardise app version display: `pubspec.yaml` currently shows `1.0.0`, About screen must match; both must be reset to `0.1.0` before first public tag.
- Clean up legacy vault on first launch (`com.example.gabbro` → `app.gabbro.gabbro` migration offer).
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Dependency licence audit for About screen (`_kComponents`) against actual Cargo.toml + pubspec.yaml at release time.

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
