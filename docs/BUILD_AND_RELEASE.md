# Build & Release

Build-environment notes and the release recipe. Architecture lives in
[ARCHITECTURE.md](ARCHITECTURE.md); user-facing install steps live in the README
under **Installation**.

---

## Build Environment

**Critical notes: read before Android or Kotlin sessions.**

- System Java is 26.0.1, incompatible with the Kotlin compiler. Fix: `org.gradle.java.home=/opt/android-studio/jbr` in `android/gradle.properties` (Java 25.0.2 since the 2026-08 android-studio update). Gradle wrapper is 9.3.1: 9.1.0 is the floor for running on Java 25, 9.3.1 is the Flutter SDK's max validated (still 9.3.1 at Flutter 3.47.0; check `maxKnownAndSupportedGradleVersion` in the SDK's `gradle_utils.dart` after an SDK bump).
- Gradle 9 accommodations (nets: `test/android_build_config_test.dart`): cargokit's vendored `plugin.gradle` uses injected `ExecOperations` (`Project.exec` was removed, so re-patch after any flutter_rust_bridge template refresh), and `app/build.gradle.kts` pins Kotlin to JVM 21 to match `compileOptions` (unpinned, Kotlin follows the running JDK and the mismatch is a hard error).
- AGP 8.11.1 in `android/settings.gradle.kts`. Java and Kotlin JVM target both set to 21 in `app/build.gradle.kts`.
- `libfido2-sys` and `pub mod fido` are gated behind `cfg(not(target_os = "android"))`: libfido2 is Linux-only; Android uses yubikit-android via Kotlin.
- yubikit-android 3.1.0: use `Ctap2Session` (raw CTAP2) not `Ctap2Client` (WebAuthn wrapper). `Ctap2Client` enforces WebAuthn domain validation, rejecting `"app.gabbro.gabbro"` as RP ID. `Ctap2Session` has no such restriction.
- `Ctap2Session` has no unified `YubiKeyConnection` constructor, so use the `ctap2Session()` private helper in `YubiKeyManager` which dispatches on `SmartCardConnection` (NFC) vs `FidoConnection` (USB HID).
- USB transport: `UsbFidoConnection` (HID interface). NFC transport: `SmartCardConnection` (ISO 7816). Both produce a `YubiKeyConnection` usable with `ctap2Session()`.
- RP ID `"app.gabbro.gabbro"` is correct at CTAP2 level: it is just an identifier string, no domain required.
- Export to shared storage uses SAF, not raw paths: the `app.gabbro.gabbro/export` MethodChannel (`MainActivity.kt`, `androidx.documentfile` dep) writes `.gabbro` files into a user-granted directory tree (`ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`). Raw `fs::rename` can't overwrite another app's file under scoped storage (EPERM). No `MANAGE_EXTERNAL_STORAGE`. See ADR-013.

---

## Release Process

**Tag format:** `v0.1.0-alpha.N` until the pre-v1 security gates (Bikeshed) clear.
Artifacts go on the GitHub Releases page.

**Releases are immutable:** once published, the tag and assets are locked: any fix
means a new `alpha.N+1`. So every **Verify** block below must pass, and the tag goes
last, after the artifacts verify.

**Every command below runs from `gabbro/` unless stated otherwise, once each, top to
bottom, in one shell (`ver` and `deb` carry through).**

**Pre-flight:**

1. Move the `[Unreleased]` block in `CHANGELOG.md` to `[0.1.0-alpha.N] - YYYY-MM-DD`, leaving `[Unreleased]` empty.
2. Bump `version` in `pubspec.yaml` to match.
3. Set `ver`. It reads the `pubspec.yaml` just bumped; if the echo is wrong, fix step 2:

   ```bash
   ver=$(sed -n 's/^version: *//p' pubspec.yaml | cut -d+ -f1) && echo "$ver"
   ```

4. Run the full gate green. It covers every suite; nothing else needs running by hand. Use `--warm` if any dependency changed since the last run:

   ```bash
   ./gabbro_test
   ```

   - New vault format VERSION this release? Generate and commit its fixtures first (recipe: `rust/tests/fixtures/FIXTURES.md`).
   - Fuzzer failure? Reproduce from the printed seed + op log, minimise, add the sequence to `vault_backward_compat.rs`. Widen with `GABBRO_FUZZ_CASES=64`.
   - Ignored Rust + Kotlin tests are hardware-only (YubiKey, biometric, AndroidKeyStore).

