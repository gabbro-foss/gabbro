# Sync-test vaults (three divergent devices)

Three copies of the same 12-entry vault — **two of every entry type** — each with different
edits, for hardware-testing N-device granular sync.

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

## How to run it

All three share passphrase `0123456789a`; **Sync from file** only merges vaults that share
a passphrase, so create your vaults with that one.

### Single device (fastest — exercises the full merge, no file copying)

1. Create a new vault, passphrase `0123456789a`.
2. **Import entries** → **Gabbro vault** section → pick `sync_test_A.gabbro`, type
   `0123456789a` in **Vault passphrase**, tap **Sync from vault**.
3. Menu → **Sync from file** → `sync_test_B.gabbro`, passphrase `0123456789a`.
4. Menu → **Sync from file** → `sync_test_C.gabbro`, passphrase `0123456789a`.

### Three devices

Do steps 1–2 with A / B / C on the three devices, then **Sync from file** the other two
files (passphrase `0123456789a`) on any device — the merge result is identical.

## Expected result — nothing lost

- Every `*-nc` entry shows **all three devices' edits** (different fields/pairs merged).
- Every `*-co` entry raises **one clash prompt** (keep mine / use theirs) on the shared
  field — **six in total, one per type**.
- Login `OldNote` raises **one keep/delete prompt** (the item is kept until you choose).
- All 12 entries survive; nothing is silently dropped.

These vaults use cheap Argon2 params (test only) — never use them for real data.
