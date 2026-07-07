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

**YubiKey NFC / NDEF OTP:** a YubiKey's OTP slot 1 (an NDEF URI) would open a browser when tapped on Android. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` and by re-arming foreground dispatch after `stopNfcDiscovery`; OTP slot 1 can stay enabled (no `ykman` workaround).

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
├── docs/                 # ARCHITECTURE, SECURITY, VAULT_UPGRADE_PATH, AI_*; decisions/ (ADRs); artefacts/
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
| Rust (`cargo test -q`) | 656 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 14 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cross-version sync, v8 file (`cargo test --release --lib cross_version_sync_loads_and_merges_a_v8_file -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1257 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 12 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 148 | 15 |

**Test isolation (non-negotiable):** no test may touch real settings or vault folders. All
config/data resolves through `GabbroPaths` (`lib/app_paths.dart`); `test/flutter_test_config.dart`
roots every `flutter test` in a throwaway temp sandbox, so even a non-isolating test reads
an empty registry and never reaches a real vault. Mirrors `rust/tests/fixtures/`.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task

**RT-3 — X25519 key derivation depends on `rand::StdRng` (robustness / latent vault-brick).**
Surfaced by an internal red-team pass. `crypto/keypair.rs:29` derives the X25519 static secret via
`StdRng::from_seed(kdf[0..32])` for **all** vault versions (2–9); the F-02 fix moved ML-KEM off
`StdRng` but left X25519 on it.

**The problem, plain English.** Every vault is opened with a key rebuilt from your passphrase by a
fixed recipe. One step of that recipe borrows a random-number helper from an outside library (`rand`)
to stretch part of the key. That helper must produce the *exact same bytes forever*, but the library
never promised it would — a future major version of `rand` / `x25519-dalek` could quietly produce a
different key and **permanently lock every existing vault** (no data leak — the passphrase still
protects everything — but the file would never open again). This is an *availability* risk, not a
confidentiality one. The same mistake exists in one other place — the legacy ML-KEM keygen
(`ml_kem.rs:63`), but only for v2–5 vaults (a full-source PRNG sweep found no others; every other
crypto step is a frozen public standard whose output can't drift).

**Decision (settled).** Take the full fix, plus auto-migration, in two stages. Rationale:
- We are **pre-public**: no external user holds an old-format vault, so we owe no stranger backward
  compatibility and can change the format cleanly now.
- The goal is that *new vaults carry zero library-drift risk* and *old vaults upgrade themselves
  invisibly* — without the user having to run a passphrase change or a CRUD save.
- An alarm-only option (a tripwire test, no format bump) was rejected as the endpoint: it removes the
  risk from *no* vault. It survives only as a temporary guard on the legacy read path (see below).

**Understanding to mirror (maintainer's summary, confirmed):**
- Bump vault format to **VERSION 10**; v10 derives X25519 directly from `kdf[0..32]` (clamp, no PRNG).
- Add **upgrade-on-unlock/lock** to the existing save-path upgrades (passphrase change, CRUD already
  re-seal at the current version). A vault upgrades the **first time it is opened or saved** after the
  release — a file sitting untouched on disk stays v9 until something opens it.
- Add a **tripwire test** protecting old vaults while the legacy read path exists: it fails the build
  if a fixed seed ever re-derives a different X25519 key (i.e. if the library's stream drifts).
- Keep the **legacy derivation code temporarily** — it is a *read-once bridge*: you must decrypt an old
  vault with the old recipe before you can re-seal it as v10. You cannot migrate a file you cannot open.
- v9 (and any v2–9) vaults **still open — no export/reimport, ever**. First open decrypts via the legacy
  path, then re-seals in place as v10. Data is preserved end to end.
- Net result: **Release N** bumps every vault to v10 as it is opened/saved; **Release N+1** deletes the
  legacy code + tripwire once the maintainer confirms no ≤v9 vault remains. All before public release.

---

**Phased plan (tick as we go).**

Phase 0 — docs (this block). [ ] committed, code untouched.

Phase 1 — net-first (pin CURRENT v9 behaviour green, before touching production):
- [ ] Confirm/trace real wiring: unlock/lock read paths, X25519 derivation, save-path re-seal.
- [ ] Pin: frozen v9 fixture opens; current X25519 derivation is deterministic; unlock/lock are
      currently read-only (no write). Green against current code.

Phase 2 — canon-TDD scenario list, then STOP for maintainer review (no test/prod code before sign-off).

Phase 3 — implement VERSION 10 (red-first per scenario):
- [ ] `keypair.rs`: version-dispatched X25519 — v>=10 direct `clamp(kdf[0..32])`, v<=9 legacy `StdRng`.
- [ ] Bump `CURRENT_VERSION` to 10; seal path writes v10.
- [ ] Frozen v10 golden fixture + regenerate helper; v9 fixture retained for the read path.

Phase 4 — auto-migration:
- [ ] Upgrade-on-unlock/lock: on open, if `version < CURRENT`, re-seal in place at v10 via
      `atomic_write_0600` + `.bak` (crash-safe, reversible); no extra YubiKey tap; only fires on
      version mismatch (steady-state v10 vaults are never written on unlock).
- [ ] Confirm existing save paths (passphrase change, CRUD) already re-seal at v10.

Phase 5 — tripwire (guards the legacy read path until Release N+1):
- [ ] Gate assertion: fixed seed must re-derive the known X25519 key; fail loudly on drift.
- [ ] Document `StdRng` + ChaCha12 as a compat-critical invariant in an in-code comment
      (`keypair.rs`) beside the tripwire test.

Phase 6 — release-gate proof (maintainer runs): full backward-compat gate, `cargo test`,
`flutter test`, Android leg; hardware matrix (Linux + Android) on **mock** vaults; add a v10 vault to
`test_data/migration_vaults/`.

Phase 7 — deferred to Release N+1 (NOT this release), once the maintainer confirms no ≤v9 vault remains:
- [ ] Delete legacy X25519 (and legacy ML-KEM) derivation + the tripwire.
- [ ] **Min supported version becomes v10.** A ≤v9 file handed to this build must be rejected with a
      clear "unsupported version — upgrade via the interim release" error, never a panic/brick.
- [ ] Convert the v2–9 gate fixtures from "must open" into a **graceful-rejection** test (assert the
      too-old error, not a crash). Backward-compat corpus floor moves to v10 and grows from there.
- [ ] `test_data/migration_vaults/`: keep pre-v10 files as historical artifacts (they still open under
      Release N); add a v10 vault; live gate floor = v10.
- [ ] See [VAULT_UPGRADE_PATH.md](VAULT_UPGRADE_PATH.md) — the interim release is a mandatory stepping
      stone (skipping it strands a ≤v9 vault).

Approach: net-first (Phase 1) before any change; canon-TDD list-first (Phase 2) is the checkpoint —
STOP for review before writing code. VERSION 10 is a vault-format change → full backward-compat TDD.

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