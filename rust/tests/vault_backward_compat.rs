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
//! The guarantee: **every future release must be able to read every v11+ vault and
//! re-seal it as the newest VERSION, and must refuse anything older without touching
//! the file.** RT-3 raised the floor to v11 — the X25519 + ML-KEM derivation that
//! opened v2–v10 is gone, so those vaults cannot be read by any code path. The kept
//! `v10_*` fixtures are REJECTION inputs, not compatibility inputs: they prove the
//! refusal is polite (clear error naming the upgrade path, file left byte-identical),
//! so the documented recovery still works — see `docs/VAULT_UPGRADE_PATH.md`.
//!
//! Until VERSION 12 ships there is only one readable format, so this file's job is
//! narrower than its name: hold v11 open forever, and refuse ≤v10 cleanly. The moment
//! a v12 lands, v11 becomes the old format this harness protects — that is why the
//! v11 goldens and this file stay. See `tests/fixtures/FIXTURES.md` for how each
//! fixture was generated and how to add a fixture when a new VERSION ships.
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
//!   6. A passphrase-less add/remove re-seals the body within the vault's own
//!      derivation era, so a v11 vault stays AT VERSION and still opens with every
//!      surviving key.
//!
//! Encoded in `yubikey_rotation_survives_key_loss_and_version_bumps`.
//!
//! ---
//!
//! # Test list (canon TDD — implement one at a time, red → green → refactor)
//!
//!   ✓ v11_passphrase_only_opens
//!   ✓ v11_multikey_opens_with_each_registered_key
//!   ✓ v10_passphrase_only_is_refused
//!   ✓ v10_multikey_is_refused
//!   ✓ refusing_an_old_vault_does_not_touch_the_file
//!   ✓ refusal_is_distinguishable_from_a_wrong_passphrase
//!   ✓ yubikey_rotation_survives_key_loss_and_version_bumps
//!   ✓ cannot_remove_the_last_yubikey
//!   ✓ passphrase_change_survives                             (vault A)
//!   ✓ wrong_old_passphrase_rejected_and_vault_left_openable
//!   ✓ passphrase_rotation_interleaved_with_key_loss          (vault B)
//!
//! See also the opt-in (`#[ignore]`'d) state-machine fuzzer in
//! `tests/vault_state_machine_fuzz.rs`, which randomises the ORDER of
//! {change_passphrase, add_key, remove_key} over these same fixtures (seeded `rand`,
//! no `proptest` dependency) and whose failures get promoted back into this
//! deterministic gate as fixed regression tests. Run it in release:
//! `cargo test --release --test vault_state_machine_fuzz -- --ignored`.

