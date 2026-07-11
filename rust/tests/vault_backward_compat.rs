//! Vault-format backward-compatibility harness — the safety net for the
//! 2026-06-08 vault-brick incident.
//!
//! # Why this file exists
//!
//! Every other "backward-compat" test in the crate *re-seals in-process with the
//! current code* and then opens it — a round-trip. That can never catch a brick,
//! because the same build both seals and opens. This harness instead loads
//! **frozen golden vault files committed to git** (`tests/fixtures/vaults/*.gabbro`)
//! that were sealed by the code that shipped each format VERSION. If any future
//! change to seal/open, `file_format.rs`, `serialization.rs`, the YubiKey keyslot,
//! AAD binding, or KDF / ML-KEM derivation stops the *current* code from reading a
//! committed fixture, the test goes red — before it can brick a real user's vault.
//!
//! The guarantee: **every future release must be able to read every v6+ vault and
//! re-seal it as the newest VERSION.** v2–v5 are out of scope (no user vaults that
//! old). See `tests/fixtures/FIXTURES.md` for how each fixture was generated and
//! how to add a fixture when a new VERSION ships.
//!
//! Everything is driven through the real public bridge functions in
//! `rust_lib_gabbro::api::vault` (the exact functions the Flutter app calls), so
//! the harness exercises the full release stack: file IO, (de)serialisation,
//! `from_bytes`/`to_bytes`, open, the mandatory re-seal, AAD, and the version bump.
//!
//! ---
//!
//! # The headline scenario (must pass as a minimum)
//!
//! A user's YubiKey vault must survive key loss *and* version bumps between any
//! step. Starting from a vault A created with passphrase + YK1 + YK2:
//!
//!   1. User creates vault A with passphrase, YK1 and YK2.
//!   2. User loses YK2, so the user adds YK3.
//!   3. User can still unlock vault A with **both** YK1 and YK3.
//!   4. User loses YK1, so the user adds YK4.
//!   5. User can still unlock vault A with **both** YK3 and YK4.
//!   6. This scenario STILL WORKS across format versions: a passphrase-less
//!      add/remove re-seals the body but (post RT-3) keeps the vault below the v10
//!      derivation boundary (the belt), so we assert it stays below AND still opens
//!      with every key. Migration to v10 happens on unlock (tested in
//!      session::migrate_on_unlock_tests). Runs from v6/v7/v8/v9 golden fixtures.
//!
//! Encoded in `yubikey_rotation_survives_key_loss_and_version_bumps`.
//!
//! ---
//!
//! # Test list (canon TDD — implement one at a time, red → green → refactor)
//!
//!   ✓ v{7,8,9,10,11}_passphrase_only_opens
//!   ✓ v7_passphrase_only_migrates_to_current_version
//!   ✓ v6_passphrase_only_opens_and_migrates
//!   ✓ v{6,7,8,9,10,11}_multikey_opens_with_each_registered_key
//!   ✓ yubikey_rotation_survives_key_loss_and_version_bumps   (from v6–v11)
//!   ✓ cannot_remove_the_last_yubikey
//!   ✓ passphrase_change_survives_and_migrates                (vault A, from v6–v9 + v11)
//!   ✓ wrong_old_passphrase_rejected_and_vault_left_openable
//!   ✓ passphrase_rotation_interleaved_with_key_loss          (vault B, from v6–v9 + v11)
//!
//! See also the opt-in (`#[ignore]`'d) state-machine fuzzer in
//! `tests/vault_state_machine_fuzz.rs`, which randomises the ORDER of
//! {change_passphrase, add_key, remove_key} over these same fixtures (seeded `rand`,
//! no `proptest` dependency) and whose failures get promoted back into this
//! deterministic gate as fixed regression tests. Run it in release:
//! `cargo test --release --test vault_state_machine_fuzz -- --ignored`.

