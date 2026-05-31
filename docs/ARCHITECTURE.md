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

**YubiKey NFC / NDEF OTP:** YubiKeys ship with OTP slot 1 as an NDEF URI over NFC (`https://my.yubico.com/yk/...`). Without mitigation, Android opens a browser tab when the key is tapped. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` (prevents NDEF being read during the CTAP2 session) and by re-arming foreground dispatch after `stopNfcDiscovery` (routes any post-session NDEF intents to `onNewIntent` rather than the browser). OTP slot 1 may remain enabled — no `ykman` workaround is needed. See LEARNINGS.md for the full diagnosis and collateral-effects table.

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
│   │   ├── manage_vaults_screen.dart
│   │   ├── export_screen.dart
│   │   ├── import_screen.dart
│   │   ├── csv_mapping_screen.dart
│   │   ├── change_passphrase_screen.dart
│   │   ├── about_screen.dart
│   │   ├── appearance_screen.dart
│   │   ├── language_screen.dart
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
│   │   ├── gabbro_logo.dart
│   │   └── password_breakdown_sheet.dart
│   ├── settings.dart
│   ├── vault_registry.dart
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
│   ├── AI_SECURITY_AUDIT.md    # AI-assisted security review (2026-05-31)
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
- Language: dedicated Language screen (Settings menu); language picker button on OnboardingScreen for first-time users; RadioGroup-based list (System / EN / FR / DE / IT / ES)
- Security: foreground + background lock timeouts
- Android screenshot prevention + app switcher blur (`FLAG_SECURE` on `MainActivity` and `UnlockActivity`)
- Copy/paste blocking on master passphrase fields (default on; user toggle in Settings → Security; keyboard inline paste is a platform limitation, documented in UI)
- Dark + light mode, WCAG AA colour scheme (olivine green `#5C7A3E`)
- YubiKey / FIDO2 authentication: Android (USB + NFC via yubikit) and Linux (USB via libfido2); minimum-2-keys enforcement (ADR-010, VERSION 4 vault format); multi-key unlock, vault delete, and change_passphrase YubiKey wiring (CTAP2 one-tap any-key); manage YubiKeys screen (add, remove, alias edit); hardware-validated on Linux and Android (USB + NFC)
- Multiple vaults: registry (`vaults.jsonc`); alias + `VaultType` (`passphrase` | `yubikey`) stored per record (backward-compatible, defaults to `passphrase`); alias stored in VERSION 5 vault header; ManageVaultsScreen (add/rename/delete); delete is a 3-step flow for YubiKey-secured vaults (warning → type DELETE → PIN + YubiKey tap authorization); passphrase vaults use 2-step delete; Cancel always enabled at all steps; "Delete vault" removed from VaultListScreen settings menu — ManageVaultsScreen is the single delete point; `showVaultList=true` shows inline vault dropdown on login screen; `showVaultList=false` (default, high-security) shows only last-used vault with no switch UI; vault CRUD accessible post-authentication via Menu → Manage vaults
- PIN visibility toggle (eye icon) on all YubiKey PIN fields
- `GabbroLogo` widget: theme-aware PNG asset selection (dark/light/hc × icon-only/with-text); wired into UnlockScreen, OnboardingScreen, AboutScreen, and Android splash (`launch_background.xml`)
- Android launcher icons: square transparent-background PNGs at all mipmap densities (mdpi→xxxhdpi), generated from `assets/images/source/ic_launcher_light.svg` via `rsvg-convert`

