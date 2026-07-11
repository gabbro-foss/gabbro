# Hardware migration tests — old-vault corpus + RT-3 migrate-on-unlock

One passphrase-only vault per shipped format VERSION. The automated gate
(`rust/tests/`) proves format backward-compat in software; this proves the
**migrate-on-unlock** behaviour (RT-3) on real devices.

## Corpus

Each vault: passphrase **`0123456789a`**, one login — title `Migration Test Login`,
user `test-user`, pw `migrate-me-2026`.

| File | Format | sha256 (first 12) |
|---|---|---|
| `v6.gabbro` | 6 | `320bf719e782` |
| `v7.gabbro` | 7 | `926d8d2401e2` |
| `v8.gabbro` | 8 | `03732cd9b1b4` |
| `v9.gabbro` | 9 | `947a82e7b933` |
| `v10.gabbro` | 10 | `dd76d02b46aa` |
| `v11.gabbro` | 11 | `3edd56cf4052` |

Add one `vN.gabbro` per version bump; never delete old ones. Regenerate (throwaway):
worktree at the tag that shipped VERSION N, add an example that builds a one-login
`VaultBody` and calls `save_vault(&body, b"0123456789a", out)`, run `--release`,
verify it opens, remove the worktree. (Current build = v11 → no worktree needed.)

---

## RT-3 test — auto-migrate v≤9 → v10 on unlock

**Ordering (safety):** migration is one-way (v≤9 → v10 on first unlock). On each
device, finish the v9 setup and confirm the `09` byte *before* installing the v10
build. Keep at least one device un-upgraded until another has migrated cleanly, so a
migration bug can't brick every device at once. Android package: `app.gabbro.gabbro`.

**Version-byte check** (`09` = v9, `0a` = v10):
- **Linux:** `xxd -s 6 -l 1 <vault-path from vaults.jsonc>` — read the file directly.
- **Android:** release APKs are not debuggable, so `run-as` / `/data/data` is out on a
  non-rooted device. In-app **Export** (byte-identical copy), then read on the host:
  ```
  adb pull /sdcard/Download/<exported>.gabbro /tmp/
  xxd -s 6 -l 1 /tmp/<exported>.gabbro
  ```

**Procedure (per device), on the v9 build:**
1. Create two vaults: **`v9_p`** (passphrase `0123456789a`) and **`v9_pyk`**
   (passphrase `0123456789a` + two YubiKeys). `v9_pyk` needs both keys registered on
   that device; a device that can only reach one key (e.g. a no-NFC tablet with a
   single USB-C key) can do `v9_p` only — mark its `v9_pyk` cells `n/a`.
2. Import `v9.gabbro` (source passphrase `0123456789a`) into **both** vaults
   (Android: `adb push v9.gabbro /sdcard/Download/` first). Make one CRUD edit in each.
3. Lock, fully close the app. Confirm both read `09` (version-byte check above).

**Then upgrade to v10** (`flutter build linux --release` / `flutter build apk --release`):
4. Open the app; unlock `v9_p` (passphrase), then `v9_pyk` (passphrase + one tap —
   whichever transport the device has: USB-C on Linux, NFC on the S23).
5. Confirm both now read `0a`.

**Pass** = both flip `09` → `0a`, all imported entries + the CRUD edit survive, and
`v9_pyk` needs only the normal single tap (no extra prompt).

| | v9_p | v9_pyk (USB-C) | v9_pyk (NFC) |
|---|---|---|---|
| Linux | pass | pass | n/a |
| S23 | pass | n/a | pass |
| Android tablet | untested | n/a | n/a |
| GrapheneOS | held v9 | held v9 | held v9 |

Legend: `n/a` = device can't run that path; `held v9` = kept un-upgraded on purpose as
the rollback fallback (see Ordering); tablet = single key only, so `v9_p` only.

## Results

**v10 (RT-3), 2026-07-08:**
- **Linux** — `v9_p` and `v9_pyk` (USB-C) both migrated `09` → `0a`; entries + CRUD
  edit intact; single tap. Pass.
