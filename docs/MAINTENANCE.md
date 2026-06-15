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
