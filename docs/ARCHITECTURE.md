# Gabbro Architecture

## Project Overview

A post-quantum password manager built with security as core DNA.
Named after the intrusive igneous rock — hard, stable, enduring.
Cross-platform: Linux (Arch, Mint), Android; Windows later. FOSS, GPL-3.0-only.

**Core principle:** if it touches a secret, it lives in Rust. Everything else lives in Flutter. Secrets never cross the Flutter/Rust bridge in plaintext.

## General Information

**Tech stack:** Flutter (Dart) frontend, Rust backend/crypto, flutter_rust_bridge v2 (FFI).

**Encryption (at rest):** Argon2id KDF → X25519 + ML-KEM-1024 hybrid key exchange → HKDF-SHA256 combiner → AES-256-GCM. Post-quantum: belt and suspenders.

**Authentication (app access):** Mandatory FIDO2/WebAuthn hardware key (YubiKey). v1 uses Ed25519 (hardware constraint); target ML-DSA-44 once Yubico ships PQ-capable hardware (ADR-005). Min 2 keys (primary + backup), max 4. Auto-lock: 30s default, configurable.

**YubiKey NFC / NDEF OTP:** a YubiKey's OTP slot 1 (an NDEF URI) would open a browser when tapped on Android. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` and by re-arming foreground dispatch after `stopNfcDiscovery`; OTP slot 1 can stay enabled (no `ykman` workaround). Full diagnosis in LEARNINGS.md.

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce, ML-KEM ciphertext, X25519 ephemeral pubkey) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 6 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom. Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, many languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text size, high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). Later: Windows.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Play Store one-time payment is licence-compatible; F-Droid free build coexists without conflict.

