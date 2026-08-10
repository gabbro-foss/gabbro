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
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, sync_review, sync_method_dialog, gabbro_dialog (every dialog goes through it), text_size_slider, url_link, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, text_scale, control_scale, gabbro_contrast (high-contrast theme flag), vault_registry, safe_file_picker, gabbro_file_picker (dialog facade), linux_file_picker (XDG portal client), android_file_picker (picker channel client), autotype_listener, autotype_target, clipboard_clear
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
├── android/…/kotlin/…/   # GabbroUnlockHostActivity (base) + MainActivity/UnlockActivity/SaveActivity, GabbroAutofillService, TapFlow, YubiKeyManager, AppPaths (paths channel), GabbroPicker (picker channel), BiometricHelper + BiometricStore (per-vault; + Robolectric tests)
├── linux/packaging/      # Desktop integration: render_icons.sh (icon tree); aur/ (AUR gabbro-bin PKGBUILD; .SRCINFO is generated in the AUR clone), deb/ (build-deb.sh -> binary .deb)
├── docs/                 # ARCHITECTURE, SECURITY, VAULT_UPGRADE_PATH, VAULT_SYNC, AUTOTYPE_AND_AUTOFILL, AI_*; decisions/ (ADRs); artefacts/
├── test/  integration_test/          # Flutter widget/unit + Linux real-FFI suites (dart test)
├── test_data/            # Sample import files + migration_vaults/ (refusal corpus at floor v11, one vault per VERSION + MIGRATION_TESTS.md + test_matrix.md)
├── assets/               # fonts, images, help/ (public_suffix_list.dat is an Android asset)
├── challenge/            # crack-me challenge vault + rules
└── CHANGELOG.md  README.md
```

## Features

Shipped features are recorded in `CHANGELOG.md`. Planned and deferred work lives in the Bikeshed at the end of this file.

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 707 | 17 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 11 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync merges a never-edited entry (`cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 2203 | 10 |
| Real-FFI suites (`dart test integration_test/ -j 1`) | 12 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 165 | 15 |

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

**Known warnings — triaged 2026-08-06; each is fixed or has a reason. The gate's own
warnings are not noise.**

| Warning | Source | Status / what it costs |
|---|---|---|
| `package=` ignored, `rust_lib_gabbro` | ours | **FIXED** 2026-08-06. Merged manifest byte-identical after. |
| `package=` ignored | `jni`, `jni_flutter`, `url_launcher_android` | Upstream. Latest versions still warn. Android build breaks at a future AGP. Was x5; the `file_picker` removal took two. Confirm the count at the next build. |
| Gradle space-assignment | `jni` 16, `jni_flutter` 13 | Upstream. Latest versions still warn. Android build breaks at Gradle 10. Was x42; `file_picker` held 13. Confirm at the next build. |
| `Task.project` at execution time | Flutter's own `compileFlutterBuildDebug` | Upstream. Breaks at Gradle 10. Only shows when the task is not UP-TO-DATE. |
| Kotlin plugin version (2.0.21 vs 2.2.20) | Flutter SDK's own `:gradle` build | Upstream. Debug and release alike. |
| JVM restricted-method (`System::load`) | Gradle 8.14 `native-platform` jar | Gradle's own jar, and the version is pinned — nothing changes on its own. Clears itself whenever we next raise Gradle. No action. |
| `cargo deny` no-license-field: `allo-isolate` | `flutter_rust_bridge` dep | Fixed on their master; await release. `[[licenses.clarify]]` is inert — don't retry. |
| `cargo deny` duplicates x6 | `argon2`->`digest`, `jni`->`libloading`, `bindgen`->`shlex` | Upstream pins. Was x7; RT-3 took the `hybrid-array` duplicate with `ml-kem`. The crate itself stays (`sha2`/`hkdf` -> `digest` need it). |
| "trying to run flutter as root" | the gate's own `unshare -r` | Cosmetic. Not Gabbro. |
| KGP via `buildscript` classpath | `url_launcher_android` | Did not reproduce 2026-08-06; re-check before acting. |

**AGP note:** every module, `rust_lib_gabbro` included, loads AGP **8.11.1**. The
`com.android.tools.build:gradle:7.3.0` line in `rust_builder/android/build.gradle` is
resolved but never applied — inert, emits no warning.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next. Completed items are deleted from this section.

### Next task

