# Gabbro Architecture

## Project Overview

A post-quantum password manager built with security as core DNA.
Named after the intrusive igneous rock — hard, stable, enduring.
Cross-platform: Linux (Arch, Mint), Android; Windows later. FOSS, GPL-3.0-only.

**Core principle:** all keys and cryptography live in Rust; the vault is decrypted there and the master keys never cross the bridge. Secrets the user actively views, generates, or autofills do reach Flutter in plaintext to be displayed (bounded by auto-lock; the Dart heap retains them until GC — see SECURITY.md / audit F-12) — the keys never do.

## General Information

**Tech stack:** Flutter (Dart) frontend, Rust backend/crypto, flutter_rust_bridge v2 (FFI).

**Encryption (at rest):** Argon2id KDF → X25519 + ML-KEM-1024 hybrid key exchange → HKDF-SHA256 combiner → AES-256-GCM. Post-quantum: belt and suspenders.

**Authentication (app access):** Mandatory FIDO2/WebAuthn hardware key (YubiKey). v1 uses Ed25519 (hardware constraint); target ML-DSA-44 once Yubico ships PQ-capable hardware (ADR-005). Min 2 keys (primary + backup), max 4. Auto-lock: 30s default, configurable.

**YubiKey NFC / NDEF OTP:** a YubiKey's OTP slot 1 (an NDEF URI) would open a browser when tapped on Android. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` and by re-arming foreground dispatch after `stopNfcDiscovery`; OTP slot 1 can stay enabled (no `ykman` workaround). Full diagnosis in LEARNINGS.md.

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce, ML-KEM ciphertext, X25519 ephemeral pubkey) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, many languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text size, high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). Later: Windows.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Play Store one-time payment is licence-compatible; F-Droid free build coexists without conflict.

