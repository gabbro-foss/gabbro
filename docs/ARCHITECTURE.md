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
| Rust (`cargo test -q`) | 641 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 11 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync merges a never-edited entry (`cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 1953 | 10 |
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

**Keyboard accessibility sweep — branch `keyboard_accessibility_sweep` (pushed, NOT merged).**

Spec + mechanism as built: [KEYBOARD_NAV.md](KEYBOARD_NAV.md). **Linux desktop only**;
"narrow/wide" = layout WIDTH, not platform. Hardware matrix in `.scratchpad`; every hardware
failure and its cause is in LEARNINGS.md. Phases are hardware-tested one at a time.

Phases 1-3, D5 and the Phase 4 control speech are done and hardware-passed (rounds 13-17).

**Phase 4 — a11y. The constraint everything here obeys** (proven from the Flutter engine
source, see LEARNINGS.md): on Linux a screen reader is given only a node's NAME. `hint` is
never read and `liveRegion` is inert, so anything event-shaped has to go through
`SemanticsService.announce()`. Android does read hints, passes today, and must not regress.

**Done and hardware-passed (rounds 22-23)**

- The new-entry picker said each of the six types twice; the row icon's
  `semanticLabel` is gone and the title carries it alone.
- Ctrl+Shift+F, Ctrl+M, Ctrl+Q and the new-entry sheet announce themselves via
  `SemanticsService.sendAnnouncement`. Ctrl+F deliberately does not: it lands in
  the named search region and the box's own name already carries its shortcuts.
- Icon-only buttons on the **vault list and entry detail** now carry a
  `semanticLabel` beside their tooltip. Orca reads a control's name and never its
  tooltip, so every one of them said only "button".
- The lock-and-quit confirm carries `semanticLabel`, so its question is read.
  Flutter supplies a default dialog name on Android only.
- The search box says one thing, not five (round 24). It was reciting its
  placeholder, what typing does and both shortcuts; the region above already
  says "Search" and the shortcuts are on the Keyboard shortcuts screen.
- Every remaining icon-only control is named (round 25) — unlock, generator,
  help, manage folders/vaults, export, import, change passphrase, review
  changes, onboarding. The a11y net sweeps all 33 catalog screens for
  `tooltip.isNotEmpty && label.isEmpty` with no skips left. The help screen's
  tap-to-enlarge image needed `MergeSemantics` instead: it is a `Tooltip` around
  a picture, so the name had to be merged onto the node carrying the tap.
- Copying a secret says so (rounds 26-27), in the generator and the entry detail
  pane. Both were silent: the generator's button renames itself to "Copied" and
  the detail pane shows a snackbar, and Linux reads neither — a name that changes
  under an already-focused control is not re-read, and a snackbar is not seen at
  all. The detail pane speaks the snackbar's own text, so it also says when the
  clipboard will clear. `GeneratorWidget` and `EntryDetailScreen` gained an
  `isAndroid` flag defaulting to `Platform.isAndroid`, so Android stays silent.

**Attempted and reverted (round 22).** Replacing each region's named Semantics
container with an announcement on focus entry. Announcements leave the Linux
embedder as ATK **polite**, and Orca discards a polite notification while it is
speaking — which it always is right after a focus change. Region entry went
silent on hardware. The named container is back; the entry list therefore
repeats its region name on every arrow press, which the maintainer has accepted
(round 23) as better than silence.

**To do**

1. **Deleting an entry moves focus silently** (round 23). Deleting from the
   two-pane detail pane unmounts it and focus lands on a row in the entry list —
   verified: the frame is correct and arrows work from there. Nothing says so,
   so the only sign is a frame appearing where you were not looking. Reported as
   a stuck frame; it is not one. Pre-existing.
2. **Ticking a checkbox is announced only after moving away and back** (round 17).
   Cause established: the row takes focus but the checked state lives on a separate
   checkbox node beneath it, and a reader only announces state changes on the FOCUSED
   object. **One attempt was made and REVERTED (round 19).** Moving `checked` onto the
   row's `Semantics` wrapper and excluding the checkbox made things worse on hardware:
   Orca stopped announcing the row entirely, the title was no longer read, and a focus
   frame stuck with Esc unable to clear it. **Its unit tests all passed** — they asserted
   the flag was on the row's node, which was true and irrelevant. The next attempt needs
   a different mechanism, and a hardware check before it is believed.
Order, quickest first: the silent delete (1), then the checkbox (2).

**Merge gate:** master once an Orca round covering the items above passes on Linux, the
Android TalkBack spot-check stays green, and the matrix's core-vault-operations section
passes.

---

## Build & Release

Build environment (Android/Kotlin/Java, SAF export) and full release process:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Features and UI/UX
- Add fastlane images to README (at least some if not all)
- **Remove the tablet NavigationRail** (`tablet_vault_layout.dart`: Vault /
  Appearance / Security / About). Redundant with the app-bar overflow menu (same
  targets), low utility. Already excluded from the keyboard Tab-cycle.
- **Final launcher logo (logo-blocked).** `render_icons.sh` renders a placeholder
  SVG. When the real logo lands, replace `assets/images/source/ic_launcher_light.svg`
  and re-run it; same render covers the Windows `.ico` (still the stock Flutter template).
- See if vault `syncing` can do without a second `passphrase + yubikey` if and only if the current vault and the incoming vault share the same `alias`, `passphrase`, `yubikey(s)`
- in `sync` path, we currently have `auto-merge` and `review all changes`, the `auto-merge` is additive only (check and verify) and therefore never deletes items in the receiving vault: (1) add a message that explains this (or the correct) behaviour to the user, (2) add a third `sync` mechanism that simply takes the incoming vault and clobbers the existing one - discuss this

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