# Gabbro Architecture

## Project Overview

A quantum-resistant password manager.
Named after the intrusive igneous rock — hard, stable, enduring.
Cross-platform: Linux (Arch, Mint), Android; Windows later. FOSS, GPL-3.0-only.

**Core principle:** all keys and cryptography live in Rust; the vault is decrypted there and the master keys never cross the bridge. Secrets the user actively views, generates, or autofills do reach Flutter in plaintext to be displayed (bounded by auto-lock; the Dart heap retains them until GC — see SECURITY.md / audit F-12) — the keys never do.

## General Information

**Tech stack:** Flutter (Dart) frontend, Rust backend/crypto, flutter_rust_bridge v2 (FFI).

**Encryption (at rest):** Argon2id KDF → HKDF-SHA256 → AES-256-GCM. Quantum resistance from Argon2id + AES-256-GCM (ADR-018). The vault key derives straight from the Argon2id output. The X25519 + ML-KEM-1024 hybrid layer was non-load-bearing and is gone: RT-3 deleted it with the `ml-kem` + `x25519-dalek` crates, and v11 is now the oldest readable format (≤v10 refused intact — see [VAULT_UPGRADE_PATH.md](VAULT_UPGRADE_PATH.md)).

**Authentication (app access):** Passphrase always; a FIDO2/WebAuthn hardware key (YubiKey) is strongly recommended but **not enforced** — a passphrase-only vault is the default. When keys are used: v1 Ed25519 (hardware constraint), target ML-DSA-44 once Yubico ships PQ-capable hardware (ADR-005), min 2 keys (primary + backup), max 4. Auto-lock: 30s default, configurable.

**YubiKey NFC / NDEF OTP:** a YubiKey's OTP slot 1 (an NDEF URI) would open a browser when tapped on Android. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` and by re-arming foreground dispatch after `stopNfcDiscovery`; OTP slot 1 can stay enabled (no `ykman` workaround).

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, many languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text scale (`text_scale`, 0.8-8.0), high-contrast, alphabet bar position.

**Keyboard shortcuts (Linux desktop):** Ctrl+L lock, Ctrl+F / Ctrl+Shift+F search, Ctrl+N new entry, Ctrl+M menu, Ctrl+Q lock and quit (confirms first), Esc dismiss/cancel. No Ctrl+C (copying a secret stays a deliberate, auto-clearing action); no Super key. Listed in-app on the desktop-only Keyboard shortcuts screen.

**Platforms:** v1: Linux (Arch + Mint/deb), Android, GrapheneOS. v2 maybe: Windows.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Every dependency licence must be GPL-3.0 compatible; the allow-list is `rust/deny.toml`, enforced by the `cargo deny` gate leg.

**Version control:** public GitHub repo at https://github.com/gabbro-foss/gabbro. SSH auth.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, export, import, generator, keyboard shortcuts, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, sync_review, text_size_slider, url_link, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, text_scale, control_scale, gabbro_contrast (high-contrast theme flag), vault_registry, safe_file_picker, autotype_listener, autotype_target, clipboard_clear
├── rust/src/
│   ├── api/              # Bridge surface: vault, vault_bridge, import, *_generator, fido_bridge, autofill_bridge, autotype_bridge, entropy, types
│   ├── crypto/           # Internal (not bridge-exposed): kdf, hkdf, aes_gcm, vault_crypto
│   ├── vault/            # Domain model: entry, file_format, io, serialization, session
│   ├── fido/             # FIDO2/libfido2 FFI (Linux only)
│   ├── import/           # enpass, bitwarden, google_pm, dashlane, csv
│   ├── hardening.rs      # Process hardening (R-04): core-dump + ptrace/mem disable (Linux)
│   ├── autotype/         # Linux auto-type (ADR-017): keysym, XTEST inject, active-window read, trigger IPC, sequences, fill orchestration (Linux-only)
│   └── bin/  scripts/  examples/   # bench_kdf, mem_forensics, crash_writer, autotype_{spike,window,trigger} (diagnostics), gabbro-autotype (shipped trigger client); wordlist gen; gen_fixtures
├── rust/tests/           # Backward-compat gate + state-machine fuzzer + parse fuzzer + crash-safety (kill mid-write) + frozen golden fixtures (FIXTURES.md)
├── android/…/kotlin/…/   # GabbroUnlockHostActivity (base) + MainActivity/UnlockActivity/SaveActivity, GabbroAutofillService, TapFlow, YubiKeyManager, BiometricHelper + BiometricStore (per-vault; + Robolectric tests)
├── linux/packaging/      # Desktop integration: render_icons.sh (icon tree); aur/ (AUR gabbro-bin PKGBUILD + .SRCINFO), deb/ (build-deb.sh -> binary .deb)
├── docs/                 # ARCHITECTURE, SECURITY, VAULT_UPGRADE_PATH, VAULT_SYNC, AUTOTYPE_AND_AUTOFILL, AI_*; decisions/ (ADRs); artefacts/
├── test/  integration_test/          # Flutter widget/unit + Linux real-FFI suites (dart test)
├── test_data/            # Sample import files + migration_vaults/ (refusal corpus at floor v11, one vault per VERSION + MIGRATION_TESTS.md + test_matrix.md)
├── assets/               # fonts, images, help/; public_suffix_list.dat (autofill eTLD+1)
├── challenge/            # crack-me challenge vault + rules
└── CHANGELOG.md  README.md
```

## Features

Shipped features are recorded in `CHANGELOG.md`. Planned and deferred work lives in the Bikeshed at the end of this file.

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 655 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 11 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync merges a never-edited entry (`cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1985 | 10 |
| Real-FFI suites (`dart test integration_test/ -j 1`) | 12 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 148 | 15 |

