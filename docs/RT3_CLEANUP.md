# RT-3 cleanup — deleting the dual-lock hybrid KEM (floor → v11)

Everything held back on the `drop-dual-lock-hybrid-kem` branch (v11 = WRITE path only)
so v2–v10 vaults can still be **read and migrated**. This is the **Release N+1** task
(ADR-018 decision item 2): run it once no ≤v10 vault remains in the field, raise the
readable floor to v11, and delete all of the below. Nothing here is load-bearing at v11.

**Precondition:** every vault migrated to v11 (see [VAULT_UPGRADE_PATH.md](VAULT_UPGRADE_PATH.md)).
Do NOT run this while any ≤v10 vault could still exist — it makes those vaults unopenable.
**Confirmed 2026-07-16:** maintainer's vaults all migrated; testers warned on the last release
and warned again before the next. Cleared to proceed.

## 0. Decisions (agreed 2026-07-16)

- **Rejection message:** `file version not supported: https://github.com/gabbro-foss/gabbro/blob/master/docs/VAULT_UPGRADE_PATH.md`
  The fix it documents: install alpha.14 → open every vault once → then install alpha.15+.
  Durable because immutable releases are on — alpha.14 can never be pulled or replaced.
  **This supersedes §9: `VAULT_UPGRADE_PATH.md` is NOT retired** — the error message points at
  it, so it stays and gets updated for the v11 floor.
- **Backward compatibility remains a standing gate requirement.** RT-3 raises the floor to v11;
  it does NOT retire the mechanism. Every future bump keeps the backward-compat gate, its
  per-version fixtures, and an upgrade path for older vaults. This is a one-off floor move to
  shed the dual-lock crates, not a licence to drop compatibility at the next bump.
- **Auto-migrate-on-unlock hooks: DELETE.** Version-generic, but unreachable at floor v11 (every
  openable vault is already current) and they cost a redundant `read_vault` per unlock. Git
  history carries them back if a v11→v12 bump needs them. Supersedes the "keep only if" in §7.
- **The v11 KAT stays.** "Delete the frozen-golden tripwire" means the *legacy `StdRng` goldens*
  in `keypair.rs`/`ml_kem.rs` only. `hkdf.rs::v11_vault_key_known_answer` is the tripwire proving
  this deletion did not alter the v11 derivation — keep it forever.
- **Net-first order:** pin current v11 behaviour green *first* (§10), then red-first the
  rejection, then delete. The v11 header is currently pinned only *relative* to v10
  (`v10.len() - v11.len() == 1600`) and that reference dies in this change — an absolute pin
  must land before anything is deleted.

## 1. Crate dependencies (`rust/Cargo.toml`)

- [ ] Remove `ml-kem = "0.2.3"` (feature `deterministic`).
- [ ] Remove `x25519-dalek = "2.0.1"` (feature `static_secrets`).
- [ ] Confirm the transitive tree shrinks (ADR-018: ~6 unique transitive crates incl. a
  compile-time proc-macro/build-dep). `rand` **stays** (`OsRng` for salts / random keys).
- [ ] Commit the regenerated `rust/Cargo.lock`.
- [ ] Drop the `ml-kem` + `x25519-dalek` licence-attribution entries from
  `lib/screens/about_screen.dart` (~L409, ~L454) — the About screen must not claim
  dependencies we no longer ship.

## 2. Whole modules

- [ ] Delete `src/crypto/keypair.rs` (`X25519Keypair`, incl. `from_kdf_output_legacy`).
- [ ] Delete `src/crypto/ml_kem.rs` (`MlKemKeypair`, FIPS + legacy keygen).
- [ ] Remove `pub mod keypair;` and `pub mod ml_kem;` from `src/crypto/mod.rs`.

## 3. `src/crypto/hkdf.rs`

- [ ] Delete `derive_vault_key` (legacy hybrid combiner) + `INFO` (`"gabbro-hybrid-kex-v1"`).
- [ ] Delete `derive_vault_key_transcript_bound` (v8 combiner) + `INFO_V2`.
- [ ] Delete their tests (`transcript_bound_differs_from_legacy`, legacy combiner tests).
- [ ] **Keep** `derive_vault_key_v11` (`INFO_VAULT_KEY_V11`) and `combine_yubikey` (`INFO_YUBIKEY`).

