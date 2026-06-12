# Build & Release

Build-environment notes and the release process for Gabbro. Extracted from
`ARCHITECTURE.md` to keep that document focused on architecture; this is the
operational reference for building and shipping.

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

## Running under a Wayland/bubblewrap sandbox

Gabbro is a normal GTK/Flutter Linux app. Launched directly it just works. The
notes below are only for testers who run it inside a hand-rolled `bwrap`
(bubblewrap) sandbox, which isolates the app from the session's display and bus
sockets — two things the app needs.

**1. The Wayland display socket.** GTK needs `$WAYLAND_DISPLAY` and the matching
socket. A sandbox that doesn't forward them aborts before any Dart runs (no
window appears). Forward the runtime dir's wayland socket and set the variable,
e.g.:

```
bwrap … \
  --ro-bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" \
  --setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY" \
  …
```

(`$WAYLAND_DISPLAY` is usually `wayland-0`. A tester who bound the socket to a
different path used an absolute `--setenv WAYLAND_DISPLAY "/tmp/wayland-0"` — the
value must match wherever the socket actually lives inside the sandbox.)

**2. The DBus session bus + the desktop portal.** Native file dialogs (open,
save, choose-folder — anywhere the app picks a path) go through the XDG Desktop
Portal over the **DBus session bus**. If the bus socket isn't bound into the
sandbox, `org.freedesktop.portal.FileChooser` can't be reached and the dialog
fails. Bind the bus (and run the portal) into the sandbox:

```
bwrap … \
  --ro-bind "$XDG_RUNTIME_DIR/bus" "$XDG_RUNTIME_DIR/bus" \
  --setenv DBUS_SESSION_BUS_ADDRESS "$DBUS_SESSION_BUS_ADDRESS" \
  …
```

(`xdg-desktop-portal` and a backend such as `xdg-desktop-portal-gtk`/`-kde`/
`-hyprland` must be running for the session.)

**Defensive fallback in the app.** If the portal still can't be reached, Gabbro
no longer crashes: every file-picker call is wrapped (`lib/safe_file_picker.dart`)
and surfaces a SnackBar instead. Where a flow has an editable path field (vault
export, onboarding, file-export), the message invites the user to type or paste
the path; picker-only flows (restore-from-file, attach-file, sync-from-file)
state that the system file portal is unreachable. So a missing portal degrades to
"type the path" rather than a dead button — but binding the bus as above is the
real fix.

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
   - The ignored Rust + Kotlin tests are hardware-only (YubiKey /
     biometric / AndroidKeyStore) and cannot run without the devices.
4. Commit, then `git tag -a v0.1.0-alpha.N -m "v0.1.0-alpha.N" && git push origin v0.1.0-alpha.N`.

**Build:**
- **Linux:** `flutter build linux --release` → self-contained bundle in `build/linux/x64/release/bundle/`; package with `tar -czf gabbro-<ver>-linux-x86_64.tar.gz -C build/linux/x64/release bundle`. (The Arch-built bundle runs on Debian trixie / Mint — glibc ≤ 2.34, verified; only build in a `debian:trixie` container if a future release raises that above 2.41.)
- **Android:** `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`; rename to `gabbro-<ver>-android.apk`. The signing keystore (`android/app/gabbro-upload.jks`) and `android/key.properties` are already configured and gitignored.

**Publish (manual — no `gh` CLI on the build box):** after the tag is pushed, create
the release by hand on github.com:

1. Repo → **Releases** → **Draft a new release**.
2. **Choose the existing tag** `v0.1.0-alpha.N` (do not create a new one).
3. Title **Gabbro v0.1.0-alpha.N**; tick **Set as a pre-release**.
4. Attach both artifacts: the Linux `.tar.gz` and the renamed `.apk`.
5. Body: the changelog section for this version, plus the disclaimer: *"Alpha — for
   invited testers only. The cryptographic implementation has not undergone external
   review. Do not store passwords you cannot afford to lose."*

If a stale draft release already exists for this version, delete it first and create
the release fresh from the tag.
