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

**Passkey provider:** website passkeys (WebAuthn discoverable credentials) are
vault entries (type Passkey, format v12) so they sync and back up; the tradeoff
is website private keys in the vault instead of hardware, the upside no slot
cap. Private keys never cross the FFI bridge (`create_entry` refuses Passkey
DTOs; edits restore key material from stored). Android:
`GabbroCredentialProviderService` via Credential Manager (log tag
`GabbroPasskey:`; emulator not viable — hardware-test on the S23). Native-app
passkeys sit behind the `app_passkeys` toggle (OFF default, F1): on, each app
login makes Gabbro's only network call — one assetlinks fetch to the login's
own site (README "Verify no telemetry"); off or network-revoked, only app
sign-ins refuse. The daemon bridge module compiles on every platform (inert
stubs off Linux) because FRB's generated code references it unconditionally;
a gate leg cargo-checks the Android target to pin that. Linux: an
in-process uhid virtual FIDO2 key (VID/PID 0x1209:0x0001, filtered out of
`fido_list_devices`) exists while the app runs; browsers speak CTAP2 to it,
consent is an in-app dialog, a locked vault answers only getInfo, and silent
allowList pre-flights (`options.up=false`) are answered without consent.

**YubiKey NFC / NDEF OTP:** a YubiKey's OTP slot 1 (an NDEF URI) would open a browser when tapped on Android. Gabbro suppresses this via `NfcConfiguration().skipNdefCheck(true)` and by re-arming foreground dispatch after `stopNfcDiscovery`; OTP slot 1 can stay enabled (no `ykman` workaround).

**Vault file format:** `.gabbro` binary. Plaintext header (magic, version, Argon2id params + salt, HKDF salt, nonce) + AES-256-GCM encrypted body (JSON-serialised entries). Self-contained; auth tag detects tampering.

**Vault entries:** 7 types — Login (displayed as "Password" in UI), Note, Identity, Card, File, Custom, Passkey (created only by the passkey provider flows, never by hand; edit covers notes/folder/custom fields). Common fields: UUID, created, modified, folder, tags, favourite. No TOTP — YubiKey covers 2FA; keeping them separate is more secure.

**Password generator:** classic (32–256 chars) and passphrase (4–20 words, many languages, EFF-style wordlists embedded at compile time). Classic mode is script-aware (Latin/Greek/Cyrillic pools). All generation in Rust.

**Settings:** `~/.config/gabbro/settings.jsonc` (Linux). JSONC format — human-editable. Theme, text scale (`text_scale`, 0.8-3.0; renders clamp to the device max — 2x under 600dp shortest side, 3x above, `lib/text_scale.dart`), high-contrast, alphabet bar position, auto-merge sync + sync folder (`auto_merge_sync`, `sync_folder`).

**Keyboard shortcuts (Linux desktop):** Ctrl+L lock, Ctrl+F / Ctrl+Shift+F search, Ctrl+N new entry, Ctrl+M menu, Ctrl+Q lock and quit (confirms first), Esc dismiss/cancel. No Ctrl+C (copying a secret stays a deliberate, auto-clearing action); no Super key. Listed in-app on the desktop-only Keyboard shortcuts screen.

**Platforms:** v1: Linux (Arch + Mint/deb), Android, GrapheneOS. v2 maybe: Windows.

**Versioning:** SemVer (semver.org/spec/v2.0.0.html); the current version lives in `pubspec.yaml` (single source of truth). `1.0` is a public trust commitment; don't ship it prematurely. CHANGELOG.md follows Keep a Changelog 1.0.0.

**Licence:** GPL-3.0-only (ADR-004). Every dependency licence must be GPL-3.0 compatible; the allow-list is `rust/deny.toml`, enforced by the `cargo deny` gate leg.

**Version control:** public GitHub repo at https://github.com/gabbro-foss/gabbro. SSH auth.

## Project Structure

