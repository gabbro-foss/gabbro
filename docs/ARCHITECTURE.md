# Gabbro Architecture

## Project Overview

A post-quantum password manager built with security as core DNA.
Named after the intrusive igneous rock — hard, stable, enduring.
Cross-platform: Linux (Arch, Mint), Android; Windows later. FOSS, GPL-3.0-only.

**Core principle:** all keys and cryptography live in Rust; the vault is decrypted there and the master keys never cross the bridge. Secrets the user actively views, generates, or autofills do reach Flutter in plaintext to be displayed (bounded by auto-lock; the Dart heap retains them until GC — see SECURITY.md / audit F-12) — the keys never do.

## General Information

**Tech stack:** Flutter (Dart) frontend, Rust backend/crypto, flutter_rust_bridge v2 (FFI).

**Encryption (at rest):** Argon2id KDF → X25519 + ML-KEM-1024 hybrid key exchange → HKDF-SHA256 combiner → AES-256-GCM. Post-quantum: belt and suspenders.

**Authentication (app access):** Passphrase always; a FIDO2/WebAuthn hardware key (YubiKey) is strongly recommended but **not enforced** — a passphrase-only vault is the default. When keys are used: v1 Ed25519 (hardware constraint), target ML-DSA-44 once Yubico ships PQ-capable hardware (ADR-005), min 2 keys (primary + backup), max 4. Auto-lock: 30s default, configurable.

**YubiKey NFC / NDEF OTP:** a YubiKey's OTP slot 1 (an NDEF URI) would open a browser when tapped on Android. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` and by re-arming foreground dispatch after `stopNfcDiscovery`; OTP slot 1 can stay enabled (no `ykman` workaround). Full diagnosis in LEARNINGS.md.

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce, ML-KEM ciphertext, X25519 ephemeral pubkey) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, many languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text scale (`text_scale`, 0.8-8.0), high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). Later: Windows. Android smoke-tested on GrapheneOS (2026-06-20): onboarding, vault sync, web autofill, l10n, settings all work — not yet exhaustive.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Play Store one-time payment is licence-compatible; F-Droid free build coexists without conflict.

**Version control:** private GitHub repo at https://github.com/Zabamund/gabbro. SSH auth.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, export, import, generator, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, sync_review, text_size_slider, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, text_scale, control_scale, vault_registry, safe_file_picker, autotype_listener, autotype_target, clipboard_clear
├── rust/src/
│   ├── api/              # Bridge surface: vault, vault_bridge, import, *_generator, fido_bridge, autofill_bridge, autotype_bridge, entropy, types
│   ├── crypto/           # Internal (not bridge-exposed): kdf, keypair, ml_kem, hkdf, aes_gcm, vault_crypto
│   ├── vault/            # Domain model: entry, file_format, io, serialization, session
│   ├── fido/             # FIDO2/libfido2 FFI (Linux only)
│   ├── import/           # enpass, bitwarden, google_pm, dashlane, csv
│   ├── hardening.rs      # Process hardening (R-04): core-dump + ptrace/mem disable (Linux)
│   ├── autotype/         # Linux auto-type (ADR-017): keysym, XTEST inject, active-window read, trigger IPC, sequences, fill orchestration (Linux-only)
│   └── bin/  scripts/  examples/   # bench_kdf, mem_forensics, crash_writer, autotype_{spike,window,trigger} (diagnostics), gabbro-autotype (shipped trigger client); wordlist gen; gen_fixtures
├── rust/tests/           # Backward-compat gate + state-machine fuzzer + parse fuzzer + crash-safety (kill mid-write) + frozen golden fixtures (FIXTURES.md)
├── android/…/kotlin/…/   # GabbroUnlockHostActivity (base) + MainActivity/UnlockActivity/SaveActivity, GabbroAutofillService, TapFlow, YubiKeyManager, BiometricHelper + BiometricStore (per-vault; + Robolectric tests)
├── docs/                 # ARCHITECTURE, LEARNINGS, SECURITY, AI_*; decisions/ (ADRs); artefacts/
├── test/  integration_test/  test_driver/   # Flutter widget/unit + Linux real-FFI device suites
├── test_data/            # Sample import files + migration_vaults/ (hardware migration corpus, one vault per VERSION + MIGRATION_TESTS.md)
├── assets/               # fonts, images, help/; public_suffix_list.dat (autofill eTLD+1)
├── challenge/            # crack-me challenge vault + rules
└── CHANGELOG.md  README.md
```

## Features

Shipped features are recorded in `CHANGELOG.md`. Planned and deferred work lives in the Bikeshed at the end of this file.

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 645 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 14 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cross-version sync, v8 file (`cargo test --release --lib cross_version_sync_loads_and_merges_a_v8_file -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1264 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 12 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 140 | 15 |

