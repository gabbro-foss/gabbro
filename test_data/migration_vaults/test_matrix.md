# RT-3 hardware test matrix

Run top to bottom. No step depends on a later one.

Fill: `pass` / `fail` / `n/a` / `held`.

## Facts (grounded in code)

| Fact | Source |
|------|--------|
| Current build writes and reads v11 only | `rust/src/vault/file_format.rs:66,74` |
| alpha.14 wrote v11, read v2+ | `v0.1.0-alpha.14:rust/src/vault/file_format.rs:88,91` |
| So an alpha.14-created vault is **v11** and opens on this build | above |
| `v10.gabbro` is a fixture, not a real-world vault | `test_data/migration_vaults/` |
| Version byte is at offset 6: v10 = `0a`, v11 = `0b` | `file_format.rs:84` |

## Step 1 — baseline build (alpha.14)

```
$ tar -xzf gabbro-0.1.0-alpha.14-linux-x86_64.tar.gz -C /tmp/gabbro-alpha14
```

Extract alongside; do not uninstall anything.

## Step 2 — baseline test, on the alpha.14 build, Linux only

| # | Step | Expect | Linux p |
|---|------|--------|---------|
| 1.1 | Add `v10.gabbro`, unlock with `0123456789a` | opens | pass |
| 1.2 | `xxd -s 6 -l 1` on it | `0a` | pass |
| 1.3 | `sha256sum` it, record | `dd76d02b46aa…` | pass |

Stop here. Close the alpha.14 build before Step 3.

## Step 3 — RT-3 build

```
$ cd rust && cargo build --release --lib && cd ..
$ flutter build linux --release
$ flutter build apk --release
```

The `cargo` line is **required**. Without it the Flutter build links the previous
`.so` and every refusal test below silently passes a v10 vault.

Verify before continuing:

| # | Step | Expect | Result |
|---|------|--------|--------|
| 2.1 | Unlock `v10.gabbro` on the new Linux build | **refused**, version-not-supported | pass |

If 2.1 opens the vault, the `.so` is stale. Redo Step 3.

## Step 4 — v11 still opens (no regression)

| # | Step | Expect | Linux p | Linux p+yk | S23 p | S23 p+yk | S23 p+bio | GrapheneOS |
|---|------|--------|---------|------------|-------|----------|-----------|------------|
| 3.1 | New passphrase vault + 1 login; lock, close, reopen | unlocks | pass | n/a | pass | gethmacsecret failed: tag was lost (happened multiple times) then pass | pass | held |
| 3.2 | New passphrase+2-key vault; reopen with EACH key | unlocks on each | n/a | pass | n/a | pass | n/a | held |
| 3.3 | Version byte on both | `0b` | pass | pass | pass | pass | pass: same vault as S23 p | held |

## Step 5 — v10 is refused, not broken

Once per device; auth mode is irrelevant here.

There is no "add a vault file" flow — `Add vault` creates a new one. A `.gabbro` file
enters the app through **Import**. So: create a throwaway vault (e.g. alias `v10_test`),
open it, then Import `v10.gabbro` from inside it. On Android `adb push` the file to
`/sdcard/Download/` first.

| # | Step | Expect | Linux | S23 | GrapheneOS |
|---|------|--------|-------|-----|------------|
| 4.1 | Import `v10.gabbro` with correct passphrase `0123456789a` | version-not-supported message; no "corrupt"; no Delete; no Restore. Error-red is correct here — the import did fail — and the text carries the meaning on its own (ADR-003) | pass | pass | held |
| 4.2 | The message shows a tappable link | link present | **fail** | **fail** | held |
| 4.3 | Tap link | opens `docs/VAULT_UPGRADE_PATH.md` | blocked by 4.2 | blocked by 4.2 | held |
| 4.4 | Set app language to Spanish, repeat 4.1 | message is in Spanish | **fail** | **fail** | held |
| 4.5 | Dismiss the message | app usable; other vaults open | pass | pass | held |
| 4.6 | Import with a WRONG passphrase | same version message, **not** "wrong passphrase" | pass | pass | held |

## Step 6 — refusal was non-destructive

| # | Step | Expect | Linux | S23 | GrapheneOS |
|---|------|--------|-------|-----|------------|
| 5.1 | `sha256sum v10.gabbro` | identical to 1.3 | pass | pass | held |
| 5.2 | Version byte | still `0a` | pass | pass | held |
| 5.3 | Directory beside it | no `.bak`, no new file | pass | pass | held |

5.1 identical proves the alpha.14 build from Step 2 would still open it.

## Step 7 — sync refuses a v10 source

Separate code path from unlock.

| # | Step | Expect | Linux | S23 | GrapheneOS |
|---|------|--------|-------|-----|------------|
| 6.1 | From a v11 vault, sync/merge `v10.gabbro` | clear refusal, no partial merge | pass | pass | held |
| 6.2 | Both files after | unchanged | pass | pass | held |

## Step 8 — v11 stays v11 under use

| # | Step | Expect | Linux p | Linux p+yk | S23 p | S23 p+yk | S23 p+bio | GrapheneOS |
|---|------|--------|---------|------------|-------|----------|-----------|------------|
| 7.1 | Add, edit, delete an entry; lock; reopen | survivors intact | pass | pass | pass | pass | pass | held |
| 7.2 | Version byte | `0b` | pass | pass | pass | pass | same vault as S23+p: pass | held |
| 7.3 | Change passphrase | reopens with NEW only; old rejected | pass | pass | pass | pass | same vault as S23+p: pass | held |
| 7.4 | Add a key, remove one (keep >=1), change passphrase | opens with each surviving key + new passphrase; removed key and old passphrase rejected | n/a | pass | n/a | pass | n/a | held |
| 7.5 | Version byte after 7.3/7.4 | `0b` | pass | pass | pass | pass | same vault as S23+p: pass | held |

## Step 9 — real vault, READ-ONLY

| # | Step | Expect | Linux | S23 | GrapheneOS |
|---|------|--------|-------|-----|------------|
| 8.1 | Open the real vault once per upgraded device | opens, entries visible | pass | pass | held |

No edits. No saves. It is v11 (created by alpha.14 or later) — Step 4 is the proof.

## Step 10 — About screen

| # | Step | Expect | Linux | S23 | GrapheneOS |
|---|------|--------|-------|-----|------------|
| 9.1 | About -> licences | no `ml-kem`, no `x25519-dalek`; rest intact | pass | pass | held |

## Pass criteria

- Every v11 vault opens in every auth mode; CRUD, rotation and passphrase change keep it `0b`.
- `v10.gabbro` is refused on every device and is byte-identical afterwards.
- No screen calls a v10 vault corrupt or offers to delete it.
- The refusal is localised and its upgrade link is tappable, on every screen that shows it.
- No vault, mock or real, is bricked.

## Open failures

| Ref | Failure |
|-----|---------|
| 4.2 | No tappable link on the import screen's version-not-supported message |
| 4.4 | That message stays English under a non-English UI locale |

Both are the same defect: `import_screen.dart:379` renders the raw Rust error
(`e.toString()`) as plain text, so the URL is not tappable and the string never
reaches the ARB. The unlock screen's card is correctly built and localised.