5. Record the build toolchain (output order: Flutter, Rust, AGP, Kotlin, Java; no NDK: `ndkVersion = flutter.ndkVersion`, so the Flutter version determines it):

   ```bash
   flutter --version | head -1 && rustc --version && grep -oP '(com\.android\.application|org\.jetbrains\.kotlin\.android)"\) version "\K[^"]+' android/settings.gradle.kts && grep -oP 'VERSION_\K[0-9]+' android/app/build.gradle.kts | head -1
   ```

   Add as an italic footer at the end of the version's CHANGELOG block:

   *Built with Flutter 3.47.0, Rust 1.94.0, AGP 8.11.1, Kotlin 2.2.20, Java 21.*

6. Commit and push the version + CHANGELOG bump.

**Build:**

Both release builds inject the About-screen version via `--dart-define=APP_VERSION="$ver"`.

### Linux

`RUSTFLAGS` keeps the build host's `$HOME` out of the binaries' embedded paths; keep it
on every release build:

```bash
RUSTFLAGS="--remap-path-prefix=$HOME=~" flutter build linux --release --dart-define=APP_VERSION="$ver"
```

Add the auto-type trigger client to the bundle (links only libc/libgcc, no new runtime
dependency):

```bash
(cd rust && cargo build --release --bin gabbro-autotype) && cp rust/target/release/gabbro-autotype build/linux/x64/release/bundle/
```

Render the icon tree beside the bundle (placeholder SVG until the logo lands):

```bash
bash linux/packaging/render_icons.sh build/linux/x64/release/icons/hicolor
```

Package bundle + icons, then sign (asks for the key passphrase):

```bash
tar -czf "gabbro-$ver-linux-x86_64.tar.gz" -C build/linux/x64/release bundle icons && gpg --detach-sign --armor "gabbro-$ver-linux-x86_64.tar.gz"
```

**Verify** the autotype binary is in, the signature is good, and the binary carries the
right version:

```bash
tar -tzf "gabbro-$ver-linux-x86_64.tar.gz" | grep gabbro-autotype && gpg --verify "gabbro-$ver-linux-x86_64.tar.gz.asc" "gabbro-$ver-linux-x86_64.tar.gz" && strings build/linux/x64/release/bundle/lib/libapp.so | grep -m1 -oF "$ver"
```

Expect `bundle/gabbro-autotype`, `Good signature from "Gabbro Releases"` on key
`369B E2CE CFD0 A528 7155 895A 4775 4EEE 7F9A ABFC`, and the version echoed back.

The Arch-built bundle runs on Debian trixie / Mint (glibc <= 2.34, verified). Build in a
`debian:trixie` container only if a future release raises that above 2.41.

### Debian `.deb` + APT index

One `debian:trixie` container run (Arch has no `dpkg-deb` or `apt-ftparchive`)
repackages the signed tarball into a `.deb` (no compile) and regenerates the APT
index in `../gabbro-apt/`. Optional `.deb` validation: add `apt-get install -y lintian`
+ `lintian ./*.deb` + `apt-get install -y ./*.deb` inside the container.
Container installs cannot prove the uhid udev rule activates (no udev, shared
kernel; verified to that limit 2026-08-22) — after a release, confirm on one
real Debian/Mint install that passkeys work without manual setup.