use rust_lib_gabbro::api::vault::{
    add_yubikey_to_vault, change_passphrase, change_passphrase_with_keys, load_vault,
    load_vault_with_key_record, remove_yubikey_from_vault, save_vault,
};
use rust_lib_gabbro::vault::entry::VaultEntry;
use rust_lib_gabbro::vault::file_format::VERSION;
use rust_lib_gabbro::vault::io::read_vault;
use rust_lib_gabbro::vault::serialization::serialize_vault_body;
use rust_lib_gabbro::vault::serialization::VaultBody;
use std::path::PathBuf;

// Shared fixture spec (passphrase, canary body contents, YubiKey material).
// The generator in `examples/gen_fixtures.rs` includes the same file, so the
// values used to seal the fixtures can never drift from the values asserted here.
include!("fixtures/fixture_spec.rs");

/// Absolute path to a committed golden vault fixture.
fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/vaults")
        .join(name)
}

/// A throwaway copy of a fixture in the temp dir, deleted on drop. Mutation and
/// migration tests operate on this copy so the committed golden file is never
/// written to.
struct TempVault {
    path: PathBuf,
}

impl Drop for TempVault {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
        let _ = std::fs::remove_file(format!("{}.bak", self.path.display()));
    }
}

/// Copy a committed fixture to a unique temp path for in-place mutation.
fn temp_copy(fixture_name: &str) -> TempVault {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "gabbro-bwc-{}-{}-{}",
        std::process::id(),
        fixture_name.replace('.', "_"),
        nanos
    ));
    std::fs::copy(fixture(fixture_name), &path).expect("copy fixture to temp");
    TempVault { path }
}

/// Assert the decrypted body still contains the canary login entry — proof the
/// body genuinely decrypted, not merely that the header parsed.
fn assert_canary(body: &VaultBody) {
    let found = body.entries.iter().any(|e| {
        matches!(e, VaultEntry::Login(le)
            if le.title == CANARY_TITLE && le.password == CANARY_PASSWORD)
    });
    assert!(found, "body must contain the decrypted canary entry");
}

#[test]
fn v7_passphrase_only_opens() {
    // A v7 passphrase-only vault sealed by the current build must open and yield
    // the canary entry, proving the body decrypts under the current code path.
    let body = load_vault(FIXTURE_PASSPHRASE, &fixture("v7_passphrase.gabbro"))
        .expect("current build must open the v7 passphrase-only golden vault");
    assert_canary(&body);
}

#[test]
fn v8_passphrase_only_opens() {
    // A v8 passphrase-only vault (transcript-bound combiner) must open under the
    // current build and yield the canary — proving v8 seal/open round-trips through
    // a frozen on-disk file, not just an in-process re-seal.
    let p = fixture("v8_passphrase.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        8,
        "fixture must be VERSION 8"
    );
    let body = load_vault(FIXTURE_PASSPHRASE, &p)
        .expect("current build must open the v8 passphrase-only golden vault");
    assert_canary(&body);
}

#[test]
fn v7_passphrase_only_migrates_to_current_version() {
    // Open the v7 passphrase fixture, then re-seal it the way the app does on any
    // CRUD save (save_vault re-derives from the passphrase). The re-sealed file
    // must be tagged the current VERSION and must re-open with the canary intact.
    let tv = temp_copy("v7_passphrase.gabbro");
    let body = load_vault(FIXTURE_PASSPHRASE, &tv.path).expect("open v7 passphrase fixture");

    save_vault(&body, FIXTURE_PASSPHRASE, &tv.path).expect("re-seal (migrate) the vault");

    assert_eq!(
        read_vault(&tv.path).unwrap().version,
        VERSION,
        "re-sealed vault must be tagged the current format VERSION"
    );
    let reopened = load_vault(FIXTURE_PASSPHRASE, &tv.path).expect("re-open after migration");
    assert_canary(&reopened);
}