- **S23** — `v9_p` and `v9_pyk` (NFC) both migrated `09` → `0a`; entries + CRUD edit
  intact; single tap. Pass.
- **Real vaults** (Linux + S23) — opened after the upgrade, not bricked.
- **Data integrity** — a v9 vault exported from the frozen GrapheneOS device was synced
  (passphrase + YubiKey) into the migrated v10 Linux vault; sync reported **no changes /
  no data loss**, confirming migration preserved the data exactly (independent code path
  from the migration itself).

**v11 (RT-3 → drop-dual-lock), 2026-07-11:** full v11 matrix green on Linux + S23 + tablet
(GrapheneOS held as rollback); v10 → v11 migrate-on-unlock, all auth modes, CRUD, rotation,
cross-version sync, and read-only real-vault integrity all pass. Detail in the v11 matrix
below (## Gabbro v11 hardware test matrix → ### Results).

## Gabbro v11 hardware test matrix — drop-dual-lock-hybrid-kem

Run AFTER `gabbro_test` is green and the branch is pushed. Fill in the result cells;
fold the outcome into `test_data/migration_vaults/MIGRATION_TESTS.md` when done.

### Preconditions
- `gabbro_test` green (rust + flutter + android legs).
- Release builds: `flutter build linux --release`, `flutter build apk --release`.
- Vaults are MOCK only. Destructive steps NEVER touch a real vault. The real vault is
  opened read-only (group G) to confirm no brick — no edits, no saves, no migration ops on it.

### Version byte (offset 6):  v10 = `0a`,  v11 = `0b`
- Linux:   `xxd -s 6 -l 1 <vault-path from vaults.jsonc>`
- Android: in-app **Export** (byte-identical copy) → `adb pull /sdcard/Download/<name>.gabbro /tmp/`
           → `xxd -s 6 -l 1 /tmp/<name>.gabbro`  (release APK not debuggable; no run-as)

### Mock source vaults
- `test_data/migration_vaults/v10.gabbro` — passphrase `0123456789a`, one login
  (`Migration Test Login` / `test-user` / `migrate-me-2026`). The ≤v10 source to migrate.
- Fresh v11 vaults created in-app for the new-vault paths.

### Hardware
- Linux: 1x USB-C YubiKey (USB transport).
- S23: NFC (tap) transport.
- Android tablet: single key only → p-only / p+bio paths; YK cells `n/a`.
- GrapheneOS: HOLD on the pre-v11 build as the rollback fallback (see Ordering) until another
  device has migrated cleanly. 2-key vaults use the USB-C key on Linux and the NFC key on S23
  (never two USB taps at once).

### Ordering (safety)
Migration is one-way (v10 → v11 on first unlock). On each device finish setup and confirm the
`0a` byte BEFORE installing the v11 build. Keep GrapheneOS un-upgraded until Linux + S23 have
migrated cleanly, so a migration bug can't strand every device.

---

### Test groups

#### A. New vault seals v11
1. Create a new passphrase-only vault (passphrase of your choice). Add one login.
2. Lock, fully close, read the version byte → expect `0b`.
3. Create a new vault with passphrase + 2 keys (USB-C on Linux / NFC on S23). Add one login.
4. Lock, read byte → `0b`; unlock with EACH registered key in turn.

#### B. Migrate-on-unlock  v10 → v11  (the headline)
Do this on the v11 build.
1. Import `v10.gabbro` (source passphrase `0123456789a`) into a passphrase-only vault `v10_p`.
   (Android: `adb push v10.gabbro /sdcard/Download/` first.) Make one CRUD edit.
2. Import it into a p+YK vault `v10_pyk` (register the device's key). Make one CRUD edit.
3. Lock, fully close.
4. Open the app, unlock `v10_p` (passphrase), then `v10_pyk` (passphrase + one tap).
5. Confirm both now read `0b`; the imported login + the CRUD edit survive; `v10_pyk` needed only
   the normal single tap (no extra prompt).

#### C. Auth-mode smoke (must not regress)
For each: create → lock → unlock, confirm the login is readable.
- p (passphrase only)
- p+yk (2 keys; unlock with each)
- p+bio (enable biometric unlock; unlock via fingerprint)          [Android only]
- p+yk+bio (biometric + key)                                        [Android only]

#### D. CRUD stays v11 (no downgrade)
On a v11 vault: add, edit, then delete an entry. Lock, read byte → still `0b`; the surviving
entries persist across the lock/unlock.

#### E. Passphrase change + YubiKey rotation
- p vault: change passphrase → reopens with the NEW passphrase only; old rejected.
- p+yk vault: add a 2nd/3rd key, remove one key (keep >=1), change passphrase → still opens with
  each surviving key + the new passphrase; removed keys + old passphrase rejected.

#### F. Cross-version sync (no data loss)
- Sync/merge a `v10_*` vault into a v11 vault and vice versa → entries merge, no loss, no brick.

#### G. Real-vault integrity (READ-ONLY)
After upgrading each device to v11, open your real vault once → not bricked, entries visible.
No edits, no saves. (Migration occurs on first unlock; keep a backup export first if you prefer —
your call on your own hardware.)

---

### Matrix (fill: pass / fail / n/a / held)

| Test | Linux (USB-C) | S23 (NFC) | Tablet (1 key) | GrapheneOS | Comments |
|------|---------------|-----------|----------------|------------|----------|
| A  new vault -> v11 (p)           | pass | pass | pass | held | |
| A  new vault -> v11 (p+yk)        | pass | pass | n/a | held | |
| B  migrate v10_p -> v11           | pass | pass | pass | held | |
| B  migrate v10_pyk -> v11         | pass | pass | n/a | held | |
| C  p unlock                       | pass | pass | pass | held | |
| C  p+yk unlock (each key)         | pass | pass | n/a | held | |
| C  p+bio unlock                   | n/a | pass | pass | held | |
| C  p+yk+bio unlock                | n/a | pass | n/a | held | |
| D  CRUD stays v11                 | pass | pass | pass | held | |
| E  passphrase change (p)          | pass | pass | pass | held | |
| E  rotation + pp change (p+yk)    | pass | pass | n/a | held | |
| F  cross-version sync v10<->v11   | pass | pass | pass (tested with v9->v11 aok) | held | cannot do the `vice versa` test, illogical test |
| G  real vault opens (read-only)   | pass | pass | pass | held | |

Legend: `n/a` = device can't run that path; `held` = kept on the pre-v11 build as rollback.

### Pass criteria
- Every `0a` vault flips to `0b` on first unlock; no entry loss anywhere.
- New vaults seal `0b`; CRUD/sync/rotation keep them at `0b`.
- p+yk needs only the normal single tap after migration (no extra prompt).
- No vault — mock or real — is bricked.

### Results

**v11 (drop-dual-lock-hybrid-kem), 2026-07-11:**
- **Linux (USB-C)** — groups A–G all pass: new vaults seal `0b`; `v10_p` and `v10_pyk`
  migrated `0a` → `0b` (entries + CRUD edit intact, single tap); CRUD stays `0b`;
  passphrase change + key rotation; real vault opens read-only, not bricked.
- **S23 (NFC)** — A–G all pass, incl. p+bio and p+yk+bio; same migration + integrity result.
- **Tablet (1 key)** — p-only / p+bio paths pass; YK cells `n/a`. Cross-version sync
  exercised as v9 → v11 (aok).
- **GrapheneOS** — `held` on the pre-v11 build as the rollback fallback throughout.
- **F (cross-version sync)** — v10 ↔ v11 merges with no loss; the "vice versa" (v11 → v10)
  direction is not a valid path (older build fail-closes on a v11 file), so it is n/a by design.

No vault, mock or real, was bricked. Full per-cell grid in the matrix table above.
