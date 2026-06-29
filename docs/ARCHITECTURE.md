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

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text size, high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). Later: Windows. Android smoke-tested on GrapheneOS (2026-06-20): onboarding, vault sync, web autofill, l10n, settings all work — not yet exhaustive.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Play Store one-time payment is licence-compatible; F-Droid free build coexists without conflict.

**Version control:** private GitHub repo at https://github.com/Zabamund/gabbro. SSH auth.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, export, import, generator, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, sync_review, …
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
├── android/…/kotlin/…/   # GabbroUnlockHostActivity (base) + MainActivity/UnlockActivity/SaveActivity, GabbroAutofillService, TapFlow, YubiKeyManager, BiometricHelper (+ Robolectric tests)
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
| Rust (`cargo test -q`) | 541 | 8 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 12 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 998 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 7 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 140 | 15 |

**Test isolation (non-negotiable):** no test may touch the user's real settings or
vault folders. All config/data directories resolve through `GabbroPaths`
(`lib/app_paths.dart`), and `test/flutter_test_config.dart` roots every `flutter test`
run in a throwaway temp sandbox — so even a test that forgets to isolate itself reads an
empty registry and can never reach a real vault (wherever the user saved it). Mirrors the
`rust/tests/fixtures/` ethos of never operating on real data.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Active task: additive, field-level vault sync

**Why.** The old merge is whole-entry last-writer-wins on one coarse `updated_at`:
independent field edits on two devices silently lose one side, and equal-time edits report
a false "nothing to sync". Gabbro has no server, so sync is file-to-file and must be
additive and user-reviewed, with nothing lost.

**The model (agreed 2026-06-29).** Sync runs one direction at a time (A into B), additive,
and you review it; running B into A afterwards converges both sides. For each entry
(matched by a permanent id), compared per field and per custom pair:

```
entry only on A ............ NEW: added to B by default, shown to you, you can drop it.
entry only on B ............ stays. additive never auto-removes.
a field changed only on A .. A's value comes over; B's replaced value -> entry history.
a field same on both ....... nothing to do.
a field changed on BOTH .... CONFLICT: both values shown, you pick one; the value not
                             picked -> entry history. NEVER auto-picked by timestamp.
item/entry the other device
   deleted ................. keep-or-delete prompt (predates this branch; now per-item too).

result on B = (A + B) minus what you dropped.
nothing overwritten is lost: every replaced value lives in that entry's history.
```

Four properties this gives: **granularity** (per field/pair), **visibility** (every
incoming change shown before it lands), **control** (drop anything; pick on a real
conflict), **fallback** (replaced values kept in per-entry history, recoverable later).

Change-times (`field_times`, integer ms) are used only to detect WHICH side edited a
field, never to pick a winner. A same-field divergence is always a user choice, because
device clocks are not trustworthy.

**v8 -> v9 / safety.** A new app reads v8 and migrates on save (no loss); an old app
*refuses* a v9 file (fail-safe, never strips data). Hardware tests run on **mock vaults
only** until trust is rebuilt. Transport (moving the file between devices) is out of scope;
users use Syncthing/Nextcloud/USB.

**Status — honest.** The whole agreed model is built and green on branch
`granular-sync-v9`; what remains is maintainer hardware verification on MOCK vaults and
the release decision. Built:

- Built: per-field diff/merge (`merge_entry_pair`), `field_times` schema + stamping,
  presence-based collisions (a field edited on both sides ALWAYS becomes a user conflict;
  the clock is only an edit-mark, never picks a winner), format v8->v9 with the
  backward-compat gate (v6-v9 open/migrate green), item-delete tombstones + keep/delete
  prompt, the fuzz harness (3 devices, varied order), the FFI bridge, and the 3-vault
  test corpus (`test_data/sync_test_vaults/`, distinct per-device edit times, varied-order
  convergence proven).
- Additive review (visibility + drop): `MergeSummary` LISTS each added entry and each
  brought-over field/pair/attachment (old + new value), not just counts them. Drop reuses
  existing calls: new entry -> `deleteEntry`; field/pair -> `resolve_field_conflict` with the
  old value; attachment -> `resolve_item_delete`.