**Real-FFI suites run under plain `dart test`, never `flutter drive` (non-negotiable):** they test
Dart -> FFI -> crypto -> disk, touch no UI, and so need no window. Needs the release cdylib (debug
Argon2id blows the timeouts) and `-j 1` (the Rust session is process-global; parallel suites clobber
each other). Under `flutter drive` they were blind (a failure exited 0) and crashed on a WM resize
— see LEARNINGS.md.

**Test isolation (non-negotiable):** no test may touch real settings or vault folders. All
config/data resolves through `GabbroPaths` (`lib/app_paths.dart`); `test/flutter_test_config.dart`
roots every `flutter test` in a throwaway temp sandbox, so even a non-isolating test reads
an empty registry and never reaches a real vault. Mirrors `rust/tests/fixtures/`.

**Known warnings — triaged 2026-07-16, no action. Gate stays green; don't re-diagnose.**

| Warning | Source | Why not fixed |
|---|---|---|
| Kotlin plugin version (2.0.21 vs 2.2.20) | Flutter SDK's own `:gradle` build | Upstream. Debug and release alike. |
| Gradle space-assignment x16 | pub-cache `jni`, `jni_flutter`, `file_picker` | Upstream. Hard error at Gradle 10. |
| JVM restricted-method (`System::load`) | Gradle 8.14 `native-platform` jar | Needs a wrapper bump — a full-gate change, do deliberately. |
| `cargo deny` no-license-field: `allo-isolate` | `flutter_rust_bridge` dep | Fixed on their master; await release. `[[licenses.clarify]]` is inert — don't retry. |
| `cargo deny` duplicates x6 | `argon2`->`digest`, `jni`->`libloading`, `bindgen`->`shlex` | Upstream pins. Was x7; RT-3 took the `hybrid-array` duplicate with `ml-kem`. The crate itself stays (`sha2`/`hkdf` -> `digest` need it). |
| KGP via `buildscript` classpath | `file_picker`, `url_launcher_android` | Upstream. Future Flutter hard error. |

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task

Build the net (R8–R10 below). No production change starts until it is green.

### Faster sync, attempt 2 — this branch

Branched from master 2026-07-28. Documentation only; no code yet.

**Two changes, both touching the vault:**
1. **Silent sync** for the same vault; a warning when only the passphrase matched.
2. **Adopt a vault file** — a new flow from `onboarding_screen`, `unlock_screen` and
   `manage_vaults_screen` that opens an existing `.gabbro` as a vault on a second device.

**Agreed split:** `sync from file` is the same vault, only ever. `import entries` is any
other source, always full credentials.

Attempt 1 (`sync_without_second_unlock`) is unmerged and never hardware-tested; its
key-protected silent path is unreachable for independently created vaults. **Do not merge,
do not delete until picked clean.**

