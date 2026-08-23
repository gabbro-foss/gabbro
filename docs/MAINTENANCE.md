# Maintenance

Vendored data and pins that need **periodic refresh**. Each entry: what, where,
how to update, and how often. Re-commit after updating (never fetched at build/run).

## Public Suffix List

- **What:** eTLD+1 / registrable-domain rules backing autofill domain matching.
- **Where:** `android/app/src/main/assets/public_suffix_list.dat`
- **Source:** https://publicsuffix.org/list/public_suffix_list.dat (Mozilla; the only supported URL).
- **Refresh:**
  ```bash
  curl -fsS https://publicsuffix.org/list/public_suffix_list.dat \
    -o android/app/src/main/assets/public_suffix_list.dat
  ```
  Then run the Android unit leg (`./gradlew :app:testDebugUnitTest`) and commit.
- **Cadence:** every few releases, or when a real site is reported mis-matched.
- **Version:** tracked by the `// VERSION:` header inside the file.

## Privileged browser list (Android passkeys)

- **What:** browsers trusted to assert their own web origin for passkeys. A browser
  released or re-signed after the snapshot is refused passkeys until re-vendored.
- **Where:** `android/app/src/main/assets/passkey_privileged_browsers.json`
- **Source:** https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json (Google's reference list).
- **Refresh** (temp-file-then-move: a failed download can never truncate the shipped asset):
  ```bash
  curl -fsS https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json -o /tmp/gpm_apps.json && \
  diff <(jq -S .apps /tmp/gpm_apps.json) <(jq -S .apps android/app/src/main/assets/passkey_privileged_browsers.json) >/dev/null && echo UNCHANGED || \
  (jq --arg c "Privileged browsers trusted to assert their own web origin for passkey calls. Vendored $(date +%F) from Google's reference list (https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json), same JSON shape. A browser absent here falls back to app-identity validation and will be refused for web rp_ids." '{_comment: $c, apps: .apps}' /tmp/gpm_apps.json > /tmp/gpm_vendored.json && \
   mv /tmp/gpm_vendored.json android/app/src/main/assets/passkey_privileged_browsers.json)
  ```
  `UNCHANGED`: done. Otherwise review `git diff`, run the Android unit leg
  (`./gradlew :app:testDebugUnitTest`) and commit.
- **Cadence:** every release (BUILD_AND_RELEASE.md pre-flight inlines this same
  recipe — keep the two in sync), plus periodically if no release ships for months.
- **Version:** the vendored date in the file's `_comment`.

## Dependencies (lockfile pins)

- **What:** Dart/Flutter deps pinned by `pubspec.lock`; Rust by `Cargo.lock`. Pinned so a build
  pulls the exact reviewed versions, not whatever floats to the top of a range.
- **Update:** bump the version in `pubspec.yaml` / `Cargo.toml`, then `flutter pub get` /
  `cargo update -p <crate>` (both **online** — the deliberate exception to the offline test gate).
  Review the lockfile diff: a new *transitive* dependency is new supply-chain surface — vet it.
  Then run the full `gabbro_test` gate and commit the updated lock alongside the manifest.
- **Cadence:** on demand, or on a security advisory — never automatic. (Hence disabling the IDE's
  auto-`pub get` / auto-reload prompts: fetch deps when *you* decide to. `pub get`/`cargo` do not
  execute dependency code; the risk is *which* packages you pull, not the fetch.)
- The Android *runtime* graph has its own lock, `android/app/gradle.lockfile`; regenerating and
  osv-scanning it is part of the release process — see BUILD_AND_RELEASE.md.

## Toolchain versions

Which pins follow something and which never move on their own. Values live in the
files named — don't copy them here, they drift.

| Thing | Pinned in | Moves when |
|---|---|---|
| Dart SDK | ships inside Flutter | Flutter is updated |
| NDK, minSdk, targetSdk | `flutter.*` refs, `android/app/build.gradle.kts` | Flutter is updated |
| Gradle | `android/gradle/wrapper/gradle-wrapper.properties` | we edit it |
| AGP, Kotlin | `android/settings.gradle.kts` | we edit it |
| compileSdk, Java | `android/app/build.gradle.kts` | we edit it |
| yubikit-android | `android/app/build.gradle.kts` | we edit it |
| Rust toolchain | **nowhere** | the build box updates |

**Flutter does not carry Gradle, AGP or Kotlin.** All three were seeded from the
Flutter Android template when the project was created and then froze; a Flutter bump
leaves them untouched. To see what a current template would pick, run
`flutter create --platforms=android <throwaway-dir>` and diff its `android/`.

**flutter_rust_bridge is a three-way lockstep.** `rust/Cargo.toml` (hard `=` pin),
`pubspec.yaml`, and the `flutter_rust_bridge_codegen` binary that regenerates
`lib/src/rust/` must all be the same version. Two are in the repo; the binary is not.

**The Rust toolchain is unpinned.** `rustc` is whatever the build box happens to have,
and the version is only captured in CHANGELOG *after* a release build — so a toolchain
update can change a release with no diff in the repo to show for it.

- **Cadence:** review at release time. BUILD_AND_RELEASE.md pre-flight step 4 already
  prints every version that ends up in the release notes.
