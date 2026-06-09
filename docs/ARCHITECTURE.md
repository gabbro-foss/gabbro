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
│   ├── app_paths.dart          # GabbroPaths: single source for config/data dirs + test sandbox override
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
│   ├── examples/
│   │   └── gen_fixtures.rs         # one-time golden-vault fixture generator (see tests/fixtures/FIXTURES.md)
│   └── tests/
│       ├── vault_backward_compat.rs    # frozen-fixture backward-compat gate (read v6+, migrate, YubiKey rotation, passphrase change)
│       ├── vault_state_machine_fuzz.rs # opt-in (#[ignore]) seeded-rand fuzzer: random {change_passphrase, add/remove key} order
│       └── fixtures/
│           ├── FIXTURES.md         # fixture provenance + recipe to add a vN_*.gabbro per new VERSION
│           ├── fixture_spec.rs     # shared seal/assert spec, included by both harness and generator (no drift)
│           └── vaults/             # committed FROZEN golden vaults: v6/v7 × {passphrase, multikey}
├── android/app/src/main/
│   └── kotlin/app/gabbro/gabbro/
│       ├── GabbroAutofillService.kt
│       ├── UnlockActivity.kt
│       ├── RustBridge.kt
│       ├── YubiKeyManager.kt      # USB FIDO2 hmac-secret (register + getHmacSecret)
│       └── BiometricHelper.kt     # AndroidKeyStore + BiometricPrompt enrol/auth/unenrol
├── android/app/src/test/
│   ├── kotlin/app/gabbro/gabbro/
│   │   ├── YubiKeyManagerTest.kt
│   │   ├── BiometricHelperTest.kt              # Robolectric: isEnrolled (real SharedPreferences)
│   │   ├── GabbroAutofillServiceTest.kt        # pure-data (CredentialSummary, ParsedStructure)
│   │   └── GabbroAutofillServiceRobolectricTest.kt  # Robolectric: Uri + org.json helpers
│   └── resources/
│       └── robolectric.properties             # pins Robolectric runtime to sdk=34
├── docs/
│   ├── ARCHITECTURE.md         # This file
│   ├── LEARNINGS.md
│   ├── SECURITY.md             # User-facing security overview (Track A Phase 2)
│   ├── AI_AUTHORSHIP_AND_IP.md
│   ├── AI_DEVELOPMENT_PROCESS.md  # "Is Gabbro vibe-coded?" — process/trust rationale
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
│   ├── vault_session_test.dart     # Phase 1: real-FFI passphrase-vault round-trip (Linux)
│   └── entry_edit_test.dart        # Phase 1: real-FFI edit/update + clear/revert password-history refresh (Linux)
├── test_driver/
│   └── integration_test.dart       # flutter drive entrypoint (run integration_test in --profile)
├── CHANGELOG.md
└── README.md
```

## Features

Shipped features are recorded in `CHANGELOG.md`. Planned and deferred work lives in the Bikeshed at the end of this file.

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 477 | 8 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 10 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 723 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 7 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 23 | 17 |

Strategy: TDD from day one. Rust native test framework; Flutter unit + widget tests in `test/`. The backward-compat harness is a separate integration binary that reads committed frozen golden vaults — see Current Focus and `rust/tests/fixtures/FIXTURES.md`. `integration_test/` covers the hard-to-reach app paths that need the real Rust bridge on a device (Current Focus → Remaining); broad cross-layer scaffolding beyond those targeted paths stays YAGNI (Bikeshed).

**Test isolation (non-negotiable):** no test may touch the user's real settings or
vault folders. All config/data directories resolve through `GabbroPaths`
(`lib/app_paths.dart`), and `test/flutter_test_config.dart` roots every `flutter test`
run in a throwaway temp sandbox — so even a test that forgets to isolate itself reads an
empty registry and can never reach a real vault (wherever the user saved it). Mirrors the
`rust/tests/fixtures/` ethos of never operating on real data.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Active task: systematic test coverage improvement

**Philosophy:** tests catch real flaws — logic errors, mishandled failure modes,
secret leakage, malformed-input crashes, state-machine bypasses — not line count.

**In progress → Flutter `integration_test/` coverage** (Rust, Kotlin and Flutter unit
layers are done — see Coverage status). The last coverage frontier; needs a real
device. **Phased, Linux-first:** Phase 1 (Linux desktop, passphrase-vault, no
hardware) is underway — harness + the real-FFI session round-trip are green; Phase 2
covers the hardware/Android-only paths. Detail and remaining scenarios under Remaining
below.

#### Coverage status

| Layer | State |
|-------|-------|
| Rust unit (`cargo test -q`) | ✅ reachable targets covered (`fido/device`, `crypto/vault_crypto`, importers, `api/vault_bridge`, `api/import`) |
| Rust vault backward-compat harness | ✅ done — see below |
| Flutter (`flutter test`) | ✅ 664 passing; hard-to-reach paths covered by `integration_test/` (below) |
| Flutter integration (`flutter drive`) | 🔶 Phase 1 underway (Linux) — session round-trip + changePassphrase + entry edit/history/revert green (7 tests); main.dart + onboarding + fallback-locale scenarios + Phase 2 hardware paths remain |
| Kotlin (`./gradlew :app:testDebugUnitTest`) | ✅ Robolectric reachable targets covered — 23 passing / 17 `@Ignore`d (hardware-only: YubiKey, BiometricPrompt, AndroidKeyStore) |

#### Vault-format backward-compatibility harness — ✅ done

The safety net the 2026-06-08 brick proved we needed (post-mortem in LEARNINGS.md).
`rust/tests/vault_backward_compat.rs` loads **frozen golden `.gabbro` vaults committed
to git** (`tests/fixtures/vaults/`, one set per format VERSION, sealed by the build
that shipped that version) and proves the *current* code can still:

- **read** each v6/v7 vault — passphrase-only and multi-key (YubiKey) keyslot paths;
- **migrate** it to the current VERSION on re-seal, contents preserved;
- **survive the full YubiKey loss/rotation journey** — create with YK1+YK2 → lose
  YK2/add YK3 → lose YK1/add YK4, unlockable with the surviving keys at every step,
  with a post-onboarding floor of one key — and this holds starting from both a v6
  and a v7 vault, asserting the on-disk version is current after every mutation;
- **survive a passphrase change** — vault A (passphrase-only) changes its passphrase
  and still opens under the new one (old one rejected); vault B (multi-key) interleaves
  a passphrase change into the rotation journey, ending with a *new passphrase AND new
  keys* and still openable by every surviving `(new passphrase + registered YK)` pair,
  with the old passphrase and removed keys all refused. A wrong old passphrase is
  rejected and leaves the vault openable under the original.

10 tests, driven through the real bridge functions the app calls. A round-trip test
can never catch a brick; only frozen old bytes can. Generation recipe and the
per-VERSION gate live in `rust/tests/fixtures/FIXTURES.md`. Scope is v6+ (no user
vaults predate v6). Fixtures use fixed fake key material and low Argon2id params, but
the passphrase-change tests re-seal at production strength — run the gate in
`--release` (~14 s vs ~6 min in debug). The opt-in `vault_state_machine_fuzz.rs`
(seeded `rand`, `#[ignore]`'d) randomises the *order* of {change_passphrase, add/remove
key} over the same fixtures to surface interleavings the hand-written tests miss;
failures get promoted here as fixed regression tests.