## 4. `src/crypto/vault_crypto.rs`

- [ ] Delete dispatchers `ml_kem_keypair_for_version`, `x25519_keypair_for_version`,
  `derive_passphrase_vault_key_for_version`.
- [ ] Collapse the 6 derivation sites: drop each `else { /* RT-3 legacy hybrid-KEM */ }`
  branch, keeping only the v11 HKDF-direct path — `seal_vault_with_params`, `open_vault`,
  `seal_vault_with_keys`, `open_vault_with_key_record`, `migrate_multikey_to_version`,
  `change_vault_passphrase_with_keys`.
- [ ] Remove legacy imports: `ml_kem::{Decapsulate, Encapsulate, Ciphertext}`,
  `x25519_dalek::{EphemeralSecret, PublicKey}`, `keypair::X25519Keypair`, `ml_kem::MlKemKeypair`.
- [ ] Simplify `capped_reseal_version_for` — one derivation era at v11+, so the two-era
  boundary (and the `X25519_DIRECT_MIN_VERSION`/`HKDF_DIRECT_MIN_VERSION` split) collapses;
  a body-only re-seal no longer risks crossing a boundary.
- [ ] Delete legacy tests: `legacy_version_5_vault_still_opens`,
  `truncated_ml_kem_ciphertext_returns_error_not_panic`, `derive_passphrase_vault_key_dispatches_on_version`,
  `migrate_multikey_across_x25519_boundary_v9_to_v10_reopens_with_each_key`, the S10/S11/S12
  legacy-`StdRng` p+YK brace tests.

## 5. Version constants

- [ ] `src/vault/file_format.rs`: raise `VERSION_MIN_READABLE` 2 → 11; delete `KEM_HEADER_MAX_VERSION`.
- [ ] `src/crypto/vault_crypto.rs`: delete `FIPS_KEYGEN_MIN_VERSION`, `AAD_MIN_VERSION`
  (AAD always on at v11), `TRANSCRIPT_BINDING_MIN_VERSION`, `X25519_DIRECT_MIN_VERSION`,
  `HKDF_DIRECT_MIN_VERSION` (becomes the floor).

## 6. Header / `SealedVault` (`src/vault/file_format.rs`)

- [ ] Remove struct fields `ml_kem_ciphertext: Vec<u8>` and `x25519_ephemeral_public: [u8; 32]`.
- [ ] Remove the `version <= KEM_HEADER_MAX_VERSION` branches in `to_bytes` / `from_bytes` /
  `header_aad` — the header is always the compact v11 form; drop the 1568-byte length guards.
- [ ] Update `test_vault()` fixtures that set those fields.

## 7. Migrate-on-unlock (`src/vault/session.rs`, `src/api/vault.rs`)

- [ ] The ≤v10 rebuild path is dead (nothing older than v11 to migrate). Remove the legacy
  derivation inside `migrate_multikey_to_version`; keep the generic on-unlock plumbing only if a
  future v11→vN bump needs it, else remove `migrate_passphrase_vault_on_unlock` /
  the p+YK migrate-on-unlock hooks (`session.rs:78,109`).

## 8. Tests & fixtures (floor now v11)

- [ ] `rust/tests/vault_backward_compat.rs`: remove the v6–v10 open/migrate/rotation tests +
  the v11 rotation/passphrase entries that reference pre-v11 fixtures; keep the v11 tests; add a
  "≤v10 file rejected with a clear unsupported-version error" test, run against the **kept v10
  fixtures** (a real old vault, not a synthetic one).
- [ ] Delete `rust/tests/fixtures/vaults/v{6,7,8,9}_*.gabbro` (8 files) + their FIXTURES.md rows.
  **Keep the `v10_*` pair** — the most recent old format, now the rejection-test input.
- [ ] `rust/tests/vault_state_machine_fuzz.rs`: drop v6/v7/v8 from `FIXTURES` (keep v11); the
  `start_version < VERSION` belt branch in `assert_invariants` becomes unreachable — simplify.