**Verified 2026-07-29:**
- One save choke point: `do_save` (`rust/src/vault/session.rs:178`). All five importers,
  alias change, YubiKey add/remove and CRUD reach it. Pin it once, not per importer.
- No adoption flow exists. `onAddVault` (`lib/main.dart:1109`) only creates;
  `_restoreFromFile` (`lib/screens/unlock_screen.dart:450`) is gated on a corrupt vault and
  overwrites a registered path.
- `import entries` (`lib/screens/import_screen.dart:445`) already demands full credentials.
  Wording only.
- Already pinned, do not re-pin: export, all 3 write paths (`rust/src/api/vault.rs:2786-3093`);
  alias AAD rebinding (`rust/src/api/vault_bridge.rs:1658`); YubiKey add/remove + `.bak`
  (`rust/src/vault/session.rs:5202-5293`); keyed file→disk sync of a different vault
  (`rust/src/api/vault_bridge.rs:2376`); cancel-sync, no-leak, batched apply, fast-merge walk
  (6 `#[ignore]` tests, run by `gabbro_test:80-85`).
- Export date on/off is a filename only, no crypto (`lib/screens/export_screen.dart:25`).

**The net — R1–R10:**

R1–R3 done: 8 pins in `rust/src/api/vault_bridge.rs`, green in release.
R4 done: 7 pins in `test/vault_registry_test.dart`. Registering a known path twice
leaves the vault listed twice; `remove`/`updateAlias`/`touchLastUsed` then hit both.

R5 done: 4 pins in `rust/src/vault/io.rs`. `restore_vault_from_file` already refuses
pre-v11 and too-new sources and leaves the target untouched; the refusal carries the
version + upgrade URL. Widget half was already covered by `unlock_screen_test.dart`.

R6 done: create now refuses an occupied path (`refuse_if_path_taken`,
`rust/src/vault/io.rs:13`) — it used to seal an empty vault over an existing one.
2 red-then-green tests + 2 unlock-screen pins. Export, restore and save overwrite by
design and are unchanged. Every route to "add a vault" is the create screen.

R7 done: 4 pins in `test/import_screen_test.dart`. All four Sync-from-vault guards
(`import_screen.dart:448-466`) were untested; an empty PIN would have reached the key.

| # | Pins | Level |
|---|---|---|
| R8 | sync-method chooser reachable + translated, 37 locales x 8x x 360dp — port from attempt 1, strip `warnSamePassphrase` | widget |
| R9 | restore-from-file does not unenroll biometrics today, then red for H1 | widget, Android |
| R10 | no `.bak` after restore-from-file today, then red for H2 | Rust |

**Three defects to fix in this branch:**
- **H1 — biometrics survive a vault swap at the same path.** `unenroll` fires on passphrase
  change only (`lib/screens/vault_list_screen.dart:1436`); restore-from-file replaces the
  bytes and leaves an enrolment that unlocks with the *previous* vault's passphrase (keyed by
  SHA of the path, `BiometricStore.kt:21`).
- **H2 — restore-from-file rotates no `.bak`** (`rust/src/vault/io.rs:221`). Every other write
  path does. A mis-picked file destroys the previous vault with no undo.
- **H3 — the occupied-path refusal reaches the user in English only.** The create screen shows
  "Setup failed: A file already exists at …" (Rust text via `onboarding_screen.dart:515`).
  Needs a localized check in the screen before create is called, all 37 ARBs; the Rust guard
  stays as the backstop.

**Design notes:**
- Linux adoption needs no file copy — register a `VaultRecord` at the picked path. Android's
  picker returns a cache copy, so a copy into app storage is forced there. That asymmetry
  decides whether adoption reuses `restore_vault_from_file`.
- A new screen must enter `test/screen_catalog.dart` and bump `screenFileCount`; that enrols
  it in the overflow probe, three a11y nets, three keyboard nets and the traversal baseline.
  New strings need all 37 ARBs (`test/l10n_test.dart` enforces the key set).
- Any new `#[ignore]` sync test must be added to `gabbro_test`, or it never runs.

**Salvage from attempt 1:** the sync-method chooser extraction and its l10n/overflow test
(R8). Rebuild passphrase-only silent sync without the cached-master branch — the probe
collapses to one bool, the warning becomes unconditional. Keep the cached-master path and
`open_vault_body_with_master` until adoption is designed; adoption is what needs them.