> **RELEASE GATE — non-negotiable.** Every new format VERSION must ship with a
> committed `vN_passphrase.gabbro` and `vN_multikey_2keys.gabbro`, generated by the
> build that introduces VERSION N (recipe in `FIXTURES.md`), with
> `cargo test --release --test vault_backward_compat` green. The gate only protects
> versions that have a fixture — skipping this step silently removes the net for that
> version.
> Mirrored in the Release Process pre-flight below.

#### Remaining — Flutter `integration_test/` (in progress)

These paths can't be reached by `flutter test` widget tests (host VM, no native lib):
they need `integration_test/` driving a real device so the **actual** Rust FFI →
crypto → disk stack runs. Phase 1 targets the passphrase-only vault path (no YubiKey).

**Run command** (profile, not debug — `flutter test -d linux` builds the Rust lib in
debug, where Argon2id is too slow; `--release` is rejected for non-web `flutter drive`):

```bash
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/<suite>_test.dart -d linux --profile
```

Phase 1 (Linux desktop, no hardware):
- ✅ **Harness + session round-trip + changePassphrase** (`integration_test/vault_session_test.dart`,
  3 tests): `initVault` → `createEntry` → real `getEntry`; `lockVault` → `unlockVault`
  re-reads from disk; `changePassphrase` re-seals and the vault re-opens under the new
  passphrase only. Proves real FFI/Argon2id/AES-GCM and the un-injectable `getEntry` path.
