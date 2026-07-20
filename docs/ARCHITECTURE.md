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
| Rust (`cargo test -q`) | 635 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 11 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync merges a never-edited entry (`cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1545 | 4 |
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

**STATE 2026-07-20.** Four nets built (behaviours 1-4 done). Item 4 (error-l10n)
is detailed in its own section below; the other three:
- **Overflow (English) axis** — `test/overflow_probe_test.dart` sweeps 33 of 35
  screens+widgets on phone + tablet at max text (2 waived: `yubikey_tap`,
  `section_index` render nothing).
- **ARB parity** (1+2) — `test/l10n_test.dart`: every locale has the base key set,
  matches base placeholders, lists all 34 endonyms. Guarded by 37-file + 34-endonym
  counts, both proven able to fail.
- **Longer-language axis (3)** — same probe, one extra pass on the phone at max text
  under a synthetic locale that doubles every ARB label (~2x). Width does not care
  which real language produced it, so one pass stands in for all 37. Green: no screen
  or dialog overflows a ~2x locale. Two meta-guards prove it can fail (padded delegate
  reaches the tree; detection still fires).

(Flutter test count of record lives in the Testing table above.)

**How item 3 works (so it is not re-litigated).** A test-only `noSuchMethod` wrapper
implements `AppLocalizations`, returning each label's English value (read from
`app_en.arb`) doubled — no 600 overrides, no shipped locale, auto-tracks new strings.
It reaches dialogs (root routes an in-body `Localizations.override` cannot touch)
because it is installed at MaterialApp level via a new `localizationsDelegates`
override on `GabbroApp` (defaults to the real list; mirrors the existing `clock`
test-seam). The padded list swaps only `AppLocalizations.delegate`, keeping the
fallback Material/Cupertino delegates verbatim.

**Error-l10n net (item 4) — DONE; net is now a regression guard.**
`test/error_l10n_net_test.dart` scans `lib/` for `e/err.toString()` fed into
user-visible text: a site is OK only when the error is trailing detail inside an
approved meaning-carrying template; otherwise it is a raw leak in `_todoRawErrors`.
That backlog is now **empty** — every raw Rust error reaching the user sits behind
a localized template. A new unlisted leak fails the test. Principle: the localized
part must carry the MEANING, English allowed only as trailing detail (see memory
project_error_l10n_by_log_level). The classifier is statement-scoped (a formatter
wrapping a template across lines is not a false leak).

Cleared 22 sites across the session via Canon-TDD: `vaultFormatTooNew` (unlock +
import, +link), importers -> `importFailed`, `export` -> `exportFailed`,
`manage_folders` -> `folderActionFailed`, `vault_list` -> `vaultLoadFailed` +
`syncFailed`, `create_entry`/`review_changes` -> `saveEntryFailed`,
`change_passphrase` -> `changePassphraseFailed`, `recovery_history` ->
`recoveryActionFailed`, `onboarding` -> `setupFailed`, `security` ->
`biometricEnrollFailed`, `unlock` (.bak-rot) -> `restoreBackupFailed`, and
`manageYubiKeysError` repurposed from meaning-empty "Error: {x}" to "Couldn't load
YubiKeys". All new strings across 37 locales.

`_notADisplayLeak` (map in the net): 3 sites where `e.toString()` appears but is
NOT shown raw — control-flow-only, or a field wrapped by a meaning-carrying
template at the build site (the assignment runs in initState, before
AppLocalizations). `vault_list` x2, `manage_yubikeys` x1. Reviewed claims, not
false greens.

**Accessibility net (item 6) — built; backlog cleared (hardware-verify pending).**
`test/a11y_net_test.dart`
sweeps every screen and dialog on a phone at natural text scale and asserts two
Flutter guidelines: `androidTapTargetGuideline` (tappable controls >= 48dp) and
`labeledTapTargetGuideline` (every tappable node named for a screen reader). Two
meta-guards prove it fires (catch the async `TestFailure` — `isNot(meetsGuideline)`
HANGS forever, see memory reference_async_matcher_no_isnot).

The screen/dialog catalog (33 builders + test data + seams) is now
`test/screen_catalog.dart`, shared by BOTH "every screen" nets — the overflow
probe and this one — so there is one source, no drift.

Backlog: **CLEARED** — every screen passes both guidelines (net has only the 2
tablet-only skips left). Fixes:
- `appearance` high-contrast toggle: `ListTile`+trailing `Switch` -> `SwitchListTile`.
- `generator` option toggles (`_switchRow`): `MergeSemantics` so the toggle
  carries its row label.
- `vault_list` folder dropdown + `generator` wordlist dropdown:
  `selectedItemBuilder` items wrapped in `minHeight: 48`, so the collapsed button
  is a 48dp tap target (open menu items still grow, ADR-016).

**First hardware pass (S23 + TalkBack) — 3/5 passed** (both dropdowns tap cleanly
+ look right; appearance toggle announced). It found what the net structurally
can't (label *quality* + operability), now fixed:
- Generator option toggles read as glyphs ("0-9" -> "zero minus nine"). Now
  `Semantics(label:)` with the char-type name + `ExcludeSemantics` on the glyph
  (`MergeSemantics` so label + tap are one node).
- Length / word-count / **text-size** sliders were unnamed and unadjustable under
  TalkBack. Now `MergeSemantics(Semantics(label:, Slider(semanticFormatterCallback:)))`
  — named + value announced; a net guard asserts they keep increase/decrease
  actions. `TextSizeSlider` takes the label as a param (stays l10n-free).

**Pending: a SECOND hardware pass** to confirm TalkBack now announces + adjusts
the toggles and sliders. The net cannot verify label quality or TalkBack
operability — that is hardware-only.

**The behaviour still needing a net.** What a user cannot do:
5. Dark mode or high contrast makes text unreadable, or the setting does nothing.

**NEXT STEP: re-run the S23/TalkBack pass on the toggle + slider fixes, then item
5 (dark/high-contrast) with [maintainer]. Items 1-4 done; item 6 net + backlog +
TalkBack-quality fixes done (2nd hardware pass pending).**

**Still-relevant traps (items 4-6)**
- A child clipped inside a fixed-size box throws no exception, so the probe cannot
  see it — clipping defects need hardware, not this net. Two of three past defects
  were clipping (recovery-history actions, sync_review chip values).
- Probing a widget outside the conditions the app builds it in reports an overflow
  the user can never meet. The two-pane layout is gated >= 600dp
  (`vault_list_screen.dart:1517`); `_tabletOnly` records the restriction.
- Collecting `tester.takeException()` filtered to `FlutterError` drops the "Multiple
  exceptions (N)" wrapper and reports a false green. Take any non-null.

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
- **Vault format version is meaningless to the user.** "v10"/"v11" is the file format and
  tracks neither the app version nor the alpha number. Both too-old and too-new paths are
  now handled: unlock and Gabbro-source import probe `vaultFormatTooOld()` /
  `vaultFormatTooNew()` and show a localized message + link, naming no number, in all 37
  locales. The only remaining leak of `file_format.rs:264` (too old) is the five importers
  below, which show the raw Rust string instead of probing — covered by fixing those (the
  error-l10n net's importer backlog).

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