**Version control:** private GitHub repo at https://github.com/Zabamund/gabbro. SSH auth. `chat_info/` is git-ignored.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, export, import, generator, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, vault_registry, safe_file_picker
├── rust/src/
│   ├── api/              # Bridge surface: vault, vault_bridge, import, *_generator, fido_bridge, autofill_bridge, entropy, types
│   ├── crypto/           # Internal (not bridge-exposed): kdf, keypair, ml_kem, hkdf, aes_gcm, vault_crypto
│   ├── vault/            # Domain model: entry, file_format, io, serialization, session
│   ├── fido/             # FIDO2/libfido2 FFI (Linux only)
│   ├── import/           # enpass, bitwarden, google_pm, dashlane, csv
│   └── bin/  scripts/  examples/   # bench_kdf, mem_forensics; wordlist gen; gen_fixtures
├── rust/tests/           # Backward-compat gate + state-machine fuzzer + parse fuzzer + frozen golden fixtures (FIXTURES.md)
├── android/…/kotlin/…/   # GabbroAutofillService, UnlockActivity, YubiKeyManager, BiometricHelper (+ Robolectric tests)
├── docs/                 # ARCHITECTURE, LEARNINGS, SECURITY, AI_*; decisions/ (ADRs); artefacts/
├── test/  integration_test/  test_driver/   # Flutter widget/unit + Linux real-FFI device suites
├── assets/               # fonts, images, help/ (in-app help screenshots)
├── challenge/            # crack-me challenge vault + rules
└── CHANGELOG.md  README.md
```

## Features

Shipped features are recorded in `CHANGELOG.md`. Planned and deferred work lives in the Bikeshed at the end of this file.

## Testing

| Suite | Passing | Ignored |
|-------|---------|---------|
| Rust (`cargo test -q`) | 514 | 8 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 10 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 808 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 7 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 26 | 17 |

**Test isolation (non-negotiable):** no test may touch the user's real settings or
vault folders. All config/data directories resolve through `GabbroPaths`
(`lib/app_paths.dart`), and `test/flutter_test_config.dart` roots every `flutter test`
run in a throwaway temp sandbox — so even a test that forgets to isolate itself reads an
empty registry and can never reach a real vault (wherever the user saved it). Mirrors the
`rust/tests/fixtures/` ethos of never operating on real data.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next task

**Wayland/bubblewrap file-picker hardening + sandbox launch docs.**

A Debian/Wayland tester (running under a bubblewrap sandbox) surfaced two distinct
problems. Only one is fixable in our binary:

1. **Boot needs `WAYLAND_DISPLAY` (packaging, not code).** The sandbox didn't
   forward the Wayland socket, so GTK found no display and the app never reached
   Dart; the tester worked around it with `--setenv WAYLAND_DISPLAY "/tmp/wayland-0"`.
   This is *before any Dart runs* → cannot be fixed in `app_paths.dart`. **Doc only.**
2. **File save/open crashes with `SocketException` (our bug).** `file_picker` on
   Linux talks *only* to the XDG Desktop Portal over the DBus **session** bus. In
   the sandbox `/run/user/1000/bus` isn't bound in, so `DBusClient._openSocket`
   throws `SocketException`, which propagates **unhandled** out of
   `FilePicker.saveFile`/`pickFiles` and crashes the isolate. Same crash lurks at
   every picker call site: `path_field.dart:_pick`, `export_screen.dart`
   (`getDirectoryPath`), `entry_detail_screen.dart` (`saveFile`),
   `create_entry_screen.dart` (`pickFiles`), `vault_list_screen.dart` (`pickFiles`),
   `unlock_screen.dart` (restore-from-file `pickFiles`). Editable path fields are
   already the manual fallback (`path_field_test.dart`), but only if you *type*
   instead of *clicking* — clicking the folder icon still crashes.

**Code + docs landed (code-green, NOT yet hardware-verified):**
- New `lib/safe_file_picker.dart`: `FilePickerUnavailable` (carries the cause),
  `runPicker<T>` (passes through value/`null`-cancel, converts any thrown
  `Exception` -> `FilePickerUnavailable`), and `showPickerUnavailable(context,
  {hasManualEntry})`. Two ARB keys: `filePickerUnavailable` (flows with an
  editable path field -> "type or paste the path instead") and
  `filePickerNoPortal` (picker-only flows -> "system file portal isn't
  reachable"), both in all 37 locales.
- All 6 call sites guarded: `path_field` and `export_screen`/`entry_detail`/
  `create_entry`/`vault_list` wrap the picker in `runPicker` at the call site;
  `unlock_screen` wraps inside `_defaultRestoreFromFile` (the seam bundles
  pick+restore, so a portal failure is distinguished from an invalid vault).
- 15 new tests (option b: dedicated widget tests for every site), `flutter test`
  808 green, `flutter analyze` clean.
- `BUILD_AND_RELEASE.md` -> "Running under a Wayland/bubblewrap sandbox": the
  `WAYLAND_DISPLAY` setenv + the `--ro-bind` for the DBus session bus +
  xdg-desktop-portal (closes problem 1, which is doc-only).

**STILL OPEN (the only thing between here and done):** the Debian/Wayland tester
must confirm on real hardware that (a) the documented `bwrap` binds let file
pick/save work, and (b) with the portal still missing, the app shows the SnackBar
instead of crashing. Component-green is not done — see the "real hardware = done"
rule. Until then this task stays in Current Focus.

**Shipped for that test:** cut as **v0.1.0-alpha.7 (2026-06-13)** after the full
release gate passed green (flutter 808, cargo 514, both integration suites,
backward-compat gate, fuzzer, Android build). The release exists *so* the
Debian/Wayland tester can run the bwrap matrix above — it does not close the task.

After this: **R-04 — Linux core-dump hardening** (now in the bikeshed Security list).

### Open from the security audit

Full per-finding status and detail live in `AI_SECURITY_AUDIT.md`. Still open:

- **F-03** — X-Wing transcript-binding combiner; gated on a human cryptographer (no verifiable-against-spec answer).
- **F-10** — eTLD+1 autofill matching; post-v1 "Strict FQDN" toggle.

A second-pass review (`AI_SECURITY_AUDIT_REVIEW.md`, 2026-06-11) added findings
**R-01…R-07** (per-finding status lives in that document's remediation table).
**R-02** (Android Auto Backup uploaded the vault to Google Drive) and **R-03**
(automatic `.bak` safety copy + corruption-recovery UX + restore-from-backup-file)
are **fixed** — remaining priorities: **R-04** Linux core-dump hardening, then
R-01/R-05/R-06/R-07.

**UI locales deferred** (RTL layout work required): Hebrew, Arabic.

---

## Build & Release

Build-environment notes (Android/Kotlin/Java setup, SAF export) and the full
release process (pre-flight gate, build, publish) live in their own document:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1 gates)
- **R-04 Linux core-dump hardening** — `PR_SET_DUMPABLE(0)` + `RLIMIT_CORE(0)`, following `AI_SECURITY_AUDIT_REVIEW.md`. Stops a crash from writing a core file that could contain decrypted vault material. Next security item after the Wayland/file-picker task.
- **F-03 X-Wing combiner** — migrate the hybrid KEM combiner to a transcript-binding (X-Wing-style) construction (`ikm = ml_kem_ss ∥ x25519_ss ∥ ml_kem_ct ∥ x25519_pubkey`). No single verifiable-against-spec answer → genuinely needs a human cryptographer's judgement. Would require VERSION 8.
- Human expert cryptography review of `rust/src/crypto/` (ETH/EPFL academic outreach, RustCrypto maintainers, or formal audit).
- Test on de-Googled Android (GrapheneOS/CalyxOS) before v1 — find a willing community tester, don't buy hardware.
- Pin CI Actions to commit SHAs; add `cargo audit` + `osv-scanner --lockfile pubspec.lock` steps (once CI exists). See Track A Phase 1 audit in `AI_SECURITY_AUDIT.md`.

### Features & UX
- Privacy-safe "open existing vault by path" (ADR-012 Option B) — a future relaxation of the
  vault-deletion privacy rules under `show_vault_list` OFF. Dead on Android app-private
  storage, low priority.
- **Autofill match quality (Android) — needs a serious dedicated session.** On-device
  reality (2026-06-09, S23): on most sites autofill offers nothing, on some it fills the
  *wrong* credential ("wrong password"), on very few it works. Three suspects, all now
  pinned by Robolectric tests in `GabbroAutofillServiceRobolectricTest`:
  (1) **field detection** — `ParsedStructure.collectIds` heuristics (autofill hints →
  inputType → hint/idEntry keywords) miss many real login forms, especially SPA/Chromium
  DOM-to-AssistStructure shapes → "offers nothing";
  (2) **domain matching** — `extractRegistrableDomain`'s naive last-two-labels eTLD+1
  (audit **F-10**) collapses e.g. `*.co.uk` to `co.uk`, so unrelated sites can collide →
  "wrong password"; needs the Public Suffix List;
  (3) **native-app matching** — `extractAppToken` + `summary.url.contains(token)` substring
  match is far too loose (e.g. token `paypal` matches any URL containing it) → wrong entry.
  Plan it as: PSL-backed eTLD+1, a real form-field model, and tightened app matching
  (package-name mapping, see the V2+ item). Touches the Android autofill security surface,
  so design-then-implement with on-device verification.
- Autofill silent no-match (unlocked path): decide whether to surface a notification/toast.
- Autofill save requests (`onSaveRequest` — full design in a dedicated session).

### Code Quality
- KGP warning: `file_picker` and `url_launcher_android` apply Kotlin Gradle Plugin (KGP) via the old per-plugin `buildscript` classpath pattern. Flutter warns this will become a hard build error in a future Flutter version. Both plugins are at their latest pub versions — fix must come from upstream. Monitor for `file_picker 12.x` and `url_launcher_android` releases that remove per-plugin KGP application.

### V2+ / Defer
- Passphrase wordlists — not viable without significant pipeline work: `yo` Yoruba (no frequency ordering, complex tonal diacritics); `sr_Latn` Serbian Latin (only Cyrillic corpora; needs transliteration pipeline); `lb` Luxembourgish (small speaker base); `wa` Walloon (nothing usable, French covers Wallonia).
- Autofill via `auto-type` (desktop) — global hotkey → foreground-window detection → synthesised keystrokes into another app (the KeePass/KeePassXC model, no browser extension). Needs a dedicated design session + ADR: Wayland blocks synthetic input outside the freedesktop RemoteDesktop portal / `libei` (KeePassXC's own auto-type is partial there), it's a new secret→input-subsystem security surface, and it cuts across "secrets live in Rust" (Rust holds the secret + synthesises input, Flutter registers the hotkey, per-platform window detection). Desktop-first; shares no code with Android autofill. Discuss-then-plan-or-drop.
- Passkey (WebAuthn discoverable credential) support.
- Vault sync across devices.
- Autofill save requests (`onSaveRequest`) — see also Features & UX above.
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
- Native app autofill matching by package name (v2).