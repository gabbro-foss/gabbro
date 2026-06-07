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

**Authentication (app access):** Mandatory FIDO2/WebAuthn hardware key (YubiKey). v1 uses Ed25519 (hardware constraint); target ML-DSA-44 once Yubico ships PQ-capable hardware (ADR-005). Min 2 keys (primary + backup), max 4. Auto-lock: 30s default, configurable.

**YubiKey NFC / NDEF OTP:** YubiKeys ship with OTP slot 1 as an NDEF URI over NFC (`https://my.yubico.com/yk/...`). Without mitigation, Android opens a browser tab when the key is tapped. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` (prevents NDEF being read during the CTAP2 session) and by re-arming foreground dispatch after `stopNfcDiscovery` (routes any post-session NDEF intents to `onNewIntent` rather than the browser). OTP slot 1 may remain enabled — no `ykman` workaround is needed. See LEARNINGS.md for the full diagnosis and collateral-effects table.

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce, ML-KEM ciphertext, X25519 ephemeral pubkey) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, 29 languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

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
│   │   ├── help_screen.dart
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
│   │   │   ├── types.rs            # Shared types (Language enum — 29 variants)
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
│   │   │   ├── bitwarden.rs
│   │   │   ├── google_pm.rs
│   │   │   ├── dashlane.rs
│   │   │   └── csv.rs
│   │   ├── bin/
│   │   │   ├── bench_kdf.rs
│   │   │   └── mem_forensics.rs    # memory-forensics self-test (--features forensics)
│   │   └── lib.rs
│   ├── scripts/
│   │   ├── mem_forensics.sh        # gcore memory-forensics driver (audit L-6)
│   │   └── gen_wordlists.py        # generates rust/assets/wordlist_XX.txt (Step 3)
├── android/app/src/main/
│   └── kotlin/app/gabbro/gabbro/
│       ├── GabbroAutofillService.kt
│       ├── UnlockActivity.kt
│       ├── RustBridge.kt
│       ├── YubiKeyManager.kt      # USB FIDO2 hmac-secret (register + getHmacSecret)
│       └── BiometricHelper.kt     # AndroidKeyStore + BiometricPrompt enrol/auth/unenrol
├── android/app/src/test/
│   └── kotlin/app/gabbro/gabbro/
│       ├── YubiKeyManagerTest.kt
│       └── BiometricHelperTest.kt
├── docs/
│   ├── ARCHITECTURE.md         # This file
│   ├── LEARNINGS.md
│   ├── SECURITY.md             # User-facing security overview (Track A Phase 2)
│   ├── AI_AUTHORSHIP_AND_IP.md
│   ├── AI_SECURITY_AUDIT.md    # AI-assisted security review (2026-05-31)
│   ├── artefacts/
│   └── decisions/              # ADR documents
├── assets/
│   ├── fonts/
│   ├── images/
│   └── help/                       # 13 annotated screenshots for the in-app help carousel
├── challenge/
│   ├── README.md               # Crack-me challenge rules and reward
│   ├── decryptMe_2026-06-01.gabbro        # Sealed vault (passphrase + YubiKey; body unreadable without hardware)
│   └── decryptMe_2026-06-01.gabbro.sha256
├── test/                       # Flutter unit/widget tests
├── integration_test/
├── CHANGELOG.md
└── README.md
```

## Features

Shipped features are recorded in `CHANGELOG.md`. Planned and deferred work lives in the Bikeshed at the end of this file.

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | ~380 | 8 |
| Flutter (`flutter test`) | 546 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 0 | 18 |

