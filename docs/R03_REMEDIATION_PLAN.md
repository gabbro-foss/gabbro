# R-03 vault safety-copy — remediation plan and session handoff

**Date:** 2026-06-11
**Branch:** `r03-vault-backup-rework` (this document lives on it)
**Master:** clean and usable at `19bf35d` — the alpha.7-ready state whose full
gate (94 min) passed on the morning of 2026-06-11. Released `v0.1.0-alpha.6` is
unaffected. **Nothing on this branch may merge to master until the complete
hardware matrix passes — Rob's call alone.**
**Written by:** Claude Fable 5, after the R-03 hardware test mostly failed.

---

## Read this first (next Claude instance)

The R-03 feature on this branch (automatic `.bak` safety copy + unlock-screen
restore flow) is **component-green and system-broken**: 769 Flutter + ~508 Rust
tests pass, and the feature failed on real hardware in three distinct ways,
one of which is unexplained and potentially masks an older, worse bug.

Process facts you must respect, learned the hard way today:

1. **Canon TDD with the list-first checkpoint.** Present the test-scenario
   list, STOP, wait for Rob's review. He materially improved the design at
   every checkpoint today and predicted failure #1 at list review — and was
   argued out of his own correct instinct.
2. **Mock-seam green is not done.** Widget tests with injected callbacks
   verified a model of the app that the device falsified within minutes. Never
   report component-green with system-level confidence. The standard for this
   branch is **real-FFI integration tests** (`flutter drive … -d linux`)
   reproducing Rob's physical steps, plus his hardware matrix.
3. **Stakes.** Rob said, verbatim: "You need to work better, or I need to stop
   all work on gabbro and delete the repo." This is not a drill. Be precise,
   be modest in claims, verify on the real app.

---

## Hardware test results (Rob, 2026-06-11, verbatim summary)

Linux (passphrase only):
1. `.bak` appears next to vault — **pass**.
2. Corrupt main → restore → **fail twice**: (a) banner did not appear while
   already sitting on the unlock screen (only after switching vaults and
   back); (b) the restored vault **did not contain the edits**.
3. Corrupt both files → **fail**: while on the unlock screen the app showed
   only "Could not unlock vault. Check your passphrase." Needed the
   vault-switch dance to see the banner; the banner then **claimed a safety
   copy was available although the `.bak` was garbage**.

Linux (passphrase + YubiKey):
1. **pass**.
2. Same re-probe failure as above. Note: the vault-switch workaround does not
   exist when `show_vault_list` is OFF — that path would strand the user.
3. **FAIL, unexplained:** steps were: create test vault (passphrase+YubiKey),
   insert an entry, edit it, lock, `ls -la` confirms files, `printf "rubbish"`
   into **both** files, unlock with YubiKey → **no error, unlocks fine to an
   EMPTY vault.**

Android: not tested — "this is still too broken".

---

## Rob's rulings (binding)

1. **Redesign the rotation semantics.** A backup behind the last safe state is
   "worse than useless, harmful to the user and to gabbro". Either fix it with
   bullet-proof tests or the whole feature is dropped (and the audit's
   credibility with it).
2. **Re-probe on unlock failure** — approved, needs rigorous testing.
3. **The restore offer must never lie.** Claiming an unusable backup is
   available is uninstall-grade UX. Probe must verify the `.bak` parses.
4. Diagnose the empty-vault mystery **first** — a normal user would call this
   "vibe-coded crap" and uninstall.

---

## Priority order for the next session

### P0 — Diagnose failure #4 (empty vault opens after garbaging both files)

Hard constraint to reason from: **garbage bytes cannot decrypt** (AES-GCM auth
tag). A successful unlock showing zero entries means a *valid* vault file was
opened. Therefore one of:

- (a) **The app's vault file is not the file Rob garbaged** — a path mismatch
  between what the app writes/reads and what `ls -la` showed (two test vaults
  with similar names/dirs from the day's testing? registry pointing
  elsewhere?). But then why empty rather than showing the inserted entry —
  unless (b) too.
- (b) **CRUD save errors are being silently swallowed in the UI** — the
  on-disk file stayed at its post-init (empty) state, entries lived only in
  the RAM session, and unlock honestly re-opened an empty-but-valid vault.
  This would ALSO re-explain failure #2's "restore did not contain the edits"
  — the edits may never have reached disk at all. **Audit every Dart call site
  of create/update/delete/save for swallowed errors.**