- ✅ **Entry edit + password-history refresh** (`integration_test/entry_edit_test.dart`,
  4 tests): `create_entry_screen` edit→`updateEntry`→real `getEntry` (auto-records
  `previous_password`); `entry_detail_screen` `getEntry` refresh after
  `sessionClearPasswordHistory` (`:355`) and `sessionRevertPassword` (`:374`); history
  survives a real `lockVault`→`unlockVault` disk round-trip.
**Re-categorised → widget/unit tests (`test/`), not `integration_test/`.** Investigation
showed the remaining "main.dart / onboarding / fallback-locale" items are *not* real-FFI
paths: the app shell and target screens mount with injectable/guarded FFI, and the
`GabbroPaths` test-sandbox refactor made onboarding's default-path step mountable. So they
were covered as fast `flutter test` widget/unit tests, not `flutter drive`:
- ✅ `main.dart` `navigateToManageVaults` → `test/main_navigation_test.dart`.
  `onActiveVaultDeleted` is **blocked pending the privacy-mode vault-delete ADR**
  (Bikeshed → Features & UX) — its navigation is known-suspect, so we don't pin it yet.
- ✅ `onboarding_screen` alias→path sanitisation (`sanitiseVaultAlias`, the path-traversal
  guard) → `test/onboarding_alias_test.dart`.
- ✅ `_Fallback{Material,Cupertino}LocalizationsDelegate` both branches (supported locale +
  English fallback for `yo`) → `test/fallback_localizations_test.dart`.

That clears the Phase 1 `integration_test/` frontier: the genuinely FFI-dependent paths
(`vault_session_test.dart`, `entry_edit_test.dart`) are covered on a device; the rest were
better served by `flutter test`.

Phase 2 (gated — hardware / native UI, documented `skip:`): multi-key **YubiKey**
unlock, **`autofillUnlockMain`** (Android), native **FilePicker** pickers.

Same philosophy as the rest of the campaign: target the real flaws on these paths, not
line count. Cross-layer integration scaffolding is otherwise YAGNI (Bikeshed) — keep this
scoped to the hard-to-reach app paths above.

### Open from the security audit

Full per-finding status and detail live in `AI_SECURITY_AUDIT.md`. Still open:

- **F-03** — X-Wing transcript-binding combiner; gated on a human cryptographer (no verifiable-against-spec answer).
- **F-10** — eTLD+1 autofill matching; post-v1 "Strict FQDN" toggle.
- **L-3** — iOS Keychain protection class; V2+ iOS port.