- Flutter one-by-one review UI (`lib/widgets/sync_review.dart`, option A): steps through
  incoming changes **one entry per step** (new entries, brought-over values keep/drop,
  clashes picked, item-deletes, whole-entry deletes, folder picks), keep by default, secrets
  masked, clashes block until picked. Replaces the old four sequential dialogs. Zero new
  l10n strings (reuses existing). Built + green (widget + grouping unit tests). Option A and
  the dropped option B both consume the same `MergeSummary`, so swapping the widget after
  hardware testing touches no Rust.
- Per-entry recovery history (the fallback property): a general `history: Vec<HistoryRecord>`
  on `EntryMeta` (serde-default, so v9 stays backward-compatible; v9 is unreleased here).
  A kept brought-over edit or a clash resolved to theirs keeps the replaced value via
  `replace_field_with_history`; merge unions history from both sides; unlock purges expired
  records. Viewer in entry detail (`lib/screens/recovery_history_screen.dart`) lists replaced
  values with restore/delete. Zero new l10n strings.

Remaining: maintainer hardware verification of the whole sync flow on MOCK vaults (Linux +
Android), then the release decision (option A may be revisited vs B after that run).

Note: import (`import.rs` `merge_source_into_session`) stays first-wins by UUID; the sync
model above is scoped to the sync path only.

---

## Build & Release

Build-environment notes (Android/Kotlin/Java setup, SAF export) and the full
release process live in their own document:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Bugs
- **CRITICAL — biometric unlock rejects the correct passphrase (GrapheneOS).** Observed
  2026-06-29 on a freshly-built test vault: enable biometric → it asks for and accepts the
  passphrase; then unlocking *with biometric* reports "wrong passphrase", while typing the
  same passphrase unlocks fine. Vault is NOT bricked (passphrase opens it). Seen while
  testing the `granular-sync-v9` branch; that branch changed no biometric/unlock source
  (only the regenerated FFI bridge) — so suspect pre-existing, the build/regen, or stale
  AndroidKeyStore on reinstall. Needs investigation (Kotlin `BiometricHelper`/the stored
  secret vs. what unlock receives). May relate to the Android-tablet biometric item below.
- **JSON export hard-codes `gabbro version 1.0.0`.** Wrong and brittle (needs a bump
  every release). Fix to read the real version (single source: `pubspec.yaml`) or drop
  the field.
- **Linux: passphrase breakdown not shown.** Long-click on an unhidden (revealed)
  passphrase shows no breakdown sheet.
- **Detail view: entry fields not consistently ordered.** Different Gabbro instances on
  the same vault/entry show different field ordering.
- **Android tablet biometric toggle doesn't persist.** Fresh alpha.10 install on an
  Android tablet: enabling biometrics doesn't stick — after logout no biometric is
  offered. Not yet investigated.
- **DuckDuckGo browser autofill not working** (Android). Likely DDG blocking autofill
  modifications, not a Gabbro bug — probably WONTFIX/YAGNI; confirm before closing.

### Security (pre-v1)
- Human expert cryptography review of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).
- Draft the free external crypto-review outreach (narrow ask: the construction only —
  hybrid combiner / transcript binding / header AAD / vault format). Deferred behind the
  sync redesign (which reshapes the vault format anyway). v1 direction in commit 9f158b5.

### Features & UX

### Code Quality
- **Autofill save loose ends.** Native review of the best-effort `eu`/`kk`/`yo` save-flow
  translations.
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.

### V2+ / Defer
- UI locales deferred (RTL layout work required): Hebrew, Kurdish.
- Passphrase wordlists — not viable without significant pipeline work: `yo` Yoruba (no frequency ordering, complex tonal diacritics); `sr_Latn` Serbian Latin (only Cyrillic corpora; needs transliteration pipeline); `lb` Luxembourgish (small speaker base); `wa` Walloon (nothing usable, French covers Wallonia).
- Autofill via `auto-type` (Linux/desktop) — global hotkey → foreground-window detection → synthesised keystrokes into another app (the KeePass/KeePassXC model, no browser extension). Needs a dedicated design session + ADR: Wayland blocks synthetic input outside the freedesktop RemoteDesktop portal / `libei` (KeePassXC's own auto-type is partial there), it's a new secret→input-subsystem security surface, and it cuts across "secrets live in Rust" (Rust holds the secret + synthesises input, Flutter registers the hotkey, per-platform window detection). Desktop-first; shares no code with Android autofill. Discuss-then-plan-or-drop.
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