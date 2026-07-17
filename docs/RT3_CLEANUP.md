# RT-3 cleanup — deleting the dual-lock hybrid KEM (floor → v11)

Everything held back on the `drop-dual-lock-hybrid-kem` branch (v11 = WRITE path only)
so v2–v10 vaults can still be **read and migrated**. This is the **Release N+1** task
(ADR-018 decision item 2): run it once no ≤v10 vault remains in the field, raise the
readable floor to v11, and delete all of the below. Nothing here is load-bearing at v11.

**Precondition:** every vault migrated to v11 (see [VAULT_UPGRADE_PATH.md](VAULT_UPGRADE_PATH.md)).
Do NOT run this while any ≤v10 vault could still exist — it makes those vaults unopenable.
**Confirmed 2026-07-16:** maintainer's vaults all migrated; testers warned on the last release
and warned again before the next. Cleared to proceed.

---

## HANDOFF — state at 2026-07-17 (read this first)

**The code is COMPLETE. Every §1–§9 deletion has landed; what remains is the gate, the
hardware matrix, and deleting this file.** All committed on `master`, nothing on a branch.

**Done and green:**
1. Net pins for v11 — absolute layout pin, reseal-cap pin, sync corpus re-minted at v11.
2. Floor raised: `VERSION_MIN_READABLE` 2 -> 11, with the refusal message.
3. `vault_backward_compat.rs` rewritten: 11 tests. v6–v10 open/migrate gone; journeys run
   from v11; 4 refusal tests.
4. The UI hole (§8a) closed: `peek_version`/`is_format_too_old` -> bridge -> `onVaultFormatTooOld`
   -> a non-destructive banner with a tappable link; 37 locales; Net A/B/C sweeps.
5. The fuzzer (§8, R8): `FIXTURES` -> v11 only; three-way version check collapsed to one.
6. §1–§7 deletions: both crates, `keypair.rs` + `ml_kem.rs`, the legacy hkdf combiners, all 6
   derivation sites, the version dispatchers, the era constants, the two header fields, and the
   migrate-on-unlock hooks. **11 crates left the tree (195 -> 184 lock entries.)**
7. §8 fixtures: v6–v9 deleted, v10 pair kept as the refusal input. §9 docs swept.

**NOT done:**
- [ ] **Full gate (~2h) — maintainer runs it, not the agent.** Everything the agent can run is
  green (table below), but the gate is the authority — in particular the Android leg, which no
  agent-run suite covers.
