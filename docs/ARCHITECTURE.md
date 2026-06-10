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

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, 29 languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text size, high-contrast, alphabet bar position.

**Platforms:** v1: Linux (Arch + Mint/deb), Android (F-Droid + Play Store). Later: Windows.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html). `pubspec.yaml` is `0.1.0-alpha.6+6`. `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Play Store one-time payment is licence-compatible; F-Droid free build coexists without conflict.

**Version control:** private GitHub repo at https://github.com/Zabamund/gabbro. SSH auth. `chat_info/` is git-ignored.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, export, import, generator, settings, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, vault_registry
├── rust/src/
│   ├── api/              # Bridge surface: vault, vault_bridge, import, *_generator, fido_bridge, autofill_bridge, entropy, types
│   ├── crypto/           # Internal (not bridge-exposed): kdf, keypair, ml_kem, hkdf, aes_gcm, vault_crypto
│   ├── vault/            # Domain model: entry, file_format, io, serialization, session
│   ├── fido/             # FIDO2/libfido2 FFI (Linux only)
│   ├── import/           # enpass, bitwarden, google_pm, dashlane, csv
│   └── bin/  scripts/  examples/   # bench_kdf, mem_forensics; wordlist gen; gen_fixtures
├── rust/tests/           # Backward-compat gate + state-machine fuzzer + frozen golden fixtures (FIXTURES.md)
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
| Rust (`cargo test -q`) | 489 | 8 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 10 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 739 | 0 |
| Flutter integration (`flutter drive … -d linux --profile`) | 7 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 23 | 17 |

**Test isolation (non-negotiable):** no test may touch the user's real settings or
vault folders. All config/data directories resolve through `GabbroPaths`
(`lib/app_paths.dart`), and `test/flutter_test_config.dart` roots every `flutter test`
run in a throwaway temp sandbox — so even a test that forgets to isolate itself reads an
empty registry and can never reach a real vault (wherever the user saved it). Mirrors the
`rust/tests/fixtures/` ethos of never operating on real data.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next.

### Next active task — `v0.1.0-alpha.6` release

The agreed next task. ADR-013 (export security + key-protected *Sync from file*) and
the Android SAF export are done, committed, and hardware-verified — the release's
anchor, alongside everything accumulated since alpha.5 (the `[0.1.0-alpha.6]` CHANGELOG
block is already the complete, correct changelog; no reconstruction needed).

**Pre-flight** (full build/package/publish commands in ## Release Process below):

1. **Gate must be green.** Rob runs `~/bash_scripts/test_gabbro` (Linux: `flutter test`,
   `cargo test -q`, `cargo clippy --all-targets`, the two `flutter drive` integration
   suites, the backward-compat gate, the fuzzer) **plus** the Android unit tests
   (`cd android && ./gradlew :app:testDebugUnitTest` — not in the script; ran green
   this session, 23/17).
2. Set the date on the `[0.1.0-alpha.6]` CHANGELOG block (currently `YYYY-MM-DD`).
3. Confirm `pubspec.yaml` is `0.1.0-alpha.6` (optionally bump the build to `+7`).
4. Commit (docs).

**⚠️ The `v0.1.0-alpha.6` tag is premature — MOVE it, don't reuse in place.** alpha.6
was **never published** (the GitHub release is an unpublished draft), but the git tag
was pushed early to commit `5f7675a` (2026-06-07) and development continued under the
same version. Before tagging the real release:

```
git push origin :refs/tags/v0.1.0-alpha.6   # delete the stale remote tag
git tag -d v0.1.0-alpha.6                    # delete it locally
# …after the release commit:
git tag -a v0.1.0-alpha.6 -m "v0.1.0-alpha.6" && git push origin v0.1.0-alpha.6
```

Safe because nothing shipped as alpha.6; on any other clone use `git fetch --tags --force`.

**Publish:** delete the stale GitHub draft release, then create it fresh from the moved
tag with the Linux tarball + Android APK + the alpha disclaimer (manually on github.com —
no `gh` CLI on Rob's box).

### Open from the security audit

Full per-finding status and detail live in `AI_SECURITY_AUDIT.md`. Still open:

- **F-03** — X-Wing transcript-binding combiner; gated on a human cryptographer (no verifiable-against-spec answer).
- **F-10** — eTLD+1 autofill matching; post-v1 "Strict FQDN" toggle.

**UI locales deferred** (RTL layout work required): Hebrew, Arabic.

---

## Build Environment

**Critical notes — read before Android or Kotlin sessions.**

- System Java is 26.0.1 — incompatible with Kotlin compiler. Fix: `org.gradle.java.home=/opt/android-studio/jbr` in `android/gradle.properties` (points to Java 21).
- AGP 8.11.1 in `android/settings.gradle.kts`. Java and Kotlin JVM target both set to 21 in `app/build.gradle.kts`.
- `libfido2-sys` and `pub mod fido` are gated behind `cfg(not(target_os = "android"))` — libfido2 is Linux-only; Android uses yubikit-android via Kotlin.
- yubikit-android 3.1.0: use `Ctap2Session` (raw CTAP2) not `Ctap2Client` (WebAuthn wrapper). `Ctap2Client` enforces WebAuthn domain validation — rejects `"app.gabbro.gabbro"` as RP ID. `Ctap2Session` has no such restriction.
- `Ctap2Session` has no unified `YubiKeyConnection` constructor — use the `ctap2Session()` private helper in `YubiKeyManager` which dispatches on `SmartCardConnection` (NFC) vs `FidoConnection` (USB HID).
- USB transport: `UsbFidoConnection` (HID interface). NFC transport: `SmartCardConnection` (ISO 7816). Both produce a `YubiKeyConnection` usable with `ctap2Session()`.
- RP ID `"app.gabbro.gabbro"` is correct at CTAP2 level — it is just an identifier string, no domain required.
- Export to shared storage uses SAF, not raw paths: the `app.gabbro.gabbro/export` MethodChannel (`MainActivity.kt`, `androidx.documentfile` dep) writes `.gabbro` files into a user-granted directory tree (`ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`). Raw `fs::rename` can't overwrite another app's file under scoped storage (EPERM). No `MANAGE_EXTERNAL_STORAGE`. See ADR-013.

---

## Release Process

**Tag format:** `v0.1.0-alpha.N` until the pre-v1 security gates (Bikeshed) clear — honest with testers that no external crypto review has happened yet. Repo is private; the Debian collaborator pulls releases from GitHub, other testers receive artifacts directly.

**Pre-flight:**

1. Move the `[Unreleased]` block in `CHANGELOG.md` to `[0.1.0-alpha.N] – YYYY-MM-DD`.
2. Bump `version` in `pubspec.yaml` to match.
3. Run **all** of the following green. The first three are the routine suites; the
   rest are NOT covered by `flutter test` or `cargo test -q` and must be run by hand:

   ```bash
   # Routine suites (debug)
   # Run from gabbro/
   flutter test
   cd rust
   cargo test -q
   cargo clippy -- -D warnings

   # Flutter integration — real Rust FFI on a device (flutter test can't load the native lib).
   # Run once per suite in integration_test/:
   cd ..
   flutter drive --driver=test_driver/integration_test.dart \
     --target=integration_test/vault_session_test.dart -d linux --profile
   flutter drive --driver=test_driver/integration_test.dart \
     --target=integration_test/entry_edit_test.dart   -d linux --profile

   # Vault backward-compat gate — run in release (debug works but is ~6 min vs ~14 s).
   cd rust
   cargo test --release --test vault_backward_compat

   # Vault state-machine fuzzer — #[ignore]'d, so cargo test -q never runs it.
   cargo test --release --test vault_state_machine_fuzz -- --ignored
   ```

   Notes:
   - **New vault format VERSION this release?** Before running the gate, generate and
     commit its `vN_passphrase.gabbro` + `vN_multikey_2keys.gabbro` fixtures (recipe:
     `rust/tests/fixtures/FIXTURES.md`). The gate only protects versions with a fixture.
   - **Fuzzer found a failure?** It prints the seed + op log. Reproduce, minimise, and
     add the sequence to `vault_backward_compat.rs` as a fixed regression test. Widen
     the search with `GABBRO_FUZZ_CASES=64`.
   - The 8 ignored Rust + 17 ignored Kotlin tests are hardware-only (YubiKey /
     biometric / AndroidKeyStore) and cannot run without the devices.
4. Commit, then `git tag -a v0.1.0-alpha.N -m "v0.1.0-alpha.N" && git push origin v0.1.0-alpha.N`.

**Build:**
- **Linux:** `flutter build linux --release` → self-contained bundle in `build/linux/x64/release/bundle/`; package with `tar -czf gabbro-<ver>-linux-x86_64.tar.gz -C build/linux/x64/release bundle`. (The Arch-built bundle runs on Debian trixie / Mint — glibc ≤ 2.34, verified; only build in a `debian:trixie` container if a future release raises that above 2.41.)
- **Android:** `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`; rename to `gabbro-<ver>-android.apk`. The signing keystore (`android/app/gabbro-upload.jks`) and `android/key.properties` are already configured and gitignored.

**Publish:** `gh release create v0.1.0-alpha.N <linux.tar.gz> <android.apk> --title "Gabbro v0.1.0-alpha.N" --prerelease`, with the disclaimer: *"Alpha — for invited testers only. The cryptographic implementation has not undergone external review. Do not store passwords you cannot afford to lose."*

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Security (pre-v1 gates)
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
- **Dedupe the YubiKey tap dispatch** — `lib/widgets/yubikey_tap.dart`
  (`getAnyYubikeyHmacSecret`, added for ADR-013 import sync) duplicates the
  Linux/Android multi-key tap logic the unlock screen still inlines. The unlock
  screen (and the single-key paths) could adopt the shared helper. Low priority,
  no behaviour change. While there, consider the app-wide gap the ADR-013 hardware
  test surfaced: the Android tap call blocks with no timeout/explicit Cancel
  (recoverable only via the back arrow); unlock has the same pattern. Deemed
  sufficient for now (a "tap your YubiKey now" cue was added to import sync).
- **Language-picker invariant tests** (quick win) — pure-function tests in
  `test/language_screen_test.dart`: every `LanguageChoice` maps to a non-empty, *unique*
  label via `languageChoiceLabel` (no ambiguous picker rows), and `sortedLanguageChoices`
  returns all `LanguageChoice.values` with `system` first and the rest alphabetical by label.
  Auto-covers future languages; replaces the brittle `values.length == 35` magic number.
  Complements the endonym guard added for the langDutch fix.
- **Locale-resolution guard** (quick win) — assert every non-`system` `LanguageChoice`
  resolves (via `_localeFor` in `main.dart`) to a locale present in
  `AppLocalizations.supportedLocales`, so a half-wired new language can't silently fall back
  to English (user picks "Polski", gets English). `_localeFor` is private — needs a small
  test seam or a per-choice GabbroApp drive that detects the fallback.
- **`SealedVault::from_bytes` malformed-input fuzz test** (quick win, security-adjacent) —
  the parser in `rust/src/vault/file_format.rs` is *currently* well-defended: every slice at
  lines ~232–369 is preceded by an `if data.len() < pos + N { return Err(..) }` guard, so each
  `try_into().unwrap()` is infallible by construction and truncated input returns a clean
  `Err`, not a panic. But that safety is held **only by inspection** — there is no negative
  test. The backward-compat harness (`rust/tests/vault_backward_compat.rs`) only ever feeds
  *valid* vaults through `from_bytes`. One careless edit (a slice added without its guard, or
  the theoretical `pos + body_len` usize-overflow from the attacker-controlled 8-byte body-len
  field at line ~369 — wraps in release, can invert a slice range) would reintroduce a
  crash-on-open and nothing would catch it. Add a property/fuzz test (mirror the
  `vault_state_machine_fuzz.rs` seeded-`rand` style, likely as a new
  `rust/tests/vault_parse_fuzz.rs`) that feeds `from_bytes`: (1) every truncation `data[..n]`
  of a valid sealed vault for all n, (2) random garbage of assorted lengths, (3) a valid magic
  prefix followed by corrupted/oversized length fields, and asserts **returns `Err`, never
  panics** (use `std::panic::catch_unwind` or just rely on the harness — a panic fails the
  test). Locks in the existing good behaviour and the project's "tests catch malformed-input
  crashes" philosophy. Audit context: only 26 production `.unwrap()`s exist repo-wide; the
  rest are the generated bridge (`frb_generated.rs`, off-limits) or `expect()` on fixed-size
  crypto conversions and dev-only bins (`mem_forensics`, `bench_kdf`) — all benign. ~30–45 min.
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