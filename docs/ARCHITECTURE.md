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

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). Later: Windows. Android smoke-tested on GrapheneOS (2026-06-20): onboarding, vault sync, web autofill, l10n, settings all work — not yet exhaustive.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Play Store one-time payment is licence-compatible; F-Droid free build coexists without conflict.

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
├── docs/                 # ARCHITECTURE, SECURITY, VAULT_UPGRADE_PATH, RT3_CLEANUP, AI_*; decisions/ (ADRs); artefacts/
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
| Rust (`cargo test -q`) | 664 | 17 |
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

**Test isolation (non-negotiable):** no test may touch real settings or vault folders. All
config/data resolves through `GabbroPaths` (`lib/app_paths.dart`); `test/flutter_test_config.dart`
roots every `flutter test` in a throwaway temp sandbox, so even a non-isolating test reads
an empty registry and never reaches a real vault. Mirrors `rust/tests/fixtures/`.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task

**>>> SESSION STATE (READ FIRST) — v11 COMPLETE, in maintainer verification <<<**
- **All dev/test/doc work for v11 is DONE, committed, and PUSHED** on `drop-dual-lock-hybrid-kem`.
  `VERSION=11`: new vaults derive the vault key straight from Argon2id via HKDF (`derive_vault_key_v11`,
  label `gabbro-vault-key-from-argon2id-v1`, KAT-frozen in `hkdf.rs`); the v11 header drops the ML-KEM
  ciphertext + X25519 ephemeral pubkey. 6 derivation sites v11-branched; ≤v10 keep the legacy hybrid
  read/migrate path (each tagged `RT-3` — deletion checklist: [RT3_CLEANUP.md](RT3_CLEANUP.md)).
  `capped_reseal` two-era (`HKDF_DIRECT_MIN_VERSION`); header branches on `KEM_HEADER_MAX_VERSION(10)`.
- **Verified:** backward-compat gate 18/18, state-machine fuzzer (v11 added), C2
  (`seal_vault_with_keys_produces_version_11_with_no_kem_header`) + C4 (rotation journey), full doc set
  + both crypto diagrams redrawn. The earlier gate failure `truncated_ml_kem_ciphertext_returns_error_not_panic`
  is fixed (retargeted to a legacy v10 vault; the v11 seal has no KEM to truncate). Testing table
  current (lib 664, backward-compat 18).
- **Remaining (maintainer-driven):**
  1. `gabbro_test` full gate re-running — confirms the fix + all v11 tests green together. Expected clean.
  2. Hardware matrix — **written to `gabbro/.scratchpad`** (v10→v11 migrate-on-unlock, all four auth
     modes, CRUD, rotation, cross-version sync, real-vault read-only). Devices: Linux USB-C / S23 NFC /
     tablet (1 key) / GrapheneOS (held as rollback). Mock vaults for all destructive steps.
  3. Release the v11 build (see VAULT_UPGRADE_PATH.md two-release strategy).
- If the gate comes back red, the likely spot is a v11-touched suite (`vault_backward_compat`,
  `vault_state_machine_fuzz`, lib) — not a brick. Flutter/Android are bridge-insulated.

**Drop the dual-lock (X25519 + ML-KEM) hybrid layer — vault VERSION 11.** Multi-session, on
branch `drop-dual-lock-hybrid-kem`. Rationale + decision: ADR-018. Follow **net-first**
(CLAUDE.md) strictly — no canon-TDD until the net is green across every path in *Must not
regress* below.

*Goal:* derive the AES-256 vault key straight from Argon2id via HKDF, deleting the
passphrase-derived X25519 + ML-KEM key-exchange. Gabbro stays PQ-resistant on Argon2id +
AES-256-GCM.

*Construction (design locked):*
- **Passphrase (v11):** `vault_key = HKDF-SHA256(salt = hkdf_salt, ikm = KM, info = "gabbro-vault-key-from-argon2id-v1")`.
  `KM = Argon2id(pass, salt)` **stays 96B** — the Argon2id call is byte-identical to the old
  format; only the post-Argon2id step changes (localises the blast radius). Label is construction-
  versioned (`-v1`, not the file format). Header **drops** `ct_M` (1568B) + `ephemeral_pub` (32B).
