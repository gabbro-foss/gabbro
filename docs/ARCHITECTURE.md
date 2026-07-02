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
│   └── bin/  scripts/  examples/   # bench_kdf, mem_forensics, crash_writer; wordlist gen; gen_fixtures
├── rust/tests/           # Backward-compat gate + state-machine fuzzer + parse fuzzer + crash-safety (kill mid-write) + frozen golden fixtures (FIXTURES.md)
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
| Rust (`cargo test -q`) | 597 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 14 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cross-version sync, v8 file (`cargo test --release --lib cross_version_sync_loads_and_merges_a_v8_file -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1084 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 12 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 140 | 15 |

**Test isolation (non-negotiable):** no test may touch real settings or vault folders. All
config/data resolves through `GabbroPaths` (`lib/app_paths.dart`); `test/flutter_test_config.dart`
roots every `flutter test` in a throwaway temp sandbox, so even a non-isolating test reads
an empty registry and never reaches a real vault. Mirrors `rust/tests/fixtures/`.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task: Large-text accessibility initiative (ADR-016)

Make Gabbro usable at very large text (low-vision): one absolute `textScale` knob
drives text **and** controls in unison; screen-derived max (600dp tiers — phone ~4x,
tablet ~6x, **calibrate on hardware**); targets scale proportionally, capped ~2x.
Design fixed in [ADR-016](decisions/ADR-016-large-text-and-target-scaling-accessibility.md).

**Phase 0 — Calibrate [DONE 2026-07-02].** Measured shortest side: S23 360dp, GOS
411dp (both phone tier), Idea Tab Pro 866dp (tablet). Phone tier = 360-411dp (360 =
worst case, the overflow-probe phone surface); tablet 866dp. Starting maxes phone 6x /
tablet 8x / target cap 2x, dialled in live during P1. Probe added + reverted (uncommitted).

**Phase 1 — Slider + model + onboarding** (canon-TDD list agreed 2026-07-02, decisions
LOCKED; branch `accessibility_initiative`). Starting consts phone 6x / tablet 8x /
target cap 2x / onboarding toggle 3x (ADR-016; tuned live). Build red-first:
- **Model** (`settings.dart`): `TextSizeChoice` enum -> `double textScale`. Persist new
  numeric key `text_scale`; still READ legacy `text_size` word + migrate
  (small/regular/large/extra_large/xxLarge -> 0.85/1.0/1.15/1.3/1.5); if both, new wins.
  Clamp to hard [0.8, 8.0].
- **New `lib/text_scale.dart`** (pure, unit-tested): `deviceMaxScale(shortestDp)` = 6.0
  (<600) / 8.0 (>=600); `targetScaleFor(textScale, deviceMax)` = lerp 1.0->2.0 clamped;
  exponential `scaleForPos`/`posForScale` (0->0.8, 1->deviceMax, exact inverse);
  `clampToDevice(stored, shortestDp)` (e.g. 8x stored on 411dp phone -> 6x).
- **`main.dart`**: MediaQuery textScaler = `clampToDevice(textScale, screen)`; REMOVE
  `TextSizeChoice`, `textScaleFor`, duplicate `_textScale` getter.
- **New `TextSizeSlider` widget** (reused on appearance + onboarding): ends = Material
  `Icons.text_decrease`/`text_increase` glyphs (language-neutral, NO l10n words); live
  preview via `textSizePreview`; 0.8->deviceMax via the exponential map.
- **Appearance**: replace `SegmentedRow` with the slider. **Onboarding**: accessibility
  toggle ON -> textScale 3.0 + reveal slider + HIDE logo; OFF reverses; toggle reflects
  current scale.
- **l10n**: drop the 5 per-size labels (`textSizeSmall`..`textSizeXXL`) from all ARBs +
  `l10n_test`; keep `sectionTextSize` + `textSizePreview`.
- Scenario groups: A model+migration, B pure helpers, C apply+cleanup, D slider widget,
  E onboarding toggle, F l10n.

**Phase 2 — Text overflow hardening** (evidence from a headless 5x overflow probe on
phone+tablet surfaces): fixed-box clippers (csv_mapping `width:88`, import_skipped
`height:300`), help page-dot spacing, onboarding accessibility button, import
`SegmentedButton`, entry_detail AppBar crowding.

**Phase 2b — Help-screen pinch-to-zoom** (its own feature, not a layout fix):
`FLAG_SECURE` blocks screenshots, so a low-vision user cannot magnify the help
pages externally — add in-app pinch/zoom (InteractiveViewer) on help content,
especially any images, which `textScaler` does not touch.

**Phase 3 — Target scaling** (the core payoff): `scaledControl` helper off `textScale`
(capped ~2x); alphabet bar (hide on phone tier / scale on tablet tier); password
breakdown sheet; FABs; drop `VisualDensity.compact`. Per-control >=48dp touch-target
tests at every scale; hardware-verified per screen.

Slider ships first and becomes the probe for Phases 2-3.

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

### Features & UX
- Autofill via `auto-type` (Linux/desktop) — global hotkey → foreground-window detection → synthesised keystrokes into another app (the KeePass/KeePassXC model, no browser extension). Needs a dedicated design session + ADR: Wayland blocks synthetic input outside the freedesktop RemoteDesktop portal / `libei` (KeePassXC's own auto-type is partial there), it's a new secret→input-subsystem security surface, and it cuts across "secrets live in Rust" (Rust holds the secret + synthesises input, Flutter registers the hotkey, per-platform window detection). Desktop-first; shares no code with Android autofill. Discuss-then-plan-or-drop.

### Code Quality
- **Autofill save loose ends.** Native review of the best-effort `eu`/`kk`/`yo` save-flow
  translations.
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