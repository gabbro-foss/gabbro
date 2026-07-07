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

Run **Android first**. Do NOT upgrade Linux / S23 / GrapheneOS until Android is green.
Package: `app.gabbro.gabbro`.

**Version-byte check** (`09` = v9, `0a` = v10):
```
adb exec-out run-as app.gabbro.gabbro ls files/                          # list vault files
adb exec-out run-as app.gabbro.gabbro cat files/<name>.gabbro | xxd -s 6 -l 1
```

**On the current alpha.12 (v9) build:**
1. Open the existing `synctest` vault.
2. Create two vaults: **`v9_p`** (passphrase `0123456789a`) and **`v9_pyk`**
   (passphrase `0123456789a` + two YubiKeys).
3. `adb push v9.gabbro /sdcard/Download/` → in-app **Import entries** → `v9.gabbro`
   (source passphrase `0123456789a`) into **both** `v9_p` and `v9_pyk`.
4. Make one CRUD edit in each.
5. Lock, fully close the app.
6. Confirm both are v9 (glob finds the file):
   `adb exec-out run-as app.gabbro.gabbro sh -c 'cat files/*v9_p*.gabbro | xxd -s 6 -l 1'` → `09`
   (repeat for `v9_pyk`).

**Then:**
7. Install the v10 release build (`flutter build apk --release`).
8. Open the app; unlock `v9_p` (passphrase), then `v9_pyk` (passphrase + one tap —
   test USB-C and NFC).
9. Confirm both migrated:
   `adb exec-out run-as app.gabbro.gabbro sh -c 'cat files/*v9_p*.gabbro | xxd -s 6 -l 1'` → `0a`
   (repeat for `v9_pyk`).

**Pass** = both flip `09` → `0a`, all synced entries + the CRUD edit survive, and
`v9_pyk` needs only the normal single tap (no extra prompt).

| | v9_p | v9_pyk (USB-C) | v9_pyk (NFC) |
|---|---|---|---|
| Android tablet |  |  |  |
| Linux |  |  | n/a |
| S23 |  |  |  |
| GrapheneOS |  |  |  |

(Linux: same steps; version-byte check is `xxd -s 6 -l 1 <vault-path from vaults.jsonc>`.)

## Runs
_(date + result)_