#[test]
fn v6_passphrase_only_opens_and_migrates() {
    // A genuine VERSION 6 passphrase vault (sealed by the alpha.4 build: FIPS
    // ML-KEM keygen, NO header AAD) must open under the current build, and a
    // re-seal must upgrade it to the current VERSION while preserving contents —
    // proving the v6 -> latest passphrase migration path.
    let tv = temp_copy("v6_passphrase.gabbro");
    assert_eq!(
        read_vault(&tv.path).unwrap().version,
        6,
        "fixture must genuinely be VERSION 6 on disk"
    );

    let body = load_vault(FIXTURE_PASSPHRASE, &tv.path).expect("current build must open v6 vault");
    assert_canary(&body);

    save_vault(&body, FIXTURE_PASSPHRASE, &tv.path).expect("re-seal migrates v6 -> current");
    assert_eq!(
        read_vault(&tv.path).unwrap().version,
        VERSION,
        "after re-seal the vault must be upgraded to the current VERSION"
    );
    assert_canary(&load_vault(FIXTURE_PASSPHRASE, &tv.path).expect("re-open after migration"));
}

/// Open a multi-key vault on disk with one key's material and assert the canary
/// survived — i.e. the body genuinely decrypted via that key's keyslot.
fn assert_opens_with(path: &std::path::Path, hmac: &[u8; 32], cred: &[u8], who: &str) {
    let (body, _master, _wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, hmac, cred, path)
            .unwrap_or_else(|e| panic!("vault must open with {who}: {e}"));
    assert_canary(&body);
}

#[test]
fn v7_multikey_opens_with_each_registered_key() {
    // A v7 passphrase + YK1 + YK2 vault must open with EITHER registered key.
    let p = fixture("v7_multikey_2keys.gabbro");
    assert_opens_with(&p, YK1_HMAC, YK1_CRED, "YK1");
    assert_opens_with(&p, YK2_HMAC, YK2_CRED, "YK2");
}

#[test]
fn v6_multikey_opens_with_each_registered_key() {
    // Same, starting from a genuine VERSION 6 multi-key vault (no header AAD).
    let p = fixture("v6_multikey_2keys.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        6,
        "fixture must be VERSION 6"
    );
    assert_opens_with(&p, YK1_HMAC, YK1_CRED, "YK1");
    assert_opens_with(&p, YK2_HMAC, YK2_CRED, "YK2");
}

#[test]
fn v8_multikey_opens_with_each_registered_key() {
    // A v8 passphrase + YK1 + YK2 vault must open with EITHER registered key.
    // YubiKey-mode derivation is unchanged at v8, so this also confirms the
    // version bump alone didn't disturb the keyslots.
    let p = fixture("v8_multikey_2keys.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        8,
        "fixture must be VERSION 8"
    );
    assert_opens_with(&p, YK1_HMAC, YK1_CRED, "YK1");
    assert_opens_with(&p, YK2_HMAC, YK2_CRED, "YK2");
}

#[test]
fn v9_passphrase_only_opens() {
    // A v9 passphrase-only vault (crypto byte-identical to v8; the body JSON gains
    // per-field change-times) must open under the current build and yield the
    // canary — proving v9 seal/open round-trips through a frozen on-disk file.
    let p = fixture("v9_passphrase.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        9,
        "fixture must be VERSION 9"
    );
    let body = load_vault(FIXTURE_PASSPHRASE, &p)
        .expect("current build must open the v9 passphrase-only golden vault");
    assert_canary(&body);
}

#[test]
fn v9_multikey_opens_with_each_registered_key() {
    // A v9 passphrase + YK1 + YK2 vault must open with EITHER registered key.
    let p = fixture("v9_multikey_2keys.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        9,
        "fixture must be VERSION 9"
    );
    assert_opens_with(&p, YK1_HMAC, YK1_CRED, "YK1");
    assert_opens_with(&p, YK2_HMAC, YK2_CRED, "YK2");
}

