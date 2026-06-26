# AI Security Audit — Third Pass (uncovered surfaces)

**Date:** 2026-06-25
**Auditor:** Claude Opus 4.8 (AI-assisted review)
**Scope:** The surfaces the first two passes explicitly left uncovered —
`rust/src/import/` (untrusted import parsers), `rust/src/api/` (FFI/JNI bridge),
the Kotlin/Android layer, and the Flutter/Dart leak channels. Organised by
data-flow threat category so cross-boundary leaks are traced end-to-end.
**Status:** Pre-v1 informational review. Same caveats as
[AI_SECURITY_AUDIT.md](AI_SECURITY_AUDIT.md) (F-series) and
[AI_SECURITY_AUDIT_REVIEW.md](AI_SECURITY_AUDIT_REVIEW.md) (R-series): AI severity
estimates, not a substitute for human review. Findings use the **S-** prefix.

> Method: dependency CVE scan (cargo audit + osv-scanner) + a read-only fan-out of
> four parallel auditors (one per threat category), every candidate verified against
> code (`file:line` + repro) before entering this register. Threat model is the prior
> passes' (Appendix D of the F-series) plus availability.

---

## Supply-chain (Phase 1, 2026-06-25)

- `cargo audit` (RustSec DB, 1138 advisories) over `rust/Cargo.lock`: **0 vulnerabilities,
  0 warnings** (209 crates). The four informational warnings from 2026-06-01 cleared via
  dependency bumps (`adler`→`adler2 2.0.1`, `rand 0.8.6`, `tokio 1.52.3`, `futures-util 0.3.32`).
- `osv-scanner` over `pubspec.lock` (109 pkgs) and `Cargo.lock` (cross-check): **0 issues**.
- Android/Gradle deps: ~~no lockfiles~~ **Resolved 2026-06-26** — release dependency
  locking enabled (`android/app/gradle.lockfile`, `releaseRuntimeClasspath`);
  `osv-scanner` over it: **0 issues** (72 pkgs). (The vulnerable `guava 28.1-android`
  / `junit 4.12` osv flagged are `debugRuntimeClasspath`-only dev tooling and never
  ship.) Regenerate per BUILD_AND_RELEASE.md after any dependency change.

**No supply-chain findings.**

---

## Findings register

Severity: **High** = immediate exploitable defect | **Med** = realistic exposure under the
threat model | **Low** = hardening / defence in depth | **Info** = informational.