- **YubiKey (v11):** `combine_yubikey(HKDF(KM), hmac_secret, ...)` — `combine_yubikey` is
  **unchanged**; only its first input's source changes. 2FA property intact (hmac-secret is the
  real second factor, mixed downstream).
- **Per-seal freshness** now comes from the random `hkdf_salt` alone (ADR-018).

*Two-release strategy (folded into RT-3 so it stays two, not three):*
- **This branch = v11 WRITE only.** New vaults seal v11; v2–v10 still *read* via the legacy
  dual-lock derivation and **auto-migrate to v11 on unlock** (full re-seal), invisible to users.
  `ml-kem` + `x25519-dalek` **stay** (needed to read/migrate old vaults) — supply-chain surface
  unchanged this release.
- **Later cleanup (Bikeshed "RT-3 + dual-lock cleanup", floor → v11):** once no ≤v10 vault
  remains, delete the legacy derivations and **drop the crates** — surface → zero, nobody notices.

*Must not regress (verify in code, then pin with the net):* p, p+yk, p+bio, p+yk+bio; CRUD saves
(cached `vault_key_master` re-seal); open/unlock (version dispatch + v≤10 migrate); lock; import
(new vault → v11); export (byte-copy, format-agnostic); sync (version-agnostic
decrypt→merge→reseal, incl. cross-version v10↔v11); passphrase-change + YubiKey rotation
(multi-key `wrapping_key` model).

*Findings (item 1 code-verification, DONE — confirms/corrects the model above):*
- **(a) `wrapping_key` is RANDOM** (`vault_crypto.rs:460`), not derived. The passphrase path derives
  `intermediate_key` (today = dual-lock HKDF) which only *encrypts* `wrapping_key` into `passphrase_blob`;
  `vault_key_master` (random) encrypts the body; `key_blob` = `combine_yubikey(wrapping_key,hmac,salt)`.
  So v11 changes ONLY `intermediate_key` -> `HKDF(KM)`; `wrapping_key`/`vault_key_master`/`combine_yubikey`/
  `key_blob`/`passphrase_blob` untouched. Note: the *Construction* `combine_yubikey(HKDF(KM),…)` line
  describes the **legacy single-key** path (`seal_vault_with_yubikey`); in the **live multi-key** path
  `combine_yubikey`'s first input is the random `wrapping_key`, so it does not change at all.
- **(b) Only multi-key body-reseal is capped.** Passphrase-only save = full re-seal (`save_vault`->`seal_vault`,
  re-derives Argon2id every save) -> auto-migrates on save AND unlock (`migrate_passphrase_vault_on_unlock`,
  `session.rs:88`). Single-key YK (legacy v2) = full re-seal (`save_vault_with_yubikey`). Multi-key = body-only
  `reseal_vault_body` gated by `capped_reseal_version`. **REQUIRED: bump that boundary 10->11** (new const),
  else a v10 body-reseal jumps to v11 while `passphrase_blob` stays dual-lock-derived -> brick. Braces
  (`migrate_multikey_to_version`, `session.rs:151`) already do the full rebuild on unlock.
- **(c) Dispatch confirmed.** Seal passes `VERSION`; open passes `sealed.version`. Three dispatchers
  (`x25519_keypair_for_version`, `ml_kem_keypair_for_version`, `derive_passphrase_vault_key_for_version`)
  branch on it; add a `v>=11` branch that derives `HKDF(KM)` and skips ML-KEM/X25519. Read/migrate keep the
  legacy KEM for <=v10.
- **(d) Sync folds into (b)+(c).** Sync merges into the in-memory session then persists via the SAME `do_save`
  dispatch as CRUD — no separate seal path. Older builds refuse a v11 file fail-closed (`file_format.rs:238`).
- **Header (biggest mechanical/risk surface):** `ml_kem_ciphertext`(1568)+`x25519_ephemeral_public`(32) are
  FIXED-POSITION in `from_bytes`/`to_bytes`/`header_aad` — v11 must version-branch all three to drop them.
  The v8+ transcript-binding combiner is moot for v11 (no KEM transcript). Parse-fuzzer + gate cover this.