#[test]
fn v10_passphrase_only_opens() {
    // A v10 passphrase-only vault (X25519 derived directly from the KDF, no StdRng)
    // must open under the current build and yield the canary.
    let p = fixture("v10_passphrase.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        10,
        "fixture must be VERSION 10"
    );
    let body = load_vault(FIXTURE_PASSPHRASE, &p)
        .expect("current build must open the v10 passphrase-only golden vault");
    assert_canary(&body);
}

#[test]
fn v10_multikey_opens_with_each_registered_key() {
    // A v10 passphrase + YK1 + YK2 vault must open with EITHER registered key.
    let p = fixture("v10_multikey_2keys.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        10,
        "fixture must be VERSION 10"
    );
    assert_opens_with(&p, YK1_HMAC, YK1_CRED, "YK1");
    assert_opens_with(&p, YK2_HMAC, YK2_CRED, "YK2");
}

#[test]
fn v11_passphrase_only_opens() {
    // A v11 passphrase-only vault (vault key derived straight from Argon2id via
    // HKDF, no ML-KEM ciphertext in the header) must open and yield the canary.
    // Frozen now so a future build (RT-3 legacy-code removal, v12+) that breaks
    // v11 reads goes red before it can brick a migrated vault.
    let p = fixture("v11_passphrase.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        11,
        "fixture must be VERSION 11"
    );
    let body = load_vault(FIXTURE_PASSPHRASE, &p)
        .expect("current build must open the v11 passphrase-only golden vault");
    assert_canary(&body);
}

#[test]
fn v11_multikey_opens_with_each_registered_key() {
    // A v11 passphrase + YK1 + YK2 vault must open with EITHER registered key.
    // The keyslot (combine_yubikey over the random wrapping_key) is unchanged at
    // v11; this confirms the HKDF-direct passphrase path didn't disturb it.
    let p = fixture("v11_multikey_2keys.gabbro");
    assert_eq!(
        read_vault(&p).unwrap().version,
        11,
        "fixture must be VERSION 11"
    );
    assert_opens_with(&p, YK1_HMAC, YK1_CRED, "YK1");
    assert_opens_with(&p, YK2_HMAC, YK2_CRED, "YK2");
}

/// Walks the full key-loss / key-rotation journey on a temp copy of `fixture_name`,
/// driving the *real* bridge functions the Flutter app calls. A passphrase-less
/// add/remove routes through `reseal_vault_body`, which re-binds the body to the new
/// header (AAD) but — post RT-3 — will NOT force the vault across the HKDF-direct
/// derivation boundary (the belt: it has no passphrase to rebuild the material). All
/// v6–v10 fixtures sit below that boundary (which landed at v11), so after each
/// mutation we assert the vault stays below VERSION AND still opens with every
/// surviving key. Migration happens on unlock (session::migrate_on_unlock_tests).
fn run_rotation_scenario(fixture_name: &str) {
    run_rotation_scenario_with(fixture_name, |v| {
        assert!(
            v < VERSION,
            "belt: add/remove must NOT force a v6-v10 vault across the derivation boundary"
        );
    });
}

