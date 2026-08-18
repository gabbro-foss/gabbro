# Build & Release

Build-environment notes and the release process for Gabbro. Extracted from
`ARCHITECTURE.md` to keep that document focused on architecture; this is the
operational reference for building and shipping.

---

## Build Environment

**Critical notes: read before Android or Kotlin sessions.**

- System Java is 26.0.1, incompatible with the Kotlin compiler. Fix: `org.gradle.java.home=/opt/android-studio/jbr` in `android/gradle.properties` (Java 25.0.2 since the 2026-08 android-studio update). Gradle wrapper is 9.3.1: 9.1.0 is the floor for running on Java 25, 9.3.1 is Flutter 3.44.8's max validated.
- Gradle 9 accommodations (nets: `test/android_build_config_test.dart`): cargokit's vendored `plugin.gradle` uses injected `ExecOperations` (`Project.exec` was removed, so re-patch after any flutter_rust_bridge template refresh), and `app/build.gradle.kts` pins Kotlin to JVM 21 to match `compileOptions` (unpinned, Kotlin follows the running JDK and the mismatch is a hard error).
- AGP 8.11.1 in `android/settings.gradle.kts`. Java and Kotlin JVM target both set to 21 in `app/build.gradle.kts`.
- `libfido2-sys` and `pub mod fido` are gated behind `cfg(not(target_os = "android"))`: libfido2 is Linux-only; Android uses yubikit-android via Kotlin.
- yubikit-android 3.1.0: use `Ctap2Session` (raw CTAP2) not `Ctap2Client` (WebAuthn wrapper). `Ctap2Client` enforces WebAuthn domain validation, rejecting `"app.gabbro.gabbro"` as RP ID. `Ctap2Session` has no such restriction.
- `Ctap2Session` has no unified `YubiKeyConnection` constructor, so use the `ctap2Session()` private helper in `YubiKeyManager` which dispatches on `SmartCardConnection` (NFC) vs `FidoConnection` (USB HID).
- USB transport: `UsbFidoConnection` (HID interface). NFC transport: `SmartCardConnection` (ISO 7816). Both produce a `YubiKeyConnection` usable with `ctap2Session()`.
- RP ID `"app.gabbro.gabbro"` is correct at CTAP2 level: it is just an identifier string, no domain required.
- Export to shared storage uses SAF, not raw paths: the `app.gabbro.gabbro/export` MethodChannel (`MainActivity.kt`, `androidx.documentfile` dep) writes `.gabbro` files into a user-granted directory tree (`ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`). Raw `fs::rename` can't overwrite another app's file under scoped storage (EPERM). No `MANAGE_EXTERNAL_STORAGE`. See ADR-013.

---

## Runtime dependencies (Linux)

The release bundle is self-contained except for a few **system shared libraries** it
links at runtime. A full desktop install has these already; a *minimal* install
(noticed on a second Arch box where `libfido2` was missing) does not. `libfido2-sys`
is built without the `vendored` feature, so it dynamically links the system
`libfido2` (and its chain: `libcbor`, `openssl`, `libudev`; `pcsclite` + a running
`pcscd` for NFC). The Flutter GTK runner needs the GTK 3 stack. File dialogs need
the XDG desktop portal (see below).

- **Arch:** `pacman -S libfido2 libcbor pcsclite gtk3 xdg-desktop-portal xdg-desktop-portal-gtk`
  (openssl, glib2, systemd-libs are part of base).
- **Debian / Mint:** `apt install libfido2-1 libcbor0 libpcsclite1 libgtk-3-0 xdg-desktop-portal xdg-desktop-portal-gtk`

Bare window managers (e.g. qtile) install the portal packages but never start the
portal, so file dialogs fall back to the type-the-path path. Fix is session-side:
start the portal from session init, e.g. in `~/.xinitrc`, `/usr/lib/xdg-desktop-portal &`.
Not a Gabbro or package issue.

---

## Running under a Wayland/bubblewrap sandbox

Gabbro is a normal GTK/Flutter Linux app. Launched directly it just works. The
notes below are only for testers who run it inside a hand-rolled `bwrap`
(bubblewrap) sandbox, which isolates the app from the session's display and bus
sockets, two things the app needs.

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
different path used an absolute `--setenv WAYLAND_DISPLAY "/tmp/wayland-0"`; the
value must match wherever the socket actually lives inside the sandbox.)