```
gabbro/
├── lib/                  # Flutter app
│   ├── screens/          # unlock, vault list, adopt vault, export, import, sync settings, generator, keyboard shortcuts, appearance, security, manage vaults/folders, …
│   ├── widgets/          # path_field, generator_widget, yubikey_tap, password_breakdown_sheet, sync_review, sync_method_dialog, gabbro_dialog (every dialog goes through it), passkey_consent_dialog, passkey_hint_banner, text_size_slider, url_link, …
│   ├── src/rust/         # Auto-generated bridge (do not edit)
│   └── *.dart            # main, app_paths (GabbroPaths), settings, text_scale, control_scale, gabbro_contrast (high-contrast theme flag), folder_label, saf_tree (Android SAF tree pick/read channel), vault_registry, safe_file_picker, gabbro_file_picker (dialog facade), linux_file_picker (XDG portal client), android_file_picker (picker channel client), autotype_listener, autotype_target, passkey_daemon (Linux daemon orchestrator), app_passkeys_flag (F1 toggle mirror channel), clipboard_clear
├── rust/src/
│   ├── api/              # Bridge surface: vault, vault_bridge, import, *_generator, fido_bridge, passkey_bridge, passkey_daemon_bridge, autofill_bridge, autotype_bridge, entropy, types
│   ├── crypto/           # Internal (not bridge-exposed): kdf, hkdf, aes_gcm, vault_crypto, webauthn
│   ├── vault/            # Domain model: entry, file_format, io, serialization, session
│   ├── fido/             # FIDO2/libfido2 FFI (Linux only)
│   ├── import/           # enpass, bitwarden, google_pm, dashlane, csv
│   ├── hardening.rs      # Process hardening (R-04): core-dump + ptrace/mem disable (Linux)
│   ├── autotype/         # Linux auto-type (ADR-017): keysym, XTEST inject, active-window read, trigger IPC, sequences, fill orchestration (Linux-only)
│   ├── ctaphid.rs  ctap2.rs  uhid.rs  passkey_daemon.rs   # Linux passkey daemon (ADR-009): CTAPHID framing, CTAP2 commands, /dev/uhid transport, fd+pump+KEEPALIVE owner (Linux-only)
│   └── bin/  scripts/  examples/   # bench_kdf, mem_forensics, crash_writer, autotype_{spike,window,trigger} (diagnostics), gabbro-autotype (shipped trigger client); wordlist gen; gen_fixtures
├── rust/tests/           # Backward-compat gate + state-machine fuzzer + parse fuzzer + crash-safety (kill mid-write) + frozen golden fixtures (FIXTURES.md)
├── android/…/kotlin/…/   # GabbroUnlockHostActivity (base) + MainActivity/UnlockActivity/SaveActivity, GabbroAutofillService, GabbroCredentialProviderService + GabbroPasskeyActivity (passkey provider; testable core in PasskeyProvider.kt; vendored passkey_privileged_browsers.json in android assets), TapFlow, YubiKeyManager, AppPaths (paths channel), GabbroPicker (picker channel), BiometricHelper + BiometricStore (per-vault; + Robolectric tests), AppPasskeysStore (F1 toggle mirror)
├── linux/packaging/      # Desktop integration: render_icons.sh (icon tree); aur/ (AUR gabbro-bin PKGBUILD + gabbro-bin.install; .SRCINFO is generated in the AUR clone), deb/ (build-deb.sh -> binary .deb), udev/ + modules-load.d/ (canonical uhid rule + conf for passkeys)
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
| Rust (`cargo test -q`) | 816 | 20 |
| Rust vault backward-compat gate (`cargo test --release --test vault_backward_compat`) | 13 | 0 |
| Rust state-machine fuzzer (`cargo test --release --test vault_state_machine_fuzz -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust crash-safety, kill mid-write (`cargo test --release --test crash_safety -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync-walk batched apply (`cargo test --release --lib sync_walk_batched_apply_matches_checker -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust sync merges a never-edited entry (`cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored`) | 1 | 1 (opt-in by default) |
| Rust cancel-sync + no-plaintext-leak (`cargo test --release --lib {cancel_sync_rolls_back_to_pre_sync_state,apply_sync_decisions_clears_backup_so_cancel_is_noop,sync_never_writes_plaintext_secret_to_disk} -- --ignored`) | 3 | 3 (opt-in by default) |
| Rust fast-merge walk (`cargo test --release --lib fast_merge_walk_incoming_wins_and_order_dependent -- --ignored`) | 1 | 1 (opt-in by default) |
| Flutter (`flutter test`) | 2867 | 171 |
| Real-FFI suites (`dart test integration_test/ -j 1`) | 17 | 0 |
| Android (`./gradlew :app:testDebugUnitTest`) | 180 | 15 |

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
| `cargo deny` no-license-field: `allo-isolate` | `flutter_rust_bridge` dep | Fixed on their master; still present at FRB 2.13.0 (pins 0.1.27). `[[licenses.clarify]]` is inert — don't retry. |
| `cargo deny` duplicates x8 | `argon2`->`digest`, `jni`->`libloading`, `bindgen`->`shlex`, `p256`->`rand_core`+`getrandom` | Upstream pins. Was x6; `p256` (passkeys) added the `rand_core 0.10`/`getrandom 0.4` pair beside `rand 0.8`'s. |
| KGP via `buildscript` classpath | `url_launcher_android` | Did not reproduce 2026-08-06; re-check before acting. |
| Flutter: AGP 8.11.1 support "will soon be dropped" (wants >= 9.0.1) | Flutter tooling, new 2026-08-21 | A future Flutter upgrade refuses to build Android until AGP is bumped. No action yet: 8.11.1 still builds; bump AGP + Kotlin together when forced. |
| Flutter: Kotlin 2.2.20 support "will soon be dropped" (wants >= 2.3.20) | Flutter tooling, new 2026-08-21 | Same consequence and plan as the AGP row above. |

**AGP note:** every module, `rust_lib_gabbro` included, loads AGP **8.11.1**. The
`com.android.tools.build:gradle:7.3.0` line in `rust_builder/android/build.gradle` is
resolved but never applied — inert, emits no warning.

---

## Current Focus

> Update at the end of each session. First thing to read at the start of the next. Completed items are deleted from this section.

### Next task

**One-click sync** — full spec. Implementation lives in Bikeshed > **Sync family**
as three sections, promoted here one at a time; tick the list below as each lands.

Goal: feature parity with other password managers' one-click sync. On the
receiving device, `menu > Sync from vault`, and done.

**Requirements, every item, from the first test on.** Works on Linux and
Android (SAF paths differ, behaviour must not). Every new string ships in all
37 locales; every new control ships with a semantics label and a
screen-reader test (ADR-015) and holds up at the large-text ceilings (ADR-016).
None of this is a follow-up.

**S1. Sync and import are distinct operations and stay so.**
Sync = UUID merge of the *same* vault from another device: same format, same
entry types, entries carry identity. Import = additive load of foreign data
(other password managers, or a *different* Gabbro vault): radically different,
unpredictable, nothing to match on.

**S2. Labels.** `menu > Sync from file` becomes **Sync from vault** (two
`.gabbro` files are synced). The import screen's Gabbro button becomes
**Import** (says where the user is, and that it is a different operation).

**S3. Import, all 6 types, Gabbro included: additive, no dedupe.** Every source
entry is added, duplicates included. A change from today's content-hash skip:
the skipped-entries dialog and the `skipped` result go. Import is a
once-at-onboarding act into an empty vault; beyond that it is the user's
responsibility. Dedupe, if ever, is a separate task.

**S4. Routes for a `.gabbro` file.** Same vault: `menu > Sync from vault`.
Different Gabbro vault: `menu > Import entries > Gabbro vault > Import`
(passphrase, plus PIN + tap if the source is keyed).

**S5. Sync settings, a new menu entry**, holding:
- **Auto-merge** toggle, off by default. On: the sync applies as *Merge
  automatically* does today, without the chooser or the review. The toggle's
  description carries the same-passphrase warning (S7), since the chooser
  that shows it is skipped.
- **Sync folder** (where the other device's export lands) + **Remember**
  checkbox.
- The export and import folders, read-only, with a note that they are changed
  on `menu > Export` / `menu > Import entries`. One place to see every folder;
  one place each to change it.

**S6. Sync from vault, the flow.**
1. Sync folder set: no picker. The source is the file in that folder called
   `<alias>.gabbro`, this vault's own export name, so both devices agree by
   construction; it never collides with the on-disk `<alias>_gabbro.gabbro`.
   No folder set, or Remember unticked: picker, as today.
2. Source keyed: PIN + tap of the *source's* YubiKey, which may differ from
   the receiving vault's, if it has one. Passphrase-only source: no prompt.
3. Auto-merge off: the chooser as today (*Merge automatically* / *Review all
   changes* / Cancel). Auto-merge on: straight to the automatic merge.
4. The held passphrase is tried first, silently, either way.

**S7. Passphrase fallback stays, auto-merge on or off.** If the held passphrase
does not open the source, ask for one and continue with the choice already
made. Same passphrase does not prove same vault; a same vault may carry a
rotated passphrase. Import is not a substitute (S3 would duplicate every
entry). A passphrase-only source keeps today's chooser warning: *Same
passphrase does not prove same vault.*

**S8. Unchanged, pinned by the net before any change:** the chooser, both its
paths (automatic; one-by-one review with keep/pick/drop, Merge the rest,
Cancel-rolls-back), the merge engine, the keyed-source flow, the fallback,
and import parsing/counts/keyed source for all 6 types.

**S9. Export and import folders** live on their own screens behind a
**Remember** checkbox (not "Lock": the app already uses *lock* for the vault).
Android export already remembers silently; that mechanism is reused, its box
arrives ticked. Export and import may point at the same folder: that is the
sync case, where the file one device writes is the file the other reads.

**S10. Each screen says what it does.** The import screen explains additive
(duplicates included), the export screen what leaves and how, Sync settings
and the chooser what a merge does. Existing text is checked against S1-S9;
whatever is missing or wrong is fixed in the same section that changes it.

**Handover 2026-08-25 (session stopped here; read before anything).**
Branch `streamline_sync_process` off master `263252fd`, 19 commits, NOT pushed,
tree clean. `.scratchpad` holds the finished pass 2a; replace it. The full gate
has not run on the branch (Rust subset
`api::import vault::entry vault::session::tests` 91 green; `flutter test` 2867
green; Android unit 180 green). No dependency changed: no `--warm` needed.

Step 1 code is complete: net (S8), labels (S2), import additive (S3, Rust
`import.rs` + Dart, skipped dialog gone, `content_hash` gone), Sync settings
screen + `auto_merge_sync`/`sync_folder` (S5), Linux portal folder picker,
Android SAF tree read (`read_tree_file`, `saf_tree.dart`), Sync from vault by
export name `<alias>.gabbro` with auto-merge skipping the chooser (S6, S7),
on-screen texts (S10), plus two finds fixed on hardware: the folder picker
must go through `runPicker` (portal refuses a non-dumpable process), and
the edge-to-edge insets below.

Hardware so far: Linux passes 1a-1e all green (passphrase one-click, keyed
source made with two USB keys swapped on one port, keyed one-click with PIN +
tap). Android S23 pass 2a green (SAF folder, `read_tree_file`, 13 added) but
found the inset regression; the fix is NOT yet device-verified.

Next, in order (write ONE pass at a time into `.scratchpad`, one action per
row, rebuild first: `(cd android && ./gradlew --stop) && flutter build apk
--split-per-abi --release`):
1. S23, 3-button nav: fresh install, pass 2a again; row 10 must show the
   snackbar and the last entry above the buttons.
2. S23, gesture nav (Settings > Display > Navigation bar): same pass.
3. S23 pass 2b: missing file (`adb shell mv`), untick Remember -> picker.
4. Linux pass 1c again to re-make `keyed.gabbro` (do NOT clean up), `adb push`
   it, S23 pass 2c: receiving vault `keyed`, NFC only, both keys.
5. Lenovo tablet (TB373FU): inset pass, portrait then landscape.
6. Full gate `./gabbro_test`; then docs (README check, VAULT_SYNC done), merge.
Then Bikeshed steps 2 and 3.

**In progress: edge-to-edge insets** (found by the Android pass 2a, 2026-08-25;
latent on master, exposed by targetSdk 36 = Flutter 3.47.x default, enforced on
Android 15+). Consequence: on the S23 the bottom of the vault list and the
sync snackbar sit under the navigation buttons.

Wiring (Flutter `scaffold.dart:3032`, `:3104`, `:3220`): the nav-bar inset
reaches a Scaffold's body and snackbar only as `MediaQuery.padding.bottom`,
and a Scaffold strips it whenever `bottomNavigationBar != null`; `minInsets`
is keyboard-only. Offenders, verified in code:
- Vault list, phone: the passkey-banner slot always holds a widget (zero-size
  when hidden, always on Android) -> body, snackbar, FAB lose the inset.
- Vault list, tablet: `TabletVaultLayout` is returned outside the `SafeArea`,
  pads with fixed `EdgeInsets`.
- Keyboard shortcuts, adopt vault, change passphrase, manage folders,
  csv mapping: no `SafeArea`, or none on the side that matters (net: adopt
  vault + manage folders fail only on a landscape side bar; manage YubiKeys
  passes); explicit `padding:` on the scroll view disables auto-inset.
- Fine as is: sheets read `padding.bottom` themselves; dialogs carry Flutter's
  own `SafeArea`; unlock/save/consent/all other screens have `SafeArea`;
  manage folders and recovery history use un-padded lists (auto-inset).

Cases: 3-button nav (~48dp bottom), gesture nav (~20dp bottom), landscape
(inset on a side), tablet two-pane, no inset (Linux). Must not regress: scroll
to the last entry, FAB tap, snackbar readable, Linux passkey banner visible and
announced, alphabet bar full height, search with keyboard, tablet divider drag.

- [x] Net: `test/inset_net_test.dart`, every catalogued screen x {phone,
      tablet} x {portrait, landscape} x {none, gesture 20, buttons 48, side 48
      (landscape only)}; scrolls each list to its end, then no text, icon,
      FAB or snackbar in the band. Green at inset 0 on today's code;
- [x] Red (same file, 25 cases): vault list phone + tablet + wide, tablet layout,
      keyboard shortcuts, change passphrase (3-button, landscape), adopt vault,
      manage folders, csv mapping (side bar). Vault-list snackbar, FAB,
      banner rows
- [x] Fix: slot null when the banner is hidden; tablet branch inside the
      SafeArea; SafeArea on the four screens
- [ ] Hardware: S23 3-button, S23 gesture, Lenovo tablet portrait + landscape

Progress (tick as each Bikeshed section lands):
- [x] Net (S8), both platforms
- [x] Labels (S2)
- [x] Import additive, no dedupe (S3)
- [x] Sync settings screen: auto-merge + sync folder + Remember (S5, S6.1)
- [x] Sync from vault by name match, picker fallback, auto-merge wiring (S6, S7)
- [ ] Import screen: one picker (Bikeshed step 2)
- [ ] Remember folders on export/import + read-only view in Sync settings (S9, S5)
- [x] On-screen explanations checked against S1-S9 (S10)
- [ ] Docs: README, VAULT_SYNC.md, CHANGELOG
- [ ] Hardware: Linux green (1a-1e); Android 2a green, inset fix unverified; 2b, 2c, tablet pending (see Handover)

---

## Build & Release

Build environment (Android/Kotlin/Java, SAF export) and full release process:
[BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md).

---

## Bikeshed / Backlog

**Procedure:** items sit here until work begins. When picked up, move the item to Current Focus and delete it from here. When done, delete it entirely — the git log is the record.

### Features and UI/UX
#### Sync family — do in this order

Spec: Current Focus > **One-click sync** (S1–S9). Promote one section at a
time; each ends with a hardware pass per platform and its ticks in the spec.

**Step 2 — import screen: one picker, not six.** Today six stacked sections each
carry their own path field; the user needs one. Replace with a single path
selector + **Remember** checkbox (one folder for all types) and a type dropdown —
Gabbro (default), Generic CSV, Google Password Manager, Dashlane, Enpass,
Bitwarden. Per-type explanation text stays; so do the top warning banner and the
size-limit note. Changing the type clears the path: extensions differ
(`.gabbro`/`.csv`/`.json`), so a stale path would arm the button on a file that
cannot parse. Gabbro selected also reveals the passphrase field and, for a
key-protected source, the PIN + Android transport sub-form. Action button label
follows the type: *Import* / *Next: map columns* / *Import*.
A rewrite of a 1000-line screen with six independent error/loading/format-check
flows.

**Step 3 — remember folders (S9) + read-only view (S5).** Export and import
folders, Linux and Android, user-selected, no built-in value. Reuse the Android
export mechanism. Then add both to Sync settings read-only with the note.

**Why step 2 before step 3:** the import screen has 3 PathField code sites
(`_gabbroSection`, `_csvSection`, the shared `_importSection`) rendered six
times. Wiring Remember first would build and test 3 sites, then delete 2 in the
remold and re-pin the tests.

- **In-app help carousel.** This will need verifying and perhaps updating as
  it's not been touched for several releases.
- **Emergency sheet.** Printable one-pager in `docs/` (vault location, YubiKey
  serials, hand-written passphrase blank, storage advice), linked from README.
  Paper only — no code.
- **Final launcher logo (logo-blocked).** `render_icons.sh` renders a placeholder
  SVG. When the real logo lands, replace `assets/images/source/ic_launcher_light.svg`
  and re-run it; same render covers the Windows `.ico` (still the stock Flutter template).

### Housekeeping
- **Reproducible builds.** Third parties rebuild from source and get
  bit-identical artifacts, proving the binaries match the code (stronger than
  the current sign-what-I-built). Hard with Flutter/Rust toolchains; scope
  first.
- **Shorten comments and user-facing messages.** Sweep the whole stack: code
  comments trimmed to what the code can't say; UI strings terse.
- **Permanent USB product id (Linux passkeys).** 0x1209:0x0001 is pid.codes'
  shared TEST id; another dev gadget with it could confuse the YubiKey filter.
  PR requesting 0x1209:0x6ABB awaits external review (volunteer-run, can take
  months; not release-blocking): https://github.com/pidcodes/pidcodes.github.com/pull/1265
  On grant: TDD the constants in `rust/src/uhid.rs`, hardware-verify on Linux.
- **Delete `purgeLegacyRecentApps` at v1.0** (`MainActivity.kt` + `LegacyPurgeTest.kt`) — the one-shot cleanup of the removed suggestion-chip store. No pre-1.0 install will still be upgrading by then.

### Security (pre-v1)
- **Human expert cryptography review** of `rust/src/crypto/` (academic outreach, RustCrypto maintainers, or formal audit) — **welcome, not blocking** (F-03, the one open design question, is addressed at VERSION 8; this is now defence-in-depth, not a release gate).

### V2+ / Defer
- **Wayland auto-type** — blocked: Wayland breaks global input injection
  (https://gist.github.com/probonopd/9feb7c20257af5dd915e3a9f2d1f2277).
  Revisit only if Mint defaults to Wayland.
- **Linux biometric unlock** (laptop fingerprint readers, e.g. libfido2/PAM or `fprintd`). Fits the current per-device model unchanged: Linux would just get its own local per-vault secret store; the vault file carries no biometric state, so nothing else changes.
- **Windows support.**
- **Yubico partnership.**
- **Donation/sustainability model**: GitHub Sponsors is live; Monero possible later (a large, dedicated effort). Liberapay ruled out (2026-07-22 — Stripe forces business-type onboarding for individuals and has suspended Liberapay-linked accounts; no PayPal). Don't re-propose Liberapay.
- **Support model** (GitHub Issues + SUPPORT.md for v1; revisit when user base exists).