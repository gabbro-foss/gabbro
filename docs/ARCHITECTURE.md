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

**Platforms:** v1: Linux (Arch + Mint/deb), Android, GrapheneOS. v2 maybe: Windows.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Every dependency licence must be GPL-3.0 compatible; the allow-list is `rust/deny.toml`, enforced by the `cargo deny` gate leg.

**Version control:** private GitHub repo at https://github.com/gabbro-foss/gabbro. SSH auth.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, export, import, generator, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, sync_review, text_size_slider, url_link, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, text_scale, control_scale, vault_registry, safe_file_picker, autotype_listener, autotype_target, clipboard_clear
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
├── docs/                 # ARCHITECTURE, SECURITY, VAULT_UPGRADE_PATH, VAULT_SYNC, AUTOTYPE_AND_AUTOFILL, RT3_CLEANUP, AI_*; decisions/ (ADRs); artefacts/
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
| Rust (`cargo test -q`) | 634 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 11 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync merges a never-edited entry (`cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1277 | 0 |
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

**Net for l10n + accessibility on every screen.**

Scope: all locales, 8x text on a 360px phone, overflow, light/dark, high-contrast,
tap targets, screen reader labels. Rust-originated strings bypass the ARB and must
be included.

First attempt (2026-07-19, Claude Opus 4.8) was reverted — nothing committed. What it
established, so it need not be redone:

**Verified**
- `test/overflow_probe_test.dart` already sweeps 14 screens x 2 surfaces at max text
  scale, English only. Extend it; do not rebuild.
- The locale axis is cheap: 34 locales x 17 screens x 2 surfaces ran in ~29 s. Cost
  was never the obstacle (an earlier "too slow" claim was made without measuring).
- ARB key sets and placeholder tokens are identical across all 37 locales today
  (jq-verified) but nothing asserts either — both are cheap tests to add.
- Placeholder tokens stay ASCII in every script, so `\{(\w+)\}` matches inside
  Greek/Cyrillic/CJK messages.

**Defects found**
- `lib/screens/recovery_history_screen.dart:96` — the `ListTile` `trailing` Row
  overflows at 360dp/2.0x in 24 of 34 locales; en, ja, ko, zh*, da, et, hr, sl, sr*
  pass, which is why it was invisible. `trailing` is intrinsically sized, so the fix
  is moving the actions out of it, not an `Expanded`. The comment at
  `overflow_probe_test.dart:149` calling this fixed is true for English only.
- `lib/widgets/sync_review.dart` — the password field cannot be scrolled and
  overflows even at small text (seen in device use). The probe **cannot** catch this:
  a child clipped inside a fixed box throws no exception.

**Traps**
- Sweeping locales inside one `testWidgets` needs the tree torn down between pumps
  (`pumpWidget(SizedBox())` first), or a stale overflow is blamed on the next locale
  — including `en`, which passes standalone. This produced a false defect report.
- A screen-coverage guard must enumerate `lib/widgets/` as well as `lib/screens/`.
  sync_review, generator_widget, password_breakdown_sheet and yubikey_tap live there;
  an attempt that checked only `lib/screens/` missed the sync_review bug entirely.
- `overflow_probe_test.dart:29` cites `docs/PHASE2_OVERFLOW_COVERAGE.md`, which does
  not exist.

**Not attempted:** light/dark, high-contrast, tap targets, screen reader labels,
Rust-originated strings. The first attempt built the locale and overflow axes only
and treated that as the whole task — it is roughly a third of the scope above.

**How the first attempt went wrong** — the method failures that produced the above,
recorded so the next attempt does not repeat them:
- *Never checked the work against the requirement.* A scenario list was invented at
  the start and then treated as the definition of done. The Bikeshed text was not
  re-read once. That is the single reason two thirds of the scope went missing.
- *Asserted instead of measuring.* "Too slow for `flutter test`" was stated with no
  timing run; the real figure was ~12 s. A "real defect found" was announced while
  `en` sat in the failure list, having passed minutes earlier — it was a harness bug.
  Both were caught by the maintainer, not by the work.
- *Built the guard without testing the guard.* The screen-coverage test existed
  solely to fail when a screen is unswept, and was pointed at `lib/screens/` without
  ever listing `lib/widgets/`. It reported green while missing nine widgets.
- *Overstated coverage.* Nine screens were waived as "covered by" other tests; that
  coverage is English-only overflow, and in two cases only logic tests. The word
  claimed far more than the tests do — see the waiver reasons before trusting them.
- *Constraints were not propagated to subagents.* Repo rules (no interpreters, no
  absolute host paths) do not reach spawned agents automatically and must be written
  into each agent prompt.

CLAUDE.md was read at session start and then not followed. Every rule under
`## Messages to the [user]` was broken, repeatedly:
- *Terse, no walls of text.* Nearly every message was long: tables, multi-section
  status reports, and restated context the maintainer already had. Correcting this
  took three separate interventions and it still recurred.
- *Never ask a question and continue without waiting.* Questions were asked and work
  continued in the same turn; decisions were also presented as settled while asking
  about one narrow point, which anchors the answer.
- *Name the consequence, not the artifact.* Findings were reported as `RenderFlex`,
  `ListTile trailing`, probe and registry internals. The maintainer had to ask
  outright what the defect meant for a user before that was stated.

Also broken from the Session Start Checklist: absolute host paths (`/home/<user>/...`)
were written into agent prompts and shell commands, which the checklist forbids
because the repo goes public.

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
- **The other five importers still show raw Rust errors.** Enpass, Bitwarden, Google PM,
  Dashlane and CSV all set their error to `e.toString()`, so any Rust failure reaches the
  user untranslated. The Gabbro source was fixed (matrix 4.2 / 4.4); these were not.
- **Vault format version is meaningless to the user.** "v10"/"v11" is the file format and
  tracks neither the app version nor the alpha number. Checked 2026-07-18 — the too-OLD
  path is already fixed: unlock and Gabbro-source import probe `vaultFormatTooOld()` and
  show `vaultFormatTooOld` + the upgrade link, naming no number, clean in all locales.
  Two raw Rust strings still leak it, both English-only:
  - `file_format.rs:264` (too old) — surfaces only where the raw error is shown instead of
    the probe, i.e. the five importers above; fixing those covers it.
  - `file_format.rs:255` (too NEW) — **the real gap.** No `vaultFormatTooNew` ARB string
    exists at all, so a vault written by a newer build gives an untranslated message citing
    a meaningless number. Reachable by syncing between devices on different versions.
    Needs a new localized string + a probe, mirroring the too-old path.

### Security (pre-v1)
- Human expert cryptography review of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).