- [ ] `rust/src/crypto/kdf.rs`, `keypair.rs`, `ml_kem.rs`: the `StdRng`/legacy golden-value +
  `fips_differs_from_legacy` tests go with their modules.
- [ ] `test_data/migration_vaults/v{6..10}.gabbro` stay as the historical manual corpus (never
  deleted per MIGRATION_TESTS.md) but the RT-3 build will not open them — expected; note it there.
- [ ] **Re-mint the sync-test corpus at v11** (sweep 2026-07-16 — missed by the original
  checklist). `test_data/sync_test_vaults/{A,B,C}.gabbro` are **v9** and would go unopenable,
  breaking three LIVE tests (`sync_test_corpus_converges_without_loss`,
  `corpus_surfaces_new_entry_then_whole_entry_delete`,
  `re_syncing_the_same_source_converges_without_loss`) plus two gate legs (sync-walk batched
  apply, fast-merge walk). Fix: `cargo test --release regenerate_sync_test_corpus -- --ignored`,
  which rewrites all three at the current VERSION. Mock vaults, documented passphrase — no risk;
  the three tracked `.gabbro` files change in the diff. Do this BEFORE raising the floor.

## 9. Docs

- [ ] Remove the "≤v10 read-only / retained until RT-3" notes added for v11 across
  `SECURITY.md`, `README.md`, `ARCHITECTURE.md` (Encryption line + format), the crypto diagrams
  (`flow.dot`/`flow.svg` note, `simple_icons.svg` — already KEM-free), `ADR-018` Implementation note.
- [ ] `kdf.rs` module doc: drop the `StdRng` / bytes-[0..32] X25519-seed description.
- [ ] **Keep** `VAULT_UPGRADE_PATH.md` — the rejection message links to it (§0), so it must
  never 404. Update it for the v11 floor: name alpha.14 as the stepping stone, state what the
  error means and the exact fix.
- [ ] Delete this file once the cleanup lands.

## 10. Test order (net-first, then red-first)

Pins land and go green against the CURRENT code before anything is deleted.

**Net (green now, commit first)**
- [x] N1 v11 fixtures open (passphrase + multikey, each key) — exists, reuse.
- [x] N2 `hkdf.rs::v11_vault_key_known_answer` — exists, keep forever (see §0).
- [x] N3 unlock→lock leaves a v11 vault byte-identical — exists, reuse.
- [x] N4 **v11 layout pinned absolutely** — `file_format.rs`:
  `v11_on_disk_layout_is_pinned_absolutely` (172 bytes) +
  `v11_header_aad_is_pinned_absolutely` (88 bytes). Expected streams are rebuilt from the
  format spec, not copied from `to_bytes`; self-contained so they survive `test_vault()`
  being re-pinned to v11.
- [x] N5 `capped_reseal_version_holds_v11_material_at_v11` extracted standalone
  (`vault_crypto.rs`) — survives the multi-era test it is carved out of.
- [x] N6 sync corpus re-minted at v11 (`vault::session::field_merge_tests::
  regenerate_sync_test_corpus -- --ignored`); all five consumers green: the three live
  merge tests + gate legs `sync_walk_batched_apply_matches_checker` and
  `fast_merge_walk_incoming_wins_and_order_dependent`.

**Red (fails now)**
- [ ] R1 v10 passphrase fixture → `Err` with the §0 message.
- [ ] R2 v10 multikey fixture → `Err` on the YubiKey path too.
- [ ] R3 v6/v7/v8/v9 fixtures → same rejection (replaces today's open/migrate tests).
- [ ] R4 **a rejected open leaves the file byte-identical on disk** — "rejected, never
  bricked"; the documented recovery (reinstall the older release, open, upgrade) depends on it.
- [ ] R5 `SealedVault::from_bytes` rejects v10 bytes at the parse layer.
- [ ] R6 a v12 file still fails closed with the *newer-version* message (the ceiling must
  survive the floor move).
- [ ] R7 rejection is distinguishable from "wrong passphrase" — a ≤v10 user must not think
  they mistyped.
- [ ] R8 fuzzer `FIXTURES` → v11 only; the unreachable `start_version < VERSION` branch
  simplified.