**Test isolation (non-negotiable):** no test may touch real settings or vault folders. All
config/data resolves through `GabbroPaths` (`lib/app_paths.dart`); `test/flutter_test_config.dart`
roots every `flutter test` in a throwaway temp sandbox, so even a non-isolating test reads
an empty registry and never reaches a real vault. Mirrors `rust/tests/fixtures/`.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task

**Per-vault authentication isolation — full fix + cross-pollution harness.**

Goal: every vault manages its own authentication alone. No auth mechanism
(passphrase, change-passphrase, YubiKey enroll/add/remove/rotate, Android biometric,
or a vault opened on Android then Linux via sync) may cross-pollinate another vault.

**Root cause (verified).** Android biometric stores ONE AndroidKeyStore alias
(`gabbro_biometric_key`) + ONE SharedPreferences slot (`ct`/`iv`/`vault_path`) + a
single global `settings.jsonc` `biometric_unlock` bool. Enrolling vault C wipes B's
key + slot, so `isEnrolled(B)` goes false and B reverts to passphrase-only. All other
auth is crypto-bound per `.gabbro` file; the only shared mutable surface is the global
`VAULT_SESSION` singleton (holds its own path + zeroizing passphrase, one vault at a time).

**Design (plain terms) — biometric is per-device, not per-vault.**
- The biometric **secret** (the encrypted passphrase + the AndroidKeyStore key) is
  **bound to one phone's hardware** and never travels. Each device keeps its own secret,
  stored **per vault** (per-vault KeyStore alias + per-vault prefs slot).
- **No in-vault flag, no `vaults.jsonc` mirror, no version bump.** The single global
  `settings.jsonc` `biometric_unlock` bool is dropped.
- **The on-device secret is the single source of truth.** A device offers biometric for
  a vault iff it holds its own secret for that vault (`isEnrolled(vaultPath)`, readable
  while locked). Linux holds none, so it never offers.
- Why per-device and not a travelling flag: a vault synced across Linux + S23 +
  GrapheneOS has independent biometric on each phone (same fingerprint, but a unique
  hardware key per device). Disabling biometric on one phone must NOT disable it on the
  other — a single shared flag can't represent that. Sync only moves the vault file and
  never touches any device's secret, so back-and-forth sync leaves each device's
  biometric intact.
- (Linux fingerprint-reader support = bikeshed v2; same model, one more device with its
  own local secret.)

Net-first throughout: pin current behaviour green BEFORE changing it.
`[NET]`/`[PIN]` = expected green (must-not-regress / proves isolation); `[RED]` = fails now (bug).
**Execution order: start with the biometric fix (D + E) and hardware-verify, then A, B, C.**

**A. Rust — multi-vault session isolation (`session.rs` tests)**
- [ ] 1. [PIN] unlock A -> unlock B -> A's `.gabbro` bytes unchanged on disk
- [ ] 2. [PIN] after unlock B, a CRUD save writes to B's path, never A's
- [ ] 3. [PIN] lock scrubs passphrase + YubiKey material (no A material readable after switching to B)
- [ ] 4. [PIN] failed unlock of B leaves prior A session intact (or cleanly locked) — never a half-session
- [ ] 5. [PIN] wrong passphrase for B never opens A's body