fn run_rotation_scenario_with(fixture_name: &str, check_version: impl Fn(u8)) {
    let tv = temp_copy(fixture_name);
    let path = tv.path.as_path();

    // Step 1: user creates vault A with passphrase, YK1 and YK2 (the fixture).
    //         Both registered keys open it.
    assert_opens_with(path, YK1_HMAC, YK1_CRED, "YK1 (initial)");
    assert_opens_with(path, YK2_HMAC, YK2_CRED, "YK2 (initial)");

    // Step 2: user loses YK2, so the user adds YK3.
    //         Authorise with a surviving key (YK1): open to get the cached
    //         vault_key_master + wrapping_key, add YK3, then drop the lost YK2.
    let (body, master, wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK1_HMAC, YK1_CRED, path)
            .expect("authorise rotation with surviving YK1");
    let wrapping = wrapping.expect("multi-key vault must expose a wrapping_key");
    let pt = serialize_vault_body(&body).expect("serialize vault body");
    add_yubikey_to_vault(
        &pt,
        &wrapping,
        &master,
        YK3_CRED.to_vec(),
        YK3_HMAC,
        YK3_SALT,
        path,
    )
    .expect("add YK3");
    remove_yubikey_from_vault(&pt, &master, YK2_CRED, path).expect("remove lost YK2");
    // A passphrase-less key mutation cannot rebuild the passphrase material, so the
    // belt (capped_reseal_version) holds the vault at/below the derivation boundary.
    // Migration happens on unlock (session::migrate_on_unlock_tests). The guarantee
    // here is no brick: it still opens with each surviving key (Steps 3/5).
    check_version(read_vault(path).unwrap().version);

    // Step 3: user can still unlock vault A with BOTH YK1 and YK3.
    assert_opens_with(path, YK1_HMAC, YK1_CRED, "YK1 after losing YK2");
    assert_opens_with(path, YK3_HMAC, YK3_CRED, "newly added YK3");

    // Step 4: user loses YK1, so the user adds YK4.
    //         Authorise with surviving YK3.
    let (body, master, wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK3_HMAC, YK3_CRED, path)
            .expect("authorise rotation with surviving YK3");
    let wrapping = wrapping.expect("multi-key vault must expose a wrapping_key");
    let pt = serialize_vault_body(&body).expect("serialize vault body");
    add_yubikey_to_vault(
        &pt,
        &wrapping,
        &master,
        YK4_CRED.to_vec(),
        YK4_HMAC,
        YK4_SALT,
        path,
    )
    .expect("add YK4");
    remove_yubikey_from_vault(&pt, &master, YK1_CRED, path).expect("remove lost YK1");
    check_version(read_vault(path).unwrap().version);

    // Step 5: user can still unlock vault A with BOTH YK3 and YK4.
    assert_opens_with(path, YK3_HMAC, YK3_CRED, "YK3 after losing YK1");
    assert_opens_with(path, YK4_HMAC, YK4_CRED, "newly added YK4");
}

#[test]
fn yubikey_rotation_survives_key_loss_and_version_bumps() {
    // The headline guarantee. Run the full create -> lose YK2/add YK3 ->
    // lose YK1/add YK4 journey starting from BOTH a genuine v6 and a genuine v7
    // golden vault, so it is proven regardless of the format version the vault was
    // born at (and regardless of the version bumps applied along the way).
    run_rotation_scenario("v6_multikey_2keys.gabbro");
    run_rotation_scenario("v7_multikey_2keys.gabbro");
    run_rotation_scenario("v8_multikey_2keys.gabbro");
    run_rotation_scenario("v9_multikey_2keys.gabbro");
    // v10 too: since the HKDF-direct boundary landed at v11, v10 now caps below it
    // like the pre-v11 fixtures (a passphrase-less mutation stays < VERSION).
    run_rotation_scenario("v10_multikey_2keys.gabbro");
    // v11 sits AT the derivation boundary (== VERSION), not below it: a v11 vault is
    // already HKDF-direct, so a passphrase-less rotation re-seals within the same era
    // and stays at VERSION. The guarantee is identical — no brick, opens with every
    // surviving key across the loss/rotation journey.
    run_rotation_scenario_with("v11_multikey_2keys.gabbro", |v| {
        assert_eq!(
            v, VERSION,
            "a v11 vault stays AT the current VERSION across a passphrase-less rotation"
        );
    });
}

