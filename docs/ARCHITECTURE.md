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

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text scale (`text_scale`, 0.8-3.0; renders clamp to the device max — 2x under 600dp shortest side, 3x above, `lib/text_scale.dart`), high-contrast, alphabet bar position.

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
| Flutter (`flutter test`) | 2246 | 10 |
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
| "Kotlin does not yet support 25 JDK target, falling back to JVM_24" | Flutter SDK's own unpinned Gradle modules | Upstream; appeared with the Java-25 JBR (2026-08-11). Our `:app` is pinned to JVM 21 (netted). Clears when Kotlin adds the 25 target. |
| JVM restricted-method (`System::load`) | Gradle `native-platform` jar | Gradle's own jar. Did NOT clear at 9.3.1 (still ships `0.22-milestone-29`); Java 25 warns on it every run. Blocks at a future Java. No action. |
| `cargo deny` no-license-field: `allo-isolate` | `flutter_rust_bridge` dep | Fixed on their master; await release. `[[licenses.clarify]]` is inert — don't retry. |
| `cargo deny` duplicates x6 | `argon2`->`digest`, `jni`->`libloading`, `bindgen`->`shlex` | Upstream pins. Was x7; RT-3 took the `hybrid-array` duplicate with `ml-kem`. The crate itself stays (`sha2`/`hkdf` -> `digest` need it). |
| KGP via `buildscript` classpath | `url_launcher_android` | Did not reproduce 2026-08-06; re-check before acting. |

**AGP note:** every module, `rust_lib_gabbro` included, loads AGP **8.11.1**. The
`com.android.tools.build:gradle:7.3.0` line in `rust_builder/android/build.gradle` is
resolved but never applied — inert, emits no warning.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next. Completed items are deleted from this section.

### Next task

**Remove the "Recently used apps" suggestion chips (Android, Login editor).**

*What it is:* under the "Android app ID" field on Android, a row of tap-to-fill chips
listing package names. Populated only when the autofill service fires on a **native**
app **while the vault is unlocked** and nothing matched; capped at 10, newest first.

*Why remove:* redundant. From that same login screen the user can just type the
password and let `onSaveRequest` create the entry with `app_id` already set — no editor
visit, no chip. The chips only help if the user hits the login screen, does *not* log
in, and later creates the entry by hand. Cost: an unencrypted SharedPreferences list of
"apps I tried to log into", with no clear/reset UI anywhere. Added 2026-06-16
(`7d5c689` + `6df2124`); stated reason was only "so you needn't hunt for the package
name" (CHANGELOG.md:222).

*Caveat to check first:* some apps never send Android a save request, so the
type-it-and-save path silently fails there and the chip is the only fallback. Not
observed in practice; maintainer accepted the risk. If it turns up, reconsider.

*Sites (verified 2026-08-16. Net-first: pin current behaviour green before cutting —
the baseline is a **full** `flutter test`, not one file: `screen_catalog.dart` feeds
other sweeps):*
- `android/…/GabbroAutofillService.kt` — `object RecentAutofillApps`, `recentAppsUpdated()`, `shouldRecordPackage()`, the `record()` call in `onFillRequest`
- `android/…/MainActivity.kt` — the **whole** `AUTOFILL_CHANNEL` MethodChannel block (it serves only `getRecentApps`), the const, class doc-comment. Safe: `UnlockActivity` registers the same channel *name* on its own engine and `lib/main.dart` targets that one
- `lib/screens/create_entry_screen.dart` — `_defaultRecentApps()`, `recentAppsFetcher`, `_recentApps`, the chips block
- `lib/l10n/*.arb` — `recentlyUsedApps` in all **37** locales (no `@`-description block); regenerate `app_localizations_*.dart`
- Tests: `android/…/GabbroAutofillServiceTest.kt` (`recentAppsUpdated_*` x3, `shouldRecordPackage_*` x3), `android/…/GabbroAutofillServiceRobolectricTest.kt` (`recentAutofillApps_*` x2), `test/create_entry_screen_test.dart` (chips x2), `test/screen_catalog.dart`
- Docs: CHANGELOG entry for the removal; `CHANGELOG.md:222` is history, leave it
- Not sites: backup rules exclude `sharedpref` by wildcard; `AutofillChipLabelTest.kt` guards the *system autofill dropdown* label — unrelated, leave it

Nets that must not regress already exist — no new ones needed for the cut:
`matchingCredentials_native_exact_app_id_match`, `matchSaveTarget_native_app_id_*`,
`parseSummariesJson_reads_app_id_field`, and four app-id tests in `create_entry_screen_test.dart`.

Accepted net gap: `onFillRequest` has no test at all. The deleted `record()` block leaves
the branch's `buildSaveOnlyResponse` untouched; pinning it needs FillRequest/AssistStructure
mocks — out of proportion to a 3-line cut. Hardware pass covers it.

The app-id field itself **stays** — only the chips and the capture store go.

*Also agreed:* purge the orphaned store on upgraded installs. `MainActivity` is a
FlutterActivity with no test harness, so put the purge in a top-level
`internal fun purgeLegacyRecentApps(context)` in `MainActivity.kt`, called from
`onCreate`; Robolectric red-tests it via `RuntimeEnvironment.getApplication()`
(pattern: `BiometricStoreTest`). `deleteSharedPreferences` is API 24 = our minSdk, no
guard needed. Add a Bikeshed entry to delete the purge at v1.0.

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