# Sync-test vaults (three divergent devices)

Three copies of the same starting vault, each with different edits — for hardware-testing
N-device granular sync. Passphrase: **`0123456789a`**.

The **same files** are loaded by the automated test
`rust/src/vault/session.rs::sync_test_corpus_converges_without_loss`, so software and
hardware exercise the identical artifacts.

Shared base (all three): **Email** (user `alice`, pw `p0-orig`), **Server**
(custom field `API key`=`k0`), **Wifi** (custom field `Draft`=`d0-secret`).

| File | What this "device" changed |
|------|----------------------------|
| `sync_test_A.gabbro` | Email password → `p0-from-A`; Server `API key` → `k0-from-A` |
| `sync_test_B.gabbro` | Email username → `alice-from-B`; Server adds custom `Port`=`8080` |
| `sync_test_C.gabbro` | Email password → `p0-from-C` (same field as A); deletes Wifi `Draft` |

## How to run it

All three files use passphrase `0123456789a`. **Sync from file** only merges vaults that
share a passphrase, so give every vault you create that same passphrase.

### Single device (fastest — exercises the full merge, no file copying)

1. Create a new vault, passphrase `0123456789a`.
2. **Import entries** → **Gabbro vault** section → pick `sync_test_A.gabbro`, type
   `0123456789a` in **Vault passphrase**, tap **Sync from vault** (loads A's entries with
   their per-field change-times).
3. Menu → **Sync from file** → `sync_test_B.gabbro`, passphrase `0123456789a`.
4. Menu → **Sync from file** → `sync_test_C.gabbro`, passphrase `0123456789a`.

Watch for the prompts in steps 3–4, then check the entries against the expected result below.

### Three devices (load one file per device, then sync)

On each device do steps 1–2 with A / B / C respectively. Then on any device, **Sync from
file** the other two files (passphrase `0123456789a`) to bring everything together — the
merge result is identical.

## Expected result — nothing lost

- **Email**: username `alice-from-B` *and* password from A both kept (different fields
  merge). The password also clashes (A and C edited the same field) → a **keep mine /
  use theirs** prompt.
- **Server**: both `API key`=`k0-from-A` and `Port`=`8080` present (different pairs merge).
- **Wifi**: `Draft` was deleted on C → a **keep / delete** prompt (the item is kept until
  you choose).

These vaults use cheap Argon2 params (test only) — never use them for real data.