#[test]
fn cannot_remove_the_last_yubikey() {
    // Onboarding requires two keys, but the post-onboarding floor is ONE: a user
    // who lost one of two must still unlock with the survivor. Removing that final
    // key must be refused so a vault can never be left permanently unopenable.
    let tv = temp_copy("v7_multikey_2keys.gabbro");
    let path = tv.path.as_path();
    let (body, master, _wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK1_HMAC, YK1_CRED, path)
            .expect("open multi-key vault with YK1");
    let pt = serialize_vault_body(&body).expect("serialize vault body");

    // Removing one of the two keys (down to a single key) is allowed.
    remove_yubikey_from_vault(&pt, &master, YK2_CRED, path)
        .expect("removing down to one key is allowed");

    // Removing the final remaining key must be refused.
    let err = remove_yubikey_from_vault(&pt, &master, YK1_CRED, path)
        .expect_err("removing the last YubiKey must be refused");
    assert!(
        err.contains("cannot remove the last"),
        "unexpected error: {err}"
    );

    // The sole surviving key still opens the vault.
    assert_opens_with(path, YK1_HMAC, YK1_CRED, "YK1 (sole remaining key)");
}

// ── Passphrase change + key rotation ──────────────────────────────────────────
//
// A v4 multi-key vault layers the YubiKey ON TOP of the passphrase: the passphrase
// unwraps the `passphrase_blob` to a `wrapping_key`, then `wrapping_key` + a
// registered key unwraps that key's `key_blob` to the `vault_key_master` that
// decrypts the body. So opening always needs BOTH a passphrase and a registered
// key. `change_passphrase_with_keys` rewraps the SAME wrapping_key under the new
// passphrase, leaving every key_blob and the body untouched, then re-seals/migrates
// the file to the current VERSION. These tests prove that property survives a real
// loss/rotation journey, starting from frozen v6 and v7 golden vaults.

/// Assert a passphrase-only vault opens with `pass` and yields the canary.
fn assert_opens_with_passphrase(path: &std::path::Path, pass: &[u8], who: &str) {
    let body = load_vault(pass, path).unwrap_or_else(|e| panic!("vault must open with {who}: {e}"));
    assert_canary(&body);
}

/// Multi-key open with an explicit passphrase (the rotation/change tests need the
/// NEW passphrase, whereas `assert_opens_with` hard-codes FIXTURE_PASSPHRASE).
fn assert_opens_with_pass(
    path: &std::path::Path,
    pass: &[u8],
    hmac: &[u8; 32],
    cred: &[u8],
    who: &str,
) {
    let (body, _master, _wrapping) = load_vault_with_key_record(pass, hmac, cred, path)
        .unwrap_or_else(|e| panic!("vault must open with {who}: {e}"));
    assert_canary(&body);
}

/// Vault A: a passphrase-only vault whose passphrase is changed. The change is a
/// load+save, so it also migrates the file to the current VERSION. Afterwards the
/// new passphrase opens it (canary intact) and the old passphrase does not.
fn run_passphrase_change_scenario(fixture_name: &str) {
    const NEW_PASSPHRASE: &[u8] = b"vault A rotated passphrase -- brand new";
    let tv = temp_copy(fixture_name);
    let path = tv.path.as_path();

    assert_opens_with_passphrase(path, FIXTURE_PASSPHRASE, "original passphrase");

    change_passphrase(path, FIXTURE_PASSPHRASE, NEW_PASSPHRASE).expect("change vault A passphrase");
    assert_eq!(
        read_vault(path).unwrap().version,
        VERSION,
        "a passphrase change re-seals and migrates the vault to the current VERSION"
    );

    assert_opens_with_passphrase(path, NEW_PASSPHRASE, "new passphrase after the change");
    assert!(
        load_vault(FIXTURE_PASSPHRASE, path).is_err(),
        "the old passphrase must stop working after the change"
    );
}

#[test]
fn passphrase_change_survives_and_migrates() {
    // Proven from both a genuine v6 and a genuine v7 passphrase-only golden vault.
    run_passphrase_change_scenario("v6_passphrase.gabbro");
    run_passphrase_change_scenario("v7_passphrase.gabbro");
    run_passphrase_change_scenario("v8_passphrase.gabbro");
    run_passphrase_change_scenario("v9_passphrase.gabbro");
    // v11: a passphrase change on an already-HKDF-direct vault re-seals within the
    // same era and stays at the current VERSION (the scenario asserts == VERSION).
    run_passphrase_change_scenario("v11_passphrase.gabbro");
}

