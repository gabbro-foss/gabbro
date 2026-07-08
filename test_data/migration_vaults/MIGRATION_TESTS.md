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

Add one `vN.gabbro` per version bump; never delete old ones. Regenerate (throwaway):
worktree at the tag that shipped VERSION N, add an example that builds a one-login
`VaultBody` and calls `save_vault(&body, b"0123456789a", out)`, run `--release`,
verify it opens, remove the worktree. (Current build = v10 → no worktree needed.)

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
