# AI Security Audit — Second-Pass Review

**Date:** 2026-06-11
**Auditor:** Claude Fable 5 (AI-assisted review of an AI-assisted review)
**Scope:** Critical assessment of `AI_SECURITY_AUDIT.md` (Claude Opus 4.7, 2026-05-31) plus targeted code verification of its claims and of surfaces it did not cover (AndroidManifest, `lib/` Flutter layer, process hardening).
**Status:** Pre-v1 informational review. Same caveats as the original: severities are AI estimates; nothing here unblocks the human-cryptographer pre-v1 gate.

> **Reading note.** This is a findings report complementing `AI_SECURITY_AUDIT.md`,
> not replacing it. Finding IDs here use the **R-** prefix to avoid collision with
> the original's **F-** series. Remediation is a separate session.

---

## Remediation status

| Finding | Sev. | Status |
|---------|------|--------|
| **R-01** original audit's "no exploitable defect" claim falsified by fuzzer; needs a correction note | Doc | **Fixed** (2026-06-14) — dated correction note + softened OWASP input-validation row in `AI_SECURITY_AUDIT.md`. |
| **R-02** Android Auto Backup silently uploads the vault to Google Drive | Medium | **Fixed** (commit `90a2095`, 2026-06-11) — `allowBackup="false"` + `dataExtractionRules` + `fullBackupContent` (all domains excluded), 3 Robolectric merged-manifest tests, APK verified via `aapt dump xmltree`; hardware-verified on device (`pkgFlags` has no `ALLOW_BACKUP`; `bmgr backupnow` → "Backup is not allowed"; upgrade-in-place, unlock, autofill unaffected) |
| **R-03** no pre-save vault backup rotation (availability gap) | Medium | **Fixed** (branch `r03-vault-backup-rework`, 2026-06-12) — automatic `.bak` safety copy (= last *verified* save) + corruption-recovery UX + restore-from-backup-file. Claude Fable 5's first pass was component-green but failed the hardware matrix; diagnosed and reworked by Claude Opus 4.8 + Rob. Linux hardware 14/14; Android emulator verified. See R-03 below. |
| **R-04** Linux process is dumpable; no `PR_SET_DUMPABLE(0)` / `RLIMIT_CORE(0)` | Low | **Fixed** (2026-06-14) — `harden_process()` in `rust/src/hardening.rs`, called from `init_app()`; unit-tested + hardware-verified on Linux (unlocked vault, `SIGSEGV` → no core dump, non-dumpable). |
| **R-05** no stated position on swap exposure of key material | Low | **Open** |
| **R-06** Dart-heap secret exposure undocumented; GUI-process forensics pending | Low | **Open** |
| **R-07** minor items: `.gabbro.sha256` wording, tapjacking, `vaults.jsonc` metadata | Info | **Open** |

---

## Verdict on the original audit

`AI_SECURITY_AUDIT.md` is a genuinely good audit — well above the typical
AI-assisted pass. Specifically:

- Real findings that were fixed and verified (F-01 AAD binding; F-11 caught by
  **dynamic** memory forensics rather than code reading).
- Honest remediation tracking and an Appendix A self-correction (the
  `thread_rng` claim) — intellectual honesty the document should keep extending
  (see R-01).
- The Proton Pass / Recurity Labs mapping — learning from someone else's
  professional audit is excellent practice.
- An explicit threat model (Appendix D), which makes its blind spots *visible*
  and criticisable — see "Structural observations" below.
- The supply-chain pass even covered IDE extensions, which most audits skip.

Verified during this review: the F-08/F-09 remediation in `rust/src/vault/io.rs`
is real and correct — temp-file + `mode(0o600)` + fsync + atomic rename
(`io.rs:28–53`), with a unit test asserting the mode.

**However**, the audit's scope is the *safest* part of the codebase (the Rust
crypto core), while the riskiest surfaces — platform/manifest configuration, the
Dart heap, import parsers, the Kotlin autofill layer — sit outside it. The
executive summary reads more complete than the scope line justifies.

