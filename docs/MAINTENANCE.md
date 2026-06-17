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