**2. The DBus session bus + the desktop portal.** Native file dialogs (open,
save, choose-folder, anywhere the app picks a path) go through the XDG Desktop
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
"type the path" rather than a dead button, but binding the bus as above is the
real fix.

---

## Release Process

**Tag format:** `v0.1.0-alpha.N` until the pre-v1 security gates (Bikeshed) clear, so testers know no external crypto review has happened yet. The repo is public; testers and the Debian collaborator pull from the GitHub Releases page.

**Every command below runs from `gabbro/` unless stated otherwise, once each, top to bottom.**

**Pre-flight:**

1. Move the `[Unreleased]` block in `CHANGELOG.md` to `[0.1.0-alpha.N] - YYYY-MM-DD`, leaving `[Unreleased]` empty.
2. Bump `version` in `pubspec.yaml` to match.
3. Set `ver` for the whole release. Every command from here on uses it, so it must be set
   in each shell you open. It reads the `pubspec.yaml` just bumped, so the printed value
   is the version being released; if it is wrong, fix step 2 before going on:

   ```bash
   ver=$(sed -n 's/^version: *//p' pubspec.yaml | cut -d+ -f1) && echo "$ver"
   ```

4. Run the full gate green. It covers every suite (Flutter, real-FFI, Rust, supply chain, Android); nothing else needs running by hand:

   ```bash
   ./gabbro_test
   ```

   Use `./gabbro_test --warm` if any dependency changed since the last run: the audit legs read cached advisory DBs offline, and only `--warm` refreshes them.

   - **New vault format VERSION this release?** Generate and commit its
     `vN_passphrase.gabbro` + `vN_multikey_2keys.gabbro` fixtures first (recipe:
     `rust/tests/fixtures/FIXTURES.md`). The gate only protects versions with a fixture.
   - **Fuzzer failure?** It prints the seed + op log. Reproduce, minimise, and add the
     sequence to `vault_backward_compat.rs` as a regression test. Widen the search with
     `GABBRO_FUZZ_CASES=64`.
   - Ignored Rust + Kotlin tests are hardware-only (YubiKey, biometric, AndroidKeyStore).
5. Record the build toolchain:

   ```bash
   flutter --version | head -1 && rustc --version && grep -oP '(com\.android\.application|org\.jetbrains\.kotlin\.android)"\) version "\K[^"]+' android/settings.gradle.kts && grep -oP 'VERSION_\K[0-9]+' android/app/build.gradle.kts | head -1
   ```

   Output order: Flutter, Rust, AGP, Kotlin, Java. Add it as an italic footer at the end
   of the version's CHANGELOG block:

   *Built with Flutter 3.44.8, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

   The NDK is deliberately absent: `ndkVersion = flutter.ndkVersion`
   (`android/app/build.gradle.kts:16`), so the Flutter version determines it. Pinning it
   separately would drift.
6. Commit and push the version + CHANGELOG bump. The tag goes last, after the artifacts verify.

**Build:**

Both release builds inject the About-screen version via `--dart-define=APP_VERSION="$ver"`.
Omitting it (e.g. `flutter run` during dev) makes About show `dev`, which is harmless.

### Linux

`RUSTFLAGS` keeps the build host's `$HOME` out of the compiled binaries' embedded paths.
Keep it on every release build.

```bash
RUSTFLAGS="--remap-path-prefix=$HOME=~" flutter build linux --release --dart-define=APP_VERSION="$ver"
```

The auto-type trigger client must sit inside the bundle, or a tester installing from a
release has no binary to bind a key to (see
[AUTOTYPE_AND_AUTOFILL.md](AUTOTYPE_AND_AUTOFILL.md)). It links only libc/libgcc, so it
adds no runtime dependency.

```bash
(cd rust && cargo build --release --bin gabbro-autotype) && cp rust/target/release/gabbro-autotype build/linux/x64/release/bundle/
```

Render the icon tree beside the bundle (placeholder until the logo lands; re-run to swap
it). The tarball and the AUR/`.deb` recipes all reference it.

```bash
bash linux/packaging/render_icons.sh build/linux/x64/release/icons/hicolor
```

Package bundle + icons, then sign (asks for the key passphrase):

```bash
tar -czf "gabbro-$ver-linux-x86_64.tar.gz" -C build/linux/x64/release bundle icons && gpg --detach-sign --armor "gabbro-$ver-linux-x86_64.tar.gz"
```

**Verify** the autotype binary made it in, the signature is good, and the built binary
carries the right version:

```bash
tar -tzf "gabbro-$ver-linux-x86_64.tar.gz" | grep gabbro-autotype && gpg --verify "gabbro-$ver-linux-x86_64.tar.gz.asc" "gabbro-$ver-linux-x86_64.tar.gz" && strings build/linux/x64/release/bundle/lib/libapp.so | grep -m1 -oF "$ver"
```

Expect `bundle/gabbro-autotype`, `Good signature from "Gabbro Releases"` on key
`369B E2CE CFD0 A528 7155 895A 4775 4EEE 7F9A ABFC`, and the version echoed back. Public
key + verify steps are in README.

The Arch-built bundle runs on Debian trixie / Mint (glibc <= 2.34, verified). Only build
in a `debian:trixie` container if a future release raises that above 2.41.

### Debian `.deb`

`dpkg-deb` is not on Arch, so build it in a throwaway container from the tarball just
signed. This repackages the same bundle, no compile:

```bash
docker run --rm -v "$PWD":/work -w /work debian:trixie bash linux/packaging/deb/build-deb.sh --version "$ver" --tarball "gabbro-$ver-linux-x86_64.tar.gz" --out /work
```

Produces `gabbro_0.1.0~alpha.N-1_amd64.deb` in the repo root; `~` sorts the pre-release
before the final `0.1.0`. Sign it on the host, since the container has no key:

```bash
deb="gabbro_${ver/-/\~}-1_amd64.deb" && ls "$deb" && gpg --detach-sign --armor "$deb"
```

**Verify:**

```bash
gpg --verify "$deb.asc" "$deb"
```

Users install with `sudo apt install ./gabbro_<debver>_amd64.deb`, which puts it in `/usr`
system-wide. Runtime deps auto-resolve (trixie: `libgtk-3-0t64 libfido2-1 libcbor0.10
libpcsclite1`; recommends `xdg-desktop-portal-gtk`, suggests `pcscd`). To validate a
build, add `apt-get install -y lintian` + `lintian ./*.deb` and `apt-get install -y
./*.deb` inside the container (see the `build-deb.sh` header).

### Android

cargokit reads `CARGO_ENCODED_RUSTFLAGS` (not `RUSTFLAGS`) and runs under a Gradle daemon
that caches its environment, so stop the daemon first:

```bash
(cd android && ./gradlew --stop) && CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=$HOME=~" flutter build apk --split-per-abi --release --dart-define=APP_VERSION="$ver"
```

Three per-ABI APKs land in `build/app/outputs/flutter-apk/`: `arm64-v8a` (modern phones),
`armeabi-v7a` (old 32-bit phones), `x86_64` (emulators / Chromebooks). Splitting replaces
the ~76 MB universal APK; each file carries only its own native libs. Rename them into the
repo root:

```bash
for a in arm64-v8a armeabi-v7a x86_64; do cp "build/app/outputs/flutter-apk/app-$a-release.apk" "gabbro-$ver-android-$a.apk"; done
```

**Verify** the embedded version in each APK:

```bash
for a in arm64-v8a armeabi-v7a x86_64; do echo -n "$a: "; unzip -p "gabbro-$ver-android-$a.apk" "lib/$a/libapp.so" | strings | grep -m1 -oF "$ver"; done
```

**Verify** the signing certificate. `keytool` cannot read these (v2/v3 signature, no v1
JAR signature) and wrongly reports `Not a signed jar file`; use `apksigner` from the SDK
build-tools:

```bash
APKSIGNER=$(ls -d "$HOME"/Android/Sdk/build-tools/*/apksigner | sort -V | tail -1) && for a in arm64-v8a armeabi-v7a x86_64; do echo -n "$a: "; "$APKSIGNER" verify --print-certs "gabbro-$ver-android-$a.apk" 2>/dev/null | grep 'SHA-256 digest'; done
```

All three must print the same digest, matching the fingerprint in README. The keystore
(`android/app/gabbro-upload.jks`) and `android/key.properties` are configured and
gitignored.

**Dependency lock.** The release runtime graph is locked in `android/app/gradle.lockfile`
(osv-scannable, reproducible). After any Android dependency change (incl. a plugin or
Flutter bump), regenerate and re-scan. A stale lock fails the release build by design:

```bash
(cd android && ./gradlew :app:dependencies --write-locks --configuration releaseRuntimeClasspath) && osv-scanner scan --lockfile android/app/gradle.lockfile
```

### Tag