---

## Structural observations

### S-1 — Scope asymmetry

The audited scope (`rust/src/crypto/`, `rust/src/vault/`) is the most carefully
written code in the repo. Unaudited surfaces, in roughly descending risk order:

- `AndroidManifest.xml` and platform configuration (→ R-02, found immediately
  on first read).
- The Flutter/Dart layer, including everywhere secrets exist in Dart (→ R-06).
- `rust/src/import/` — parsers consuming **untrusted input** (CSV, Enpass,
  Bitwarden, Dashlane, Google PM files a victim could be sent). The post-audit
  parse fuzzer now covers `.gabbro` parsing; the import parsers have no
  equivalent.
- `rust/src/api/` (bridge surface) — partially touched (F-11) but not
  systematically read.
- Kotlin: `GabbroAutofillService`, `UnlockActivity`, `RustBridge`,
  `BiometricHelper`. Only F-10 touches this layer.
- `rust/src/fido/` — explicitly deferred to ADR-010; fine, but it belongs on
  the same "unaudited" list so nobody mistakes silence for coverage.

**Recommendation:** add an explicit "Unaudited surfaces" list to the original
document so future readers (including the eventual human reviewer) don't
mistake it for full-codebase coverage.

### S-2 — Availability is missing from the threat model

Appendix D covers confidentiality and integrity but never **availability** —
yet for a password-manager user, losing the vault is the catastrophic outcome,
worse than most disclosure scenarios. This is not theoretical: an AI session
bricked the real vault on 2026-06-08 (the incident that produced the
backward-compat gate). The atomic-rename fix prevents *half-written* files, but
a bug that successfully writes garbage, disk corruption, ransomware, or
accidental deletion still destroys the only copy. See R-03.

### S-3 — The Dart heap is a memory-disclosure blind spot

The threat model puts "partial memory disclosure of an unlocked process" in
scope, and the Rust side is hardened for it (`Zeroizing` everywhere, the gcore
self-test). But every memory claim stops at the bridge, and the bridge is not
where the secrets stop:

- The **master passphrase is typed in Flutter** — an immutable, garbage-collected
  Dart `String` that cannot be zeroized and may be copied by the GC before
  collection.
- Viewed passwords (entry detail), generated passwords (generator screens), and
  the autofill JSON all exist in the Dart heap.

L-2 covers the JNI→Kotlin leg but never mentions Dart. The mem-forensics test
runs against a Rust harness binary, not the GUI process (Appendix C item 6
admits the extension is pending, but not *why it matters*): a gcore of the
running Flutter app would very likely find the passphrase and any viewed
password in the Dart heap, where `Zeroize` cannot reach. The core principle
"secrets never cross the Flutter/Rust bridge in plaintext" is aspirational
against these flows, and the audit does not reconcile that. See R-06.

---

## Findings

Severity scale as in the original: **High** = immediate exploitable defect |
**Medium** = realistic exposure under plausible threat model | **Low** =
hardening / defence in depth | **Info** = informational | **Doc** = documentation
correctness.

### R-01 (Doc) — "No exploitable defect identified" was falsified within ten days; the original audit needs a correction note

**Where:** `AI_SECURITY_AUDIT.md` Executive summary; OWASP mapping row "Input
validation" ("binary header parser bounds-checks every field").

**Detail.** On 2026-06-10 the `from_bytes` parse fuzzer found a real
crash-on-open integer overflow in `rust/src/vault/file_format.rs` — a file the
audit read line-by-line, in the exact parsing logic the OWASP row vouched for.
The fix is the `checked_add` at `file_format.rs:378`. A malicious `.gabbro`
file crashing the app on open is a denial-of-service-grade defect inside the
audited scope.