### Going public (pre-v1)
- **Flip the repo to public.** Repo now lives in the `gabbro-foss` org (transferred; URLs
  migrated). Flip visibility to public once the pre-v1 gates clear (crypto-review outreach
  above is welcome-not-blocking). Optional: a read-only Codeberg mirror for redundancy.

### Code Quality
- **Linux ships no desktop icon.** No `.desktop` file and no hicolor icon tree, so an
  installed build (AUR) shows a generic placeholder in the app menu and taskbar. Render
  16/32/48/64/128/256/512 plus a scalable SVG from `ic_launcher_*.svg` and add a `.desktop`
  entry. Blocked on the new logo. Same render covers the Windows `.ico`, still the stock
  Flutter template.
- **Auto-type: unlock-then-type + cold start (ADR-017 Phase 4).** A trigger while the
  vault is locked or Gabbro is closed does nothing today. Add: prompt-unlock-then-type
  and an opt-in setting. Secret stays in Rust; auto-lock preserved.

### V2+ / Defer
- **Linux biometric unlock** (laptop fingerprint readers, e.g. libfido2/PAM or `fprintd`). Fits the current per-device model unchanged: Linux would just get its own local per-vault secret store; the vault file carries no biometric state, so nothing else changes.
- Passkey (WebAuthn discoverable credential) support.
- Custom and hideable filter chips (post-v1 user feedback gate).
- Windows support.
- Yubico partnership.
- Destination Linux podcast outreach (when approaching public release).
- Donation/sustainability model (GitHub Sponsors + Liberapay + Monero — dedicated session near release).
- No-telemetry verification guide (ripgrep scan, Wireshark, NetGuard).
- Support model (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).
- Import: content-hash deduplication and entry-level merge.