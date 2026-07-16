# Gabbro Architecture

## Project Overview

A quantum-resistant password manager.
Named after the intrusive igneous rock — hard, stable, enduring.
Cross-platform: Linux (Arch, Mint), Android; Windows later. FOSS, GPL-3.0-only.

**Core principle:** all keys and cryptography live in Rust; the vault is decrypted there and the master keys never cross the bridge. Secrets the user actively views, generates, or autofills do reach Flutter in plaintext to be displayed (bounded by auto-lock; the Dart heap retains them until GC — see SECURITY.md / audit F-12) — the keys never do.

## General Information

**Tech stack:** Flutter (Dart) frontend, Rust backend/crypto, flutter_rust_bridge v2 (FFI).

**Encryption (at rest):** Argon2id KDF → HKDF-SHA256 → AES-256-GCM. Quantum resistance from Argon2id + AES-256-GCM (ADR-018). New vaults (VERSION 11+) derive the vault key straight from the Argon2id output; the removed X25519 + ML-KEM-1024 hybrid layer survives read-only to open/migrate ≤v10 vaults (dropped entirely at RT-3).

**Authentication (app access):** Passphrase always; a FIDO2/WebAuthn hardware key (YubiKey) is strongly recommended but **not enforced** — a passphrase-only vault is the default. When keys are used: v1 Ed25519 (hardware constraint), target ML-DSA-44 once Yubico ships PQ-capable hardware (ADR-005), min 2 keys (primary + backup), max 4. Auto-lock: 30s default, configurable.

**YubiKey NFC / NDEF OTP:** a YubiKey's OTP slot 1 (an NDEF URI) would open a browser when tapped on Android. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` and by re-arming foreground dispatch after `stopNfcDiscovery`; OTP slot 1 can stay enabled (no `ykman` workaround).

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce; ≤v10 also carry an ML-KEM ciphertext + X25519 ephemeral pubkey, dropped at v11) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, many languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text scale (`text_scale`, 0.8-8.0), high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android, GrapheneOS. v2 maybe: Windows.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Every dependency licence must be GPL-3.0 compatible; the allow-list is `rust/deny.toml`, enforced by the `cargo deny` gate leg.

**Version control:** private GitHub repo at https://github.com/gabbro-foss/gabbro. SSH auth.

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
├── docs/                 # ARCHITECTURE, SECURITY, VAULT_UPGRADE_PATH, VAULT_SYNC, RT3_CLEANUP, AI_*; decisions/ (ADRs); artefacts/
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
| Rust (`cargo test -q`) | 668 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 18 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cross-version sync, v8 file (`cargo test --release --lib cross_version_sync_loads_and_merges_a_v8_file -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1257 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 12 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 148 | 15 |

**Integration suites must use `testWidgets`, not `test` (non-negotiable):** only `testWidgets`
reaches the `integration_test` binding's result recorder, so a plain `test()` failure leaves the
`flutter drive` leg reporting success and exiting 0 — silently blind. Enforced by a grep guard in
`gabbro_test`. (The "integration_test plugin was not detected" warning is unrelated and cosmetic:
it is the native Android/XCTest reporting channel, absent on Linux desktop.)

**Test isolation (non-negotiable):** no test may touch real settings or vault folders. All
config/data resolves through `GabbroPaths` (`lib/app_paths.dart`); `test/flutter_test_config.dart`
roots every `flutter test` in a throwaway temp sandbox, so even a non-isolating test reads
an empty registry and never reaches a real vault. Mirrors `rust/tests/fixtures/`.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task

Fix warnings from last gate run — see Bikeshed `### Code Quality` for individual items.

---

## Build & Release

Build environment (Android/Kotlin/Java, SAF export) and full release process:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Features and UI/UX
- See if vault `syncing` can do without a second `passphrase + yubikey` if and only if the current vault and the incoming vault share the same `alias`, `passphrase`, `yubikey(s)`
- in `sync` path, we currently have `auto-merge` and `review all changes`, the `auto-merge` is additive only (check and verify) and therefore never deletes items in the receiving vault: (1) add a message that explains this (or the correct) behaviour to the user, (2) add a third `sync` mechanism that simply takes the incoming vault and clobbers the existing one - discuss this
- Autotype in linux often has typos in the login/email. and it often fails perhaps due to a typo in the passphrase. investigate.

### Security (pre-v1)
- Human expert cryptography review of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).

### Going public (pre-v1)
- **Flip the repo to public.** Repo now lives in the `gabbro-foss` org (transferred; URLs
  migrated). Flip visibility to public once the pre-v1 gates clear (crypto-review outreach
  above is welcome-not-blocking). Optional: a read-only Codeberg mirror for redundancy.