| ID | Finding | Sev | Layer | Status |
|----|---------|-----|-------|--------|
| **S-01** | Enpass expiry parser panics on a crafted `ccExpiry` (non-char-boundary byte slice) → import DoS | Med | Rust | Fixed |
| **S-02** | No input size cap on Bitwarden/Enpass/Dashlane/Google-PM parsers (only CSV caps 10 MB) → memory-exhaustion DoS | Med | Rust (+Dart) | Fixed |
| **S-03** | Enpass base64 attachment decode unbounded (compounds S-02; also bloats the vault) | Low-Med | Rust | Fixed |
| **S-04** | Export / plaintext-JSON-export / `.sha256` writes bypass the F-09 symlink guard (`atomic_write_0600`) | Low (Med for JSON export) | Rust | Fixed |
| **S-05** | Native-app autofill identity from spoofable `windowNode.title`, not OS-attested `activityComponent` | Low | Kotlin | Fixed |
| **S-06** | Three plaintext buffers dropped without `zeroize` (autofill `getEntry` JSON, JSON-export, import raw input) | Low | Rust | Fixed |
| **S-07** | `login_summaries_json` hand-rolls JSON escaping (escapes only `"`) → a `\`/control char drops an autofill row | Info | Rust | Fixed |
| **S-08** | Zero fuzz coverage for any import parser (only `.gabbro` is fuzzed) — root-cause enabler of S-01 | Info/process | Rust | Fixed |

**Noted, not new findings:** tapjacking/overlay on the unlock screen (R-07 deferred) remains
unaddressed (Low-Med); the immutable JVM/Dart `String` password lifetime is the already-accepted
F-12 class.

---

## Finding detail

### S-01 (Med) — Enpass expiry parser panics on crafted input
**Where:** `rust/src/import/enpass.rs:407-408`. `if parts.len() == 2 && parts[1].len() == 4`
checks *byte* length, then `&parts[1][2..]` slices at byte index 2. A `ccExpiry` like `"1/2€"`
(`2€` = 4 bytes) slices mid-codepoint → `byte index 2 is not a char boundary` panic, unwinding
out of `convert_card` → `parse` → `import_from_enpass`. FRB's `catch_unwind` likely surfaces it
as a failed import rather than a process abort, but it is a no-import DoS on attacker input and a
latent panic. **Fix:** char-safe slice / validate `MM/YYYY` numerically before formatting.

### S-02 (Med) — No input size cap on four import parsers
**Where:** `bitwarden.rs:113`, `enpass.rs:96`, `dashlane.rs:38`, `google_pm.rs:36` parse a
caller-supplied `Vec<u8>`/`&str` with no length guard; only `csv.rs:36` caps (10 MB). The Flutter
side (`import_screen.dart`) also `readAsBytes()` uncapped, so a multi-GB "export" is resident
before the parser runs, then `serde_json`/CSV allocates a parsed copy on top → OOM. **Fix:** size
guard at each `parse` (match CSV's pattern); ideally a pre-read cap in Dart too.

### S-03 (Low-Med) — Unbounded Enpass attachment decode
**Where:** `rust/src/import/enpass.rs:322-337` (`BASE64.decode(&a.data)`), no decoded-size bound.
Compounds S-02; oversized attachments also persist into the vault. **Fix:** cap per-attachment and
aggregate decoded size, skip oversized (same shape as the existing corrupt-attachment skip).

### S-04 (Low; Med for JSON export) — Export writes bypass the F-09 symlink guard
**Where:** `atomic_write_0600` (`rust/src/vault/io.rs:31`) opens `<path>.tmp` with `create+truncate`
and **no** symlink/`O_NOFOLLOW` check, unlike `write_vault` which calls `check_not_symlink` first.
Reached by `export_vault` / `export_vault_preserving` (`api/vault.rs:555/603`), the `.gabbro.sha256`
sidecar (`vault.rs:616`), and the **plaintext** JSON export (`session.rs:737`). A pre-planted
`<path>.tmp` symlink in the export directory redirects the write; the JSON export (cleartext) is the
material case. **Fix:** add the symlink check / `O_NOFOLLOW`+`O_EXCL` on the temp inside
`atomic_write_0600` (single chokepoint covers all sites).

### S-05 (Low) — Native autofill identity from a spoofable window title
**Where:** `GabbroAutofillService.kt:796-801` (`ParsedStructure.from`) and `:929-935`
(`CapturedSaveRequest.from`) derive the requesting package from
`windowNode.title.substringBefore("/")`; `getActivityComponent()` (OS-attested) is never used.
Strict exact-equality matching (`nativeAppIdMatches`) plus the OS controlling the fill target reduce
credential *theft* to ordinary on-device phishing; the residual genuine risk is a **credential-existence
enumeration oracle** (a malicious app probing which packages have stored logins by watching whether a
chip appears) and possible save mis-attribution (user-confirmed in `SaveConfirmScreen`). **Fix:**
derive the native package from `structure.activityComponent?.packageName`, title as fallback only.
Needs Android hardware verification.

### S-06 (Low) — Plaintext buffers dropped without zeroize
**Where:** `session.rs:849-877` (autofill `getEntry` JSON: `password.clone()` → `serde_json::Value`
→ `String`), `session.rs:717-739` (full-vault JSON export buffer), `api/import.rs` (raw import
`String` + transient parsed entries). Same accepted class as F-04/F-11 but new, distinct hot-path
instances. On-disk JSON export is plaintext by design (0600); this is only the in-RAM residual.
**Fix:** wrap the serialized buffers in `Zeroizing`.

### S-07 (Info) — Hand-rolled JSON escaping in the autofill summary list
**Where:** `rust/src/vault/session.rs:795-811` escapes only `"`. A `\` or control char in a
non-secret summary field (`username`/`url`/`email`/`app_id`) yields JSON the Kotlin `org.json`
parser may drop — a garbled/missing autofill candidate row, no UB. (The by-UUID `get_entry_for_autofill`
already uses `serde_json` correctly.) **Fix:** build the array with `serde_json`.