- [ ] Hardware matrix.
- [ ] Decide whether this warrants a release (maintainer's call). CHANGELOG `[Unreleased]` is
  written: Security (v11 minimum, crates gone) + Changed (≤v10 refused, not damaged).
- [ ] Delete this file (§9) once the gate is green and it has shipped.

**Two checklist claims turned out to be WRONG — do not re-trust them:**
- §1/ARCHITECTURE said `ml-kem` was `hybrid-array`'s only source and the crate "dies with RT-3".
  It does not: `sha2`/`hkdf` -> `digest` still need it. What died is the **duplicate** (`ml-kem`
  pulled 0.2.3 alongside 0.4.12), so `cargo deny` duplicates went 7 -> 6. Table corrected.
- §8's fixture list missed two live consumers of the deleted fixtures, both found by grep, not by
  the checklist: `tests/vault_parse_fuzz.rs` (seeded off `v7_passphrase.gabbro`; its truncation
  test needs a file that *parses*, so it moved to v11) and the **gate leg**
  `cross_version_sync_loads_and_merges_a_v8_file`, which loaded `v8_passphrase.gabbro`.
  **Both were `#[ignore]`d or gate-only, so no routine suite would have caught either.**

  The gate leg is now `sync_merges_a_never_edited_entry`, building the body in memory
  (`gabbro_test` line 79 + the ARCHITECTURE row follow it). Its old name and comment were
  actively misleading and nearly got it deleted: they framed "an entry with no `field_times`"
  as a pre-v9 artifact, when in fact `create_login_entry` (`api/vault.rs:289`) starts EVERY
  entry with `field_times` empty — only `update_entry` fills them in. So the shape under test is
  the everyday one (create an entry, sync it before ever editing it), and has nothing to do with
  v8; the v8 file was just where the original author found that shape lying around. The test
  stays, and the v8 archaeology is gone from its name and comment.

**Verification state — what was actually run, and what was NOT:**

| Suite | Result | When |
|---|---|---|
| `cargo test --release --lib` (full Rust lib) | **634 pass, 0 fail, 17 ignored** | after all deletions |
| `cargo test --release --test vault_backward_compat` | 11 pass, 0 fail | after all deletions |
| `cargo test --release --test vault_state_machine_fuzz -- --ignored` | 1 pass | after all deletions |
| `cargo test --release --test vault_parse_fuzz` | 4 pass | after the v11 re-seed |
| `cargo test --release --lib sync_merges_a_never_edited_entry -- --ignored` | 1 pass (count checked, not 0-filtered) | after the rewrite |
| `cargo deny --offline check` | advisories/bans/licences/sources **ok**; duplicates 7 -> 6 | after crate removal |
| `cargo audit -n` | no vulnerabilities (184 crates) | after crate removal |
| `flutter test` (whole suite) | 1265 pass, 0 fail | after the About-screen edit |
| `flutter analyze` (touched files) | clean | after the About-screen edit |
| `dart test integration_test/ -j 1` (real FFI) | 12 pass | against the new release cdylib |
| `cargo clippy --release --all-targets -- -D warnings` | clean | **after** the final `cargo fmt` |
| `cargo fmt --check` | clean | final |
| Full `gabbro_test` gate (~2h) incl. **Android** | **NOT RUN** | — |
| Hardware matrix | **NOT RUN** | — |

The Rust unit count is **634** (measured, not arithmetic — was 668). ARCHITECTURE updated; the
gate remains the authority.

**Traps found the hard way — do not re-learn these:**
- `cargo test --exact <bare_name>` silently runs **0 tests** and prints `ok`. Always use the full
  module path (`vault::file_format::tests::x`) and check the count, or a "pass" means nothing.
- The corpus generator lives at `vault::session::field_merge_tests::regenerate_sync_test_corpus`
  (not `merge_tests`).
- Rust-layer refusal tests passing does NOT mean the app behaves: the Dart side discarded the
  Rust error entirely and would have shown "corrupt -> Delete file". Always trace to the screen.
- `_bareUnlock()` in `unlock_screen_test.dart` has a READABLE vault, so the existing Net A/B/C
  sweeps never render any banner. New banners need their own sweeps (`_bareFormatTooOld()`).
- `nn`/`yo` throw a locale-delegate warning in any all-locale widget sweep. Pre-existing and
  app-wide; now a Bikeshed item. Tolerate that exact string, never blanket-ignore exceptions.

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

- [x] Remove `ml-kem = "0.2.3"` (feature `deterministic`).
- [x] Remove `x25519-dalek = "2.0.1"` (feature `static_secrets`).
- [x] Confirm the transitive tree shrinks. **Actual: 11 crates, 195 -> 184 lock entries**
  (ADR-018 estimated ~6): `ml-kem`, `x25519-dalek`, `curve25519-dalek`,
  `curve25519-dalek-derive`, `fiat-crypto`, `kem`, `keccak`, `sha3`, `rustc_version`,
  `semver`, and the duplicate `hybrid-array` 0.2.3. `rand` **stays** (`OsRng` for salts /
  random keys).
- [x] Commit the regenerated `rust/Cargo.lock`.
- [x] Drop the `ml-kem` + `x25519-dalek` licence-attribution entries from
  `lib/screens/about_screen.dart` (~L409, ~L454) — the About screen must not claim
  dependencies we no longer ship.

## 2. Whole modules

- [x] Delete `src/crypto/keypair.rs` (`X25519Keypair`, incl. `from_kdf_output_legacy`).
- [x] Delete `src/crypto/ml_kem.rs` (`MlKemKeypair`, FIPS + legacy keygen).
- [x] Remove `pub mod keypair;` and `pub mod ml_kem;` from `src/crypto/mod.rs`.

## 3. `src/crypto/hkdf.rs`

- [x] Delete `derive_vault_key` (legacy hybrid combiner) + `INFO` (`"gabbro-hybrid-kex-v1"`).
- [x] Delete `derive_vault_key_transcript_bound` (v8 combiner) + `INFO_V2`.
- [x] Delete their tests (`transcript_bound_differs_from_legacy`, legacy combiner tests).
- [x] **Keep** `derive_vault_key_v11` (`INFO_VAULT_KEY_V11`) and `combine_yubikey` (`INFO_YUBIKEY`).

## 4. `src/crypto/vault_crypto.rs`

- [x] Delete dispatchers `ml_kem_keypair_for_version`, `x25519_keypair_for_version`,
  `derive_passphrase_vault_key_for_version`.
- [x] Collapse the 6 derivation sites: drop each `else { /* RT-3 legacy hybrid-KEM */ }`
  branch, keeping only the v11 HKDF-direct path — `seal_vault_with_params`, `open_vault`,
  `seal_vault_with_keys`, `open_vault_with_key_record`, `migrate_multikey_to_version`,
  `change_vault_passphrase_with_keys`.
- [x] Remove legacy imports: `ml_kem::{Decapsulate, Encapsulate, Ciphertext}`,
  `x25519_dalek::{EphemeralSecret, PublicKey}`, `keypair::X25519Keypair`, `ml_kem::MlKemKeypair`.
- [x] Simplify `capped_reseal_version_for` — one derivation era at v11+, so the two-era
  boundary (and the `X25519_DIRECT_MIN_VERSION`/`HKDF_DIRECT_MIN_VERSION` split) collapses;
  a body-only re-seal no longer risks crossing a boundary.
- [x] Delete legacy tests: `legacy_version_5_vault_still_opens`,
  `truncated_ml_kem_ciphertext_returns_error_not_panic`, `derive_passphrase_vault_key_dispatches_on_version`,
  `migrate_multikey_across_x25519_boundary_v9_to_v10_reopens_with_each_key`, the S10/S11/S12
  legacy-`StdRng` p+YK brace tests.

## 5. Version constants

- [x] `src/vault/file_format.rs`: raise `VERSION_MIN_READABLE` 2 → 11; delete `KEM_HEADER_MAX_VERSION`.
- [x] `src/crypto/vault_crypto.rs`: delete `FIPS_KEYGEN_MIN_VERSION`, `AAD_MIN_VERSION`
  (AAD always on at v11), `TRANSCRIPT_BINDING_MIN_VERSION`, `X25519_DIRECT_MIN_VERSION`,
  `HKDF_DIRECT_MIN_VERSION` (becomes the floor).

## 6. Header / `SealedVault` (`src/vault/file_format.rs`)

- [x] Remove struct fields `ml_kem_ciphertext: Vec<u8>` and `x25519_ephemeral_public: [u8; 32]`.
- [x] Remove the `version <= KEM_HEADER_MAX_VERSION` branches in `to_bytes` / `from_bytes` /
  `header_aad` — the header is always the compact v11 form; drop the 1568-byte length guards.
- [x] Update `test_vault()` fixtures that set those fields.

## 7. Migrate-on-unlock (`src/vault/session.rs`, `src/api/vault.rs`)

- [x] The ≤v10 rebuild path is dead (nothing older than v11 to migrate). Remove the legacy
  derivation inside `migrate_multikey_to_version`; keep the generic on-unlock plumbing only if a
  future v11→vN bump needs it, else remove `migrate_passphrase_vault_on_unlock` /
  the p+YK migrate-on-unlock hooks (`session.rs:78,109`).

## 8. Tests & fixtures (floor now v11)

- [x] `rust/tests/vault_backward_compat.rs`: remove the v6–v10 open/migrate/rotation tests +
  the v11 rotation/passphrase entries that reference pre-v11 fixtures; keep the v11 tests; add a
  "≤v10 file rejected with a clear unsupported-version error" test, run against the **kept v10
  fixtures** (a real old vault, not a synthetic one).
- [x] Delete `rust/tests/fixtures/vaults/v{6,7,8,9}_*.gabbro` (8 files) + their FIXTURES.md rows.
  **Keep the `v10_*` pair** — the most recent old format, now the rejection-test input.
- [x] `rust/tests/vault_state_machine_fuzz.rs`: `FIXTURES` -> v11 only; the `start_version <
  VERSION` belt branch in `assert_invariants` deleted (it guarded the hybrid-era boundary) and
  the two remaining branches merged — one era, one expected version. `start_version` is now
  asserted at baseline instead of threaded through. Done 2026-07-17, green in release.

## 8a. UI: the refusal must not read as corruption (sweep 2026-07-16)

Raising the floor alone makes the app tell the user their v10 vault is **corrupt** and offer to
delete it — worse than the brick we set out to avoid. The Rust error never reaches the screen:

- `unlock_screen.dart:27-39` `_defaultVaultIsReadable` probes with `readVaultHeader`; a v10 file
  now fails `from_bytes`, so the probe returns false -> corruption banner + restore/delete offer.
  The `.bak` is v10 too, so restore "fails" as well.
- `unlock_screen.dart:600-603` discards the Rust text and shows the localised
  "wrong passphrase" instead.

- [x] Rust: `peek_version` / `is_format_too_old` (`file_format.rs`, no floor check) ->
  `io::vault_format_too_old` -> bridge `vault_format_too_old`. Bridge regenerated.
- [x] Dart: `onVaultFormatTooOld` seam (additive — the bool `onVaultIsReadable` is unchanged)
  + `_vaultFormatTooOld` state, consulted at BOTH probe sites (mount and post-unlock-failure).
  Its card offers no restore/delete and is not error-red; unlock controls hide as for corrupt.
- [x] l10n: `vaultFormatTooOld` + `vaultFormatUpgradeLink` across **all 37 locales** (not 18 —
  earlier count was wrong), reusing each locale's established vault term and the existing
  `close` / `openInBrowser` keys.
- [x] Tappable link via the new `lib/widgets/url_link.dart` `showUrlDialog`, extracted from
  About's two duplicate copies (its 5 tests pin the extraction) — same show-URL-then-open
  convention everywhere.
- [x] Widget tests first (red), per the Rust side: behaviour (3) + Net A/B/C sweeps the
  existing ones missed, since `_bareUnlock` has a readable vault and never renders the banner —
  8x text on a 360px phone, short viewport, light/dark, high-contrast, `de`, tap-target,
  labelled-tap-target, contrast.
- [x] `rust/src/crypto/kdf.rs`, `keypair.rs`, `ml_kem.rs`: the `StdRng`/legacy golden-value +
  `fips_differs_from_legacy` tests go with their modules.
- [x] `test_data/migration_vaults/v{6..10}.gabbro` stay as the historical manual corpus (never
  deleted per MIGRATION_TESTS.md) but the RT-3 build will not open them — expected; note it there.
- [x] **Re-mint the sync-test corpus at v11** (sweep 2026-07-16 — missed by the original
  checklist). `test_data/sync_test_vaults/{A,B,C}.gabbro` are **v9** and would go unopenable,
  breaking three LIVE tests (`sync_test_corpus_converges_without_loss`,
  `corpus_surfaces_new_entry_then_whole_entry_delete`,
  `re_syncing_the_same_source_converges_without_loss`) plus two gate legs (sync-walk batched
  apply, fast-merge walk). Fix: `cargo test --release regenerate_sync_test_corpus -- --ignored`,
  which rewrites all three at the current VERSION. Mock vaults, documented passphrase — no risk;
  the three tracked `.gabbro` files change in the diff. Do this BEFORE raising the floor.

## 9. Docs

- [x] Remove the "≤v10 read-only / retained until RT-3" notes added for v11 across
  `SECURITY.md`, `README.md`, `ARCHITECTURE.md` (Encryption line + format), the crypto diagrams
  (`flow.dot`/`flow.svg` note, `simple_icons.svg` — already KEM-free), `ADR-018` Implementation note.
- [x] `kdf.rs` module doc: drop the `StdRng` / bytes-[0..32] X25519-seed description.
- [x] **Keep** `VAULT_UPGRADE_PATH.md` — the rejection message links to it (§0), so it must
  never 404. Update it for the v11 floor: name alpha.14 as the stepping stone, state what the
  error means and the exact fix.
- [x] Delete this file once the cleanup lands.

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
- [x] R1 v10 passphrase fixture → `Err` with the §0 message.
- [x] R2 v10 multikey fixture → `Err` on the YubiKey path too.
- [x] R3 v6/v7/v8/v9 fixtures → same rejection (replaces today's open/migrate tests).
- [x] R4 **a rejected open leaves the file byte-identical on disk** — "rejected, never
  bricked"; the documented recovery (reinstall the older release, open, upgrade) depends on it.
- [x] R5 `SealedVault::from_bytes` rejects v10 bytes at the parse layer.
- [x] R6 a v12 file still fails closed with the *newer-version* message (the ceiling must
  survive the floor move).
- [x] R7 rejection is distinguishable from "wrong passphrase" — a ≤v10 user must not think
  they mistyped.
- [x] R8 fuzzer `FIXTURES` → v11 only; the unreachable `start_version < VERSION` branch
  simplified. Re-expand both only if a future VERSION changes key derivation.