**UI locales deferred** (RTL layout work required): Hebrew, Arabic.

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
3. Run **all** of the following green. The first three are the routine suites; the
   rest are NOT covered by `flutter test` or `cargo test -q` and must be run by hand:

   ```bash
   # Routine suites (debug)
   # Run from gabbro/
   flutter test
   cd rust
   cargo test -q
   cargo clippy -- -D warnings

   # Flutter integration — real Rust FFI on a device (flutter test can't load the native lib).
   # Run once per suite in integration_test/:
   cd ..
   flutter drive --driver=test_driver/integration_test.dart \
     --target=integration_test/vault_session_test.dart -d linux --profile
   flutter drive --driver=test_driver/integration_test.dart \
     --target=integration_test/entry_edit_test.dart   -d linux --profile

   # Vault backward-compat gate — run in release (debug works but is ~6 min vs ~14 s).
   cd rust
   cargo test --release --test vault_backward_compat

   # Vault state-machine fuzzer — #[ignore]'d, so cargo test -q never runs it.
   cargo test --release --test vault_state_machine_fuzz -- --ignored
   ```

   Notes:
   - **New vault format VERSION this release?** Before running the gate, generate and
     commit its `vN_passphrase.gabbro` + `vN_multikey_2keys.gabbro` fixtures (recipe:
     `rust/tests/fixtures/FIXTURES.md`). The gate only protects versions with a fixture.
   - **Fuzzer found a failure?** It prints the seed + op log. Reproduce, minimise, and
     add the sequence to `vault_backward_compat.rs` as a fixed regression test. Widen
     the search with `GABBRO_FUZZ_CASES=64`.
   - The 8 ignored Rust + 17 ignored Kotlin tests are hardware-only (YubiKey /
     biometric / AndroidKeyStore) and cannot run without the devices.
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
- Pin CI Actions to commit SHAs; add `cargo audit` + `osv-scanner --lockfile pubspec.lock` steps (once CI exists). See Track A Phase 1 audit in `AI_SECURITY_AUDIT.md`.

### Features & UX
- Privacy-safe "open existing vault by path" (ADR-012 Option B) — a future relaxation of the
  vault-deletion privacy rules under `show_vault_list` OFF. Dead on Android app-private
  storage, low priority.
- **Autofill match quality (Android) — needs a serious dedicated session.** On-device
  reality (2026-06-09, S23): on most sites autofill offers nothing, on some it fills the
  *wrong* credential ("wrong password"), on very few it works. Three suspects, all now
  pinned by Robolectric tests in `GabbroAutofillServiceRobolectricTest`:
  (1) **field detection** — `ParsedStructure.collectIds` heuristics (autofill hints →
  inputType → hint/idEntry keywords) miss many real login forms, especially SPA/Chromium
  DOM-to-AssistStructure shapes → "offers nothing";
  (2) **domain matching** — `extractRegistrableDomain`'s naive last-two-labels eTLD+1
  (audit **F-10**) collapses e.g. `*.co.uk` to `co.uk`, so unrelated sites can collide →
  "wrong password"; needs the Public Suffix List;
  (3) **native-app matching** — `extractAppToken` + `summary.url.contains(token)` substring
  match is far too loose (e.g. token `paypal` matches any URL containing it) → wrong entry.
  Plan it as: PSL-backed eTLD+1, a real form-field model, and tightened app matching
  (package-name mapping, see the V2+ item). Touches the Android autofill security surface,
  so design-then-implement with on-device verification.
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).

### Code Quality
- **Summarize `ARCHITECTURE.md`** — the document has grown too long again. Once the code
  coverage task is finished, do a condensing pass (trim historical narration the git log /
  CHANGELOG already capture, tighten Coverage status and Current Focus).
- **Language-picker invariant tests** (quick win) — pure-function tests in
  `test/language_screen_test.dart`: every `LanguageChoice` maps to a non-empty, *unique*
  label via `languageChoiceLabel` (no ambiguous picker rows), and `sortedLanguageChoices`
  returns all `LanguageChoice.values` with `system` first and the rest alphabetical by label.
  Auto-covers future languages; replaces the brittle `values.length == 35` magic number.
  Complements the endonym guard added for the langDutch fix.
- **Locale-resolution guard** (quick win) — assert every non-`system` `LanguageChoice`
  resolves (via `_localeFor` in `main.dart`) to a locale present in
  `AppLocalizations.supportedLocales`, so a half-wired new language can't silently fall back
  to English (user picks "Polski", gets English). `_localeFor` is private — needs a small
  test seam or a per-choice GabbroApp drive that detects the fallback.