### Code Quality
- Kotlin-version warning (Android gate leg): `WARNING: Unsupported Kotlin plugin version. The
  embedded-kotlin and kotlin-dsl plugins rely on features of Kotlin 2.0.21 that might work
  differently than in the requested version 2.2.20`. Emitted under `> Configure project :gradle` —
  that project is the Flutter SDK's own included build `flutter_tools/gradle/build.gradle.kts`
  (pulled in by `android/settings.gradle.kts:11`), which applies `kotlin-dsl` + `kotlin("jvm")
  version "2.2.20"` (lines 10-11). Gradle 8.14 embeds Kotlin 2.0.21; Flutter's build requests
  2.2.20 on top. Both versions live outside our tree (Flutter SDK install + Gradle wrapper) — we
  set neither; upstream-owned. Cosmetic. Verified 2026-07-16: it appears in release builds too
  (`./gradlew :app:assembleRelease`) — it is a configure-phase warning, so build type is
  irrelevant. `flutter build apk` hides it (the tool suppresses Gradle's configure output).
- **RT-3 + dual-lock cleanup (merged, floor → v11)** — once no ≤v10 vault remains: delete the
  legacy `StdRng` X25519, the legacy ML-KEM + dual-lock derivations, and the frozen-golden
  tripwire; **drop the `ml-kem` + `x25519-dalek` crates** (supply-chain surface → zero); min
  supported version → v11 (≤v10 rejected gracefully, never bricked); convert the v2–v10 gate
  fixtures to a graceful-rejection test; migration-vault + gate corpus floor → v11. The v11
  auto-migrate release (alpha.14) has shipped; gated now only on field vaults migrating off ≤v10
  — see VAULT_UPGRADE_PATH.md. Also silences the `hybrid-array` 0.2.3/0.4.12 `cargo deny` duplicate
  warning for free: `ml-kem` is its only source. **Exhaustive deletion checklist:
  [RT3_CLEANUP.md](RT3_CLEANUP.md).**
- **Auto-type: unlock-then-type + cold start (ADR-017 Phase 4).** A trigger while the
  vault is locked or Gabbro is closed does nothing today. Add: prompt-unlock-then-type,
  an opt-in setting, README key-binding examples, and package `gabbro-autotype` into the
  release bundle (update BUILD_AND_RELEASE). Secret stays in Rust; auto-lock preserved.
- **Autofill save loose ends.** Native review of the best-effort `eu`/`kk`/`yo` save-flow
  translations (and the `resizeColumns` label added the same way).
- **Native-review `aboutTagline` translations** (all locales, 2026-07-09 rename): `eu` Basque
  and `yo` Yoruba lowest confidence, `kk`/`lt` medium.
- Gradle space-assignment deprecations (16 remaining, Android leg): `Properties should be assigned
  using the 'propName = value' syntax ... deprecated ... removed in Gradle 10.0`. All 16 are in
  pub-cache plugins we don't control (`jni-1.0.0` x6, `jni_flutter-1.0.1` x5, `file_picker-11.0.2`
  x5) — upstream-owned; wait for releases. (The 4 that were ours, in
  `rust_builder/android/build.gradle`, are fixed — and verified to survive
  `flutter_rust_bridge_codegen generate`, which does not own that file: the frb config scopes to
  `rust/` -> `lib/src/rust` only.) Cosmetic until Gradle 10; gate stays green.
- Android gate leg: `WARNING: java.lang.System::load has been called ... restricted method`. The
  caller is `net.rubygrapefruit.platform.NativeLibraryLoader` inside Gradle 8.14's own
  `native-platform-0.22-milestone-28.jar` (`gradle-8.14/lib/`), not our code or a plugin. Newer
  JDKs require modules to declare native access; Gradle 8.14 doesn't, so the JVM warns — and the
  warning says it becomes a hard error in a future JDK. Fix is ours to time, not upstream's to
  ship: bump the Gradle wrapper (`android/gradle/wrapper/gradle-wrapper.properties`, currently
  `gradle-8.14-all`) to a version whose bundled `native-platform` declares native access. A
  wrapper bump is a full-gate change (AGP 8.11.1 / Kotlin 2.2.20 compat), not a warning tweak — do
  it deliberately. Cosmetic until then; gate stays green.
- `cargo deny` `no-license-field` warning on `allo-isolate` (via `flutter_rust_bridge`): the
  published 0.1.27 manifest declares only `license-file`, no SPDX `license` field, so deny infers
  Apache-2.0 from the file text and passes. Already fixed on their master — wait for a release.
  Cosmetic; gate stays green. A `[[licenses.clarify]]` entry does NOT suppress it (tested
  2026-07-16: inert, silently ignores a wrong hash and a disallowed expression) — don't retry it.
- `cargo deny` duplicate warnings, 6 of 8 (`block-buffer`, `crypto-common`, `digest`,
  `cpufeatures`, `libloading`, `shlex`): two deps pin incompatible versions of a shared crate.
  Upstream-owned (`argon2` -> `digest` 0.11, `jni` -> `libloading`, `bindgen` -> `shlex`);
  warn-only, gate stays green. Diagnosed 2026-07-16 — don't re-diagnose.
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.

### V2+ / Defer
- **Linux biometric unlock** (laptop fingerprint readers, e.g. libfido2/PAM or `fprintd`). Fits the current per-device model unchanged: Linux would just get its own local per-vault secret store; the vault file carries no biometric state, so nothing else changes.
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
- `cargo miri` — **rejected, don't re-propose.** Miri cannot cross an FFI boundary, and
  every `unsafe` block here is exactly that: `frb_generated.rs` (68, Dart bridge),
  `hardening.rs` (12, libc), `fido/` (4, libfido2), `mem_forensics.rs` (2). `crypto/` and
  `vault/` contain zero `unsafe`. Miri would have nothing in scope to check — and needs a
  nightly toolchain we don't install. Revisit only if internal `unsafe` ever appears.
- `cargo fuzz` (coverage-guided libFuzzer) — deferred: needs nightly. `tests/vault_parse_fuzz.rs`
  already covers the attacker-controlled surface (truncation, garbage, oversized length
  fields) on stable and caught the real `pos + body_len` overflow. Revisit as an occasional
  soak, not a gate leg — it is unbounded by nature.