### S-08 (Info/process) — No fuzz coverage for import parsers
Only `.gabbro` is fuzzed (`rust/tests/vault_parse_fuzz.rs`); the five attacker-facing import parsers
have none — which is why S-01 went unnoticed. **Fix:** a deterministic in-tree fuzz harness per
parser, mirroring the `.gabbro` parse fuzzer (offline, runnable under the gate's netns).

---

## Verified clean (checked 2026-06-25 — do not re-litigate)

| Property | Evidence |
|----------|----------|
| **Keys never cross the bridge** | Every `vault_bridge.rs` return type enumerated; no master/wrapping/private-key or KDF output returned; `merge_*_with_key`/`import_from_gabbro_with_key` discard `(_master,_wrapping)` with `_`. |
| FFI panic-safety | FRB 2.12.0 generated handler wraps calls in `catch_unwind`; raw JNI fns (`autofill_bridge.rs`) return `"{}"`/`"[]"` on malformed/locked input, no panic on a bad UUID. |
| No secret logging | Dart: zero `print`/`debugPrint`/`developer.log`. Kotlin autofill debug-dump (`Log.d`) is metadata-only and `BuildConfig.DEBUG`-gated (compiled out of release). Rust `eprintln!` only in tests / hardening-warning / attachment *name* on decode failure. |
| Error-echo sites carry no secrets | `security_screen.dart:168`, `entry_detail_screen.dart:249/381/400`, `unlock_screen.dart:375` surface file-IO/bridge errors (IDs, paths, "not a Login entry"), never a password; unlock auth failures use fixed localized strings. |
| Biometric storage | AES-GCM ciphertext of passphrase in AndroidKeyStore (`BIOMETRIC_STRONG`, `setInvalidatedByBiometricEnrollment(true)`), `MODE_PRIVATE`; passphrase `ByteArray.fill(0)` on every exit path. |
| serde_json nesting DoS | Default recursion limit (128) rejects deeply-nested malicious JSON as `Err`, no stack overflow. |
| webDomain trust | Browser-attested `node.webDomain`; no `compatibilityPackages` declared (compat screen-scraping off). |
| Intent-extra / JNI reach | `UnlockActivity`/`SaveActivity` `exported=false`, launched only via own `FLAG_IMMUTABLE` PendingIntents; `RustBridge` is an in-process object, not cross-app reachable. |
| Read-path symlink guard | `read_vault`, restore paths (`restore_vault_backup`/`_from_file`) all `check_not_symlink`; live saves use the guarded `write_vault`. |
| Prior items intact | R-02 backup exclusion, FLAG_SECURE on all unlock surfaces, exported-component posture, F-08 atomic 0600 writes — no regressions. |

---

## Remediation status

| Finding | Sev | Status |
|---------|-----|--------|
| S-01 | Med | **Fixed** — char-safe expiry (`enpass.rs`); unit + import regression tests. |
| S-02 | Med | **Fixed** — per-parser size caps (Rust) + Flutter pre-read check + on-screen limit note (l10n x37); tests. |
| S-03 | Low-Med | **Fixed** — per-attachment decoded-size cap before base64 decode (`enpass.rs`); test. |
| S-04 | Low/Med | **Fixed** — `O_NOFOLLOW` on the temp in `atomic_write_0600`; symlink-temp regression test. |
| S-05 | Low | **Fixed** — native package from OS-attested `activityComponent`, title fallback; hardware-verified on Android (native-app match + Brave web + save flow). |
| S-06 | Low | **Fixed** — `Zeroizing` on autofill-`getEntry`/JSON-export/import buffers (drop-time; verified by reasoning + `mem_forensics`). |
| S-07 | Info | **Fixed** — `serde_json` for the autofill summary list; backslash/control-char round-trip test. |
| S-08 | Info | **Fixed** — deterministic in-tree `import_parse_fuzz` over all 5 parsers (routine `cargo test`). |

_All eight closed (2026-06-25). Full gate green (Flutter 983, Rust 549, all drives, Android
unit tests); release APK builds clean; hardware matrix green on Android (autofill native-app
match + Brave web + save) and Linux (import limits + oversized rejection + export)._