#[test]
fn wrong_old_passphrase_rejected_and_vault_left_openable() {
    // A change attempted with the wrong old passphrase must fail at the decrypt
    // step and leave the vault byte-for-byte usable under the ORIGINAL passphrase —
    // no partial write, no half-applied new passphrase.
    const WRONG: &[u8] = b"not the real old passphrase";
    const WOULD_BE_NEW: &[u8] = b"the passphrase that must never take effect";
    let tv = temp_copy("v7_passphrase.gabbro");
    let path = tv.path.as_path();

    change_passphrase(path, WRONG, WOULD_BE_NEW)
        .expect_err("changing with the wrong old passphrase must be rejected");

    assert_opens_with_passphrase(path, FIXTURE_PASSPHRASE, "original after a rejected change");
    assert!(
        load_vault(WOULD_BE_NEW, path).is_err(),
        "a rejected change must not have applied the would-be new passphrase"
    );
}

/// Vault B: the headline multi-key journey with a passphrase change interleaved.
/// The journey: created with passphrase + YK1 + YK2 (the fixture); lose YK2 ->
/// remove YK2, add YK3; change the passphrase (multi-key path); lose YK1 -> remove
/// YK1, add YK4.
///
/// At the end the vault has a NEW passphrase AND new keys (YK3, YK4) and must still
/// open with `new passphrase + YK3/YK4`; the old passphrase and the removed keys
/// must all be refused; the canary survives every step. Passphrase-less rotations
/// stay below the v10 boundary (belt); the passphrase change migrates to current,
/// after which further rotations remain at current.
fn run_passphrase_rotation_scenario(fixture_name: &str) {
    // v6-v10 sit below the derivation boundary: a passphrase-less rotation stays
    // < VERSION (belt) until the passphrase change migrates it.
    run_passphrase_rotation_scenario_with(fixture_name, |v| {
        assert!(
            v < VERSION,
            "belt: passphrase-less rotation stays below the boundary until a migrating op runs"
        );
    });
}