Note: Rust test count does not yet reflect the new Google PM and Dashlane importer unit tests — run after the next full `cargo test -q`.

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`. Cross-layer integration tests deferred (see V2+/YAGNI note in Bikeshed).

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next session

TBD — check Bikeshed with [user].

**UI locales deferred** (RTL layout work required): Hebrew, Arabic.

### Open from the security audit

Full per-finding status and detail live in `AI_SECURITY_AUDIT.md`. Still open:

- **F-03** — X-Wing transcript-binding combiner; gated on a human cryptographer (no verifiable-against-spec answer).
- **F-10** — eTLD+1 autofill matching; post-v1 "Strict FQDN" toggle.
- **L-3** — iOS Keychain protection class; V2+ iOS port.

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

**Tag format:** `v0.1.0-alpha.N` until the pre-v1 security gates (Bikeshed) clear — honest with testers that no external crypto review has happened yet. Repo is private; the Debian collaborator pulls releases from GitHub, other testers receive artifacts directly.

**Pre-flight:**
1. Move the `[Unreleased]` block in `CHANGELOG.md` to `[0.1.0-alpha.N] – YYYY-MM-DD`.
2. Bump `version` in `pubspec.yaml` to match.
3. `flutter test` + `cargo test -q` + `cargo clippy -- -D warnings` all green.
4. Commit, then `git tag -a v0.1.0-alpha.N -m "v0.1.0-alpha.N" && git push origin v0.1.0-alpha.N`.

**Build:**
- **Linux:** `flutter build linux --release` → self-contained bundle in `build/linux/x64/release/bundle/`; package with `tar -czf gabbro-<ver>-linux-x86_64.tar.gz -C build/linux/x64/release bundle`. (The Arch-built bundle runs on Debian trixie / Mint — glibc ≤ 2.34, verified; only build in a `debian:trixie` container if a future release raises that above 2.41.)
- **Android:** `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`; rename to `gabbro-<ver>-android.apk`. The signing keystore (`android/app/gabbro-upload.jks`) and `android/key.properties` are already configured and gitignored.

**Publish:** `gh release create v0.1.0-alpha.N <linux.tar.gz> <android.apk> --title "Gabbro v0.1.0-alpha.N" --prerelease`, with the disclaimer: *"Alpha — for invited testers only. The cryptographic implementation has not undergone external review. Do not store passwords you cannot afford to lose."*

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1 gates)
- **F-03 X-Wing combiner** — migrate the hybrid KEM combiner to a transcript-binding (X-Wing-style) construction (`ikm = ml_kem_ss ∥ x25519_ss ∥ ml_kem_ct ∥ x25519_pubkey`). No single verifiable-against-spec answer → genuinely needs a human cryptographer's judgement. Would require VERSION 8.
- Human expert cryptography review of `rust/src/crypto/` (ETH/EPFL academic outreach, RustCrypto maintainers, or formal audit).
- Verify Android storage permissions hold on Android 11+ (app-private storage + SAF — no `MANAGE_EXTERNAL_STORAGE`).
- Test on de-Googled Android (GrapheneOS/CalyxOS) before v1 — find a willing community tester, don't buy hardware.
- test/measure code test coverage before launch
- Pin CI Actions to commit SHAs; add `cargo audit` + `osv-scanner --lockfile pubspec.lock` steps (once CI exists). See Track A Phase 1 audit in `AI_SECURITY_AUDIT.md`.

### Features & UX
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).

### Code Quality
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.
- Explain if this project can be defined as "vide-coding" or not, and why, especially in the light of things like this: "vibe-coded cryptography software" in https://blogs.gentoo.org/mgorny/2026/05/28/why-gentoo/#more-2634
- verify that the artefact files are still valid (ammend or remove as required)

### V2+ / Defer
- Passphrase wordlists — not viable without significant pipeline work: `yo` Yoruba (no frequency ordering, complex tonal diacritics); `sr_Latn` Serbian Latin (only Cyrillic corpora; needs transliteration pipeline); `lb` Luxembourgish (small speaker base); `wa` Walloon (nothing usable, French covers Wallonia).
- Passkey (WebAuthn discoverable credential) support.
- Vault sync across devices.
- Autofill save requests (`onSaveRequest`) — see also Features & UX above.
- Data breach alerts / HaveIBeenPwned integration.
- Panic button / app hiding on mobile.
- Remote app / vault deletion.
- Custom and hideable filter chips (post-v1 user feedback gate).
- Cross-layer integration tests (`integration_test/` + Rust `tests/` crate). YAGNI: if users file bugs, those become the organic integration test suite.
- iOS, Windows, macOS support.
- Yubico partnership.
- Destination Linux podcast outreach (when approaching public release).
- Donation/sustainability model (GitHub Sponsors + Liberapay + Monero — dedicated session near release).
- No-telemetry verification guide (ripgrep scan, Wireshark, NetGuard, iOS caveat).
- Support model (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).
- Import: content-hash deduplication and entry-level merge.
- Native app autofill matching by package name (v2).