use rust_lib_gabbro::api::vault::{
    add_yubikey_to_vault, change_passphrase, change_passphrase_with_keys, load_vault,
    load_vault_with_key_record, remove_yubikey_from_vault,
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

/// Open a multi-key vault on disk with one key's material and assert the canary
/// survived — i.e. the body genuinely decrypted via that key's keyslot.
fn assert_opens_with(path: &std::path::Path, hmac: &[u8; 32], cred: &[u8], who: &str) {
    let (body, _master, _wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, hmac, cred, path)
            .unwrap_or_else(|e| panic!("vault must open with {who}: {e}"));
    assert_canary(&body);
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

// ── Floor v11: ≤v10 vaults are refused, never damaged ─────────────────────────
//
// RT-3 dropped the ml-kem + x25519-dalek layer, so a ≤v10 vault can no longer be
// opened by any code path. The v10 fixtures below are kept as REJECTION inputs —
// real old vaults, not synthetic bytes — proving the refusal is polite: a clear
// error pointing at the upgrade path, and the file left untouched on disk so the
// documented recovery (reinstall alpha.14, open, migrate) still works.

/// The link the error must carry, so a user who hits it knows what to do.
const UPGRADE_PATH_URL: &str =
    "https://github.com/gabbro-foss/gabbro/blob/master/docs/VAULT_UPGRADE_PATH.md";

/// Assert an open attempt failed with the unsupported-version error, and that the
/// error names the upgrade path rather than reading as corruption or a bad passphrase.
fn assert_unsupported_version_error(err: &str) {
    assert!(
        err.contains("file version not supported"),
        "error must say the version is unsupported, got: {err}"
    );
    assert!(
        err.contains(UPGRADE_PATH_URL),
        "error must link to the upgrade path so the user can recover, got: {err}"
    );
}

#[test]
fn v10_passphrase_only_is_refused() {
    let err = load_vault(FIXTURE_PASSPHRASE, &fixture("v10_passphrase.gabbro"))
        .expect_err("a v10 vault must not open at floor v11");
    assert_unsupported_version_error(&err);
}

#[test]
fn v10_multikey_is_refused() {
    // The YubiKey path must refuse too — not just the passphrase-only path.
    let err = load_vault_with_key_record(
        FIXTURE_PASSPHRASE,
        YK1_HMAC,
        YK1_CRED,
        &fixture("v10_multikey_2keys.gabbro"),
    )
    .expect_err("a v10 multi-key vault must not open at floor v11");
    assert_unsupported_version_error(&err);
}

#[test]
fn refusing_an_old_vault_does_not_touch_the_file() {
    // The recovery documented in VAULT_UPGRADE_PATH.md (reinstall alpha.14, open,
    // migrate) only holds if the refusal writes nothing. Byte-compare the file
    // either side of a refused open — including the .bak the writer would rotate.
    let tv = temp_copy("v10_passphrase.gabbro");
    let before = std::fs::read(&tv.path).expect("read fixture copy");

    load_vault(FIXTURE_PASSPHRASE, &tv.path).expect_err("v10 must be refused");

    let after = std::fs::read(&tv.path).expect("re-read after the refused open");
    assert_eq!(
        before, after,
        "a refused open must leave the vault byte-identical — the user's recovery depends on it"
    );
    assert!(
        !PathBuf::from(format!("{}.bak", tv.path.display())).exists(),
        "a refused open must not rotate a .bak"
    );
}

#[test]
fn refusal_is_distinguishable_from_a_wrong_passphrase() {
    // A user with an old vault must not be sent chasing their passphrase. The
    // wrong-passphrase error on a CURRENT vault must not mention the version, and
    // the version error must not mention the passphrase.
    let version_err = load_vault(FIXTURE_PASSPHRASE, &fixture("v10_passphrase.gabbro"))
        .expect_err("v10 must be refused");
    assert!(
        !version_err.to_lowercase().contains("passphrase"),
        "the version error must not blame the passphrase, got: {version_err}"
    );

    let passphrase_err = load_vault(
        b"definitely the wrong passphrase",
        &fixture("v11_passphrase.gabbro"),
    )
    .expect_err("a wrong passphrase on a v11 vault must fail");
    assert!(
        !passphrase_err.contains("file version not supported"),
        "a wrong passphrase must not be reported as a version problem, got: {passphrase_err}"
    );
}

/// Walks the full key-loss / key-rotation journey on a temp copy of `fixture_name`,
/// driving the *real* bridge functions the Flutter app calls. A passphrase-less
/// add/remove routes through `reseal_vault_body`, which re-binds the body to the new
/// header (AAD). At floor v11 every vault is already in the current derivation era,
/// so a rotation re-seals within it and the vault stays AT VERSION.
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
    // The headline guarantee: create -> lose YK2/add YK3 -> lose YK1/add YK4, and the
    // vault opens with every surviving key at each step. Proven from the v11 golden
    // vault — the only format that can exist at floor v11.
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
    let tv = temp_copy("v11_multikey_2keys.gabbro");
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
/// load+save, so the file is re-sealed at the current VERSION. Afterwards the new
/// passphrase opens it (canary intact) and the old passphrase does not.
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
fn passphrase_change_survives() {
    // A passphrase change re-seals the vault; the new passphrase opens it with the
    // canary intact and the old one stops working.
    run_passphrase_change_scenario("v11_passphrase.gabbro");
}

#[test]
fn wrong_old_passphrase_rejected_and_vault_left_openable() {
    // A change attempted with the wrong old passphrase must fail at the decrypt
    // step and leave the vault byte-for-byte usable under the ORIGINAL passphrase —
    // no partial write, no half-applied new passphrase.
    const WRONG: &[u8] = b"not the real old passphrase";
    const WOULD_BE_NEW: &[u8] = b"the passphrase that must never take effect";
    let tv = temp_copy("v11_passphrase.gabbro");
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
/// must all be refused; the canary survives every step.
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
    // The vault-B headline guarantee, proven from the v11 golden vault.
    run_passphrase_rotation_scenario_with("v11_multikey_2keys.gabbro", |v| {
        assert_eq!(
            v, VERSION,
            "a v11 vault stays AT the current VERSION across a passphrase-less rotation"
        );
    });
}