fn run_passphrase_rotation_scenario_with(fixture_name: &str, step2_version_check: impl Fn(u8)) {
    const NEW_PASSPHRASE: &[u8] = b"vault B rotated passphrase -- mid journey";
    let tv = temp_copy(fixture_name);
    let path = tv.path.as_path();

    // Step 1: both initial keys open it.
    assert_opens_with(path, YK1_HMAC, YK1_CRED, "YK1 (initial)");
    assert_opens_with(path, YK2_HMAC, YK2_CRED, "YK2 (initial)");

    // Step 2: lose YK2, add YK3 — authorise with surviving YK1.
    let (body, master, wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK1_HMAC, YK1_CRED, path)
            .expect("authorise rotation with YK1");
    let wrapping = wrapping.expect("multi-key vault must expose a wrapping_key");
    let pt = serialize_vault_body(&body).expect("serialize vault body");
    add_yubikey_to_vault(
        &pt,
        &wrapping,
        &master,
        YK3_CRED.to_vec(),
        YK3_HMAC,
        YK3_SALT,
        path,
    )
    .expect("add YK3");
    remove_yubikey_from_vault(&pt, &master, YK2_CRED, path).expect("remove lost YK2");
    // A passphrase-less rotation re-seals within the vault's own era (no re-tap/no
    // passphrase to rebuild the material): pre-v11 stays below the boundary, v11
    // stays AT it. The passphrase change in Step 3 migrates either way.
    step2_version_check(read_vault(path).unwrap().version);

    // Step 3: change the passphrase on the multi-key vault. Get the master via a
    // surviving key under the CURRENT passphrase, then rotate.
    let (body, master, _wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK1_HMAC, YK1_CRED, path)
            .expect("open to fetch master before passphrase change");
    let pt = serialize_vault_body(&body).expect("serialize vault body");
    change_passphrase_with_keys(FIXTURE_PASSPHRASE, NEW_PASSPHRASE, &master, &pt, path)
        .expect("change passphrase on multi-key vault B");
    assert_eq!(
        read_vault(path).unwrap().version,
        VERSION,
        "a multi-key passphrase change also re-seals + migrates to the current VERSION"
    );

    // The old passphrase no longer opens it, even with a registered key...
    assert!(
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK1_HMAC, YK1_CRED, path).is_err(),
        "old passphrase must stop working after the change, even with a registered key"
    );
    // ...but the new passphrase + either surviving key (YK1 or YK3) does.
    assert_opens_with_pass(
        path,
        NEW_PASSPHRASE,
        YK1_HMAC,
        YK1_CRED,
        "YK1 + new passphrase",
    );
    assert_opens_with_pass(
        path,
        NEW_PASSPHRASE,
        YK3_HMAC,
        YK3_CRED,
        "YK3 + new passphrase",
    );

    // Step 4: lose YK1, add YK4 — authorise with surviving YK3 under the NEW passphrase.
    let (body, master, wrapping) =
        load_vault_with_key_record(NEW_PASSPHRASE, YK3_HMAC, YK3_CRED, path)
            .expect("authorise second rotation with YK3 + new passphrase");
    let wrapping = wrapping.expect("multi-key vault must expose a wrapping_key");
    let pt = serialize_vault_body(&body).expect("serialize vault body");
    add_yubikey_to_vault(
        &pt,
        &wrapping,
        &master,
        YK4_CRED.to_vec(),
        YK4_HMAC,
        YK4_SALT,
        path,
    )
    .expect("add YK4");
    remove_yubikey_from_vault(&pt, &master, YK1_CRED, path).expect("remove lost YK1");
    assert_eq!(
        read_vault(path).unwrap().version,
        VERSION,
        "version current after rotation 2"
    );

    // Final state: new passphrase AND new keys. YK3/YK4 + new passphrase open it.
    assert_opens_with_pass(path, NEW_PASSPHRASE, YK3_HMAC, YK3_CRED, "YK3 (final)");
    assert_opens_with_pass(path, NEW_PASSPHRASE, YK4_HMAC, YK4_CRED, "YK4 (final)");

    // Everything that should be locked out, is: removed keys and the old passphrase.
    assert!(
        load_vault_with_key_record(NEW_PASSPHRASE, YK1_HMAC, YK1_CRED, path).is_err(),
        "removed YK1 must not open vault B"
    );
    assert!(
        load_vault_with_key_record(NEW_PASSPHRASE, YK2_HMAC, YK2_CRED, path).is_err(),
        "removed YK2 must not open vault B"
    );
    assert!(
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK3_HMAC, YK3_CRED, path).is_err(),
        "the old passphrase must not open vault B with any key"
    );
}

#[test]
fn passphrase_rotation_interleaved_with_key_loss() {
    // The vault-B headline guarantee, proven from both a v6 and a v7 golden vault.
    run_passphrase_rotation_scenario("v6_multikey_2keys.gabbro");
    run_passphrase_rotation_scenario("v7_multikey_2keys.gabbro");
    run_passphrase_rotation_scenario("v8_multikey_2keys.gabbro");
    run_passphrase_rotation_scenario("v9_multikey_2keys.gabbro");
    // v11: already HKDF-direct, so the Step-2 passphrase-less rotation stays AT the
    // current VERSION rather than below it. The rest of the journey is identical.
    run_passphrase_rotation_scenario_with("v11_multikey_2keys.gabbro", |v| {
        assert_eq!(
            v, VERSION,
            "a v11 vault stays AT the current VERSION across a passphrase-less rotation"
        );
    });
}