**Findings not to be re-litigated:**
- A passphrase-only save re-seals the whole file with fresh salts (`session.rs:186`,
  `rust/src/api/vault.rs:1079`). Nothing per-vault survives but the alias, so "it opened"
  proves only *same passphrase* — hence the warning. An entry-UUID-overlap heuristic was
  **rejected** (cries wolf on an empty or fully-replaced vault); do not re-propose it.
- A key-protected save re-seals the body only (`reseal_vault_body`,
  `rust/src/crypto/vault_crypto.rs:335`), so the random per-vault master survives every save,
  alias change and key add/remove. Two files sharing a master are provably the same vault.
- The AES-GCM AAD binds a header to its own body only (`rust/src/vault/file_format.rs:163`).
  Not a cross-file check — the alias comparison is policy, not crypto.
- A YubiKey set that differs per device is expected and must **not** be compared: add/remove
  rewraps the same master. The hmac-secret salt is random per registration
  (`rust/src/fido/device.rs:123`), so a genuinely different vault always needs a tap.
- The credential screen stays the fallback for every case not proven silent.
- Nothing here is done until it runs on hardware with mock vaults.

---

## Build & Release

Build environment (Android/Kotlin/Java, SAF export) and full release process:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Features and UI/UX
- **Final launcher logo (logo-blocked).** `render_icons.sh` renders a placeholder
  SVG. When the real logo lands, replace `assets/images/source/ic_launcher_light.svg`
  and re-run it; same render covers the Windows `.ico` (still the stock Flutter template).
- in `sync` path, we currently have `auto-merge` and `review all changes`, the `auto-merge` is additive only (check and verify) and therefore never deletes items in the receiving vault: (1) add a message that explains this (or the correct) behaviour to the user, (2) add a third `sync` mechanism that simply takes the incoming vault and clobbers the existing one - discuss this

### Code Quality
- **The vault list body overflows at 8x text on a 360dp phone.** A `Column` in
  `vault_list_screen.dart`, ~232-814 px over. The overflow probe sweeps at 2x, which is why
  it never saw this. Related: an `AlertDialog`'s `actions` never scroll, so any button left
  there is unreachable at the maximum text scale — audit every dialog that still puts one
  there. Found during the sync-without-a-second-unlock investigation.

- **Can the auto-type fill error carry secret material to stdout?** `lib/main.dart:478`
  prints the exception text from `autotypeFill`, and `debugPrint` writes in release builds
  too — visible to anyone who launched Gabbro from a terminal. The fill runs in Rust, so the
  error is expected to be something like "window not found", but that is untraced. If it can
  never carry secret material, leave all three auto-type prints (`main.dart:459, 462, 478`)
  as useful diagnostics for a feature that talks to X11; if it can, silence that one in
  release. Answer the question before changing anything.

- **Does a passphrase-only downgrade export mean to drop the vault's name?**
  `build_passphrase_only_bytes` (`rust/src/api/vault.rs:1013`) passes `None` as the alias,
  so the exported copy has no name and opens as an unnamed vault. May be deliberate
  (ADR-013) or an oversight — decide before changing anything. Found during the
  sync-without-a-second-unlock investigation.

### Security (pre-v1)
- Human expert cryptography review of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).

### V2+ / Defer
- **Linux biometric unlock** (laptop fingerprint readers, e.g. libfido2/PAM or `fprintd`). Fits the current per-device model unchanged: Linux would just get its own local per-vault secret store; the vault file carries no biometric state, so nothing else changes.
- Passkey provider: store website passkeys (WebAuthn discoverable credentials) in
  the vault so they sync/back up. Distinct from the YubiKey (which unlocks the app);
  tradeoff — website private keys would live in the vault, not in hardware.
- Custom and hideable filter chips (post-v1 user feedback gate).
- Windows support.
- Yubico partnership.
- Donation/sustainability model: GitHub Sponsors is live; Monero possible later (a large, dedicated effort). Liberapay ruled out (2026-07-22 — Stripe forces business-type onboarding for individuals and has suspended Liberapay-linked accounts; no PayPal). Don't re-propose Liberapay.
- No-telemetry verification guide (ripgrep scan, Wireshark, NetGuard).
- Support model (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).
- Import: content-hash deduplication and entry-level merge.