**Not yet implemented (see Bikeshed):**
- Autofill save requests (`onSaveRequest`)
- Passkey support, breach alerts, vault sync

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 338 | 8 |
| Flutter (`flutter test`) | 450 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 0 | 10 |

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`. Cross-layer integration tests deferred (see V2+/YAGNI note in Bikeshed).

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task: implement remediations from `docs/AI_SECURITY_AUDIT.md`

The AI security review (Claude Opus 4.7, 2026-05-31) identified 10 findings across `rust/src/crypto/` and `rust/src/vault/` — all rated Low or Info, none exploitable under the in-scope threat model. Plus 6 cross-cutting lessons drawn from the Recurity Labs Proton Pass audit (526.2501). Remediation is split into two rounds by file-format impact.

**Model selection (self-check before coding — switch via `/model` if mismatched):**

- **Round 1 (F-04, F-06, F-07, F-08, F-09):** Sonnet 4.6 is fine. Mechanical changes with clear pass/fail criteria; strict TDD covers the F-08 atomic-write footgun.
- **Round 2 F-01 (AES-GCM AAD over header):** Sonnet 4.6 acceptable with TDD-first — write `tampered_<field>_fails_to_open` tests before plumbing AAD.
- **Round 2 F-02 (FIPS 203 ML-KEM KeyGen alignment):** prefer **Opus 4.7**, or defer until after the human crypto review. Wrong KeyGen produces silently-different keypairs from the same passphrase; no unit test catches this without FIPS test vectors.
- **Round 2 F-03 (X-Wing combiner):** defer to the human crypto review — implementing pre-emptively risks re-work.
- **Recommended order:** ship Round 1 now; hold Round 2 until after the academic / RustCrypto pre-v1 gate clears, because the reviewer's opinion may change the spec.

**Round 1 — non-breaking hygiene (no `.gabbro` VERSION bump):**

- **F-04** Memory hygiene typing — change `VaultSession.passphrase` to `Zeroizing<Vec<u8>>` and `YubikeyMaterial.hmac_secret` to `Zeroizing<[u8; 32]>` so abnormal-exit paths still zeroize (panics, SIGKILL, OOM kill). `vault_key_master` and `wrapping_key` are already correctly typed — match them.
- **F-06** Replace the three bounded `.unwrap()` calls in `rust/src/crypto/vault_crypto.rs` (lines 423, 440, 592) with `.expect("length checked above")` to satisfy the CLAUDE.md "no `unwrap()` in non-test code" rule.
- **F-07** Fix doc-comment drift in `rust/src/crypto/kdf.rs:33-37` — describe what the implementation actually does (32-byte seed via `StdRng`, bytes [64..96] reserved/unused).
- **F-08** Atomic 0600-mode writes — replace bare `fs::write` in `rust/src/vault/io.rs:20`, `rust/src/api/vault.rs:815,836`, and `rust/src/vault/session.rs:696` with an `OpenOptions { mode: 0o600 }` + temp-file + atomic rename pattern (unix-only `cfg`; Windows path keeps `fs::write`).
- **F-09** Symlink validation — call `std::fs::symlink_metadata` before opening a vault path for read or write; refuse with a clear error when `.is_symlink()`.

**Round 2 — design-level (may require `.gabbro` file-format bump to VERSION 6):**

- **F-01** Bind the plaintext `.gabbro` header to the AES-GCM auth tag via AAD. Pass the serialised header (everything before the body length prefix) as AAD to `aes_gcm::encrypt` / `decrypt`. Detects tampering with `alias`, YubiKey `credential_id`, and any other plaintext metadata. **VERSION 6 bump** with read-only backward compat for VERSION 2–5.
- **F-02** Align ML-KEM-1024 KeyGen with FIPS 203 — use `(d, z) ∈ {0,1}^256 × {0,1}^256` directly from KDF bytes `[32..64]` and `[64..96]`, removing the `StdRng` indirection and the dead-bytes range. Requires verifying that `ml-kem` 0.3.x exposes a path to `KeyGen(d, z)`; otherwise stay on the PRNG path but shorten the KDF output to 64 bytes and document the deviation. **Changes derived keypair under same passphrase** → either gated behind VERSION 6 with old vaults still readable via the legacy path, or one-shot migrate-on-open.
- **F-03** Hybrid combiner — discuss with the human cryptographer (pre-v1 gate) whether to migrate to an X-Wing-style transcript-binding combiner (`ikm = ml_kem_ss ∥ x25519_ss ∥ ml_kem_ct ∥ x25519_pubkey`). May or may not warrant a VERSION bump on its own; preferable to bundle with F-01 + F-02 into a single VERSION 6 release if pursued.

**Deferred from remediation scope:**

- **F-05** Plaintext JSON export — by design, Flutter-side warning already surfaced. No action.
- **F-10** eTLD+1 autofill matching — UX tradeoff, candidate for a post-v1 "Strict FQDN" toggle. Move to Bikeshed when starting work.
- **L-3** iOS Keychain protection class — pinned for the V2+ iOS port (already in Bikeshed via "iOS, Windows, macOS support").
- **L-6** `gcore` memory-forensics test of an unlocked gabbro process — Bikeshed candidate; ideally before the human-expert crypto review.

After Round 1 ships, run `flutter test` + `cargo test -q` + `cargo clippy -- -D warnings` to confirm no regression. Round 2 work is gated behind a separate session and a `.gabbro` VERSION 6 spec.

**Previous task completed (2026-05-31):** AI-assisted security review (Claude Opus 4.7) of `rust/src/crypto/` and `rust/src/vault/` — see [`docs/AI_SECURITY_AUDIT.md`](AI_SECURITY_AUDIT.md). 0 CVEs across 211 crates, 0 secrets in git history, 0 `unsafe`/`transmute`/`asm!` in scope, 0 hardcoded credentials, 10 findings (all Low or Info), and the full Recurity Labs Proton Pass audit mapped to gabbro's posture.

---

#### Adding a language after v1 (n+1 cost)

Adding a further language is cheap — **not** a full session:

- One new `lib/l10n/app_XX.arb` file (~430 translated key-value pairs)
- 2 lines of code: add locale to `supportedLocales` and to the in-app picker list
- Run `flutter gen-l10n` + `flutter test`
- Estimated effort: **20–30 minutes per language** (Claude generates translations; user spot-checks)

Confidence varies by language family:

| Language                          | Confidence  | Notes                                                             |
|-----------------------------------|-------------|-------------------------------------------------------------------|
| Norwegian (Bokmål), Swedish, Dutch| High        | Close to German/English; translations are reliable                |
| Portuguese, Romanian              | High        | Close to Spanish/French                                           |
| Polish, Czech, Slovak             | Medium      | Good training data; Slavic case system warrants native spot-check |
| Hungarian, Finnish, Estonian      | Medium-Low  | Uralic grammar differs structurally; more likely to need review   |

Non-trivial plural rules use ARB's built-in `{count, plural, one{…} other{…}}` syntax — no extra plumbing needed. Right-to-left languages (Arabic, Hebrew) would require additional layout-mirroring work and are out of scope for v1.

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

## Release Process

**Tag format:** `v0.1.0-alpha.N` (not `v0.1.0`) until the pre-v1 security gates in Bikeshed are cleared. This is honest with testers: the crypto review has not happened.

**Distribution model (current):** repo is private. Debian collaborator accesses releases via GitHub. Other testers receive the artifact directly (email / transfer).

---

### Pre-flight checklist

1. Move `[Unreleased]` block in `CHANGELOG.md` to `[0.1.0-alpha.N] – YYYY-MM-DD`.
2. Bump `version` in `pubspec.yaml` to match.
3. Run `flutter test` (450 passing) and `cargo clippy -- -D warnings`.
4. Commit, then tag: `git tag -a v0.1.0-alpha.N -m "v0.1.0-alpha.N"` and `git push origin v0.1.0-alpha.N`.

---

### Linux build

```bash
flutter build linux --release
```

Output lands in `build/linux/x64/release/bundle/`. That directory is self-contained (exe + Flutter libs + data assets).

**Packaging as tar.gz (Arch):**
```bash
tar -czf gabbro-v0.1.0-alpha.1-linux-x86_64.tar.gz \
    -C build/linux/x64/release bundle