Last step before publishing, only after every artifact above verifies. A pushed tag forces
every clone to re-fetch, so it goes after the builds succeed.

```bash
git tag -a "v$ver" -m "v$ver" && git push origin "v$ver"
```

### Publish

Manual, since there is no `gh` CLI on the build box. On github.com:

1. Repo -> **Releases** -> **Draft a new release**.
2. **Choose the existing tag** `v0.1.0-alpha.N`. Do not create a new one.
3. Title **Gabbro v0.1.0-alpha.N**; tick **Set as a pre-release**.
4. Attach 7 files from the repo root: the `.tar.gz` and its `.asc`, the `.deb` and its
   `.asc`, and all three renamed `.apk` files.
5. Body: the alpha disclaimer **first**, then the changelog section for this version
   including its build-toolchain footer. The disclaimer, verbatim:

   > Alpha release: the cryptographic implementation `rust/src/crypto` has not yet
   > undergone external review. It is provided as-is, without warranty, as stated in the
   > GPL-3.0.

If a stale draft release exists for this version, delete it and create the release fresh
from the tag.

GitHub rewrites `~` in asset names, so the `.deb` appears as
`gabbro_0.1.0.alpha.N-1_amd64.deb`. Cosmetic only: `apt` reads the version from the
control file, and the signature covers content, not the filename.

### AUR (`gabbro-bin`)

Runs after publishing. The PKGBUILD pins the tarball's sha256, so Arch users stay on the
previous version until it is bumped.

The clone is a sibling of `gabbro/`, at `../gabbro-bin-aur/`. It holds exactly two files
before and after this procedure:

```
../gabbro-bin-aur/
├── PKGBUILD
└── .SRCINFO
```

In between, `makepkg` adds `LICENSE`, the downloaded tarball and `src/`. Step 5 deletes
all three, restoring the two-file state.

1. Print the tarball hash. Run from `gabbro/`:

   ```bash
   sha256sum "gabbro-$ver-linux-x86_64.tar.gz"
   ```

2. Edit `linux/packaging/aur/PKGBUILD`: set `pkgver` to the underscore form (e.g.
   `0.1.0_alpha.21`) and the **first** `sha256sums` entry to that hash. The second entry
   is LICENSE and changes only if LICENSE did. Commit and push it in `gabbro/`.
3. Copy it across and check the published asset. Run from `gabbro/`:

   ```bash
   cp linux/packaging/aur/PKGBUILD ../gabbro-bin-aur/PKGBUILD && (cd ../gabbro-bin-aur && makepkg --verifysource)
   ```

   `--verifysource` downloads the published tarball and checks it against the pinned sha.
   That is the proof the uploaded asset is what was built. Both source lines must say
   `Passed`.
4. Regenerate `.SRCINFO` and push to the AUR. It is generated and lives only in the clone,
   never in `gabbro/`:

   ```bash
   cd ../gabbro-bin-aur && makepkg --printsrcinfo > .SRCINFO && git add PKGBUILD .SRCINFO && git commit -m "Update to $ver" && git push
   ```

5. Clean up, restoring the two-file state:

   ```bash
   rm -f LICENSE gabbro-*-linux-x86_64.tar.gz && rm -rf src && ls -a
   ```

   `ls -a` must show only `.`, `..`, `.git`, `PKGBUILD`, `.SRCINFO`. Note `src/` is empty
   and untracked, so `git status` reads clean whether or not it is there.

**AUR gotchas.** Pushes are SSH-only and master-branch-only. A maintenance banner over SSH
while the web site still serves is their outage, not a key problem; retry later. After a
successful push the RPC and `yay` index lag a few minutes, so the old version showing here
is cache, not a failed push:

```bash
curl -sS 'https://aur.archlinux.org/rpc/v5/info?arg[]=gabbro-bin' | grep -oE '"Version":[^,}]*'
```

### Releases are immutable

GitHub immutable releases are enabled: once published, the tag and attached assets are
locked. You cannot replace an asset or move the tag, so any fix after publishing means a
new `alpha.N+1`. Run every **Verify** block above before publishing.

The build log only echoes the shell variable, never the baked value, which is why the
verify blocks read the version out of the built binaries instead. Last check before
tagging is a smoke test of the freshly-built bundle, never an installed copy still on your
PATH from a prior release:

```bash
./build/linux/x64/release/bundle/gabbro
```

Unlock a vault, open an entry, and confirm the About screen shows the new version.
