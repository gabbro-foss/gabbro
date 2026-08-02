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
│   ├── screens/          # unlock, vault list, adopt vault, export, import, generator, keyboard shortcuts, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, sync_review, sync_method_dialog, text_size_slider, url_link, …
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
| Rust (`cargo test -q`) | 689 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 11 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync merges a never-edited entry (`cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 2066 | 10 |
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
The sandbox is never torn down mid-run (`testMain()` returns at declaration, not completion —
a teardown there once nulled it before any test ran and a production save overwrote the real
registry, 2026-08-01). Pinned by `test/sandbox_net_test.dart`, including a self-restoring
canary that drives the real save paths and byte-compares the real config/vault locations.

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

(empty — set with maintainer)

### Faster sync

Attempt 2 merged to master 2026-08-01 (`93aeaac`; gate ALL GREEN on `94bcf19`),
branch deleted local + remote. All three rows hardware-passed; tick-lists and
findings in git log. Attempt 1: the `916cbc0` port landed 2026-08-02 (9 Rust
pins, obsolete Dart pin dropped); `sync_without_second_unlock` branch deletion
+ full gate (= alpha.17 pre-flight) pending.

Mock vaults for future rounds: `.scratchpad` (A, B, D; C and E deleted 2026-08-01).

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
- In the `sync` apply-choice dialog: (1) explain what `auto-merge` does. **Verified 2026-07-30
  — it is not additive only.** It applies the incoming value on a clash, the incoming folder,
  removes items the other side removed, and deletes an entry the other side deleted
  (`session.rs:3540`). What it never does is drop an entry the other side has simply never
  seen (pinned by `fast_merge_keeps_an_entry_only_this_vault_has`). So the copy must say
  "deletes only what the other device deleted on purpose", not "never deletes".
  (2) Add a third choice that takes the incoming vault and replaces this one — discuss first.
  Note the dialog is already three buttons (auto, review, Cancel) in a scrollable column;
  a fourth is what `test/sync_chooser_l10n_overflow_test.dart` will catch at 8x text.

### Code Quality
- **`VaultRecord.type` is stored but never rendered.** Set on registration
  (`main.dart`), read by nothing — keyed-ness shown to the user always comes from a
  live header read (unlock screen, delete dialog). Either surface it (key badge in
  Manage vaults) or drop the field. Found 2026-08-01 verifying the adopt matrix.
- **One locale sweep lets an error through, so it could hide an overflow.** The
  format-too-old sweep (`test/unlock_screen_test.dart:633`) tolerates the "locale not
  supported by all delegates" warning for nn and yo. If a real overflow lands in the
  same frame the two collapse into an opaque "Multiple exceptions" wrapper and the
  tolerance swallows it. Cause: the shared `_appShell` helper uses
  `AppLocalizations.localizationsDelegates`, while production uses
  `gabbroLocalizationsDelegates`, which ships fallbacks for both locales — so the
  warning is a test artefact users never meet. Fix `_appShell` to match production and
  the sweep can demand a clean render, as the biometric-notice sweep now does.

- **`sr.arb` has one Latin-script value in a Cyrillic file.** `vaultRestoredBiometricDisabled`
  is written in Latin (identical to `sr_Latn.arb`), unlike every neighbouring sr string. Found
  2026-07-31; no test checks script. Fix the value; consider a script-consistency net.

- **Shipped strings are still in English in every locale.** Found 2026-07-29:
  `changePassphraseBiometricDisabled` is the untranslated English sentence in all 37
  ARBs and in the generated Dart (`app_localizations_fr.dart:1113`). `l10n_test.dart`
  enforces the key set, not that a value was ever translated. Size the problem first
  (how many keys, which locales — `jq`/`grep`, never python), then decide. A net that
  fails on "value identical to English" would stop the next one.

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
- **Human expert cryptography review** of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).

### V2+ / Defer
- **Linux biometric unlock** (laptop fingerprint readers, e.g. libfido2/PAM or `fprintd`). Fits the current per-device model unchanged: Linux would just get its own local per-vault secret store; the vault file carries no biometric state, so nothing else changes.
- **Passkey provider**: store website passkeys (WebAuthn discoverable credentials) in
  the vault so they sync/back up. Distinct from the YubiKey (which unlocks the app);
  tradeoff — website private keys would live in the vault, not in hardware.
- **Custom and hideable filter chips** (post-v1 user feedback gate).
- **Windows support.**
- **Yubico partnership.**
- **Donation/sustainability model**: GitHub Sponsors is live; Monero possible later (a large, dedicated effort). Liberapay ruled out (2026-07-22 — Stripe forces business-type onboarding for individuals and has suspended Liberapay-linked accounts; no PayPal). Don't re-propose Liberapay.
- **No-telemetry verification guide** (ripgrep scan, Wireshark, NetGuard).
- **Support model** (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).
- **Import**: content-hash deduplication and entry-level merge.