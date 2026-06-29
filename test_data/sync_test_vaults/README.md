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

## Hardware procedure

1. On each of three devices, create a fresh empty vault.
2. Import/sync one file into each: A → device 1, B → device 2, C → device 3.
3. Sync the three vaults together (each into the others, in any order).

## Expected result — nothing lost

- **Email**: username `alice-from-B` *and* password from A both kept (different fields
  merge). The password also clashes (A and C edited the same field) → a **keep mine /
  use theirs** prompt.
- **Server**: both `API key`=`k0-from-A` and `Port`=`8080` present (different pairs merge).
- **Wifi**: `Draft` was deleted on C → a **keep / delete** prompt (the item is kept until
  you choose).

These vaults use cheap Argon2 params (test only) — never use them for real data.