**Recommendation.** The document has a precedent for corrections (the Appendix A
note). Add one for this: a row in the remediation table recording that the
fuzzer found an in-scope parser defect the static read missed, and soften the
OWASP input-validation row. The doc's purpose is to be handed to a human
cryptographer; its track record of what static AI review *missed* is exactly
what that reviewer needs to calibrate trust.

### R-02 (Medium) — Android Auto Backup silently uploads the vault to Google Drive

**Where:** `android/app/src/main/AndroidManifest.xml` — sets neither
`android:allowBackup` (defaults to **true**) nor
`android:dataExtractionRules` / `android:fullBackupContent` (no backup-rules
XML exists in `res/xml/`).

**Detail.** The vault resolves to `getApplicationSupportDirectory()`
(`lib/app_paths.dart`) — app-private `files/`, which Android Auto Backup
includes. On any standard consumer device the encrypted vault is therefore
silently copied to the user's Google Drive, and also migrates via
device-to-device transfer.

**Why it matters even though the vault is encrypted at rest:**

- It hands a third party a copy for offline brute force of the passphrase.
- Old vault copies linger in cloud backups after local deletion.
- It flatly contradicts the zero-tracking / local-only promise the app is
  built on.

This is the adjacent issue to Proton finding 526.2501.101 (data in device
storage); the original audit walked past it because the manifest was out of
scope.

**Recommendation.** Set `android:allowBackup="false"` plus
`android:dataExtractionRules` (API 31+) and `android:fullBackupContent`
(API ≤ 30) rules files excluding every domain. These are not redundant
encodings: the OS consults them at different decision points (cloud backup vs
device-to-device transfer), and OEM migration tools do not all honour the
blanket flag — declare the intent at every layer. Because the rules exclude
*all* app-private domains, the vault, `settings.jsonc` and `vaults.jsonc`
(alias-bearing metadata) are covered in one stroke, and future app-private
files are excluded by default. **Scope boundary (Rob, 2026-06-11):** this must
not — and by mechanism cannot — affect user-driven export/backup of `.gabbro`
files via SAF to shared storage (e.g. rsync→NAS 3-2-1 flows); the backup
framework rules only govern the app-private storage root. Hardware-verify on
device (build success ≠ device success).

### R-03 (Medium) — No pre-save vault backup rotation (availability)

**Where:** `rust/src/vault/io.rs` — `write_vault` atomically replaces the only
copy of the vault.

**Detail.** See S-2. Atomic rename prevents torn writes but not
successfully-written garbage (the 2026-06-08 incident class), disk corruption,
ransomware, or accidental deletion.

**Recommendation.** Before each save, rotate the existing `.gabbro` file to a
sibling backup (`.gabbro.bak`, or N generations). Cheap; would have turned the
2026-06-08 bricking into a non-event; complements (does not duplicate) the
backward-compat gate. Decide the retention policy with Rob (single `.bak` is
probably enough; N generations costs disk for large File entries).

**Resolution (Claude Opus 4.8 + Rob, 2026-06-12; branch `r03-vault-backup-rework`).**
Claude Fable 5's first attempt was component-green but failed the hardware
matrix in several distinct ways; Claude Opus 4.8 and Rob diagnosed and reworked
it. Per issue raised during remediation:

- **Save-path rotation (the core ask).** `write_vault` rotates the previous save
  to `.bak`, writes the main file atomically, **reads it back and
  parse-verifies it**, then syncs `.bak` to the verified bytes — so the safety
  copy always equals the *last verified save*. A save whose bytes do not parse
  leaves `.bak` at the previous good state and returns a loud error: the
  2026-06-08 brick class now fails at the bad save instead of propagating.
  Single `.bak`, same disk — corruption insurance, not a backup.
- **Restore lost the latest edit (P1, hardware-found).** Fable's rotate-only
  scheme left `.bak` one save behind, so restoring after corruption dropped the
  most recent edit. The sync-after-verified-save model above fixes it (pinned by
  a real-FFI integration test reproducing the exact edit→edit→corrupt→restore
  sequence).