*Sweep (item 2 functional sweep, DONE — CURRENT coverage of the Must-not-regress list):*
- **Rust crypto/format = STRONG** on every path: p + p+yk seal/open; version dispatch; migrate on
  save (`save_vault`/`seal_vault_with_yubikey` full re-seal) AND on unlock (`migrate_*_vault_on_unlock`);
  export (byte-copy preserve + passphrase-only downgrade); sync incl. cross-version
  (`cross_version_sync_loads_and_merges_a_v8_file`); passphrase-change + YK add/remove rotation.
  Gate `vault_backward_compat.rs` has frozen fixtures **v6–v10** (passphrase + 2-key each); parse-fuzzer
  routine; state-machine fuzzer v6–v9 (opt-in).
- **Flutter = insulated** — user flows call Rust via callbacks; version negotiation opaque. Real-FFI
  integration covers passphrase unlock + entry edit/history + lock->unlock. No Dart version-byte assert
  (by design; Rust gate owns format).
- **Android = fully insulated** — biometric stores the RAW passphrase under AndroidKeyStore; YubiKey
  returns RAW hmac-secret. So **p+bio / p+yk+bio need no format work**.
- **GAPS (CLOSED, item 3):** G1 `v10_multikey_rotation_survives_key_loss` (gate; parameterized
  `run_rotation_scenario` — v10 sits AT the boundary, carries to VERSION not below). G2
  `build_passphrase_only_bytes_{seals_at_current_version,opens_with_passphrase_alone}`. G3
  `import_from_csv_persists_at_current_version`. All green against current code.

*Tick-list (work through in order; check off as landed):*
- [x] Code-verify the high/unknown paths (a)-(d) — DONE; see *Findings* above.
- [x] Functional sweep: list every *Must not regress* mechanism with its CURRENT test coverage — DONE; see *Sweep* above.
- [x] Net: pin CURRENT behaviour green (all paths, all versions) BEFORE touching production; add
  characterization tests for any gap the sweep finds — DONE; G1-G3 closed (see *Sweep* above).
- [x] Remove dead legacy single-YK (v2) path — net-first side-effect. DONE. Deleted
  `seal/open/save/load/unlock_vault_with_yubikey`, the 3 legacy session branches, AND the legacy
  read-fallback inside `open_vault_with_key_record` (empty-`key_blob` branch now fails closed) —
  the third tentacle the first sweep missed. Collapsed the session `YubikeyMaterial`
  (`vault_key_master` no longer `Option`; dropped the dead cached `hmac_secret`/`hkdf_salt`/
  `credential_id`). Kept `combine_yubikey` + `derive_vault_key` (multi-key uses them). Ported the
  P0 garbage-doesn't-open-empty test + 3 bridge tests to the multi-key path. Then dropped the
  vestigial salt param from the whole unlock chain (bridge fn + session fn + Dart `unlock_screen`;
  FFI regenerated) — multi-key open reads each key's salt from the record. Net green: gate 17/17
  (v6–v10 multi-key still open), affected lib tests green, clippy + flutter analyze clean. No
  freeze fixture (per plan).
- [x] Canon-TDD list (reviewed) + v11 write path — DONE (code). New `derive_vault_key_v11`
  (`hkdf.rs`, label `gabbro-vault-key-from-argon2id-v1`, frozen KAT). v11 branch wired into all 5
  derivation sites (seal/open passphrase, seal/open multi-key, `migrate_multikey_to_version`);
  ≤v10 keep the legacy hybrid path (tagged RT-3). `VERSION` 10→11. Core round-trips green
  (passphrase + multi-key seal→bytes→open, 4 tests) + clippy -D warnings clean. **Full ripple +
  backward-compat + migration = maintainer's gate (not yet run).**
- [x] Version dispatch — DONE: seal passes VERSION(11); open/migrate branch on the parsed version.
- [x] Header: drop `ct_M` + `ephemeral_pub` for v11 — DONE (`to_bytes`/`from_bytes`/`header_aad`
  version-branch on `KEM_HEADER_MAX_VERSION`; AAD covers the full v11 header). `capped_reseal`
  two-era boundary (`HKDF_DIRECT_MIN_VERSION`) so v10 body-reseal can't jump to v11 (E1/E2 green).