```

**Debian compatibility:** verified for v0.1.0-alpha.1 — the Arch-built bundle requires glibc ≤ 2.34 (confirmed via `objdump -T`), well below Debian trixie (stable, 2.41) and Linux Mint (2.42). No Docker build needed. If a future release raises the requirement above 2.41, build inside a Debian trixie container:
```bash
docker run --rm -v "$PWD":/app -w /app debian:trixie \
    bash -c "apt-get update && apt-get install -y flutter ... && flutter build linux --release"
```

---

### Android build

**Signing keystore (one-time setup — do this before the first release build):**

```bash
# Generate the keystore — keep this file safe and backed up; losing it means
# you can never publish an update to the same Play Store listing.
keytool -genkey -v \
  -keystore android/app/gabbro-upload.jks \
  -alias gabbro \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

Create `android/key.properties` (already in `.gitignore` — do not commit this):
```
storePassword=<your-store-password>
keyPassword=<your-key-password>
keyAlias=gabbro
storeFile=gabbro-upload.jks
```

In `android/app/build.gradle.kts`, add before `android {`:
```kotlin
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
keyProperties.load(keyPropertiesFile.inputStream())
```

And inside `android { ... }` replace / add the signing config:
```kotlin
signingConfigs {
    create("release") {
        keyAlias = keyProperties["keyAlias"] as String
        keyPassword = keyProperties["keyPassword"] as String
        storeFile = file(keyProperties["storeFile"] as String)
        storePassword = keyProperties["storePassword"] as String
    }
}
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

**Build:**
```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

