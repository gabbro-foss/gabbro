# Sync-test vaults (three divergent devices)

Three copies of a shared 12-entry vault — **two of every entry type** — each with different
edits, plus a **B-only new entry** and an entry **deleted on C**, for hardware-testing
N-device granular sync.

- **Alias:** `synctest` (all three)
- **Passphrase:** `0123456789a` (all three)

The **same files** back the automated test
`rust/src/vault/session.rs::sync_test_corpus_converges_without_loss`, so software and
hardware exercise the identical artifacts. The test converges them in **several different
sync orders** and asserts the same result every time (order must not matter).

Each device stamps its edits at a **different time** (A oldest, then B, then C), so a
colliding field genuinely differs in time — a real two-device clash, not an artificial
same-millisecond tie. A clash is raised because **both sides edited the field**, never
because the times match; the newer time is not used to silently pick a winner.

## The 12-entry base (identical on all three)

`login-nc` Email (alice / p0; custom `OldNote`), `login-co` Bank (bob / q0),
`note-nc` Shopping, `note-co` Ideas, `id-nc` Me (Alex Stone), `id-co` Partner (Sam Stone),
`card-nc` Visa (cvv 123), `card-co` Amex (cvv 999), `file-nc` passport.txt (one-word text
payload `original`), `file-co` key.txt (`base`), `custom-nc` API creds (`api_key`,`secret`),
`custom-co` Tokens (`token`).

The two File entries hold a small one-word text payload so it's easy to edit.

## Two extra entries (the add / delete review paths)

- `delme` — a Note present on **A and B only**. **C deletes it** (tombstone), so syncing C
  surfaces it as a **whole-entry delete**.
- `extra-b` — a Login present on **B only**, so syncing B surfaces it as a **new entry**.

## What each device changed

For every type, `*-nc` gets **non-colliding** edits (each device touches a *different*
field → all merge) and `*-co` gets a **colliding** edit (two devices change the *same*
field → clash).

| Type | `*-nc` (non-colliding) | `*-co` (colliding) |
|------|------------------------|--------------------|
| Login | A→username, B→password, C→url; **C deletes custom `OldNote`** | A & C → password (clash); B → username |
| Note | A→title, B→content, C→adds custom `Tag` | A & C → content (clash); B → title |
| Identity | A→phone, B→email, C→address | A & C → last name (clash); B → first name |
| Card | A→CVV, B→expiry, C→bank name | A & C → CVV (clash); B → expiry |
| File | A→filename, B→notes, C→data | A & C → data (clash); B → filename |
| Custom | A→edits `api_key`, B→adds `env`, C→title | A & C → `token` (clash); B → adds `scope` |

## Hardware test — granular flow: follow exactly

One device. Mock vaults only. Passphrase for everything: `0123456789a`.
Make the picks below exactly; the result is then checked against a known answer.

**1.** Create a new vault, passphrase `0123456789a`.

**2.** Menu → **Import entries** → **Gabbro vault** → `sync_test_A.gabbro` →
**Sync from vault**.

**3. Sync B.** Menu → **Sync from file** → `sync_test_B.gabbro`. The review opens
(13 screens). On **every** screen leave the default and tap **Continue**, then tap
**OK**. (The first screen is the new entry **New on B** — leave **Keep**.)

**4. Sync C.** Menu → **Sync from file** → `sync_test_C.gabbro`. The review opens
(13 screens). Each screen's **title** is at the top — match it in the table and do
exactly what it says, then **Continue**. Order is roughly top-to-bottom, but match by
title, not position.

Each value row has two chips: **Use this vault** (your value) and **Use other vault** (the
incoming value). Brought-over rows default to **Use other vault** — leave them.

| Screen title | What to do |
|--------------|-----------|
| **Email** | leave the URL row as-is (default **Use other vault**); on the **OldNote** row pick **Delete** |
| **Shopping-A** | **Continue** (leave default) |
| **Alex Stone** | **Continue** (leave default) |
| **Visa** | **Continue** (leave default) |
| **passport-A.txt** | **Continue** (leave default) |
| **API creds** | **Continue** (leave default) |
| **Bank** | tap the **eye** to reveal, then tap **Use other vault** |
| **Ideas-B** | tap **Use this vault** |
| **Sam-B StoneA** | tap **Use other vault** |
| **Amex** | tap **Use this vault** |
| **key-B.txt** | tap **Use other vault** |
| **Tokens** | tap **Use this vault** |
| **Delete me** | pick **Delete** |

Tap **OK** at the end.

**5.** Export the vault to **JSON** (Menu → Export → JSON), save as `/tmp/sync_walk.json`.

**6.** Run the checker from `rust/`:

```
GABBRO_WALK_JSON=/tmp/sync_walk.json cargo test --release --lib check_sync_walk_export -- --ignored
```

Green = the resulting vault matches the known answer exactly. Red = it prints which
field differs.

Watch for (flag if wrong): every choice is a clearly labelled button (**Keep** /
**Delete** / **Use other**); the **Bank** and **Amex** screens hide their two values
behind dots with an **eye** to reveal.

## Hardware test — fast auto-merge

The same corpus, but exercising the **Merge automatically** path (no per-change
review; the incoming vault wins every clash, replaced values kept in history).
One device, mock vaults only, passphrase `0123456789a`.

**1.** Create a new vault, passphrase `0123456789a`.

**2.** Menu → **Import entries** → **Gabbro vault** → `sync_test_A.gabbro` →
**Sync from vault**.

**3. Sync B.** Menu → **Sync from file** → `sync_test_B.gabbro`. On the
"How should this sync apply?" prompt, tap **Merge automatically**. No review opens.

**4. Sync C.** Menu → **Sync from file** → `sync_test_C.gabbro` → **Merge
automatically**.

**5.** Export the vault to **JSON** (Menu → Export → JSON), save as
`/tmp/fast_sync_walk.json`.

**6.** Run the checker from `rust/`:

```
GABBRO_FAST_WALK_JSON=/tmp/fast_sync_walk.json cargo test --release --lib check_fast_sync_walk_export -- --ignored
```

Green = the export matches a fresh in-process fast A→B→C merge of the same corpus
(compared by field values, ignoring timestamps/history). Red = it prints the entry
that differs.

Expected outcome (no prompts): every `*-co` clash field takes **C's** value; `delme`
(deleted on C) is **gone**; `extra-b` (new on B) is **kept**; the `login-nc` `OldNote`
item C deleted is **removed**.

## Regenerate

These are committed binaries. To rebuild them after changing the corpus, run the generator
that defines them (in `rust/src/vault/session.rs`):

```
cargo test --release regenerate_sync_test_corpus -- --ignored
```

It writes all three files with cheap Argon2 params and alias `synctest`.

These vaults use cheap Argon2 params (test only) — never use them for real data.