- [~] Auto-migrate v≤10 → v11 on unlock — FOLDED IN (the wired on-unlock paths target VERSION, so
  the migrate fns now produce v11). Needs gate + hardware confirmation.
- [x] Fixtures: `v11_passphrase.gabbro` + `v11_multikey_2keys.gabbro` (frozen for FUTURE compat — RT-3
  legacy-code removal). Backward-compat gate 18/18 green (v11 open + rotation-at-boundary `== VERSION`
  + interleaved passphrase-change journeys). State-machine fuzzer extended to v11 (belt parameterised
  by starting era), green. FIXTURES.md + harness test-list updated.
- [x] Migration-vault corpus: `v11.gabbro` added (production params, opens; sha `3edd56cf4052`,
  version byte `0b`) + MIGRATION_TESTS.md table row. Hardware v10->v11 procedure/results at the
  hardware-matrix item.
- [ ] Hardware matrix (maintainer): Linux + Android; p / p+yk / p+bio / p+yk+bio; migrate-on-unlock;
  cross-version sync; real-vault integrity (no data loss).
- [x] Docs: ADR-018 (v11 landed note), SECURITY (v11 mechanism + removed single-YK mode + audit
  notes), README (prose/ASCII/alt-text + embedded diagram), ARCHITECTURE (Encryption line + format),
  crypto diagrams (flow.dot/svg, simple_icons.svg redrawn 6-band, A4 PNG+PDF regenerated),
  VAULT_UPGRADE_PATH (rewritten for v10->v11 stepping stone).
- [x] `gabbro_test` gate: no change needed — new v11 tests live in suites the gate already runs
  wholesale (`cargo test -q`, `--test vault_backward_compat`, `--test vault_state_machine_fuzz`).
- [ ] Release the v11 auto-migrate build; let existing vaults migrate in the field.
- [ ] DEFERRED to the RT-3 cleanup (NOT this branch): delete legacy derivations, drop `ml-kem`
  + `x25519-dalek`, raise floor → v11. **Exhaustive deletion checklist: [RT3_CLEANUP.md](RT3_CLEANUP.md).**

---

## Build & Release

Build environment (Android/Kotlin/Java, SAF export) and full release process:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1)
- Human expert cryptography review of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).
- **RT-3 + dual-lock cleanup (merged, floor → v11)** — once no ≤v10 vault remains: delete the
  legacy `StdRng` X25519, the legacy ML-KEM + dual-lock derivations, and the frozen-golden
  tripwire; **drop the `ml-kem` + `x25519-dalek` crates** (supply-chain surface → zero); min
  supported version → v11 (≤v10 rejected gracefully, never bricked); convert the v2–v10 gate
  fixtures to a graceful-rejection test; migration-vault + gate corpus floor → v11. Must ship the
  v11 auto-migrate release first (Current Focus task 2) — see VAULT_UPGRADE_PATH.md.
  **Exhaustive deletion checklist: [RT3_CLEANUP.md](RT3_CLEANUP.md).**

### Going public (pre-v1)
- **Flip the repo to public.** Repo now lives in the `gabbro-foss` org (transferred; URLs
  migrated). Flip visibility to public once the pre-v1 gates clear (crypto-review outreach
  above is welcome-not-blocking). Optional: a read-only Codeberg mirror for redundancy.

### Code Quality
- **Auto-type: unlock-then-type + cold start (ADR-017 Phase 4).** A trigger while the
  vault is locked or Gabbro is closed does nothing today. Add: prompt-unlock-then-type,
  an opt-in setting, README key-binding examples, and package `gabbro-autotype` into the
  release bundle (update BUILD_AND_RELEASE). Secret stays in Rust; auto-lock preserved.
- **Autofill save loose ends.** Native review of the best-effort `eu`/`kk`/`yo` save-flow
  translations (and the `resizeColumns` label added the same way).
- **Native-review `aboutTagline` translations** (all locales, 2026-07-09 rename): `eu` Basque
  and `yo` Yoruba lowest confidence, `kk`/`lt` medium.
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