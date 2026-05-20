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
| Flutter (`flutter test`) | 291 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 0 | 4 |

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`; cross-layer integration tests in `tests/` (not yet created — before v1).

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

- **YubiKey session 5 COMPLETE: Change passphrase with YubiKey**
  - `change_passphrase_screen.dart`: added `vaultPath` (required) and `yubikeyRecords` (DI, null = auto-detect via `listVaultYubikeyRecords`); shows YubiKey info banner when vault is YubiKey-protected; same passphrase flow for both modes; no PIN field needed
  - `vault_list_screen.dart`: passes `vaultPath: widget.vaultPath` to `ChangePassphraseScreen`
  - **Key design decision:** No PIN field or extra YubiKey tap. `session_change_passphrase` (Rust) already caches the `hmac_secret` from unlock; CTAP2 hmac-secret is deterministic (same credential + salt → same bytes), so a second tap would return identical bytes — pure ceremony. The old passphrase check is the re-authentication factor.
  - Flutter tests: +2 new widget tests (YubiKey banner shown/not-shown)
  - Flutter: 287 passing (+2), Rust: 246 passing (unchanged), Android: 0 passing / 4 ignored (unchanged)

- **Previous sessions:**
  - Session 4b complete: Flutter UI for YubiKey vault create + unlock
  - Session 4a complete: Rust + bridge layer (`seal/open_vault_with_yubikey`, `YubikeyMaterial`, bridge functions)
  - Session 3 complete: `YubiKeyManager.kt` hardware-verified on Samsung S23 + YubiKey 5C
  - Session 2 complete: `rust/src/fido/` — libfido2 FFI, hardware-verified on Linux
  - Session 1 complete: vault format v2 `YubiKeyRecord`; `combine_yubikey` HKDF combiner

- **Pre-session-6 bikeshed cleanup (complete):**
  - `onboarding_screen.dart`: added "20–30 seconds" slow-vault warning container inside the YubiKey opt-in block
  - `unlock_screen.dart`: fixed landscape bug — replaced `Stack` + `Center` body with `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight)` so the Unlock button is reachable in short-height (landscape) viewports; `mainAxisSize: MainAxisSize.min` added to Column
  - YubiKey option in onboarding: already implemented (`SwitchListTile` defaults OFF, lets user choose); confirmed and removed from bikeshed
  - Flutter: 289 passing (+2), Rust: 246 (unchanged), Android: 0 / 4 ignored (unchanged)

- **YubiKey session 6 COMPLETE: Vault delete with YubiKey**
  - `vault_list_screen.dart`: added `yubikeyRecords` DI param (null = auto-detect via `listVaultYubikeyRecords` in `initState`); `_isYubikeyVault` getter; Step 1 delete dialog shows *"...and remove the YubiKey binding."* for YubiKey vaults
  - **Key design decision:** No PIN field or extra YubiKey tap — `deleteWholeVault` just deletes the file and drops the session; YubiKey material was already verified at unlock; same reasoning as session 5
  - Flutter tests: +2 new widget tests (YubiKey binding mention shown/not-shown)
  - Flutter: 291 passing (+2), Rust: 246 (unchanged), Android: 0 / 4 ignored (unchanged)

- **Pre-session-7 hardware testing + fixes (partially complete):**
  - Hardware test matrix blocks 1–11 passed on Samsung S23 (see below for block 12 status)
  - **Retry fix:** `get_hmac_secret` and `register_and_get_hmac` handlers in `MainActivity.kt` now retry once after 500ms — guards against transient USB enumeration races
  - **Card editing bug fixed:** `_hasChanges` missing `creditLimit`, `cardAccountNumber`, `paymentNetwork`, `notes` for Card → "No changes to save" on optional fields; `_buildFieldDiffs` missing `cardNumber` + same fields → no diff in review screen; both fixed (+4 regression tests)
  - Flutter: 295 passing (+4), Rust: 246 (unchanged), Android: 0 / 4 ignored (unchanged)

- **UNRESOLVED — YubiKey vault creation single-tap (blocks test A.1 and block 12)**

  **Symptom:** `CTAP error: action_timeout (0x3a)` from `registerAndGetHmac`. User taps once; YubiKey blinks a second time and times out.

  **Device:** Samsung S23, YubiKey 5C + 5A, firmware 5.4.3 (both). CTAP2.1-capable.

  **Root cause of earlier "passphrase-only login" report:** the 30s foreground lock timer was firing during the long CTAP2 operation, disposing `OnboardingScreen` and triggering an unhandled null-setState crash. The vault WAS being created correctly; the app was crashing after. Fixed (mounted guards + `_lock()` file guard).

  **Mitigation attempts (all failed on 5.4.3 hardware):**
  1. `up=false` on `getAssertions` — YubiKey ignored it, still prompted for touch
  2. Combined PIN token (`PIN_PERMISSION_MC or PIN_PERMISSION_GA`) + `up=false` — same `action_timeout`

  **Where the second blink comes from:** `registerAndGetHmac` does two CTAP2 operations: `makeCredential` (tap 1) then `getAssertions` (tap 2). All attempts to make `getAssertions` skip UP have failed, suggesting the YubiKey 5.4.3 firmware enforces UP for `getAssertions` regardless of `up=false` when the PIN token does not carry the UP flag (UP flag is only set in a pinUvAuthToken if UP was performed during token construction — PIN-only `getPinToken` does not set it on this firmware).

  **Proposed solutions for next session (in order of preference):**

  A. **Two-tap onboarding with clear UI (one-time only, simplest):** Keep `up=true` default, show explicit step UI: "Step 1 of 2 — tap YubiKey to register" → "Step 2 of 2 — tap again to activate". Unlock always remains one tap. This is the correct behaviour per the CTAP2 protocol.

  B. **Retrieve hmac-secret via getPinToken + UV-bearing token:** Investigate whether `getPinUvAuthTokenUsingUvWithPermissions` (built-in UV, not PIN) or `getPinUvAuthTokenUsingPinWithPermissions` with explicit UP option sets the UP flag in the token on this firmware. If UP flag is set in the token, `getAssertions` with `up=false` MUST be respected per CTAP2.1 spec.

  C. **Split registration from first hmac-secret fetch:** `makeCredential` (one tap) during onboarding → store credential ID; vault is created with a provisional key; on first unlock `getAssertions` (one tap, same as normal unlock) retrieves the real hmac-secret → vault re-sealed. Net: one tap per event, two total across two separate user interactions. Significant Rust+Kotlin+Dart change.

  **Recommendation:** Try option A first — it is honest about the protocol constraint and unblocks the rest of the test matrix immediately. Option B should be investigated in parallel with a logcat trace to confirm exactly which CTAP2 operation is generating the second blink.

- **Next: resolve YubiKey vault creation (options A/B/C above), then Session 7 — NFC support**

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
    5. Change passphrase with YubiKey ✓
    6. Vault delete with YubiKey ✓
    7. NFC support
- Multiple vaults.
  - multiple vaults should not be listed on login screen -> allows better obfuscation and coercion resistance
- Vault sync across devices (one-shot overwrite is v1 candidate; file-level sync warning is v1 candidate; entry-level merge is v2).
- Export vault to JSON - consistent with gabbro stance: we don't lock the user in. Include warning about user's responsibility with a decrypted vault file.
- Export/import security note: `.gabbro` exports are AES-256-GCM encrypted (passphrase-only — YubiKey not required to import, by design; passphrase is the durable recovery factor, YubiKey is the live-vault second factor). JSON exports are plaintext — no encryption at all. Add visible warnings in the export UI distinguishing the two: `.gabbro` ("protected by your passphrase only") and JSON ("completely unencrypted — store securely").
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
