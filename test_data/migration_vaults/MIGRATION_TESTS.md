# Hardware migration tests — old-vault corpus

A permanent corpus of one passphrase-only vault per shipped format VERSION, plus the
hardware test matrix that proves each new build still reads them. The automated
backward-compat gate (`rust/tests/fixtures/vaults/`) proves this in software; this
corpus proves it **on real devices, through real FFI, in the app** — the part the gate
can't reach.

**Per version bump:** when a new format VERSION ships, add a `vN.gabbro` here (sealed
by the code that shipped that VERSION — see the generation note at the bottom) and run
the matrix on a release build. Never delete old ones; that is the whole point.

The current matrix (below) was first run for the **v7 -> v8** transcript-binding change
(commit `968a049`): it proves a fresh v8 vault seals/opens, and that the v8 build still
reads v6/v7/v8 vaults. It tests reads via **import/sync** (open + decrypt an old file
with the current crypto = the real backward-compat risk, no installation surgery); the
in-place auto-upgrade write is just a normal v8 save, covered by creating the fresh
vaults and already proven by the 12/12 software gate.

All steps are **physical app actions and observations** — no function names. Run on a
**release build** (`flutter build linux --release` / `flutter build apk --release`).
Mark each cell **Pass / Fail / N/A**; note anything surprising.

## The corpus

Each is a genuine passphrase-only vault of that format, passphrase **`0123456789a`**,
holding one login: title **`Migration Test Login`**, user `test-user`, pw `migrate-me-2026`.

| File | Format | sha256 (first 12) |
|---|---|---|
| `v6.gabbro` | v6 (alpha.3/4 era) | `320bf719e782` |
| `v7.gabbro` | v7 (alpha.5-8) | `926d8d2401e2` |
| `v8.gabbro` | v8 (transcript-binding) | `03732cd9b1b4` |
| `v9.gabbro` | v9 (granular sync) | `947a82e7b933` |

> To test, copy the files where the file picker can reach them — any folder on Linux;
> on Android, push to **Downloads** (`adb push v7.gabbro /sdcard/Download/`). Sync only
> reads them, so the originals here are never modified.

---

## Scenarios

### S1 — Fresh passphrase-only v8 vault (the new seal/open path)
For each format you'll test, create a destination vault first:
1. **Add Vault** -> onboarding. Leave YubiKey **off** (passphrase-only is default).
2. Give it a clear alias (e.g. **`Dest-v6`**, **`Dest-v7`**, **`Dest-v8`**) and a
   passphrase; add no entries; finish.
3. **Lock**, then unlock with that passphrase.

**Expected:** each vault creates, locks and unlocks cleanly. (This is the new v8
transcript-bound seal/open running on real hardware.)

| | Linux | Android |
|---|---|---|
| Dest-v6 created + lock/unlock | p | p |
| Dest-v7 created + lock/unlock | p | p |
| Dest-v8 created + lock/unlock | p | p |

### S2 — Sync from each old-format file (backward-compat read on device)
For each format, with its destination vault unlocked:
1. Menu -> **Import entries** (the **"Import entries"** menu — *not* the separate
   "Sync from file" menu, which needs both vaults to share a passphrase).
2. Scroll to the **Gabbro vault** section; pick the matching file (`v6.gabbro`
   into Dest-v6, etc.).
3. Type the source passphrase **`0123456789a`** in the **Vault passphrase** field
   and tap **Sync from vault**.
4. Look through the destination vault's entries.

**Expected:** sync succeeds; **`Migration Test Login`** (pw `migrate-me-2026`)
appears. Proves the v8 build decrypted a v6 / v7 / v8 file through real FFI on device.

| Source | Linux | Android |
|---|---|---|
| `v6.gabbro` -> Dest-v6 | p | p |
| `v7.gabbro` -> Dest-v7 | p | p |
| `v8.gabbro` -> Dest-v8 | p | p |

### S3 — Synced entry survives lock + restart
1. After S2, **lock** Dest-v7, fully close Gabbro, relaunch.
2. Unlock Dest-v7; check entries.

**Expected:** `Migration Test Login` is still there. (The destination was re-sealed
as v8 on the sync save — confirms the v8 write is durable on disk.)

| Linux | Android |
|---|---|
| p | p |

### S4 — Wrong source passphrase is rejected
1. Unlock any destination vault; **Import entries** -> **Gabbro vault** section ->
   pick `v7.gabbro`.
2. Enter a **wrong** source passphrase; tap **Sync from vault**.

**Expected:** sync refused with a decrypt error; **no** entries added.

| Linux | Android |
|---|---|
| p | p |

### S5 — YubiKey vault is unaffected (hardening was scoped to passphrase-only)
1. Create (or open an existing) **passphrase + YubiKey** vault on the v8 build.
2. Add/confirm an entry; **lock**.
3. Unlock with passphrase **+ tap**. On Android, repeat over **USB-C and NFC**.

**Expected:** the YubiKey vault seals and unlocks exactly as before; both transports
work on Android. (We deliberately did not change the YubiKey derivation.)

| Linux | Android (USB-C) | Android (NFC) |
|---|---|---|
| p | p | p |

---

## Notes / findings

_(Record failures with the exact step, the message shown, and the platform. The
Rust/Dart layers are gate-green, so a hardware failure is most likely in the
platform tap path or the FFI/import wiring, not the crypto.)_

### 2026-06-22 — v8 run
All scenarios pass on Linux and Android (see cells above). F-03 passphrase-only
transcript-binding (VERSION 8) verified end-to-end.

### 2026-06-29 — v9 added (granular field-level sync)
`v9.gabbro` added to the corpus (crypto byte-identical to v8; the body gains per-field
change-times). Software gate green (v6–v9 open + migrate under the v9 build); v9 hardware
run not yet done.

Scope note: this matrix tests only **format backward-compat** (a v9 build reading old
files). The actual N-device granular **sync/merge** is a separate test —
`test_data/sync_test_vaults/` ships three divergent vaults, the hardware procedure, and the
automated test (`session.rs::sync_test_corpus_converges_without_loss`) that loads those same
files.

---

## Generating a new `vN.gabbro` (per version bump)

These vaults must be sealed by the code that shipped each VERSION, so a future build
can't accidentally seal them as the current format. Recipe (one-off, throwaway):

1. `git worktree add --detach /tmp/wt_vN <tag-that-shipped-vN>` (e.g. v6 = `v0.1.0-alpha.4`,
   v7 = `v0.1.0-alpha.8`, v8 = `master`).
2. In `<worktree>/rust/examples/`, add a small example that builds a one-entry
   `VaultBody` and calls `save_vault(&body, b"0123456789a", out_path)` (match that tag's
   `LoginEntry` fields — older tags lack `app_id`/`email`).
3. `cargo run --release --example <name> -- 0123456789a <repo>/test_data/migration_vaults/vN.gabbro`.
4. Verify it opens under current code, then `git worktree remove --force /tmp/wt_vN`.

Production Argon2 params (whatever that tag used) are fine — they're stored in the
header and honoured on open.