**Version control:** private GitHub repo at https://github.com/Zabamund/gabbro. SSH auth. `chat_info/` is git-ignored.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, export, import, generator, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, vault_registry, safe_file_picker
├── rust/src/
│   ├── api/              # Bridge surface: vault, vault_bridge, import, *_generator, fido_bridge, autofill_bridge, entropy, types
│   ├── crypto/           # Internal (not bridge-exposed): kdf, keypair, ml_kem, hkdf, aes_gcm, vault_crypto
│   ├── vault/            # Domain model: entry, file_format, io, serialization, session
│   ├── fido/             # FIDO2/libfido2 FFI (Linux only)
│   ├── import/           # enpass, bitwarden, google_pm, dashlane, csv
│   ├── hardening.rs      # Process hardening (R-04): core-dump + ptrace/mem disable (Linux)
│   └── bin/  scripts/  examples/   # bench_kdf, mem_forensics; wordlist gen; gen_fixtures
├── rust/tests/           # Backward-compat gate + state-machine fuzzer + parse fuzzer + frozen golden fixtures (FIXTURES.md)
├── android/…/kotlin/…/   # GabbroAutofillService, UnlockActivity, YubiKeyManager, BiometricHelper (+ Robolectric tests)
├── docs/                 # ARCHITECTURE, LEARNINGS, SECURITY, AI_*; decisions/ (ADRs); artefacts/
├── test/  integration_test/  test_driver/   # Flutter widget/unit + Linux real-FFI device suites
├── assets/               # fonts, images, help/; public_suffix_list.dat (autofill eTLD+1)
├── challenge/            # crack-me challenge vault + rules
└── CHANGELOG.md  README.md
```

## Features

Shipped features are recorded in `CHANGELOG.md`. Planned and deferred work lives in the Bikeshed at the end of this file.

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 526 | 8 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 10 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 838 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 7 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 89 | 17 |

**Test isolation (non-negotiable):** no test may touch the user's real settings or
vault folders. All config/data directories resolve through `GabbroPaths`
(`lib/app_paths.dart`), and `test/flutter_test_config.dart` roots every `flutter test`
run in a throwaway temp sandbox — so even a test that forgets to isolate itself reads an
empty registry and can never reach a real vault (wherever the user saved it). Mirrors the
`rust/tests/fixtures/` ethos of never operating on real data.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task — locked-vault autofill unlock (reuse the main `UnlockScreen`)

**Goal:** the locked autofill path has no unlock flow, so it never reaches matching. Build it
by **reusing the main `UnlockScreen`** in the autofill activity — vault picker, passphrase,
YubiKey (USB/NFC), PIN, multi-key, biometric.

**Design (decided with Rob):**
- No new JNI unlock. `autofillUnlockMain` already calls `RustLib.init()`, so the generated
  Flutter bridge drives the same shared `VAULT_SESSION`; Flutter unlocks directly, then
  signals Kotlin to `buildFillIntent()`.
- Add an `onUnlocked` hook to `UnlockScreen` (autofill signals Kotlin instead of navigating to
  `VaultListScreen`); main app behaviour unchanged when the hook is absent.
- `UnlockActivity` → `FlutterFragmentActivity` hosting the same `…/yubikey` + `…/biometric`
  channels + NFC suppression as `MainActivity`, extracted to a shared base (DRY).
- `autofillUnlockMain` loads `VaultRegistry` (picker — user chooses which vault) and mirrors
  `main.dart`'s `MaterialApp` wiring (locale/theme/textScaler). Fixes a latent bug: the
  entrypoint builds a bare `MaterialApp`; current tests pass only because `testApp()` injects
  the delegates the production entrypoint lacks.

**Rule: a regression net is written and green against *current* code before any production change.**

Net A — `UnlockScreen` behaviour:
- [ ] success (passphrase, then YubiKey) → navigates to `VaultListScreen`
- [ ] transport seam: default `usb`; selecting NFC passes `nfc`
- [ ] PIN copy/paste blocked; vault-switch re-detects YubiKey records
- [ ] keyboard submit unlocks; loading disables controls; biometric+YubiKey hint shown
- [ ] no overflow with keyboard inset (both modes, error showing)

Net B — appearance/language:
- [ ] renders under light/dark/system + high-contrast; large `textScaler`; non-English + long-string locale

Net C — accessibility (broad sweep):
- [ ] tap-target + labeled-target, text-contrast (light+dark), focus order, large-text reflow
  (contrast may surface a real finding — fix or waive, don't weaken the check)

Net D — autofill entrypoint:
- [ ] extract testable `buildAutofillUnlockApp(settings, registry)`; assert it wires delegates/locale/theme/textScaler

Net E — Kotlin tap-flow (Robolectric):
- [ ] exactly one of timeout/cancel/success/error completes; cancel→`TAP_CANCELLED`; retry-once; transport dispatch
- [ ] `MainActivity` still wires export + getRecentApps after extraction

**Then production (each step, then device-test):**
- [ ] `onUnlocked` hook on `UnlockScreen`
- [ ] autofill entrypoint reuses `UnlockScreen` (picker + appearance/locale wiring)
- [ ] `UnlockActivity` → FragmentActivity + shared host extraction (yubikey/biometric/NFC)
- [ ] device gate: locked autofill unlocks (passphrase / YubiKey USB+NFC with no `demo.yubico.com`
  escape / biometric); picker chooses a non-default vault; locked-path matching matrix; main-app
  YubiKey/biometric/export regression

**Verifiable now (independent):** unlocked path — open → unlock → autofill without locking → fills.

After this lands, remaining autofill candidates: `onSaveRequest`, silent no-match toast.

### Open from the security audit

Full per-finding status and detail live in `AI_SECURITY_AUDIT.md`. Still open:

- **F-03** — X-Wing transcript-binding combiner; gated on a human cryptographer (no verifiable-against-spec answer).

A second-pass review (`AI_SECURITY_AUDIT_REVIEW.md`, 2026-06-11) added findings
**R-01…R-07**; per-finding status lives in that document's remediation table. All
now closed.

---

## Build & Release

Build-environment notes (Android/Kotlin/Java setup, SAF export) and the full
release process live in their own document:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1 gates)
- **F-03 X-Wing combiner** — migrate the hybrid KEM combiner to a transcript-binding (X-Wing-style) construction (`ikm = ml_kem_ss ∥ x25519_ss ∥ ml_kem_ct ∥ x25519_pubkey`). No single verifiable-against-spec answer → genuinely needs a human cryptographer's judgement. Would require VERSION 8.
- Human expert cryptography review of `rust/src/crypto/` (ETH/EPFL academic outreach, RustCrypto maintainers, or formal audit).
- Test on de-Googled Android (GrapheneOS/CalyxOS) before v1 — find a willing community tester, don't buy hardware.
- Pin CI Actions to commit SHAs; add `cargo audit` + `osv-scanner --lockfile pubspec.lock` steps (once CI exists). See Track A Phase 1 audit in `AI_SECURITY_AUDIT.md`.

### Features & UX
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).

### Code Quality
- **Scrub real app names and personal names from test data.** Tests across the suite use real apps the user runs (e.g. github) and the user's name as placeholder usernames. Test data must be generic (`com.company.app`, `https://example.com`, `user`/`alice`/`bob`) — never a real app the user has installed or a real person's name. Audit all of `rust/`, `android/`, `test/`, `integration_test/` and replace. commit message will not surface this information: it will only say `code cleanup`
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.
- **Offline test gate — Android leg still online.** `gabbro_test` runs flutter/cargo/rust fully offline (rootless netns), but the Android `./gradlew :app:testDebugUnitTest` leg runs online: the Flutter `integration_test` plugin declares a dynamic transitive dep (`androidx.test:runner:1.2+`) that gradle won't resolve `--offline`. `dependencyLocking` on `:app` doesn't pin that plugin's config; the netns also needs `JAVA_TOOL_OPTIONS=-Duser.home=/home/gamer` (uid-0 remap → JVM home `/root`). Likely fix: force a concrete `androidx.test:runner` version across all projects (or lock every project), then move the leg into the offline block.

### V2+ / Defer
- UI locales deferred (RTL layout work required): Hebrew, Arabic.
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
- Windows support.
- Yubico partnership.
- Destination Linux podcast outreach (when approaching public release).
- Donation/sustainability model (GitHub Sponsors + Liberapay + Monero — dedicated session near release).
- No-telemetry verification guide (ripgrep scan, Wireshark, NetGuard).
- Support model (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).
- Import: content-hash deduplication and entry-level merge.
- Native app autofill matching by package name (v2).