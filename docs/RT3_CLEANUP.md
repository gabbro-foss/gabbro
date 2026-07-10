# RT-3 cleanup — deleting the dual-lock hybrid KEM (floor → v11)

Everything held back on the `drop-dual-lock-hybrid-kem` branch (v11 = WRITE path only)
so v2–v10 vaults can still be **read and migrated**. This is the **Release N+1** task
(ADR-018 decision item 2): run it once no ≤v10 vault remains in the field, raise the
readable floor to v11, and delete all of the below. Nothing here is load-bearing at v11.

**Precondition:** every vault migrated to v11 (see [VAULT_UPGRADE_PATH.md](VAULT_UPGRADE_PATH.md)).
Do NOT run this while any ≤v10 vault could still exist — it makes those vaults unopenable.

## 1. Crate dependencies (`rust/Cargo.toml`)

- [ ] Remove `ml-kem = "0.2.3"` (feature `deterministic`).
- [ ] Remove `x25519-dalek = "2.0.1"` (feature `static_secrets`).
- [ ] Confirm the transitive tree shrinks (ADR-018: ~6 unique transitive crates incl. a
  compile-time proc-macro/build-dep). `rand` **stays** (`OsRng` for salts / random keys).

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
  "≤v10 file rejected with a clear unsupported-version error" test.
- [ ] Delete `rust/tests/fixtures/vaults/v{6,7,8,9,10}_*.gabbro` (10 files) + their FIXTURES.md rows.
- [ ] `rust/tests/vault_state_machine_fuzz.rs`: drop v6/v7/v8 from `FIXTURES` (keep v11); the
  `start_version < VERSION` belt branch in `assert_invariants` becomes unreachable — simplify.
- [ ] `rust/src/crypto/kdf.rs`, `keypair.rs`, `ml_kem.rs`: the `StdRng`/legacy golden-value +
  `fips_differs_from_legacy` tests go with their modules.
- [ ] `test_data/migration_vaults/v{6..10}.gabbro` stay as the historical manual corpus (never
  deleted per MIGRATION_TESTS.md) but the RT-3 build will not open them — expected; note it there.

## 9. Docs

- [ ] Remove the "≤v10 read-only / retained until RT-3" notes added for v11 across
  `SECURITY.md`, `README.md`, `ARCHITECTURE.md` (Encryption line + format), the crypto diagrams
  (`flow.dot`/`flow.svg` note, `simple_icons.svg` — already KEM-free), `ADR-018` Implementation note.
- [ ] `kdf.rs` module doc: drop the `StdRng` / bytes-[0..32] X25519-seed description.
- [ ] Retire `VAULT_UPGRADE_PATH.md` (its v10→v11 stepping stone is complete) or re-instantiate
  it for the next bump.
- [ ] Delete this file once the cleanup lands.