- **Fix stale Current Focus facts** (quick win, distinct from the summarize pass) — Coverage
  status still says Flutter "664 passing" (now 723); the `onActiveVaultDeleted` note still
  says "blocked pending the privacy-mode vault-delete ADR" though ADR-012 has shipped and the
  remnant was removed.
- **`SealedVault::from_bytes` malformed-input fuzz test** (quick win, security-adjacent) —
  the parser in `rust/src/vault/file_format.rs` is *currently* well-defended: every slice at
  lines ~232–369 is preceded by an `if data.len() < pos + N { return Err(..) }` guard, so each
  `try_into().unwrap()` is infallible by construction and truncated input returns a clean
  `Err`, not a panic. But that safety is held **only by inspection** — there is no negative
  test. The backward-compat harness (`rust/tests/vault_backward_compat.rs`) only ever feeds
  *valid* vaults through `from_bytes`. One careless edit (a slice added without its guard, or
  the theoretical `pos + body_len` usize-overflow from the attacker-controlled 8-byte body-len
  field at line ~369 — wraps in release, can invert a slice range) would reintroduce a
  crash-on-open and nothing would catch it. Add a property/fuzz test (mirror the
  `vault_state_machine_fuzz.rs` seeded-`rand` style, likely as a new
  `rust/tests/vault_parse_fuzz.rs`) that feeds `from_bytes`: (1) every truncation `data[..n]`
  of a valid sealed vault for all n, (2) random garbage of assorted lengths, (3) a valid magic
  prefix followed by corrupted/oversized length fields, and asserts **returns `Err`, never
  panics** (use `std::panic::catch_unwind` or just rely on the harness — a panic fails the
  test). Locks in the existing good behaviour and the project's "tests catch malformed-input
  crashes" philosophy. Audit context: only 26 production `.unwrap()`s exist repo-wide; the
  rest are the generated bridge (`frb_generated.rs`, off-limits) or `expect()` on fixed-size
  crypto conversions and dev-only bins (`mem_forensics`, `bench_kdf`) — all benign. ~30–45 min.
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.

### V2+ / Defer
- Passphrase wordlists — not viable without significant pipeline work: `yo` Yoruba (no frequency ordering, complex tonal diacritics); `sr_Latn` Serbian Latin (only Cyrillic corpora; needs transliteration pipeline); `lb` Luxembourgish (small speaker base); `wa` Walloon (nothing usable, French covers Wallonia).
- Autofill via `auto-type` (desktop) — global hotkey → foreground-window detection → synthesised keystrokes into another app (the KeePass/KeePassXC model, no browser extension). Needs a dedicated design session + ADR: Wayland blocks synthetic input outside the freedesktop RemoteDesktop portal / `libei` (KeePassXC's own auto-type is partial there), it's a new secret→input-subsystem security surface, and it cuts across "secrets live in Rust" (Rust holds the secret + synthesises input, Flutter registers the hotkey, per-platform window detection). Desktop-first; shares no code with Android autofill. Discuss-then-plan-or-drop.
- Passkey (WebAuthn discoverable credential) support.
- Vault sync across devices.
- Autofill save requests (`onSaveRequest`) — see also Features & UX above.
- Data breach alerts / HaveIBeenPwned integration.
- Panic button / app hiding on mobile.
- Remote app / vault deletion.
- Custom and hideable filter chips (post-v1 user feedback gate).
- *Broad* cross-layer integration scaffolding beyond the targeted hard-to-reach paths now in Current Focus (e.g. an exhaustive `integration_test/` × Rust `tests/` matrix). YAGNI: if users file bugs, those become the organic integration test suite.
- iOS, Windows, macOS support.
- Yubico partnership.
- Destination Linux podcast outreach (when approaching public release).
- Donation/sustainability model (GitHub Sponsors + Liberapay + Monero — dedicated session near release).
- No-telemetry verification guide (ripgrep scan, Wireshark, NetGuard, iOS caveat).
- Support model (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).
- Import: content-hash deduplication and entry-level merge.
- Native app autofill matching by package name (v2).