The APT clone is a sibling of `gabbro/`, at `../gabbro-apt/` (GitHub Pages serves it at
https://gabbro-foss.github.io/gabbro-apt). apt accepts its ed25519 signing key (verified
2026-08-19 on trixie apt 3.0.3 and ubuntu:24.04 apt 2.8.3, Mint 22's base). State after
a release; `pool/` holds only the current `.deb` (Pages caps a site at 1 GB), older
versions stay on the Releases page:

```
../gabbro-apt/
├── README.md
├── gabbro-archive-keyring.gpg
├── pool/gabbro_<debver>_amd64.deb
└── dists/stable/{InRelease,Release,Release.gpg,main/binary-amd64/{Packages,Packages.gz}}
```

`~` in the Debian version sorts the pre-release before the final `0.1.0`. The `chown`
keeps the outputs editable by the next release:

```bash
deb="gabbro_${ver/-/\~}-1_amd64.deb" && rm -f ../gabbro-apt/pool/*.deb && docker run --rm -e DEBIAN_FRONTEND=noninteractive -e ver="$ver" -e deb="$deb" -e OWNER="$(id -u):$(id -g)" -v "$PWD":/work -v "$PWD/../gabbro-apt":/repo -w /work debian:trixie bash -euc 'bash linux/packaging/deb/build-deb.sh --version "$ver" --tarball "gabbro-$ver-linux-x86_64.tar.gz" --out /work && cp "$deb" /repo/pool/ && apt-get update -qq && apt-get install -y -qq apt-utils >/dev/null && cd /repo && apt-ftparchive packages pool > dists/stable/main/binary-amd64/Packages && gzip -9kf dists/stable/main/binary-amd64/Packages && apt-ftparchive -o APT::FTPArchive::Release::Origin=Gabbro -o APT::FTPArchive::Release::Suite=stable -o APT::FTPArchive::Release::Codename=stable -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main release dists/stable > /tmp/Release && cp /tmp/Release dists/stable/Release && chown -R "$OWNER" /repo "/work/$deb"'
```

Sign the `.deb` and the index on the host, since the container has no key. `apt` reads
`InRelease`; `Release.gpg` covers older clients:

```bash
gpg --detach-sign --armor "$deb" && (cd ../gabbro-apt/dists/stable && rm -f InRelease Release.gpg && gpg --clearsign -o InRelease Release && gpg --detach-sign --armor -o Release.gpg Release)
```

**Verify** both signatures and that the index advertises the version just built:

```bash
gpg --verify "$deb.asc" "$deb" && gpg --verify ../gabbro-apt/dists/stable/InRelease && grep -E '^(Package|Version):' ../gabbro-apt/dists/stable/main/binary-amd64/Packages
```

**Verify** end to end on Mint's base: the one check that proves a user's machine will
accept the repo:

```bash
docker run --rm -v "$PWD/../gabbro-apt":/repo ubuntu:24.04 bash -euc 'apt-get update -qq >/dev/null && apt-get install -y -qq gnupg >/dev/null && install -d /etc/apt/keyrings && cp /repo/gabbro-archive-keyring.gpg /etc/apt/keyrings/gabbro.gpg && printf "Types: deb\nURIs: file:///repo\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/gabbro.gpg\n" > /etc/apt/sources.list.d/gabbro.sources && apt-get update && apt-cache policy gabbro'
```

Expect no signature warning and `Candidate:` matching the release. The `../gabbro-apt/`
push happens in **APT publish** below, after the GitHub release.

### Android

cargokit reads `CARGO_ENCODED_RUSTFLAGS` (not `RUSTFLAGS`) and the Gradle daemon caches
its environment, so stop it first:

```bash
(cd android && ./gradlew --stop) && CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=$HOME=~" flutter build apk --split-per-abi --release --dart-define=APP_VERSION="$ver"
```

Per-ABI APKs land in `build/app/outputs/flutter-apk/`: `arm64-v8a` (modern phones),
`armeabi-v7a` (old 32-bit phones), `x86_64` (emulators / Chromebooks). Rename into the
repo root:

```bash
for a in arm64-v8a armeabi-v7a x86_64; do cp "build/app/outputs/flutter-apk/app-$a-release.apk" "gabbro-$ver-android-$a.apk"; done
```

**Verify** the embedded version in each APK:

```bash
for a in arm64-v8a armeabi-v7a x86_64; do echo -n "$a: "; unzip -p "gabbro-$ver-android-$a.apk" "lib/$a/libapp.so" | strings | grep -m1 -oF "$ver"; done
```

**Verify** the signing certificate with `apksigner` (`keytool` cannot read a v2/v3-only
signature and wrongly reports `Not a signed jar file`):

```bash
APKSIGNER=$(ls -d "$HOME"/Android/Sdk/build-tools/*/apksigner | sort -V | tail -1) && for a in arm64-v8a armeabi-v7a x86_64; do echo -n "$a: "; "$APKSIGNER" verify --print-certs "gabbro-$ver-android-$a.apk" 2>/dev/null | grep 'SHA-256 digest'; done
```

All three must print the same digest, matching the fingerprint in README. The keystore
(`android/app/gabbro-upload.jks`) and `android/key.properties` are configured and
gitignored.

**Dependency lock**: only if any Android dependency changed (plugin or Flutter bump
included); a stale lock fails the release build by design:

```bash
(cd android && ./gradlew :app:dependencies --write-locks --configuration releaseRuntimeClasspath) && osv-scanner scan --lockfile android/app/gradle.lockfile
```

### Smoke test

Run the freshly built bundle, never an installed copy from a prior release still on
your PATH:

```bash
./build/linux/x64/release/bundle/gabbro
```

Unlock a vault, open an entry, confirm the About screen shows the new version.

### Tag

Only after every **Verify** block and the smoke test above pass (releases are
immutable):

```bash
git tag -a "v$ver" -m "v$ver" && git push origin "v$ver"
```

### Publish

Manual, since there is no `gh` CLI on the build box. On github.com:

1. Repo -> **Releases** -> **Draft a new release**. If a stale draft exists for this version, delete it first.
2. **Choose the existing tag** `v0.1.0-alpha.N`. Do not create a new one.
3. Title **Gabbro v0.1.0-alpha.N**; tick **Set as a pre-release**.
4. Attach 7 files from the repo root: the `.tar.gz` and its `.asc`, the `.deb` and its `.asc`, and the three renamed `.apk` files.
5. Body: the alpha disclaimer **first**, then this version's changelog section with its toolchain footer. The disclaimer, verbatim:

   > Alpha release: the cryptographic implementation `rust/src/crypto` has not yet
   > undergone external review. It is provided as-is, without warranty, as stated in the
   > GPL-3.0.

GitHub rewrites `~` in asset names (the `.deb` shows as
`gabbro_0.1.0.alpha.N-1_amd64.deb`). Cosmetic only: `apt` reads the version from the
control file, and the signature covers content, not the filename.

### AUR (`gabbro-bin`)

The clone is a sibling of `gabbro/`, at `../gabbro-bin-aur/`, holding exactly
`PKGBUILD` + `gabbro-bin.install` + `.SRCINFO` before and after this procedure (in between, `makepkg` adds
`LICENSE`, the downloaded tarball and `src/`; step 5 removes them).

1. Print the tarball hash. Run from `gabbro/`:

   ```bash
   sha256sum "gabbro-$ver-linux-x86_64.tar.gz"
   ```

2. Edit `linux/packaging/aur/PKGBUILD`: set `pkgver` to the underscore form (e.g. `0.1.0_alpha.21`) and the **first** `sha256sums` entry to that hash (the second is LICENSE, changes only if LICENSE did). Commit and push it in `gabbro/`.
3. Copy it across with the install hooks and check the published asset against the pinned sha; both source lines must say `Passed`. Run from `gabbro/`:

   ```bash
   cp linux/packaging/aur/PKGBUILD linux/packaging/aur/gabbro-bin.install ../gabbro-bin-aur/ && (cd ../gabbro-bin-aur && makepkg --verifysource)
   ```

4. Regenerate `.SRCINFO` (generated, lives only in the clone) and push to the AUR:

   ```bash
   cd ../gabbro-bin-aur && makepkg --printsrcinfo > .SRCINFO && git add PKGBUILD gabbro-bin.install .SRCINFO && git commit -m "Update to $ver" && git push
   ```

5. Clean up, restoring the clone state: `ls -a` must show only `.`, `..`, `.git`, `PKGBUILD`, `gabbro-bin.install`, `.SRCINFO`:

   ```bash
   rm -f LICENSE gabbro-*-linux-x86_64.tar.gz && rm -rf src && ls -a
   ```

**Gotchas:** pushes are SSH-only and master-branch-only. A maintenance banner over SSH
is their outage, not a key problem; retry later. The RPC / `yay` index lags a few
minutes after a push:

```bash
curl -sS 'https://aur.archlinux.org/rpc/v5/info?arg[]=gabbro-bin' | grep -oE '"Version":[^,}]*'
```

### APT publish (`gabbro-apt`)

The index was built, signed and verified in the `.deb` step; publishing is one push.
Pages serves it a minute or so later, and users get the release via `apt upgrade` /
Mint's Update Manager (setup: README **Installation**):

```bash
(cd ../gabbro-apt && git add -A && git commit -m "Publish $ver" && git push)
```
