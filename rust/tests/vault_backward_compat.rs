//! Vault-format backward-compatibility harness — the safety net for the
//! 2026-06-08 vault-brick incident (see `docs/LEARNINGS.md`).
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
//!   6. This scenario STILL WORKS if vault A has been bumped *n* versions between
//!      any of the steps above (every add/remove re-seals and migrates the file to
//!      the current VERSION, so we assert the on-disk version == current after each
//!      mutation, starting from both a v6 and a v7 golden fixture).
//!
//! Encoded in `yubikey_rotation_survives_key_loss_and_version_bumps`.
//!
//! ---
//!
//! # Test list (canon TDD — implement one at a time, red → green → refactor)
//!
//!   ✓ v7_passphrase_only_opens
//!   ✓ v7_passphrase_only_migrates_to_current_version
//!   ✓ v6_passphrase_only_opens_and_migrates
//!   ✓ v6_multikey_opens_with_each_registered_key
//!   ✓ v7_multikey_opens_with_each_registered_key
//!   ✓ yubikey_rotation_survives_key_loss_and_version_bumps   (from v6 and v7)
//!   ✓ cannot_remove_the_last_yubikey

use rust_lib_gabbro::api::vault::{
    add_yubikey_to_vault, load_vault, load_vault_with_key_record, remove_yubikey_from_vault,
    save_vault,
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

/// Walks the full key-loss / key-rotation journey on a temp copy of `fixture_name`,
/// driving the *real* bridge functions the Flutter app calls. Every add/remove
/// routes through `reseal_vault_body`, which re-binds the body to the new header
/// (AAD) and migrates the file to the current VERSION — so after each mutation we
/// assert the on-disk version is current, proving the scenario holds even as the
/// vault is "bumped n versions between steps".
fn run_rotation_scenario(fixture_name: &str) {
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
    assert_eq!(
        read_vault(path).unwrap().version,
        VERSION,
        "after add/remove the vault must be migrated to the current VERSION"
    );

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
    assert_eq!(
        read_vault(path).unwrap().version,
        VERSION,
        "after the second rotation the vault must again be at the current VERSION"
    );

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
