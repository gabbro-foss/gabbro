# Sync-test vaults (three divergent devices)

Three copies of a shared 12-entry vault — two of every entry type — with divergent
edits, plus a **B-only** new entry (`extra-b`, shown as **New on B**) and an entry
**deleted on C** (`delme`, shown as **Delete me**). The same files back the automated
test `rust/src/vault/session.rs::sync_test_corpus_converges_without_loss`.

- **Alias:** `synctest` — **passphrase:** `0123456789a` (all three).
- One device, **mock vaults only**.

**Shared start** (both required walks begin here): create a new vault (passphrase
`0123456789a`), then Menu → **Import entries** → **Gabbro vault** →
`sync_test_A.gabbro` → **Sync from vault**.

> **Order matters — always sync A, then B, then C.** The checkers validate the
> **A→B→C** result. Syncing C before B produces a *different but still-correct*
> vault that won't match — `delme` reappears, because a device that still holds a
> deleted entry re-adds it on sync (union: a sync never silently loses an entry).
> A checker failing with `delme` present means you synced out of order, not a bug.

---

# Required — do these three

## Walk 1 — granular review

1. **Sync B:** Menu → **Sync from file** → `sync_test_B.gabbro` → **Review all
   changes**. On every screen leave the default and tap **Continue**; the first
   screen (**New on B**) leave as **Keep**. Tap **OK**.
2. **Sync C:** Menu → **Sync from file** → `sync_test_C.gabbro` → **Review all
   changes**. Match each screen by its **title** and do what the table says, then
   **Continue**. Tap **OK** at the end. (Rows default to **Use other vault**.)

   | Screen title | What to do |
   |--------------|-----------|
   | **Email** | leave the URL row default; on the **OldNote** row pick **Delete** |
   | **Shopping-A** | **Continue** (default) |
   | **Alex Stone** | **Continue** (default) |
   | **Visa** | **Continue** (default) |
   | **passport-A.txt** | **Continue** (default) |
   | **API creds** | **Continue** (default) |
   | **Bank** | tap the **eye** to reveal, then **Use other vault** |
   | **Ideas-B** | **Use this vault** |
   | **Sam-B StoneA** | **Use other vault** |
   | **Amex** | **Use this vault** |
   | **key-B.txt** | **Use other vault** |
   | **Tokens** | **Use this vault** |
   | **Delete me** | pick **Delete** |

3. On the C-sync snackbar (*"Vault synced — 0 added, 9 updated, 1 deleted"*) tap
   **Details** before it fades. Confirm the dialog lists **Updated (9)**,
   **Deleted (1): Delete me**, **no Added**, and no Ideas-B / Amex / Tokens.
4. Export the vault to **JSON**, save as `/tmp/sync_walk.json`.

**Command** (from `rust/`):

```
GABBRO_WALK_JSON=/tmp/sync_walk.json cargo test --release --lib check_sync_walk_export -- --ignored
```

**Expected:** green — the vault matches the known answer. Red prints the field that differs.

## Walk 2 — fast auto-merge

From the shared start:
1. **Sync B:** Menu → **Sync from file** → `sync_test_B.gabbro` → **Merge
   automatically** (no review).
2. **Sync C:** `sync_test_C.gabbro` → **Merge automatically**.
3. Export to **JSON**, save as `/tmp/fast_sync_walk.json`.

**Command** (from `rust/`):

```
GABBRO_FAST_WALK_JSON=/tmp/fast_sync_walk.json cargo test --release --lib check_fast_sync_walk_export -- --ignored
```

**Expected:** green — matches a fresh in-process fast A→B→C merge (`delme` gone,
`extra-b` kept, incoming wins every clash).

## Editor check — duplicate custom-field label (30 seconds, no command)

Any vault: add a new entry (any type) → **Add custom field** (Label `dup`, Value
`one`) → **Add custom field** again (Label `dup`, Value `two`) → **Save**.

**Expected:** save **blocked**; the **Label** fields show **"Label must be unique"**.
Rename one to `dup2` → **Save** succeeds.

---

# Optional — already gate-green

These behaviours are proven by automated Rust tests in the release gate. Run them only
for extra on-device confidence.

- **Cancel = nothing changes** (`cancel_sync_rolls_back_to_pre_sync_state`). Shared
  start → **Sync from file** → `sync_test_B.gabbro` → **Review all changes** →
  **Cancel** → **Cancel sync**. Expect a **Sync cancelled** snackbar and no change
  (**New on B** absent; **Email** still shows `p0`).

- **"Merge the rest" mid-review** (`fast_merge_walk...`). Like Walk 2 but reach the
  fast path from inside the review: for B and C, **Sync from file** → **Review all
  changes** → **Cancel** → **Merge automatically**. Export to `/tmp/fast_sync_walk.json`
  and run Walk 2's command — expect the **same** green result.

- **Cross-version source** (`cross_version_sync_loads_and_merges_a_v8_file`). New vault
  with one Login **`Local Only`** → **Sync from file** → `migration_vaults/v8.gabbro`
  → passphrase `0123456789a` → **Review all changes** → keep **Migration Test Login**.
  Expect both entries present, nothing lost.

---

## Regenerate

Committed binaries. To rebuild after changing the corpus (from `rust/`):

```
cargo test --release regenerate_sync_test_corpus -- --ignored
```

Cheap Argon2 params, alias `synctest` — test only, never for real data.