**Dependency trimming, remaining (branch `dependency_trimming`).** Same
net-first + TDD method:
1. **url_launcher:** Android = one ACTION_VIEW intent via MethodChannel;
   Linux = `xdg-open`. Then delete `url_launcher`.

   Sweep, verified 2026-08-10. `launchUrl` is called in two places, both
   `LaunchMode.externalApplication` (system browser, never a webview):
   `url_link.dart:37` inside `showUrlDialog`, which seven screens reach
   (unlock x2, import x2, about x2, adopt); and
   `entry_detail_screen.dart:53`, an injectable seam behind its own confirm
   dialog. `entry_detail` is tested either side of its confirm dialog
   (`entry_detail_screen_test.dart:578,595`); `url_link` had nothing.
   (The old "3 call sites (url_link, entry_detail, about)" note was wrong:
   About goes through `showUrlDialog` like the rest.)

   Net — pin green against current code before any red test:
   - [x] N1 the dialog's "Open in browser" reaches the launcher with the URL
     shown; Close launches nothing (`test/url_link_test.dart`, new `openUrl`
     seam)
   - [x] N2 a failed launch tells the user (`couldNotOpen`)
   - [x] N3 the entry's confirm dialog, both ways — already covered
   - [x] N4 a bare `example.com` becomes `https://example.com`; an unreadable
     one opens nothing. The scheme logic is now `browserUri()`, named and
     tested apart from the launch it used to be tangled with.

   Design: one channel on `GabbroUnlockHostActivity` — the unlock screen shows
   URL dialogs (`unlock_screen.dart:988,1015`) and the autofill prompts use
   that screen, so the main activity alone is not enough. Linux runs `xdg-open`
   with the URL as one argument, never through a shell. **Web pages only:**
   `http`/`https` are opened, anything else is refused and says so. Entry URLs
   are user data, and nothing in Gabbro is a file/ftp/ssh client (YAGNI).

   TDD, red-first, in order:
   - [x] 1 Linux: opening runs `xdg-open` with the URL as a single argument
     (`lib/linux_url_opener.dart`, `test/linux_url_opener_test.dart`)
   - [x] 2 Linux: `xdg-open` missing or failing reports failure, so the user is
     told rather than left with nothing (a box without xdg-utils threw, which
     would have killed the isolate on a link tap)
   - [x] 3 Android: opening sends the URL over the channel; a platform failure
     reports failure (`lib/android_url_opener.dart`, channel-mocked)
   - [x] 4 Kotlin: the channel starts a view intent; no app to handle it
     reports failure instead of crashing (`GabbroUrl.kt` + `GabbroUrlTest.kt`;
     the handler sits on `GabbroUnlockHostActivity` beside the picker)
   - [x] 5 one facade picks Linux vs Android, shaped like the file picker
     (`lib/gabbro_url_opener.dart`; `browserUri` moved in from `entry_detail`).
     Not yet wired to the call sites — that lands with 7.
   - [x] 6 anything but `http`/`https` is refused and says so — in the facade,
     the single place both call sites and both platforms pass through.
     `file://`, `ftp://` and `ssh://` all reached the system before.
   - [x] 7a both call sites go through the facade; `url_launcher` out of
     `pubspec.yaml`; About screen drops it. `open()` answers with which of the
     three outcomes happened, so callers can tell a refusal from a failure.
   - [x] 7b `entry_detail` says so when opening fails — it showed nothing
     before, so a refused link was a button that did nothing
   - [x] 7c a refused non-web link gets its own message (`onlyWebLinks`, all 37
     locales): "could not open" reads as a malfunction when it is a rule
   - [x] 7d both messages announced on Linux (`reportUrlOutcome`, shared by both
     call sites) — a screen reader never reads a SnackBar there
   - [x] 7e the new string survives 8x text on a 360px phone in every locale
     (`test/url_link_overflow_test.dart`). At 8x no message this long fits a
     screen, so the test asks whether it can be **scrolled to**, not whether it
     fits. Both checks proven to fail against a SnackBar before being trusted.
     Two real defects found:
     - the message ran off the bottom in all 37 locales (2080dp of text on an
       800dp screen); both messages now use a dialog, which scrolls (ADR-016)
     - the URL dialog's close button was shutting the message dialog instead of
       itself, so the explanation vanished the instant it appeared
   - [ ] 8 hardware: an About link, an entry's URL and an import help link, on
     Android and Linux

---

## Build & Release

Build environment (Android/Kotlin/Java, SAF export) and full release process:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Release
- **Outstanding: the AUR push.** `gabbro-bin` is bumped to `0.1.0_alpha.18` and
  committed in the AUR clone; the push fails — the AUR is in maintenance
  (still down 2026-08-05). Until it lands, Arch users install alpha.16. Retry with
  `git -C ../gabbro-bin-aur push` from `gabbro/`.

### Features and UI/UX
- **Every SnackBar is unreadable at the largest text sizes.** A SnackBar clips
  instead of scrolling, so at 8x on a 360dp phone its text runs off the bottom
  of the screen — measured 2080dp tall against 800dp, in all 37 locales
  (found 2026-08-10 while netting the URL messages). Those two messages moved to
  a dialog; every other SnackBar in the app has the same problem. Sweep them and
  decide: dialog, capped text scale, or accepted limit. Test by the message's
  rectangle — a clipped SnackBar throws no layout exception.
- **Final launcher logo (logo-blocked).** `render_icons.sh` renders a placeholder
  SVG. When the real logo lands, replace `assets/images/source/ic_launcher_light.svg`
  and re-run it; same render covers the Windows `.ico` (still the stock Flutter template).
- **A third sync choice — decide whether we want it at all before building.** It would take
  the incoming vault and replace this one (dropping local-only entries, which nothing does
  today). A third path may make the choice more confusing, not less; settle that first. The
  dialog is already three buttons (auto, review, Cancel) in a scrollable column; a fourth is
  what `test/sync_chooser_l10n_overflow_test.dart` will catch at 8x text.

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