**B. Rust — YubiKey per-vault (`session`/`vault_bridge` tests)**
- [ ] 6. [PIN] add YubiKey to B doesn't alter A's header records
- [ ] 7. [PIN] remove/rotate on B leaves A's key records + openability intact
- [ ] 8. [PIN] A (passphrase-only) and B (YubiKey) coexist: each opens only with its own credentials

**C. Rust — sync isolation (extend `merge_tests`)**
- [ ] 9. [PIN] syncing B from a file doesn't mutate A's auth header/body
- [ ] 10. [PIN] a vault written on "Android" (fast Argon params) opens on "Linux" and keeps its auth after a sync round-trip (cross-version already partly covered by `cross_version_sync_*`)

**D. Kotlin — biometric per-vault (`BiometricHelperTest`, Robolectric for prefs)**
- [x] 0. [NET] pinned: single-vault `isEnrolled` contract green (Robolectric) + partial-enrolment guard added; enroll/authenticate/unenroll are `@Ignore` (AndroidKeyStore not backed by Robolectric) -> the fix must split prefs bookkeeping from key lifecycle to make 11-13 unit-testable
- [x] 11. store A + store B -> both `isEnrolled` true (green via new `BiometricStore` seam)
- [x] 12. `forget`/`unenroll(vaultPath)` A leaves B enrolled (green via seam)
- [x] 13. distinct KeyStore alias per vault (green via seam); `BiometricHelper` refactored to per-vault alias + prefs, channel updated
- [x] 14. enroll -> authenticate per vault: HARDWARE-VERIFIED 2026-07-06 on device (mock vaults A/B/C). Passed: reported bug (B survives enrolling C), disable-independence, change-passphrase staleness, Android->Linux->Android sync round-trip. Key-invalidation left as optional.

**E. Dart — drop the global bool, gate on per-vault enrollment (widget tests)**
- [x] 15. enabling biometric on B doesn't affect C: global `settings.jsonc` bool REMOVED; UI gates on `isEnrolled(vaultPath)` only; `unenroll(vaultPath)` threaded through security/change-passphrase/tablet call sites (green)
- [x] 16. unlock offers biometric only for the enrolled vault: gate removed from widget, `vaultPath` now a required param on both phone + tablet paths (two-layout trap structurally prevented); per-vault display pinned in unlock_screen_test

---

## Build & Release

Build environment (Android/Kotlin/Java, SAF export) and full release process:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1)
- Human expert cryptography review of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).
- Draft the free external crypto-review outreach (narrow ask: the construction only —
  hybrid combiner / transcript binding / header AAD / vault format). Vault format is now
  stable at VERSION 9, so this is no longer blocked. v1 direction in commit 9f158b5.

### Code Quality
- **Auto-type: unlock-then-type + cold start (ADR-017 Phase 4).** A trigger while the
  vault is locked or Gabbro is closed does nothing today. Add: prompt-unlock-then-type,
  an opt-in setting, README key-binding examples, and package `gabbro-autotype` into the
  release bundle (update BUILD_AND_RELEASE). Secret stays in Rust; auto-lock preserved.
- **Autofill save loose ends.** Native review of the best-effort `eu`/`kk`/`yo` save-flow
  translations (and the `resizeColumns` label added the same way).
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.

### V2+ / Defer
- UI locales deferred (RTL layout work required): Hebrew, Kurdish.
- Passphrase wordlists — not viable without significant pipeline work: `yo` Yoruba (no frequency ordering, complex tonal diacritics); `sr_Latn` Serbian Latin (only Cyrillic corpora; needs transliteration pipeline); `lb` Luxembourgish (small speaker base); `wa` Walloon (nothing usable, French covers Wallonia).
- Passkey (WebAuthn discoverable credential) support.
- Vault sync across devices.
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