Rename before attaching: `gabbro-v0.1.0-alpha.1-android.apk`.

**Testers must enable "Install from unknown sources"** on their Android device. Send the APK directly (email / file transfer) — no Play Store needed for test distribution.

---

### GitHub Release

```bash
gh release create v0.1.0-alpha.1 \
  gabbro-v0.1.0-alpha.1-linux-x86_64.tar.gz \
  gabbro-v0.1.0-alpha.1-android.apk \
  --title "Gabbro v0.1.0-alpha.1" \
  --notes "$(cat CHANGELOG.md | sed -n '/## \[0.1.0-alpha.1\]/,/## \[/p' | head -n -1)" \
  --prerelease
```

Or create via the GitHub web UI and attach the two files manually.

Add a disclaimer in the release notes:
> **Alpha release — for invited testers only.** The cryptographic implementation has not yet undergone external review. Do not store passwords you cannot afford to lose.

---

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1 gates)
- Human expert cryptography review of `rust/src/crypto/` (ETH/EPFL academic outreach, RustCrypto maintainers, or formal audit).
- Supply-chain audit: `cargo audit`, `flutter pub audit`, IDE extension review, pin CI Actions to commit SHAs when CI is added.
- Verify Android storage permissions hold on Android 11+ (app-private storage + SAF — no `MANAGE_EXTERNAL_STORAGE`).
- Add an encrypted `vault.gabbro` file on the public github containing: a 256 char passphrase, a note stating that if anyone decrypts the file, they will be gifted two yubikeys if they send proof (the 256 char passsphrase) and their crack to gabbro.app@gmail.com -> include a "vault not cracked for n days" counter on github if possible
- Test on de-Googled Android (GrapheneOS/CalyxOS) before v1 — find a willing community tester, don't buy hardware.
- test/measure code test coverage before launch

### Features & UX
- bug: in android, cannot move the cursor in text fields, can position it but not drag it
- l10n bug: example text in font size (`appearance_screen.dart`) is hard-coded in English
- l10n bugs: many entry field tooltips are still hard-coded in English (examples: card state, custom fields label and value) -> audit all entries for hard-coded text and apply l10n
- l10n bug: default folder names are hard-coded in English
- add option in vault export to exclude date in filename -> for file sync with rsync
- Add tutorial/onboarding: probably in the README as snapshots from linux/emulator
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).
- Dependency licence audit for About screen (`_kComponents`) against actual Cargo.toml + pubspec.yaml at release time.

### Code Quality
- Dependency surface audit: remove any crate that can be replaced with `std` before v1 (`cargo tree`).
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.
- Explain if this project can be defined as "vide-coding" or not, and why, especially in the light of things like this: "vibe-coded cryptography software" in https://blogs.gentoo.org/mgorny/2026/05/28/why-gentoo/#more-2634

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
- Import: content-hash deduplication and entry-level merge.
- Native app autofill matching by package name (v2).