- **The offer could lie (P3).** `vault_backup_exists` checked only presence, so
  the unlock screen advertised a "usable safety copy" even when the `.bak` was
  itself garbage. Replaced with `vault_backup_usable`, which parse-checks it.
- **Banner only appeared after a vault-switch (P2).** The parse probe ran once
  at mount. The screen now also re-probes on any unlock failure and on app
  resume, so corruption surfaces without the switch-away-and-back dance. The
  auth-failure invariant (wrong passphrase / PIN / key never offers restore)
  still holds.
- **Dead-end / misleading UX (P5).** Unlock controls are hidden while the vault
  is unreadable. Two states: **A** (usable `.bak`) offers restore-from-safety-
  copy; **B** (no usable `.bak`) is honest that the vault is unrecoverable on
  device and offers recovery/removal. Platform-aware: desktop offers *Remove
  from list* (keeps the file) and *Delete file*; Android offers only *Delete
  file*, because app-private storage makes "remove from list" leave an
  unreachable orphan (hardware-found).
- **Tablet crash + settings-toggle spam (P6).** `tablet_vault_layout` fetched
  the selected entry synchronously during build; when the entry vanished
  (delete, or a locked/corrupt session surfaced by any app-wide rebuild such as
  toggling a security setting) it threw inside layout and spammed
  `DiagnosticsProperty<void>`. The fetch is guarded: it falls back to the empty
  state and clears the stale selection after the frame.
- **No actual recovery path (new feature, Rob-mandated).** "Restore from a
  backup file": the user picks their own off-device 3-2-1 `.gabbro`; the bridge
  validates it parses, then writes it over the corrupt vault, which then opens
  with the user's credentials. Offered in both states; refuses a non-vault file,
  leaving the corrupt vault untouched.
- **The empty-vault mystery (P0).** Fable's report of a YubiKey vault unlocking
  to an *empty* vault after both files were garbaged was diagnosed as
  **environmental** (a stale build), not a code defect: garbage cannot pass the
  AES-GCM tag and there is no auto-create on the load path. Pinned by a
  pure-Rust test (garbaged YubiKey vault never opens) and a real-FFI integration
  test (garbage → unlock fails, never empty); did not reproduce on a fresh build.

**Verification.** Rust unit + bridge tests; real-FFI integration suite (Linux);
full Flutter suite; `clippy --all-targets` clean; new UI strings across all 37
locales. **Linux hardware: 14/14.** **Android emulator: State A/B, restore-from-
file via SAF, platform button set, and delete-file (disk-confirmed).**

**Residual limitation (stated honestly).** A save that *parses but is logically
wrong* still propagates into `.bak` — no single-generation scheme covers that;
the backward-compat gate and the parser fuzzer remain the guards for that class.

### R-04 (Low) — Linux process is dumpable; core dumps capture unlocked secrets

**Where:** app startup (no `prctl` call exists anywhere in the app — only
`rust/src/bin/mem_forensics.rs` touches `prctl`, and that is to *allow* tracing
for the self-test).

**Detail.** The audit's own forensics test proves a same-user `gcore` captures
unlocked secrets — and then doesn't ask the obvious next question: why is the
production process dumpable at all? Without hardening, systemd-coredump
persists an unlocked-vault core dump to disk on any crash, and any same-user
process can ptrace-attach (subject to `yama/ptrace_scope`). KeePassXC sets
exactly this hardening.

**Recommendation.** At startup: `prctl(PR_SET_DUMPABLE, 0)` and
`setrlimit(RLIMIT_CORE, 0)`. Gate behind an env var (e.g.
`GABBRO_ALLOW_TRACE=1`) so `scripts/mem_forensics.sh` still works. A few lines;
Linux-only `cfg`.

### R-05 (Low) — No stated position on swap exposure of key material

**Where:** original audit F-04 mentions swap only in a parenthetical
("suspend-to-disk, core dump, swap, memory dump") and recommends nothing.

**Detail.** `Zeroize` does not prevent key material being paged out *before*
it is zeroized. Options in rising order of effort:

1. Document honestly in user-facing docs that encrypted swap is recommended.
2. `madvise(MADV_DONTDUMP)` on key-holding pages (pairs with R-04).
3. `mlock` the handful of 32-byte master-key allocations (e.g. via `memsec`
   or `region`), accepting `RLIMIT_MEMLOCK` constraints.

**Recommendation.** At minimum option 1 before v1; discuss 2–3 with the human
reviewer. The audit should state a position either way.

### R-06 (Low) — Dart-heap secret exposure is undocumented and unmeasured

**Where:** `lib/screens/unlock_screen.dart` (passphrase entry),
`lib/screens/onboarding_screen.dart` / `change_passphrase_screen.dart`
(passphrase creation), entry detail / generator screens (displayed passwords).

**Detail.** See S-3. There is no perfect fix — Dart strings are immutable and
GC-managed — but the honest posture is to document the residual exposure,
minimise secret lifetime in Dart, and *measure* it.

**Recommendation.**
1. Add a finding to the original audit documenting the Dart-heap residual
   exposure (mirror of L-2 for the Rust→Dart and Dart-input legs).
2. Extend `scripts/mem_forensics.sh` to the real GUI process (already listed as
   pending in Appendix C item 6 — this finding raises its priority): unlock,
   view an entry, lock, gcore, grep for canaries. Expect the passphrase to be
   present in the Dart heap; record the measured result rather than assuming.
3. Where cheap, shorten lifetimes (e.g. clear password-reveal state on
   navigation away and on auto-lock — verify this already happens).

### R-07 (Info) — Minor items

- **`.gabbro.sha256` sidecar** (`rust/src/api/vault.rs`, export path): detects
  corruption only. Anyone who can tamper with the export can rewrite the
  sidecar. Docs/UI must never present it as tamper-proofing — the AAD (F-01
  fix) does that job. Wording check, no code change.
- **Tapjacking** on the unlock screen: `filterTouchesWhenObscured` /
  Android 12+ untrusted-touch blocking. Worth one line of verification when the
  Android autofill session happens; `FLAG_SECURE` does not block overlays.
- **`vaults.jsonc`** (vault registry): reveals vault paths and aliases to any
  local reader. Metadata only; probably not worth `0600` ceremony, but note it.

---

## Verified good (checked 2026-06-11 — do not re-litigate)

| Property | Evidence |
|----------|----------|
| Clipboard auto-clear exists, 60 s default, configurable | `lib/settings.dart` (`clipboard_clear_timeout`), `entry_detail_screen.dart`, `generator_widget.dart` |
| `FLAG_SECURE` set on both activities (screenshots, recents thumbnails, casting) | `MainActivity.kt:51`, `UnlockActivity.kt:46` — original audit never mentions this; it's done |
| `UnlockActivity` not exported | `AndroidManifest.xml` (`android:exported="false"`) |
| Atomic `0600` vault writes (F-08/F-09 fix) implemented correctly with a mode-asserting test | `rust/src/vault/io.rs:28–53, 197–199` |
| Passphrase strength estimation at vault creation **and** change; change screen enforces strong tier | `onboarding_screen.dart`, `change_passphrase_screen.dart:170` |
| Obscured text fields map to Android password input type (IMEs won't learn) | Flutter `obscureText` → `TYPE_TEXT_VARIATION_PASSWORD` |
| `from_bytes` overflow already fixed | `file_format.rs:378` (`checked_add`) |

---

## Priority order (most user-safety per hour of work)

Done: **R-02** (backup manifest), **R-03** (vault safety copy + recovery), **R-04** (core-dump hardening), **R-01** (audit correction note) — see the status table.

Outstanding:
1. **R-06** — GUI-process forensics run (measure, then decide).
2. **R-05**, **R-07**, **S-1** doc updates — fold into the same docs session.

None of these need a cryptographer; all are the kind of thing the eventual
human reviewer will check first.
