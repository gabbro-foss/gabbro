# Golden vault fixtures — provenance & regeneration

These `.gabbro` files under `vaults/` are **frozen** golden vaults for the
backward-compatibility harness (`../vault_backward_compat.rs`). They are sealed
once, by the code that shipped each format VERSION, and committed to git. The
harness loads them and proves the **current** build can still read and migrate
them. They are deliberately **not** regenerated on each test run — a vault that
the current code both seals and opens proves nothing (that is exactly the gap
that let the 2026-06-08 brick through).

## What each fixture is

| File | VERSION | Sealed by | Shape | Role |
|------|---------|-----------|-------|------|
| `v10_passphrase.gabbro` | 10 | `master` (X25519 direct from KDF, no StdRng) | passphrase only | refusal input |
| `v10_multikey_2keys.gabbro` | 10 | `master` | passphrase + YK1 + YK2 | refusal input |
| `v11_passphrase.gabbro` | 11 | ADR-018 (vault key from Argon2id via HKDF, no KEM) | passphrase only | open/migrate |
| `v11_multikey_2keys.gabbro` | 11 | same | passphrase + YK1 + YK2 | open/migrate |

(Table grows as the harness grows — see the test list at the top of
`../vault_backward_compat.rs`.)

**The v10 pair is kept deliberately.** RT-3 raised the readable floor to v11 and
deleted the hybrid derivation that opened v2–v10, so these two no longer open —
that is their job. They are a *real* old vault (not a synthetic one) proving the
refusal is graceful and leaves the file byte-identical. Do not delete them, and do
not "fix" the tests that expect them to fail. The v6–v9 fixtures were deleted at
RT-3: below the floor and redundant once v10 covers the refusal. Git history has
them if a future archaeology needs one.

All fixtures seal the same canary body and use the same passphrase / YubiKey
material, defined in `fixture_spec.rs` (shared with the generator so seal-time
and assert-time values never drift).

## Low Argon2id params

The shipped `seal_*` functions hardcode `Argon2idParams::default()` (production
cost: m=65536, t=25, p=4) and there is no public seal-with-params entry point.
So fixtures are generated with the default **transiently lowered** to a cheap
value, keeping the recurring test fast. This changes nothing about the code path
under test: Argon2id is the same algorithm, and the params are stored in the
file header and read back on open. Production code is reverted afterwards and is
never committed with lowered params.

## Recipe — generating the current-VERSION fixtures (on `master`)

```bash
cd rust
# 1. Transiently lower the Argon2id default (DO NOT COMMIT this edit):
#    src/crypto/kdf.rs  Argon2idParams::default()  ->  m_cost: 64, t_cost: 1, p_cost: 1
# 2. Generate:
cargo run --example gen_fixtures
# 3. Revert the production source:
git checkout src/crypto/kdf.rs
# 4. Confirm only fixtures changed (kdf.rs must NOT appear):
git status
```

## Recipe — generating an older-VERSION fixture from a tag

```bash
# Generate in an isolated worktree at the tag that shipped the VERSION:
git worktree add /tmp/gabbro-old <tag>
cd /tmp/gabbro-old/rust
# Drop in a generator adapted to that tag's public API (older save_* signatures)
# and the same low-params edit, run it, then copy the produced .gabbro file(s)
# back into this repo's tests/fixtures/vaults/. Remove the worktree when done:
git worktree remove /tmp/gabbro-old
```

## Adding a fixture when a NEW VERSION ships

1. Tag the release that introduces VERSION N.
2. Generate `vN_passphrase.gabbro` and `vN_multikey_2keys.gabbro` from that tag
   (current-build recipe if N is the build you're on; tag-worktree recipe if not).
3. Drop the files in `vaults/`, add a row to the table above, and extend the
   parametrised tests in `../vault_backward_compat.rs` to cover them.

Any future change that stops the current code from reading a committed fixture
fails the harness — before it can brick a real vault.