- (c) Stale build under test (a binary from before this branch's changes).
  Verify which bundle Rob ran.

Diagnostic harness: a new real-FFI integration test
(`integration_test/`) that scripts Rob's exact sequence — init
passphrase vault → create entry → edit entry → lock → overwrite both files
with garbage **from the test** → attempt unlock → **assert it fails**. If the
harness passes while the device failed, the difference is environmental
(a or c); instrument paths (log the canonical vault path at save/unlock).

### P1 — Redesign rotation: ".bak must equal the last safe state"

Approved design ("sync-after-verified-save"):

1. Keep rotate-before-write (protects the rotation itself against a
   mid-write crash).
2. After `atomic_write_0600` of the main file succeeds, **read back and
   parse-verify the just-written bytes** (`SealedVault::from_bytes` — cheap,
   no KDF).
3. If they parse: **sync `.bak` to the current bytes.** The backup now always
   equals the last verified save — never behind in normal operation.
4. If they do not parse: leave `.bak` at the previous good state and return a
   loud error (this is the 2026-06-08 brick class actually firing).
5. Credential-change refresh (`refresh_backup_after_credential_change`) and
   its delete-stale-on-failure semantics stay as built.

Limitation to state honestly in docs: a save that *parses but is logically
wrong* propagates into `.bak`. No single-generation scheme covers that; the
backward-compat gate + fuzzer remain the guards for that class.

### P2 — Re-probe on unlock failure (ruling 2)

`_probeVault()` runs once in `initState`. Add: on **any** unlock failure,
re-run the probe before showing the generic error; if (and only if) the probe
finds a parse failure, show the corruption banner instead of "check your
passphrase". The auth-failure invariant (tests 20a–e: wrong passphrase / wrong
PIN / wrong key / timeout / cancel never show restore) must keep passing —
the probe itself enforces it, since auth failures leave the file readable.

### P3 — The offer must verify usability (ruling 3)

Replace existence-probing with usability-probing: bridge fn (rename to
`vaultBackupUsable` or change semantics of `vault_backup_exists`) returns true
only if the `.bak` **parses** (`SealedVault::from_bytes`). Banner texts then
cannot lie. Keep the failed-restore → delete-unusable-copy flow for the case
where the `.bak` rots between probe and restore.

### P4 — Integration-test standard (the "bullet-proof" requirement)

New `flutter drive` suite (real FFI, Linux) covering at minimum:
- save → corrupt main → unlock fails with corruption banner (not passphrase
  error) → restore → unlock succeeds → **all entries including the last edit
  present** (P1 acceptance).
- corrupt both → banner without restore offer (P3) or restore-refused +
  delete flow.
- corruption introduced **while the unlock screen is already mounted** (P2
  acceptance — this is exactly what Rob did with `printf`).
Then Rob's full hardware matrix on Linux + Android (debug build + `run-as`
for the corruption steps), repeated from scratch.

---

## What is on this branch (inventory)

- `rust/src/vault/io.rs` — rotation (`rotate_backup`), refresh
  (`sync_backup_to_current`, `refresh_backup_after_credential_change`),
  restore (`restore_vault_backup`, refuses unparseable `.bak`),
  `backup_exists`, `remove_backup`; 12 new unit tests.
- `rust/src/vault/session.rs` — credential-change refresh wired into
  passphrase change + YubiKey add/remove; 4 new tests; all test teardowns
  clean `.bak`.
- `rust/src/api/vault.rs` — `delete_whole_vault` removes `.bak`; 2 tests.
- `rust/src/api/vault_bridge.rs` — `vault_backup_exists`,
  `restore_vault_backup`, `delete_vault_backup` + roundtrip test.
- `rust/tests/*` — `.bak` cleanup in harness Drop impls.
- `lib/src/rust/*` — regenerated bridge (flutter_rust_bridge_codegen 2.12.0).
- `lib/vault_registry.dart` — `deleteVaultFiles` (vault + `.bak`); wired into
  `main.dart` onDelete; 3 tests.
- `lib/screens/unlock_screen.dart` — probe + corruption banner + restore /
  delete-backup confirm flows; 4 injected seams; `StateError` from an
  uninitialized bridge maps to "cannot probe → healthy" (12 indirect widget
  tests caught that).
- `lib/screens/manage_vaults_screen.dart` — wipe dialog mentions the safety
  copy without overselling it; 1 test.
- `test/unlock_screen_test.dart` (+7), `test/manage_vaults_screen_test.dart`
  (+1), `test/vault_registry_test.dart` (+3).
- All 37 `lib/l10n/app_*.arb` — 11 new keys, translated per-locale with
  terminology matched to each file's existing vault/backup vocabulary;
  regenerated `app_localizations*.dart`.
- `CHANGELOG.md` — `[Unreleased]` R-03 Security entry (**rewrite during
  remediation: it describes behavior that failed hardware**).

Suite state on the branch: Flutter 769/769, targeted Rust subsets green in
release, clippy `--all-targets` clean, Android 43/43. **None of which proved
sufficient — see "Read this first".**
